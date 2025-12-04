#!/bin/bash
# Feature: harbor-irsa-workshop, Property 3: Infrastructure Security Best Practices
# Validates: Requirements 5.6
#
# Property: For any AWS resource created by the workshop infrastructure code (S3 buckets, 
# KMS keys, IAM roles), the resource should have appropriate tags (Environment, Project, 
# ManagedBy), encryption enabled where applicable, and follow AWS security best practices 
# (e.g., S3 bucket public access blocked, KMS key rotation enabled).

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

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

# Required tags
REQUIRED_TAGS=("Project" "Environment" "ManagedBy")

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

# Get resource identifiers from Terraform
get_terraform_outputs() {
    cd "$TERRAFORM_DIR"
    
    S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    KMS_KEY_ID=$(terraform output -raw kms_key_id 2>/dev/null || echo "")
    IAM_ROLE_NAME=$(terraform output -raw harbor_iam_role_name 2>/dev/null || echo "")
    CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
    
    if [ -z "$S3_BUCKET" ] || [ -z "$KMS_KEY_ID" ] || [ -z "$IAM_ROLE_NAME" ]; then
        echo -e "${RED}Error: Could not retrieve resource identifiers from Terraform${NC}"
        echo "Make sure infrastructure is deployed"
        exit 1
    fi
}

