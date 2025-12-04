#!/bin/bash
# Harbor IRSA Workshop - Deployment Validation Script
# This script validates that the infrastructure is correctly deployed

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

# Validation results
PASSED=0
FAILED=0
WARNINGS=0

# Functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_test() {
    echo -e "${BLUE}Testing: $1${NC}"
}

print_pass() {
    echo -e "${GREEN}  ✓ PASS: $1${NC}"
    PASSED=$((PASSED + 1))
}

print_fail() {
    echo -e "${RED}  ✗ FAIL: $1${NC}"
    FAILED=$((FAILED + 1))
}

print_warning() {
    echo -e "${YELLOW}  ⚠ WARNING: $1${NC}"
    WARNINGS=$((WARNINGS + 1))
}

print_info() {
    echo -e "  ${BLUE}ℹ $1${NC}"
}

# Validation tests
validate_eks_cluster() {
    print_header "Validating EKS Cluster"
    
    cd "$TERRAFORM_DIR"
    
    print_test "EKS cluster exists and is accessible"
    if kubectl cluster-info &> /dev/null; then
        print_pass "Cluster is accessible"
    else
        print_fail "Cannot access cluster"
        return 1
    fi
    
    print_test "Cluster nodes are ready"
    local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
    if [ "$ready_nodes" -gt 0 ]; then
        print_pass "$ready_nodes node(s) ready"
    else
        print_fail "No ready nodes found"
    fi
    
    print_test "OIDC provider is configured"
    local oidc_url=$(terraform output -raw oidc_provider_url 2>/dev/null || echo "")
    if [ -n "$oidc_url" ]; then
        print_pass "OIDC provider URL: $oidc_url"
    else
        print_fail "OIDC provider not found"
    fi
}

