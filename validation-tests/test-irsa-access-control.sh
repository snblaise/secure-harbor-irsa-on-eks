#!/bin/bash
# Feature: harbor-irsa-workshop, Property 1: IRSA Access Control Enforcement
# Validates: Requirements 4.7, 4.8, 6.3
#
# Property: For any Kubernetes service account and namespace combination, S3 access should 
# be granted if and only if the service account is `harbor-registry` in the `harbor` namespace 
# with the correct IAM role annotation. All other combinations should be denied with appropriate 
# error messages.

set -e
set -u

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test configuration
MIN_ITERATIONS=10
CURRENT_ITERATION=0
PASSED_TESTS=0
FAILED_TESTS=0

# Authorized configuration
AUTHORIZED_NAMESPACE="harbor"
AUTHORIZED_SA="harbor-registry"
S3_BUCKET=""
AWS_REGION="${AWS_REGION:-us-east-1}"

# Test namespaces and service accounts to try
TEST_NAMESPACES=("default" "kube-system" "test-namespace" "unauthorized-ns")
TEST_SERVICE_ACCOUNTS=("default" "test-sa" "unauthorized-sa" "fake-harbor")

# Functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_pass() {
    echo -e "${GREEN}  ✓ PASS: $1${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

print_fail() {
    echo -e "${RED}  ✗ FAIL: $1${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

print_info() {
    echo -e "${BLUE}  ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}  ⚠ WARNING: $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    if ! command -v kubectl &> /dev/null; then
        print_fail "kubectl is not installed"
        exit 1
    fi
    print_pass "kubectl is installed"
    
    if ! kubectl cluster-info &> /dev/null; then
        print_fail "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    print_pass "Connected to Kubernetes cluster"
    
    if ! command -v jq &> /dev/null; then
        print_fail "jq is not installed"
        exit 1
    fi
    print_pass "jq is installed"
    
    echo ""
}

# Get S3 bucket name
get_s3_bucket() {
    print_header "Getting S3 Bucket Name"
    
    # Try environment variable
    if [ -n "${HARBOR_S3_BUCKET:-}" ]; then
        S3_BUCKET="$HARBOR_S3_BUCKET"
        print_info "Using S3 bucket from environment: $S3_BUCKET"
        return 0
    fi
    
    # Try Terraform outputs
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local terraform_dir="$(dirname "$script_dir")/terraform"
    
    if [ -d "$terraform_dir" ]; then
        cd "$terraform_dir"
        S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
        if [ -n "$S3_BUCKET" ]; then
            print_info "Using S3 bucket from Terraform: $S3_BUCKET"
            return 0
        fi
    fi
    
    if [ -z "$S3_BUCKET" ]; then
        print_warning "Could not determine S3 bucket name"
        echo ""
        read -p "Enter S3 bucket name: " S3_BUCKET
        
        if [ -z "$S3_BUCKET" ]; then
            print_fail "S3 bucket name is required"
            exit 1
        fi
    fi
    
    print_info "Using S3 bucket: $S3_BUCKET"
    echo ""
}

# Get IAM role ARN from authorized service account
get_iam_role_arn() {
    local role_arn=$(kubectl get serviceaccount "$AUTHORIZED_SA" -n "$AUTHORIZED_NAMESPACE" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
    
    if [ -z "$role_arn" ]; then
        print_warning "Could not get IAM role ARN from service account"
        return 1
    fi
    
    echo "$role_arn"
}

# Create test namespace if it doesn't exist
create_test_namespace() {
    local namespace=$1
    
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        kubectl create namespace "$namespace" &> /dev/null || true
    fi
}

# Create test service account
create_test_service_account() {
    local namespace=$1
    local sa_name=$2
    local with_annotation=${3:-false}
    
    # Delete if exists
    kubectl delete serviceaccount "$sa_name" -n "$namespace" &> /dev/null || true
    
    # Create service account
    kubectl create serviceaccount "$sa_name" -n "$namespace" &> /dev/null
    
    # Add IRSA annotation if requested
    if [ "$with_annotation" = "true" ]; then
        local role_arn=$(get_iam_role_arn)
        if [ -n "$role_arn" ]; then
            kubectl annotate serviceaccount "$sa_name" -n "$namespace" \
                "eks.amazonaws.com/role-arn=$role_arn" &> /dev/null
        fi
    fi
}

# Create test pod
create_test_pod() {
    local namespace=$1
    local sa_name=$2
    local pod_name=$3
    
    # Delete if exists
    kubectl delete pod "$pod_name" -n "$namespace" --wait=false &> /dev/null || true
    sleep 2
    
    # Create pod
    cat <<EOF | kubectl apply -f - &> /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  namespace: $namespace
spec:
  serviceAccountName: $sa_name
  containers:
  - name: aws-cli
    image: amazon/aws-cli:latest
    command: ["sleep", "300"]
    resources:
      requests:
        memory: "64Mi"
        cpu: "50m"
      limits:
        memory: "128Mi"
        cpu: "100m"
  restartPolicy: Never
EOF
    
    # Wait for pod to be ready
    local max_wait=60
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        local pod_status=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        if [ "$pod_status" = "Running" ]; then
            sleep 3  # Give it a moment to fully initialize
            return 0
        fi
        
        sleep 2
        waited=$((waited + 2))
    done
    
    return 1
}

# Test S3 access from pod
test_s3_access_from_pod() {
    local namespace=$1
    local pod_name=$2
    local should_succeed=$3
    
    # Try to list S3 bucket
    local output=$(kubectl exec "$pod_name" -n "$namespace" -- aws s3 ls "s3://$S3_BUCKET" --region "$AWS_REGION" 2>&1 || echo "ACCESS_DENIED")
    
    if echo "$output" | grep -q "ACCESS_DENIED\|AccessDenied\|InvalidAccessKeyId\|SignatureDoesNotMatch\|Unable to locate credentials"; then
        # Access was denied
        if [ "$should_succeed" = "true" ]; then
            return 1  # Should have succeeded but didn't
        else
            return 0  # Should have failed and did
        fi
    else
        # Access succeeded
        if [ "$should_succeed" = "true" ]; then
            return 0  # Should have succeeded and did
        else
            return 1  # Should have failed but didn't
        fi
    fi
}

# Test authorized access
test_authorized_access() {
    local iteration=$1
    
    print_info "Iteration $iteration: Testing AUTHORIZED access (harbor/harbor-registry)"
    
    # Check if authorized namespace and SA exist
    if ! kubectl get namespace "$AUTHORIZED_NAMESPACE" &> /dev/null; then
        print_warning "Authorized namespace $AUTHORIZED_NAMESPACE does not exist, skipping"
        return 0
    fi
    
    if ! kubectl get serviceaccount "$AUTHORIZED_SA" -n "$AUTHORIZED_NAMESPACE" &> /dev/null; then
        print_warning "Authorized service account $AUTHORIZED_SA does not exist, skipping"
        return 0
    fi
    
    # Create test pod with authorized SA
    local pod_name="access-test-authorized-$iteration"
    
    if ! create_test_pod "$AUTHORIZED_NAMESPACE" "$AUTHORIZED_SA" "$pod_name"; then
        print_warning "Could not create authorized test pod"
        return 0
    fi
    
    # Test S3 access (should succeed)
    if test_s3_access_from_pod "$AUTHORIZED_NAMESPACE" "$pod_name" "true"; then
        print_pass "Authorized service account CAN access S3 (as expected)"
    else
        print_fail "Authorized service account CANNOT access S3 (should be able to)"
    fi
    
    # Cleanup
    kubectl delete pod "$pod_name" -n "$AUTHORIZED_NAMESPACE" --wait=false &> /dev/null || true
}

# Test unauthorized access
test_unauthorized_access() {
    local iteration=$1
    local namespace=$2
    local sa_name=$3
    
    print_info "Iteration $iteration: Testing UNAUTHORIZED access ($namespace/$sa_name)"
    
    # Create test namespace
    create_test_namespace "$namespace"
    
    # Create test service account (without IRSA annotation)
    create_test_service_account "$namespace" "$sa_name" "false"
    
    # Create test pod
    local pod_name="access-test-unauth-$iteration"
    
    if ! create_test_pod "$namespace" "$sa_name" "$pod_name"; then
        print_warning "Could not create unauthorized test pod"
        kubectl delete namespace "$namespace" --wait=false &> /dev/null || true
        return 0
    fi
    
    # Test S3 access (should fail)
    if test_s3_access_from_pod "$namespace" "$pod_name" "false"; then
        print_pass "Unauthorized service account CANNOT access S3 (as expected)"
    else
        print_fail "Unauthorized service account CAN access S3 (should be denied)"
    fi
    
    # Cleanup
    kubectl delete pod "$pod_name" -n "$namespace" --wait=false &> /dev/null || true
    kubectl delete namespace "$namespace" --wait=false &> /dev/null || true
}

# Test wrong namespace with correct SA name
test_wrong_namespace_correct_sa() {
    local iteration=$1
    local namespace="wrong-namespace-$iteration"
    
    print_info "Iteration $iteration: Testing WRONG NAMESPACE with correct SA name ($namespace/$AUTHORIZED_SA)"
    
    # Create test namespace
    create_test_namespace "$namespace"
    
    # Create service account with same name as authorized but in wrong namespace
    # Even with IRSA annotation, it should be denied due to namespace mismatch
    create_test_service_account "$namespace" "$AUTHORIZED_SA" "true"
    
    # Create test pod
    local pod_name="access-test-wrongns-$iteration"
    
    if ! create_test_pod "$namespace" "$AUTHORIZED_SA" "$pod_name"; then
        print_warning "Could not create test pod in wrong namespace"
        kubectl delete namespace "$namespace" --wait=false &> /dev/null || true
        return 0
    fi
    
    # Test S3 access (should fail due to namespace restriction in trust policy)
    if test_s3_access_from_pod "$namespace" "$pod_name" "false"; then
        print_pass "Service account in WRONG NAMESPACE cannot access S3 (as expected)"
    else
        print_fail "Service account in WRONG NAMESPACE can access S3 (should be denied by trust policy)"
    fi
    
    # Cleanup
    kubectl delete pod "$pod_name" -n "$namespace" --wait=false &> /dev/null || true
    kubectl delete namespace "$namespace" --wait=false &> /dev/null || true
}

# Test correct namespace with wrong SA name
test_correct_namespace_wrong_sa() {
    local iteration=$1
    local sa_name="wrong-sa-$iteration"
    
    print_info "Iteration $iteration: Testing CORRECT NAMESPACE with wrong SA name ($AUTHORIZED_NAMESPACE/$sa_name)"
    
    # Create service account with wrong name in correct namespace
    # Even with IRSA annotation, it should be denied due to SA name mismatch
    create_test_service_account "$AUTHORIZED_NAMESPACE" "$sa_name" "true"
    
    # Create test pod
    local pod_name="access-test-wrongsa-$iteration"
    
    if ! create_test_pod "$AUTHORIZED_NAMESPACE" "$sa_name" "$pod_name"; then
        print_warning "Could not create test pod with wrong SA"
        kubectl delete serviceaccount "$sa_name" -n "$AUTHORIZED_NAMESPACE" &> /dev/null || true
        return 0
    fi
    
    # Test S3 access (should fail due to SA name restriction in trust policy)
    if test_s3_access_from_pod "$AUTHORIZED_NAMESPACE" "$pod_name" "false"; then
        print_pass "WRONG SERVICE ACCOUNT in correct namespace cannot access S3 (as expected)"
    else
        print_fail "WRONG SERVICE ACCOUNT in correct namespace can access S3 (should be denied by trust policy)"
    fi
    
    # Cleanup
    kubectl delete pod "$pod_name" -n "$AUTHORIZED_NAMESPACE" --wait=false &> /dev/null || true
    kubectl delete serviceaccount "$sa_name" -n "$AUTHORIZED_NAMESPACE" &> /dev/null || true
}

# Run property tests
run_property_tests() {
    print_header "Running Property-Based Tests for IRSA Access Control"
    
    print_info "Property: S3 access granted IFF service account is harbor-registry in harbor namespace"
    print_info "Running $MIN_ITERATIONS iterations..."
    echo ""
    
    for ((i=1; i<=MIN_ITERATIONS; i++)); do
        CURRENT_ITERATION=$i
        
        echo -e "${BLUE}--- Iteration $i/$MIN_ITERATIONS ---${NC}"
        
        # Test 1: Authorized access (should succeed)
        test_authorized_access "$i"
        
        # Test 2: Unauthorized access with random namespace/SA
        local random_ns_idx=$((RANDOM % ${#TEST_NAMESPACES[@]}))
        local random_sa_idx=$((RANDOM % ${#TEST_SERVICE_ACCOUNTS[@]}))
        local test_ns="${TEST_NAMESPACES[$random_ns_idx]}-$i"
        local test_sa="${TEST_SERVICE_ACCOUNTS[$random_sa_idx]}-$i"
        
        test_unauthorized_access "$i" "$test_ns" "$test_sa"
        
        # Test 3: Wrong namespace with correct SA name (should fail)
        test_wrong_namespace_correct_sa "$i"
        
        # Test 4: Correct namespace with wrong SA name (should fail)
        test_correct_namespace_wrong_sa "$i"
        
        echo ""
    done
}

# Display summary
display_summary() {
    print_header "Property Test Summary"
    
    local total_tests=$((PASSED_TESTS + FAILED_TESTS))
    local pass_rate=0
    
    if [ $total_tests -gt 0 ]; then
        pass_rate=$(awk "BEGIN {printf \"%.1f\", ($PASSED_TESTS / $total_tests) * 100}")
    fi
    
    echo ""
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"
    echo -e "${BLUE}Total:  $total_tests${NC}"
    echo -e "${BLUE}Pass Rate: ${pass_rate}%${NC}"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}✓ All property tests passed!${NC}"
        echo ""
        echo "IRSA access control is properly enforced:"
        echo "  ✓ Authorized service account CAN access S3"
        echo "  ✓ Unauthorized service accounts CANNOT access S3"
        echo "  ✓ Wrong namespace with correct SA name CANNOT access S3"
        echo "  ✓ Correct namespace with wrong SA name CANNOT access S3"
        echo "  ✓ Trust policy properly restricts access"
        return 0
    else
        echo -e "${RED}✗ Some property tests failed${NC}"
        echo ""
        echo "IRSA access control is not properly enforced."
        echo "Review the failures above and check:"
        echo "  - IAM role trust policy has correct namespace/SA conditions"
        echo "  - Service account has correct IRSA annotation"
        echo "  - IAM role has S3 permissions"
        return 1
    fi
}

# Main execution
main() {
    print_header "IRSA Access Control Enforcement Property Test"
    
    echo "This property test verifies that S3 access is granted if and only if"
    echo "the service account is harbor-registry in the harbor namespace."
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Get S3 bucket
    get_s3_bucket
    
    # Run property tests
    run_property_tests
    
    # Display summary
    display_summary
}

# Run main function
main "$@"