# Test S3 bucket properties
test_s3_bucket_properties() {
    local bucket=$1
    local iteration=$2
    
    print_info "Iteration $iteration: Testing S3 bucket: $bucket"
    
    # Test 1: Check required tags
    local tags=$(aws s3api get-bucket-tagging --bucket "$bucket" --output json 2>/dev/null || echo '{"TagSet":[]}')
    local has_all_tags=true
    
    for required_tag in "${REQUIRED_TAGS[@]}"; do
        if ! echo "$tags" | jq -e ".TagSet[] | select(.Key==\"$required_tag\")" > /dev/null 2>&1; then
            print_fail "S3 bucket missing required tag: $required_tag"
            has_all_tags=false
        fi
    done
    
    if [ "$has_all_tags" = true ]; then
        print_pass "S3 bucket has all required tags"
    fi
    
    # Test 2: Check encryption is enabled
    if aws s3api get-bucket-encryption --bucket "$bucket" > /dev/null 2>&1; then
        local encryption_type=$(aws s3api get-bucket-encryption --bucket "$bucket" --query 'Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)
        if [ "$encryption_type" = "aws:kms" ]; then
            print_pass "S3 bucket has KMS encryption enabled"
        else
            print_fail "S3 bucket encryption is not KMS (found: $encryption_type)"
        fi
    else
        print_fail "S3 bucket does not have encryption enabled"
    fi
    
    # Test 3: Check versioning is enabled
    local versioning=$(aws s3api get-bucket-versioning --bucket "$bucket" --query 'Status' --output text 2>/dev/null || echo "")
    if [ "$versioning" = "Enabled" ]; then
        print_pass "S3 bucket has versioning enabled"
    else
        print_fail "S3 bucket versioning is not enabled (status: $versioning)"
    fi
    
    # Test 4: Check public access is blocked
    local public_access=$(aws s3api get-public-access-block --bucket "$bucket" 2>/dev/null || echo "")
    if [ -n "$public_access" ]; then
        local block_public_acls=$(echo "$public_access" | jq -r '.PublicAccessBlockConfiguration.BlockPublicAcls')
        local block_public_policy=$(echo "$public_access" | jq -r '.PublicAccessBlockConfiguration.BlockPublicPolicy')
        local ignore_public_acls=$(echo "$public_access" | jq -r '.PublicAccessBlockConfiguration.IgnorePublicAcls')
        local restrict_public_buckets=$(echo "$public_access" | jq -r '.PublicAccessBlockConfiguration.RestrictPublicBuckets')
        
        if [ "$block_public_acls" = "true" ] && [ "$block_public_policy" = "true" ] && \
           [ "$ignore_public_acls" = "true" ] && [ "$restrict_public_buckets" = "true" ]; then
            print_pass "S3 bucket has all public access blocked"
        else
            print_fail "S3 bucket public access is not fully blocked"
        fi
    else
        print_fail "S3 bucket does not have public access block configuration"
    fi
    
    # Test 5: Check bucket policy enforces encryption
    local bucket_policy=$(aws s3api get-bucket-policy --bucket "$bucket" --query 'Policy' --output text 2>/dev/null || echo "")
    if [ -n "$bucket_policy" ]; then
        if echo "$bucket_policy" | jq -e '.Statement[] | select(.Sid=="DenyUnencryptedObjectUploads")' > /dev/null 2>&1; then
            print_pass "S3 bucket policy enforces encryption"
        else
            print_fail "S3 bucket policy does not enforce encryption"
        fi
        
        if echo "$bucket_policy" | jq -e '.Statement[] | select(.Sid=="DenyInsecureTransport")' > /dev/null 2>&1; then
            print_pass "S3 bucket policy enforces TLS"
        else
            print_fail "S3 bucket policy does not enforce TLS"
        fi
    else
        print_fail "S3 bucket does not have a bucket policy"
    fi
}

# Test KMS key properties
test_kms_key_properties() {
    local key_id=$1
    local iteration=$2
    
    print_info "Iteration $iteration: Testing KMS key: $key_id"
    
    # Test 1: Check key exists and get metadata
    local key_metadata=$(aws kms describe-key --key-id "$key_id" --output json 2>/dev/null || echo "")
    if [ -z "$key_metadata" ]; then
        print_fail "KMS key not found or not accessible"
        return 1
    fi
    
    # Test 2: Check required tags
    local tags=$(aws kms list-resource-tags --key-id "$key_id" --output json 2>/dev/null || echo '{"Tags":[]}')
    local has_all_tags=true
    
    for required_tag in "${REQUIRED_TAGS[@]}"; do
        if ! echo "$tags" | jq -e ".Tags[] | select(.TagKey==\"$required_tag\")" > /dev/null 2>&1; then
            print_fail "KMS key missing required tag: $required_tag"
            has_all_tags=false
        fi
    done
    
    if [ "$has_all_tags" = true ]; then
        print_pass "KMS key has all required tags"
    fi
    
    # Test 3: Check key rotation is enabled
    local rotation_status=$(aws kms get-key-rotation-status --key-id "$key_id" --query 'KeyRotationEnabled' --output text 2>/dev/null || echo "false")
    if [ "$rotation_status" = "True" ]; then
        print_pass "KMS key rotation is enabled"
    else
        print_fail "KMS key rotation is not enabled"
    fi
    
    # Test 4: Check key state is enabled
    local key_state=$(echo "$key_metadata" | jq -r '.KeyMetadata.KeyState')
    if [ "$key_state" = "Enabled" ]; then
        print_pass "KMS key is in Enabled state"
    else
        print_fail "KMS key is not enabled (state: $key_state)"
    fi
    
    # Test 5: Check key is customer managed
    local key_manager=$(echo "$key_metadata" | jq -r '.KeyMetadata.KeyManager')
    if [ "$key_manager" = "CUSTOMER" ]; then
        print_pass "KMS key is customer managed"
    else
        print_fail "KMS key is not customer managed (manager: $key_manager)"
    fi
}

# Test IAM role properties
test_iam_role_properties() {
    local role_name=$1
    local iteration=$2
    
    print_info "Iteration $iteration: Testing IAM role: $role_name"
    
    # Test 1: Check role exists
    local role_info=$(aws iam get-role --role-name "$role_name" --output json 2>/dev/null || echo "")
    if [ -z "$role_info" ]; then
        print_fail "IAM role not found"
        return 1
    fi
    
    # Test 2: Check required tags
    local tags=$(echo "$role_info" | jq -r '.Role.Tags // []')
    local has_all_tags=true
    
    for required_tag in "${REQUIRED_TAGS[@]}"; do
        if ! echo "$tags" | jq -e ".[] | select(.Key==\"$required_tag\")" > /dev/null 2>&1; then
            print_fail "IAM role missing required tag: $required_tag"
            has_all_tags=false
        fi
    done
    
    if [ "$has_all_tags" = true ]; then
        print_pass "IAM role has all required tags"
    fi
    
    # Test 3: Check trust policy uses OIDC provider (IRSA)
    local trust_policy=$(echo "$role_info" | jq -r '.Role.AssumeRolePolicyDocument')
    if echo "$trust_policy" | jq -e '.Statement[] | select(.Action=="sts:AssumeRoleWithWebIdentity")' > /dev/null 2>&1; then
        print_pass "IAM role trust policy uses AssumeRoleWithWebIdentity (IRSA)"
    else
        print_fail "IAM role trust policy does not use IRSA"
    fi
    
    # Test 4: Check trust policy has conditions (namespace/service account restriction)
    if echo "$trust_policy" | jq -e '.Statement[].Condition.StringEquals' > /dev/null 2>&1; then
        print_pass "IAM role trust policy has StringEquals conditions"
    else
        print_fail "IAM role trust policy missing conditions for access restriction"
    fi
    
    # Test 5: Check attached policies follow least privilege
    local attached_policies=$(aws iam list-attached-role-policies --role-name "$role_name" --output json)
    local policy_count=$(echo "$attached_policies" | jq '.AttachedPolicies | length')
    
    if [ "$policy_count" -le 3 ]; then
        print_pass "IAM role has reasonable number of attached policies ($policy_count)"
    else
        print_fail "IAM role has too many attached policies ($policy_count), may not follow least privilege"
    fi
    
    # Test 6: Check for AWS managed policies (should use custom policies)
    local has_aws_managed=false
    while IFS= read -r policy_arn; do
        if [[ "$policy_arn" == *"arn:aws:iam::aws:policy/"* ]] && [[ "$policy_arn" != *"ReadOnly"* ]]; then
            print_fail "IAM role uses AWS managed policy: $policy_arn (should use custom policies)"
            has_aws_managed=true
        fi
    done < <(echo "$attached_policies" | jq -r '.AttachedPolicies[].PolicyArn')
    
    if [ "$has_aws_managed" = false ]; then
        print_pass "IAM role uses custom policies (least privilege)"
    fi
}

# Test EKS cluster properties (if applicable)
test_eks_cluster_properties() {
    local cluster_name=$1
    local iteration=$2
    
    if [ -z "$cluster_name" ]; then
        return 0
    fi
    
    print_info "Iteration $iteration: Testing EKS cluster: $cluster_name"
    
    # Test 1: Check cluster exists
    local cluster_info=$(aws eks describe-cluster --name "$cluster_name" --output json 2>/dev/null || echo "")
    if [ -z "$cluster_info" ]; then
        print_fail "EKS cluster not found"
        return 1
    fi
    
    # Test 2: Check required tags
    local tags=$(echo "$cluster_info" | jq -r '.cluster.tags // {}')
    local has_all_tags=true
    
    for required_tag in "${REQUIRED_TAGS[@]}"; do
        if ! echo "$tags" | jq -e ".[\"$required_tag\"]" > /dev/null 2>&1; then
            print_fail "EKS cluster missing required tag: $required_tag"
            has_all_tags=false
        fi
    done
    
    if [ "$has_all_tags" = true ]; then
        print_pass "EKS cluster has all required tags"
    fi
    
    # Test 3: Check OIDC provider is enabled
    local oidc_issuer=$(echo "$cluster_info" | jq -r '.cluster.identity.oidc.issuer // ""')
    if [ -n "$oidc_issuer" ]; then
        print_pass "EKS cluster has OIDC provider enabled"
    else
        print_fail "EKS cluster does not have OIDC provider enabled"
    fi
    
    # Test 4: Check encryption is enabled
    local encryption_config=$(echo "$cluster_info" | jq -r '.cluster.encryptionConfig // []')
    if [ "$(echo "$encryption_config" | jq 'length')" -gt 0 ]; then
        print_pass "EKS cluster has encryption enabled"
    else
        print_fail "EKS cluster does not have encryption enabled"
    fi
    
    # Test 5: Check logging is enabled
    local logging=$(echo "$cluster_info" | jq -r '.cluster.logging.clusterLogging[0].enabled')
    if [ "$logging" = "true" ]; then
        print_pass "EKS cluster has logging enabled"
    else
        print_fail "EKS cluster does not have logging enabled"
    fi
}

# Run property test iterations
run_property_tests() {
    print_header "Running Property-Based Tests for Infrastructure Best Practices"
    
    print_info "Property: All AWS resources should have required tags, encryption, and security best practices"
    print_info "Running $MIN_ITERATIONS iterations..."
    echo ""
    
    for ((i=1; i<=MIN_ITERATIONS; i++)); do
        CURRENT_ITERATION=$i
        
        echo -e "${BLUE}--- Iteration $i/$MIN_ITERATIONS ---${NC}"
        
        # Test S3 bucket
        test_s3_bucket_properties "$S3_BUCKET" "$i"
        
        # Test KMS key
        test_kms_key_properties "$KMS_KEY_ID" "$i"
        
        # Test IAM role
        test_iam_role_properties "$IAM_ROLE_NAME" "$i"
        
        # Test EKS cluster
        test_eks_cluster_properties "$CLUSTER_NAME" "$i"
        
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
        echo "Infrastructure follows all security best practices:"
        echo "  ✓ All resources have required tags"
        echo "  ✓ Encryption is enabled where applicable"
        echo "  ✓ Public access is blocked"
        echo "  ✓ Least privilege IAM policies"
        echo "  ✓ IRSA is properly configured"
        return 0
    else
        echo -e "${RED}✗ Some property tests failed${NC}"
        echo ""
        echo "Review the failures above and ensure infrastructure follows best practices."
        return 1
    fi
}

# Main execution
main() {
    print_header "Infrastructure Best Practices Property Test"
    
    # Check prerequisites
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}AWS CLI is not installed${NC}"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}jq is not installed${NC}"
        exit 1
    fi
    
    if [ ! -d "$TERRAFORM_DIR" ]; then
        echo -e "${RED}Terraform directory not found${NC}"
        exit 1
    fi
    
    # Get resource identifiers
    get_terraform_outputs
    
    print_info "Testing resources:"
    print_info "  S3 Bucket: $S3_BUCKET"
    print_info "  KMS Key: $KMS_KEY_ID"
    print_info "  IAM Role: $IAM_ROLE_NAME"
    print_info "  EKS Cluster: $CLUSTER_NAME"
    
    # Run tests
    run_property_tests
    
    # Display summary
    display_summary
}

# Run main function
main "$@"