validate_irsa_configuration() {
    print_header "Validating IRSA Configuration"
    
    cd "$TERRAFORM_DIR"
    
    local namespace=$(terraform output -raw harbor_namespace 2>/dev/null || echo "harbor")
    local sa_name=$(terraform output -raw harbor_service_account 2>/dev/null || echo "harbor-registry")
    
    print_test "Harbor namespace exists"
    if kubectl get namespace "$namespace" &> /dev/null; then
        print_pass "Namespace '$namespace' exists"
    else
        print_fail "Namespace '$namespace' not found"
        return 1
    fi
    
    print_test "Service account exists with IRSA annotation"
    if kubectl get sa -n "$namespace" "$sa_name" &> /dev/null; then
        print_pass "Service account '$sa_name' exists"
        
        local role_arn=$(kubectl get sa -n "$namespace" "$sa_name" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
        if [ -n "$role_arn" ]; then
            print_pass "IRSA annotation present: $role_arn"
        else
            print_fail "IRSA annotation missing"
        fi
    else
        print_fail "Service account '$sa_name' not found"
    fi
    
    print_test "IAM role exists"
    local role_name=$(terraform output -raw harbor_iam_role_name 2>/dev/null || echo "")
    if [ -n "$role_name" ]; then
        if aws iam get-role --role-name "$role_name" &> /dev/null; then
            print_pass "IAM role '$role_name' exists"
        else
            print_fail "IAM role '$role_name' not found"
        fi
    else
        print_warning "Could not determine IAM role name"
    fi
}

validate_s3_kms() {
    print_header "Validating S3 and KMS Configuration"
    
    cd "$TERRAFORM_DIR"
    
    print_test "S3 bucket exists"
    local bucket_name=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    if [ -n "$bucket_name" ]; then
        if aws s3 ls "s3://$bucket_name" &> /dev/null; then
            print_pass "S3 bucket '$bucket_name' exists"
        else
            print_fail "S3 bucket '$bucket_name' not accessible"
        fi
        
        print_test "S3 bucket has versioning enabled"
        local versioning=$(aws s3api get-bucket-versioning --bucket "$bucket_name" --query 'Status' --output text 2>/dev/null || echo "")
        if [ "$versioning" = "Enabled" ]; then
            print_pass "Versioning is enabled"
        else
            print_fail "Versioning is not enabled"
        fi
        
        print_test "S3 bucket has encryption enabled"
        if aws s3api get-bucket-encryption --bucket "$bucket_name" &> /dev/null; then
            print_pass "Encryption is enabled"
        else
            print_fail "Encryption is not enabled"
        fi
        
        print_test "S3 bucket has public access blocked"
        local public_block=$(aws s3api get-public-access-block --bucket "$bucket_name" --query 'PublicAccessBlockConfiguration.BlockPublicAcls' --output text 2>/dev/null || echo "false")
        if [ "$public_block" = "True" ]; then
            print_pass "Public access is blocked"
        else
            print_fail "Public access is not blocked"
        fi
    else
        print_fail "Could not determine S3 bucket name"
    fi
    
    print_test "KMS key exists"
    local kms_key_id=$(terraform output -raw kms_key_id 2>/dev/null || echo "")
    if [ -n "$kms_key_id" ]; then
        if aws kms describe-key --key-id "$kms_key_id" &> /dev/null; then
            print_pass "KMS key exists"
            
            local key_rotation=$(aws kms get-key-rotation-status --key-id "$kms_key_id" --query 'KeyRotationEnabled' --output text 2>/dev/null || echo "false")
            if [ "$key_rotation" = "True" ]; then
                print_pass "Key rotation is enabled"
            else
                print_warning "Key rotation is not enabled"
            fi
        else
            print_fail "KMS key not accessible"
        fi
    else
        print_fail "Could not determine KMS key ID"
    fi
}

validate_harbor_deployment() {
    print_header "Validating Harbor Deployment"
    
    cd "$TERRAFORM_DIR"
    
    local namespace=$(terraform output -raw harbor_namespace 2>/dev/null || echo "harbor")
    
    print_test "Harbor pods are running"
    local running_pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local total_pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$total_pods" -gt 0 ]; then
        if [ "$running_pods" -eq "$total_pods" ]; then
            print_pass "All Harbor pods are running ($running_pods/$total_pods)"
        else
            print_warning "$running_pods/$total_pods pods are running"
            print_info "Run 'kubectl get pods -n $namespace' for details"
        fi
    else
        print_fail "No Harbor pods found"
    fi
    
    print_test "Harbor services are created"
    local services=$(kubectl get svc -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$services" -gt 0 ]; then
        print_pass "$services Harbor service(s) created"
    else
        print_fail "No Harbor services found"
    fi
    
    print_test "Harbor LoadBalancer has external IP"
    local release_name=$(terraform output -raw harbor_release_name 2>/dev/null || echo "harbor")
    local lb_hostname=$(kubectl get svc -n "$namespace" "${release_name}-portal" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    if [ -n "$lb_hostname" ] && [ "$lb_hostname" != "null" ]; then
        print_pass "LoadBalancer hostname: $lb_hostname"
    else
        print_warning "LoadBalancer hostname not yet assigned (may take a few minutes)"
    fi
}

validate_no_static_credentials() {
    print_header "Validating No Static Credentials"
    
    cd "$TERRAFORM_DIR"
    
    local namespace=$(terraform output -raw harbor_namespace 2>/dev/null || echo "harbor")
    
    print_test "Harbor pods do not have AWS credential environment variables"
    
    local pods=$(kubectl get pods -n "$namespace" -o name 2>/dev/null | grep "harbor" || echo "")
    
    if [ -z "$pods" ]; then
        print_warning "No Harbor pods found to check"
        return 0
    fi
    
    local found_credentials=false
    
    for pod in $pods; do
        local env_vars=$(kubectl get "$pod" -n "$namespace" -o jsonpath='{.spec.containers[*].env[*].name}' 2>/dev/null || echo "")
        
        if echo "$env_vars" | grep -q "AWS_ACCESS_KEY_ID\|AWS_SECRET_ACCESS_KEY"; then
            print_fail "Found AWS credentials in $pod"
            found_credentials=true
        fi
    done
    
    if [ "$found_credentials" = false ]; then
        print_pass "No static AWS credentials found in pod specifications"
    fi
}

validate_s3_access() {
    print_header "Validating S3 Access from Harbor"
    
    cd "$TERRAFORM_DIR"
    
    local namespace=$(terraform output -raw harbor_namespace 2>/dev/null || echo "harbor")
    local bucket_name=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    
    print_test "Harbor can access S3 bucket"
    
    # Find a Harbor registry pod
    local registry_pod=$(kubectl get pods -n "$namespace" -l component=registry -o name 2>/dev/null | head -1 || echo "")
    
    if [ -z "$registry_pod" ]; then
        print_warning "No Harbor registry pod found to test S3 access"
        return 0
    fi
    
    print_info "Testing S3 access from $registry_pod"
    
    # Check if AWS CLI is available in the pod (it may not be)
    if kubectl exec -n "$namespace" "$registry_pod" -- which aws &> /dev/null; then
        if kubectl exec -n "$namespace" "$registry_pod" -- aws s3 ls "s3://$bucket_name" &> /dev/null; then
            print_pass "Harbor pod can access S3 bucket via IRSA"
        else
            print_warning "Could not verify S3 access (may require Harbor to be fully initialized)"
        fi
    else
        print_info "AWS CLI not available in pod (this is normal)"
        print_info "S3 access will be validated when Harbor stores images"
    fi
}

display_summary() {
    print_header "Validation Summary"
    
    echo ""
    echo -e "${GREEN}Passed:   $PASSED${NC}"
    echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
    echo -e "${RED}Failed:   $FAILED${NC}"
    echo ""
    
    if [ $FAILED -eq 0 ]; then
        if [ $WARNINGS -eq 0 ]; then
            echo -e "${GREEN}✓ All validations passed!${NC}"
            echo ""
            echo "Your Harbor IRSA workshop infrastructure is correctly configured."
        else
            echo -e "${YELLOW}⚠ Validations passed with warnings${NC}"
            echo ""
            echo "Review the warnings above. Some may resolve automatically as resources initialize."
        fi
    else
        echo -e "${RED}✗ Some validations failed${NC}"
        echo ""
        echo "Please review the failures above and check your infrastructure."
        return 1
    fi
}

# Main execution
main() {
    print_header "Harbor IRSA Workshop - Deployment Validation"
    
    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}kubectl is not installed${NC}"
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}AWS CLI is not installed${NC}"
        exit 1
    fi
    
    if [ ! -d "$TERRAFORM_DIR" ]; then
        echo -e "${RED}Terraform directory not found${NC}"
        exit 1
    fi
    
    # Run validations
    validate_eks_cluster
    validate_irsa_configuration
    validate_s3_kms
    validate_harbor_deployment
    validate_no_static_credentials
    validate_s3_access
    
    # Display summary
    display_summary
}

# Run main function
main "$@"
