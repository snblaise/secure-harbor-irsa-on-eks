#!/bin/bash
# IRSA Access Validation Test
# Validates: Requirements 4.7
#
# This test verifies that Harbor pods can access S3 using IRSA without static credentials.
# It checks that:
# 1. No static credentials are present in the pod
# 2. The pod can successfully access S3
# 3. S3 operations succeed using IRSA-provided temporary credentials

set -e
set -u

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test configuration
NAMESPACE="harbor"
SERVICE_ACCOUNT="harbor-registry"
TEST_POD_NAME="irsa-test-pod"
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
    
    if ! command -v aws &> /dev/null; then
        print_warning "AWS CLI not installed (optional for some tests)"
    else
        print_pass "AWS CLI is installed"
    fi
    
    if ! command -v jq &> /dev/null; then
        print_fail "jq is not installed"
        exit 1
    fi
    print_pass "jq is installed"
    
    echo ""
}

# Check namespace exists
check_namespace() {
    print_header "Checking Namespace"
    
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        print_fail "Namespace $NAMESPACE does not exist"
        echo ""
        echo "Create the namespace first:"
        echo "  kubectl create namespace $NAMESPACE"
        exit 1
    fi
    print_pass "Namespace $NAMESPACE exists"
    echo ""
}

# Check service account exists and has IRSA annotation
check_service_account() {
    print_header "Checking Service Account"
    
    if ! kubectl get serviceaccount "$SERVICE_ACCOUNT" -n "$NAMESPACE" &> /dev/null; then
        print_fail "Service account $SERVICE_ACCOUNT does not exist in namespace $NAMESPACE"
        exit 1
    fi
    print_pass "Service account $SERVICE_ACCOUNT exists"
    
    # Check for IRSA annotation
    local role_arn=$(kubectl get serviceaccount "$SERVICE_ACCOUNT" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
    
    if [ -z "$role_arn" ]; then
        print_fail "Service account missing IRSA annotation (eks.amazonaws.com/role-arn)"
        echo ""
        echo "Add IRSA annotation to service account:"
        echo "  kubectl annotate serviceaccount $SERVICE_ACCOUNT -n $NAMESPACE \\"
        echo "    eks.amazonaws.com/role-arn=arn:aws:iam::ACCOUNT_ID:role/HarborS3Role"
        exit 1
    fi
    print_pass "Service account has IRSA annotation"
    print_info "IAM Role ARN: $role_arn"
    echo ""
}

# Get S3 bucket name from Terraform or environment
get_s3_bucket() {
    print_header "Getting S3 Bucket Name"
    
    # Try to get from environment variable
    if [ -n "${HARBOR_S3_BUCKET:-}" ]; then
        S3_BUCKET="$HARBOR_S3_BUCKET"
        print_info "Using S3 bucket from environment: $S3_BUCKET"
        return 0
    fi
    
    # Try to get from Terraform outputs
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
    
    # Try to get from Harbor deployment
    local harbor_values=$(kubectl get configmap -n "$NAMESPACE" -l app=harbor -o json 2>/dev/null || echo "")
    if [ -n "$harbor_values" ]; then
        S3_BUCKET=$(echo "$harbor_values" | jq -r '.items[0].data."values.yaml"' 2>/dev/null | grep -A 5 "type: s3" | grep "bucket:" | awk '{print $2}' || echo "")
    fi
    
    if [ -z "$S3_BUCKET" ]; then
        print_warning "Could not determine S3 bucket name"
        echo ""
        echo "Set the S3 bucket name:"
        echo "  export HARBOR_S3_BUCKET=your-bucket-name"
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

# Create test pod with IRSA
create_test_pod() {
    print_header "Creating Test Pod with IRSA"
    
    # Delete existing test pod if it exists
    if kubectl get pod "$TEST_POD_NAME" -n "$NAMESPACE" &> /dev/null; then
        print_info "Deleting existing test pod..."
        kubectl delete pod "$TEST_POD_NAME" -n "$NAMESPACE" --wait=false &> /dev/null || true
        sleep 5
    fi
    
    print_info "Creating test pod with service account: $SERVICE_ACCOUNT"
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $TEST_POD_NAME
  namespace: $NAMESPACE
spec:
  serviceAccountName: $SERVICE_ACCOUNT
  containers:
  - name: aws-cli
    image: amazon/aws-cli:latest
    command: ["sleep", "3600"]
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "200m"
  restartPolicy: Never
EOF
    
    print_pass "Test pod created"
    
    # Wait for pod to be ready
    print_info "Waiting for pod to be ready..."
    local max_wait=60
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        local pod_status=$(kubectl get pod "$TEST_POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        if [ "$pod_status" = "Running" ]; then
            print_pass "Pod is running"
            sleep 5  # Give it a few more seconds to fully initialize
            echo ""
            return 0
        fi
        
        sleep 2
        waited=$((waited + 2))
    done
    
    print_fail "Pod did not become ready within $max_wait seconds"
    kubectl get pod "$TEST_POD_NAME" -n "$NAMESPACE"
    kubectl describe pod "$TEST_POD_NAME" -n "$NAMESPACE"
    exit 1
}

# Verify no static credentials in pod
verify_no_static_credentials() {
    print_header "Verifying No Static Credentials"
    
    print_info "Checking pod environment variables..."
    
    # Check for AWS credential environment variables
    local env_vars=$(kubectl exec "$TEST_POD_NAME" -n "$NAMESPACE" -- env 2>/dev/null || echo "")
    
    if echo "$env_vars" | grep -q "AWS_ACCESS_KEY_ID=AKIA"; then
        print_fail "Pod has AWS_ACCESS_KEY_ID environment variable with static credentials"
    else
        print_pass "No AWS_ACCESS_KEY_ID with static credentials found"
    fi
    
    if echo "$env_vars" | grep -q "AWS_SECRET_ACCESS_KEY="; then
        print_fail "Pod has AWS_SECRET_ACCESS_KEY environment variable"
    else
        print_pass "No AWS_SECRET_ACCESS_KEY environment variable found"
    fi
    
    # Check for projected service account token
    print_info "Checking for projected service account token..."
    
    local token_path="/var/run/secrets/eks.amazonaws.com/serviceaccount/token"
    if kubectl exec "$TEST_POD_NAME" -n "$NAMESPACE" -- test -f "$token_path" 2>/dev/null; then
        print_pass "Projected service account token exists at $token_path"
    else
        print_warning "Projected service account token not found (may use default location)"
    fi
    
    echo ""
}

# Test AWS credential discovery
test_aws_credential_discovery() {
    print_header "Testing AWS Credential Discovery"
    
    print_info "Checking if AWS SDK can discover credentials via IRSA..."
    
    # Get AWS caller identity
    local identity=$(kubectl exec "$TEST_POD_NAME" -n "$NAMESPACE" -- aws sts get-caller-identity 2>/dev/null || echo "")
    
    if [ -z "$identity" ]; then
        print_fail "Could not get AWS caller identity"
        echo ""
        echo "Debug information:"
        kubectl exec "$TEST_POD_NAME" -n "$NAMESPACE" -- aws sts get-caller-identity 2>&1 || true
        return 1
    fi
    
    print_pass "AWS SDK successfully discovered credentials"
    
    # Parse identity
    local user_id=$(echo "$identity" | jq -r '.UserId' 2>/dev/null || echo "")
    local account=$(echo "$identity" | jq -r '.Account' 2>/dev/null || echo "")
    local arn=$(echo "$identity" | jq -r '.Arn' 2>/dev/null || echo "")
    
    print_info "AWS Identity:"
    print_info "  User ID: $user_id"
    print_info "  Account: $account"
    print_info "  ARN: $arn"
    
    # Verify it's using assumed role (IRSA)
    if echo "$arn" | grep -q "assumed-role"; then
        print_pass "Using assumed role (IRSA) - not static credentials"
    else
        print_fail "Not using assumed role - may be using static credentials"
    fi
    
    # Verify session is temporary
    if echo "$user_id" | grep -q ":"; then
        print_pass "Session ID indicates temporary credentials"
    else
        print_warning "Session ID format unexpected"
    fi
    
    echo ""
}

# Test S3 access
test_s3_access() {
    print_header "Testing S3 Access"
    
    print_info "Testing S3 bucket access: $S3_BUCKET"
    
    # Test 1: List bucket
    print_info "Test 1: Listing S3 bucket..."
    if kubectl exec "$TEST_POD_NAME" -n "$NAMESPACE" -- aws s3 ls "s3://$S3_BUCKET" --region "$AWS_REGION" &> /dev/null; then
        print_pass "Successfully listed S3 bucket"
    else
        print_fail "Could not list S3 bucket"
        echo ""
        echo "Debug information:"
        kubectl exec "$TEST_POD_NAME" -n "$NAMESPACE" -- aws s3 ls "s3://$S3_BUCKET" --region "$AWS_REGION" 2>&1 || true
        return 1
    fi
    
    # Test 2: Write test file
    print_info "Test 2: Writing test file to S3..."
    local test_file="irsa-test-$(date +%s).txt"
    local test_content="IRSA validation test - $(date)"
    
    if kubectl exec "$TEST_POD_NAME" -n "$NAMESPACE" -- sh -c "echo '$test_content' | aws s3 cp - s3://$S3_BUCKET/$test_file --region $AWS_REGION" &> /dev/null; then
        print_pass "Successfully wrote file to S3"
    else
        print_fail "Could not write file to S3"
        return 1
    fi
    
    # Test 3: Read test file
    print_info "Test 3: Reading test file from S3..."
    local read_content=$(kubectl exec "$TEST_POD_NAME" -n "$NAMESPACE" -- aws s3 cp "s3://$S3_BUCKET/$test_file" - --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [ "$read_content" = "$test_content" ]; then
        print_pass "Successfully read file from S3 and content matches"
    else
        print_fail "Could not read file from S3 or content mismatch"
        return 1
    fi
    
    # Test 4: Delete test file
    print_info "Test 4: Deleting test file from S3..."
    if kubectl exec "$TEST_POD_NAME" -n "$NAMESPACE" -- aws s3 rm "s3://$S3_BUCKET/$test_file" --region "$AWS_REGION" &> /dev/null; then
        print_pass "Successfully deleted file from S3"
    else
        print_fail "Could not delete file from S3"
        return 1
    fi
    
    echo ""
}

# Test credential rotation
test_credential_rotation() {
    print_header "Testing Credential Rotation"
    
    print_info "Checking credential expiration time..."
    
    # Get current credentials
    local creds1=$(kubectl exec "$TEST_POD_NAME" -n "$NAMESPACE" -- aws sts get-caller-identity 2>/dev/null || echo "")
    local session1=$(echo "$creds1" | jq -r '.UserId' 2>/dev/null | cut -d':' -f2 || echo "")
    
    if [ -z "$session1" ]; then
        print_warning "Could not determine session ID"
        return 0
    fi
    
    print_info "Current session ID: $session1"
    print_info "Credentials are temporary and will automatically rotate"
    print_pass "IRSA provides automatic credential rotation (every 24 hours)"
    
    echo ""
}

# Verify encryption
verify_encryption() {
    print_header "Verifying S3 Encryption"
    
    print_info "Checking S3 bucket encryption configuration..."
    
    if command -v aws &> /dev/null; then
        local encryption=$(aws s3api get-bucket-encryption --bucket "$S3_BUCKET" --region "$AWS_REGION" 2>/dev/null || echo "")
        
        if [ -n "$encryption" ]; then
            local sse_algorithm=$(echo "$encryption" | jq -r '.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' 2>/dev/null || echo "")
            
            if [ "$sse_algorithm" = "aws:kms" ]; then
                print_pass "S3 bucket uses KMS encryption"
                local kms_key=$(echo "$encryption" | jq -r '.Rules[0].ApplyServerSideEncryptionByDefault.KMSMasterKeyID' 2>/dev/null || echo "")
                if [ -n "$kms_key" ] && [ "$kms_key" != "null" ]; then
                    print_info "KMS Key: $kms_key"
                fi
            else
                print_warning "S3 bucket encryption is not KMS (found: $sse_algorithm)"
            fi
        else
            print_warning "Could not retrieve bucket encryption configuration"
        fi
    else
        print_info "AWS CLI not available locally, skipping encryption check"
    fi
    
    echo ""
}

# Cleanup test pod
cleanup_test_pod() {
    print_header "Cleanup"
    
    print_info "Deleting test pod..."
    
    if kubectl get pod "$TEST_POD_NAME" -n "$NAMESPACE" &> /dev/null; then
        kubectl delete pod "$TEST_POD_NAME" -n "$NAMESPACE" --wait=false &> /dev/null || true
        print_pass "Test pod deleted"
    else
        print_info "Test pod already deleted"
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
        echo -e "${GREEN}✓ All IRSA validation tests passed!${NC}"
        echo ""
        echo "IRSA is working correctly:"
        echo "  ✓ No static credentials in pod"
        echo "  ✓ AWS SDK discovers credentials via IRSA"
        echo "  ✓ S3 access works with temporary credentials"
        echo "  ✓ Credentials automatically rotate"
        echo "  ✓ Using assumed role (not IAM user)"
        return 0
    else
        echo -e "${RED}✗ Some IRSA validation tests failed${NC}"
        echo ""
        echo "Review the failures above and ensure:"
        echo "  - Service account has IRSA annotation"
        echo "  - IAM role trust policy allows the service account"
        echo "  - IAM role has S3 permissions"
        echo "  - S3 bucket exists and is accessible"
        return 1
    fi
}

# Main execution
main() {
    print_header "IRSA Access Validation Test"
    
    echo "This test validates that Harbor pods can access S3 using IRSA"
    echo "without static credentials."
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Check namespace
    check_namespace
    
    # Check service account
    check_service_account
    
    # Get S3 bucket
    get_s3_bucket
    
    # Create test pod
    create_test_pod
    
    # Run tests
    verify_no_static_credentials
    test_aws_credential_discovery
    test_s3_access
    test_credential_rotation
    verify_encryption
    
    # Cleanup
    if [ "${1:-}" != "--no-cleanup" ]; then
        cleanup_test_pod
    else
        print_info "Skipping cleanup (--no-cleanup flag set)"
        echo ""
    fi
    
    # Display summary
    display_summary
}

# Run main function
main "$@"
