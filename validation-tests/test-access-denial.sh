#!/bin/bash
# Access Denial Test
# Validates: Requirements 4.8
#
# This test creates unauthorized service accounts and attempts S3 access from unauthorized pods.
# It verifies that access is properly denied with appropriate error messages.

set -e
set -u

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test configuration
TEST_NAMESPACE="access-denial-test"
UNAUTHORIZED_SA="unauthorized-sa"
TEST_POD_NAME="unauthorized-pod"
S3_BUCKET=""
AWS_REGION="${AWS_REGION:-us-east-1}"

# Test results
PASSED_TESTS=0
FAILED_TESTS=0

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

print_expected_denial() {
    echo -e "${GREEN}  ✓ EXPECTED DENIAL: $1${NC}"
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

# Create test namespace
create_test_namespace() {
    print_header "Creating Test Namespace"
    
    if kubectl get namespace "$TEST_NAMESPACE" &> /dev/null; then
        print_info "Test namespace already exists, deleting..."
        kubectl delete namespace "$TEST_NAMESPACE" --wait=false &> /dev/null || true
        sleep 5
    fi
    
    print_info "Creating namespace: $TEST_NAMESPACE"
    kubectl create namespace "$TEST_NAMESPACE" &> /dev/null
    print_pass "Test namespace created"
    echo ""
}

# Create unauthorized service account (no IRSA annotation)
create_unauthorized_service_account() {
    print_header "Creating Unauthorized Service Account"
    
    print_info "Creating service account WITHOUT IRSA annotation"
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $UNAUTHORIZED_SA
  namespace: $TEST_NAMESPACE
EOF
    
    print_pass "Unauthorized service account created"
    print_info "Service account: $TEST_NAMESPACE/$UNAUTHORIZED_SA"
    print_info "IRSA annotation: NONE (this is intentional for testing)"
    echo ""
}

# Create test pod with unauthorized service account
create_unauthorized_pod() {
    print_header "Creating Unauthorized Pod"
    
    print_info "Creating pod with unauthorized service account"
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $TEST_POD_NAME
  namespace: $TEST_NAMESPACE
spec:
  serviceAccountName: $UNAUTHORIZED_SA
  containers:
  - name: aws-cli
    image: amazon/aws-cli:latest
    command: ["sleep", "600"]
    resources:
      requests:
        memory: "64Mi"
        cpu: "50m"
      limits:
        memory: "128Mi"
        cpu: "100m"
  restartPolicy: Never
EOF
    
    print_pass "Unauthorized pod created"
    
    # Wait for pod to be ready
    print_info "Waiting for pod to be ready..."
    local max_wait=60
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        local pod_status=$(kubectl get pod "$TEST_POD_NAME" -n "$TEST_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        if [ "$pod_status" = "Running" ]; then
            print_pass "Pod is running"
            sleep 3
            echo ""
            return 0
        fi
        
        sleep 2
        waited=$((waited + 2))
    done
    
    print_fail "Pod did not become ready within $max_wait seconds"
    kubectl get pod "$TEST_POD_NAME" -n "$TEST_NAMESPACE"
    exit 1
}

# Test 1: Attempt to get AWS caller identity (should fail)
test_caller_identity_denial() {
    print_header "Test 1: AWS Caller Identity (Should Be Denied)"
    
    print_info "Attempting to get AWS caller identity from unauthorized pod..."
    
    local output=$(kubectl exec "$TEST_POD_NAME" -n "$TEST_NAMESPACE" -- aws sts get-caller-identity 2>&1 || echo "FAILED")
    
    if echo "$output" | grep -q "Unable to locate credentials\|InvalidClientTokenId\|AccessDenied\|FAILED"; then
        print_expected_denial "AWS caller identity request was denied (as expected)"
        print_pass "Unauthorized pod cannot get AWS credentials"
        
        # Show the error message
        print_info "Error message:"
        echo "$output" | head -5 | sed 's/^/    /'
    else
        print_fail "Unauthorized pod was able to get AWS credentials (SECURITY ISSUE)"
        echo "$output"
    fi
    
    echo ""
}

# Test 2: Attempt to list S3 bucket (should fail)
test_s3_list_denial() {
    print_header "Test 2: S3 Bucket List (Should Be Denied)"
    
    print_info "Attempting to list S3 bucket from unauthorized pod..."
    
    local output=$(kubectl exec "$TEST_POD_NAME" -n "$TEST_NAMESPACE" -- aws s3 ls "s3://$S3_BUCKET" --region "$AWS_REGION" 2>&1 || echo "FAILED")
    
    if echo "$output" | grep -q "Unable to locate credentials\|InvalidAccessKeyId\|AccessDenied\|FAILED"; then
        print_expected_denial "S3 list request was denied (as expected)"
        print_pass "Unauthorized pod cannot list S3 bucket"
        
        # Show the error message
        print_info "Error message:"
        echo "$output" | head -5 | sed 's/^/    /'
    else
        print_fail "Unauthorized pod was able to list S3 bucket (SECURITY ISSUE)"
        echo "$output"
    fi
    
    echo ""
}

# Test 3: Attempt to write to S3 bucket (should fail)
test_s3_write_denial() {
    print_header "Test 3: S3 Bucket Write (Should Be Denied)"
    
    print_info "Attempting to write to S3 bucket from unauthorized pod..."
    
    local test_file="unauthorized-test-$(date +%s).txt"
    local output=$(kubectl exec "$TEST_POD_NAME" -n "$TEST_NAMESPACE" -- sh -c "echo 'test' | aws s3 cp - s3://$S3_BUCKET/$test_file --region $AWS_REGION" 2>&1 || echo "FAILED")
    
    if echo "$output" | grep -q "Unable to locate credentials\|InvalidAccessKeyId\|AccessDenied\|FAILED"; then
        print_expected_denial "S3 write request was denied (as expected)"
        print_pass "Unauthorized pod cannot write to S3 bucket"
        
        # Show the error message
        print_info "Error message:"
        echo "$output" | head -5 | sed 's/^/    /'
    else
        print_fail "Unauthorized pod was able to write to S3 bucket (SECURITY ISSUE)"
        echo "$output"
    fi
    
    echo ""
}

# Test 4: Verify no AWS credentials in environment
test_no_credentials_in_environment() {
    print_header "Test 4: No AWS Credentials in Environment"
    
    print_info "Checking pod environment for AWS credentials..."
    
    local env_vars=$(kubectl exec "$TEST_POD_NAME" -n "$TEST_NAMESPACE" -- env 2>/dev/null || echo "")
    
    local has_access_key=false
    local has_secret_key=false
    
    if echo "$env_vars" | grep -q "AWS_ACCESS_KEY_ID=AKIA"; then
        print_fail "Pod has AWS_ACCESS_KEY_ID environment variable"
        has_access_key=true
    else
        print_pass "No AWS_ACCESS_KEY_ID in environment"
    fi
    
    if echo "$env_vars" | grep -q "AWS_SECRET_ACCESS_KEY="; then
        print_fail "Pod has AWS_SECRET_ACCESS_KEY environment variable"
        has_secret_key=true
    else
        print_pass "No AWS_SECRET_ACCESS_KEY in environment"
    fi
    
    if [ "$has_access_key" = false ] && [ "$has_secret_key" = false ]; then
        print_pass "Pod has no AWS credentials in environment (as expected)"
    fi
    
    echo ""
}

# Test 5: Verify service account has no IRSA annotation
test_no_irsa_annotation() {
    print_header "Test 5: No IRSA Annotation on Service Account"
    
    print_info "Checking service account for IRSA annotation..."
    
    local role_arn=$(kubectl get serviceaccount "$UNAUTHORIZED_SA" -n "$TEST_NAMESPACE" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
    
    if [ -z "$role_arn" ]; then
        print_pass "Service account has no IRSA annotation (as expected)"
        print_info "This is why AWS access is denied"
    else
        print_fail "Service account has IRSA annotation: $role_arn"
        print_warning "This test setup is incorrect"
    fi
    
    echo ""
}

# Test 6: Verify error messages are informative
test_error_message_quality() {
    print_header "Test 6: Error Message Quality"
    
    print_info "Verifying error messages are informative..."
    
    local output=$(kubectl exec "$TEST_POD_NAME" -n "$TEST_NAMESPACE" -- aws sts get-caller-identity 2>&1 || echo "")
    
    if echo "$output" | grep -q "Unable to locate credentials"; then
        print_pass "Error message clearly indicates credential issue"
        print_info "Message: 'Unable to locate credentials'"
    elif echo "$output" | grep -q "InvalidClientTokenId\|AccessDenied"; then
        print_pass "Error message indicates access denial"
    else
        print_warning "Error message may not be clear enough"
        echo "$output" | head -3
    fi
    
    echo ""
}

# Test 7: Attempt access from default service account
test_default_service_account_denial() {
    print_header "Test 7: Default Service Account (Should Be Denied)"
    
    print_info "Creating pod with default service account..."
    
    local default_pod="default-sa-test-pod"
    
    cat <<EOF | kubectl apply -f - &> /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $default_pod
  namespace: $TEST_NAMESPACE
spec:
  serviceAccountName: default
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
    
    # Wait for pod
    local max_wait=30
    local waited=0
    while [ $waited -lt $max_wait ]; do
        local pod_status=$(kubectl get pod "$default_pod" -n "$TEST_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$pod_status" = "Running" ]; then
            break
        fi
        sleep 2
        waited=$((waited + 2))
    done
    
    # Test S3 access
    local output=$(kubectl exec "$default_pod" -n "$TEST_NAMESPACE" -- aws s3 ls "s3://$S3_BUCKET" --region "$AWS_REGION" 2>&1 || echo "FAILED")
    
    if echo "$output" | grep -q "Unable to locate credentials\|InvalidAccessKeyId\|AccessDenied\|FAILED"; then
        print_expected_denial "Default service account cannot access S3 (as expected)"
        print_pass "Default service account is properly restricted"
    else
        print_fail "Default service account can access S3 (SECURITY ISSUE)"
    fi
    
    # Cleanup
    kubectl delete pod "$default_pod" -n "$TEST_NAMESPACE" --wait=false &> /dev/null || true
    
    echo ""
}

# Cleanup test resources
cleanup_test_resources() {
    print_header "Cleanup"
    
    print_info "Deleting test namespace and all resources..."
    
    if kubectl get namespace "$TEST_NAMESPACE" &> /dev/null; then
        kubectl delete namespace "$TEST_NAMESPACE" --wait=false &> /dev/null || true
        print_pass "Test namespace deleted"
    else
        print_info "Test namespace already deleted"
    fi
    
    echo ""
}

# Display summary
display_summary() {
    print_header "Test Summary"
    
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
        echo -e "${GREEN}✓ All access denial tests passed!${NC}"
        echo ""
        echo "Access control is properly enforced:"
        echo "  ✓ Unauthorized pods cannot get AWS credentials"
        echo "  ✓ Unauthorized pods cannot list S3 bucket"
        echo "  ✓ Unauthorized pods cannot write to S3 bucket"
        echo "  ✓ No AWS credentials in pod environment"
        echo "  ✓ Service accounts without IRSA annotation are denied"
        echo "  ✓ Default service account is properly restricted"
        echo "  ✓ Error messages are informative"
        return 0
    else
        echo -e "${RED}✗ Some access denial tests failed${NC}"
        echo ""
        echo "SECURITY ISSUE: Unauthorized access may be possible!"
        echo "Review the failures above and ensure:"
        echo "  - IAM role trust policy restricts to specific namespace/SA"
        echo "  - Only authorized service accounts have IRSA annotation"
        echo "  - S3 bucket policy enforces proper access control"
        return 1
    fi
}

# Main execution
main() {
    print_header "Access Denial Test"
    
    echo "This test verifies that unauthorized service accounts are properly denied"
    echo "access to S3 resources."
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Get S3 bucket
    get_s3_bucket
    
    # Create test environment
    create_test_namespace
    create_unauthorized_service_account
    create_unauthorized_pod
    
    # Run tests
    test_caller_identity_denial
    test_s3_list_denial
    test_s3_write_denial
    test_no_credentials_in_environment
    test_no_irsa_annotation
    test_error_message_quality
    test_default_service_account_denial
    
    # Cleanup
    if [ "${1:-}" != "--no-cleanup" ]; then
        cleanup_test_resources
    else
        print_info "Skipping cleanup (--no-cleanup flag set)"
        echo ""
    fi
    
    # Display summary
    display_summary
}

# Run main function
main "$@"
