#!/bin/bash
# Error Scenario Demonstrations
# Validates: Requirements 6.6
#
# This test demonstrates common misconfigurations, shows error messages and logs,
# and provides resolution steps for troubleshooting IRSA deployments.

set -e
set -u

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test configuration
TEST_NAMESPACE="error-scenario-test"
S3_BUCKET=""
AWS_REGION="${AWS_REGION:-us-east-1}"

# Functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_error_scenario() {
    echo -e "${RED}ERROR SCENARIO: $1${NC}"
}

print_resolution() {
    echo -e "${GREEN}RESOLUTION: $1${NC}"
}

print_info() {
    echo -e "${BLUE}  ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}  ⚠ $1${NC}"
}

print_command() {
    echo -e "${BLUE}  $ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}kubectl is not installed${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✓ kubectl is installed${NC}"
    
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✓ Connected to Kubernetes cluster${NC}"
    
    echo ""
}

# Get S3 bucket name
get_s3_bucket() {
    if [ -n "${HARBOR_S3_BUCKET:-}" ]; then
        S3_BUCKET="$HARBOR_S3_BUCKET"
    else
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local terraform_dir="$(dirname "$script_dir")/terraform"
        
        if [ -d "$terraform_dir" ]; then
            cd "$terraform_dir"
            S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "harbor-test-bucket")
        else
            S3_BUCKET="harbor-test-bucket"
        fi
    fi
}

# Scenario 1: Missing IRSA annotation
scenario_missing_irsa_annotation() {
    print_header "Scenario 1: Missing IRSA Annotation"
    
    print_error_scenario "Service account created without IRSA annotation"
    echo ""
    
    print_info "Symptom:"
    echo "  Pod cannot access AWS resources"
    echo "  Error: 'Unable to locate credentials'"
    echo ""
    
    print_info "Example Error Message:"
    echo "  Unable to locate credentials. You can configure credentials by running \"aws configure\"."
    echo ""
    
    print_info "Root Cause:"
    echo "  Service account is missing the eks.amazonaws.com/role-arn annotation"
    echo "  AWS SDK cannot discover IAM role to assume"
    echo ""
    
    print_resolution "Add IRSA annotation to service account"
    echo ""
    print_command "kubectl annotate serviceaccount harbor-registry -n harbor \\"
    print_command "  eks.amazonaws.com/role-arn=arn:aws:iam::ACCOUNT_ID:role/HarborS3Role"
    echo ""
    
    print_info "Verification:"
    print_command "kubectl get serviceaccount harbor-registry -n harbor -o yaml | grep eks.amazonaws.com"
    echo ""
    
    print_info "Expected Output:"
    echo "  eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/HarborS3Role"
    echo ""
}

# Scenario 2: Wrong IAM role ARN
scenario_wrong_iam_role_arn() {
    print_header "Scenario 2: Wrong IAM Role ARN"
    
    print_error_scenario "Service account has incorrect IAM role ARN"
    echo ""
    
    print_info "Symptom:"
    echo "  Pod cannot assume IAM role"
    echo "  Error: 'AccessDenied' or 'InvalidClientTokenId'"
    echo ""
    
    print_info "Example Error Message:"
    echo "  An error occurred (AccessDenied) when calling the AssumeRoleWithWebIdentity operation:"
    echo "  Not authorized to perform sts:AssumeRoleWithWebIdentity"
    echo ""
    
    print_info "Root Cause:"
    echo "  IAM role ARN in annotation is incorrect or doesn't exist"
    echo "  Typo in account ID, role name, or region"
    echo ""
    
    print_resolution "Verify and correct IAM role ARN"
    echo ""
    print_command "# Get the correct IAM role ARN"
    print_command "aws iam get-role --role-name HarborS3Role --query 'Role.Arn' --output text"
    echo ""
    print_command "# Update service account annotation"
    print_command "kubectl annotate serviceaccount harbor-registry -n harbor \\"
    print_command "  eks.amazonaws.com/role-arn=<CORRECT_ARN> --overwrite"
    echo ""
    
    print_info "Verification:"
    print_command "kubectl get serviceaccount harbor-registry -n harbor -o jsonpath='{.metadata.annotations.eks\\.amazonaws\\.com/role-arn}'"
    echo ""
}

# Scenario 3: Trust policy mismatch
scenario_trust_policy_mismatch() {
    print_header "Scenario 3: Trust Policy Mismatch"
    
    print_error_scenario "IAM role trust policy doesn't allow service account"
    echo ""
    
    print_info "Symptom:"
    echo "  Pod cannot assume IAM role"
    echo "  Error: 'AccessDenied' when calling AssumeRoleWithWebIdentity"
    echo ""
    
    print_info "Example Error Message:"
    echo "  An error occurred (AccessDenied) when calling the AssumeRoleWithWebIdentity operation:"
    echo "  User: arn:aws:sts::123456789012:assumed-role/... is not authorized to perform:"
    echo "  sts:AssumeRoleWithWebIdentity on resource: arn:aws:iam::123456789012:role/HarborS3Role"
    echo ""
    
    print_info "Root Cause:"
    echo "  Trust policy conditions don't match the service account"
    echo "  Wrong namespace or service account name in trust policy"
    echo "  OIDC provider URL mismatch"
    echo ""
    
    print_resolution "Update IAM role trust policy"
    echo ""
    print_command "# Get EKS cluster OIDC provider URL"
    print_command "aws eks describe-cluster --name <cluster-name> --query 'cluster.identity.oidc.issuer' --output text"
    echo ""
    print_command "# Update trust policy to include correct conditions"
    echo ""
    print_info "Trust policy should include:"
    echo '  "Condition": {'
    echo '    "StringEquals": {'
    echo '      "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:harbor:harbor-registry",'
    echo '      "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:aud": "sts.amazonaws.com"'
    echo '    }'
    echo '  }'
    echo ""
    
    print_info "Verification:"
    print_command "aws iam get-role --role-name HarborS3Role --query 'Role.AssumeRolePolicyDocument'"
    echo ""
}

# Scenario 4: Missing S3 permissions
scenario_missing_s3_permissions() {
    print_header "Scenario 4: Missing S3 Permissions"
    
    print_error_scenario "IAM role lacks required S3 permissions"
    echo ""
    
    print_info "Symptom:"
    echo "  Pod can assume role but cannot access S3"
    echo "  Error: 'AccessDenied' on S3 operations"
    echo ""
    
    print_info "Example Error Message:"
    echo "  An error occurred (AccessDenied) when calling the PutObject operation:"
    echo "  Access Denied"
    echo ""
    
    print_info "Root Cause:"
    echo "  IAM role permissions policy missing required S3 actions"
    echo "  Bucket name in policy doesn't match actual bucket"
    echo "  Resource ARN is incorrect"
    echo ""
    
    print_resolution "Add required S3 permissions to IAM role"
    echo ""
    print_command "# Create or update IAM policy with required permissions"
    echo ""
    print_info "Required S3 permissions:"
    echo "  - s3:PutObject"
    echo "  - s3:GetObject"
    echo "  - s3:DeleteObject"
    echo "  - s3:ListBucket"
    echo "  - s3:GetBucketLocation"
    echo ""
    print_info "Policy should target specific bucket:"
    echo "  Resource: arn:aws:s3:::$S3_BUCKET"
    echo "  Resource: arn:aws:s3:::$S3_BUCKET/*"
    echo ""
    
    print_info "Verification:"
    print_command "aws iam list-attached-role-policies --role-name HarborS3Role"
    print_command "aws iam get-policy-version --policy-arn <policy-arn> --version-id <version>"
    echo ""
}

# Scenario 5: OIDC provider not configured
scenario_oidc_not_configured() {
    print_header "Scenario 5: OIDC Provider Not Configured"
    
    print_error_scenario "IAM OIDC provider not created for EKS cluster"
    echo ""
    
    print_info "Symptom:"
    echo "  Pod cannot assume IAM role"
    echo "  Error: 'InvalidIdentityToken'"
    echo ""
    
    print_info "Example Error Message:"
    echo "  An error occurred (InvalidIdentityToken) when calling the AssumeRoleWithWebIdentity operation:"
    echo "  Couldn't retrieve verification key from your identity provider"
    echo ""
    
    print_info "Root Cause:"
    echo "  IAM OIDC identity provider not created for EKS cluster"
    echo "  OIDC provider URL in trust policy doesn't match cluster"
    echo ""
    
    print_resolution "Create IAM OIDC provider for EKS cluster"
    echo ""
    print_command "# Get OIDC provider URL"
    print_command "aws eks describe-cluster --name <cluster-name> --query 'cluster.identity.oidc.issuer' --output text"
    echo ""
    print_command "# Create OIDC provider (using eksctl)"
    print_command "eksctl utils associate-iam-oidc-provider --cluster <cluster-name> --approve"
    echo ""
    print_command "# Or create manually via AWS CLI"
    print_command "aws iam create-open-id-connect-provider \\"
    print_command "  --url <oidc-url> \\"
    print_command "  --client-id-list sts.amazonaws.com \\"
    print_command "  --thumbprint-list <thumbprint>"
    echo ""
    
    print_info "Verification:"
    print_command "aws iam list-open-id-connect-providers"
    echo ""
}

# Scenario 6: Pod not using service account
scenario_pod_not_using_sa() {
    print_header "Scenario 6: Pod Not Using Service Account"
    
    print_error_scenario "Pod not configured to use IRSA service account"
    echo ""
    
    print_info "Symptom:"
    echo "  Pod cannot access AWS resources"
    echo "  Pod uses default service account instead"
    echo ""
    
    print_info "Root Cause:"
    echo "  Pod spec doesn't specify serviceAccountName"
    echo "  Pod uses default service account (no IRSA annotation)"
    echo ""
    
    print_resolution "Update pod to use correct service account"
    echo ""
    print_info "In pod spec or Helm values:"
    echo "  spec:"
    echo "    serviceAccountName: harbor-registry"
    echo ""
    print_command "# For existing deployment"
    print_command "kubectl patch deployment harbor-registry -n harbor -p \\"
    print_command "  '{\"spec\":{\"template\":{\"spec\":{\"serviceAccountName\":\"harbor-registry\"}}}}'"
    echo ""
    
    print_info "Verification:"
    print_command "kubectl get pod <pod-name> -n harbor -o jsonpath='{.spec.serviceAccountName}'"
    echo ""
    print_info "Expected Output:"
    echo "  harbor-registry"
    echo ""
}

# Scenario 7: KMS key access denied
scenario_kms_access_denied() {
    print_header "Scenario 7: KMS Key Access Denied"
    
    print_error_scenario "IAM role cannot use KMS key for S3 encryption"
    echo ""
    
    print_info "Symptom:"
    echo "  S3 operations fail with KMS-related errors"
    echo "  Error: 'AccessDenied' on KMS operations"
    echo ""
    
    print_info "Example Error Message:"
    echo "  An error occurred (AccessDenied) when calling the PutObject operation:"
    echo "  Access Denied (Service: Amazon S3; Status Code: 403; Error Code: AccessDenied)"
    echo "  User: arn:aws:sts::123456789012:assumed-role/HarborS3Role/... is not authorized to"
    echo "  perform: kms:GenerateDataKey on resource: arn:aws:kms:..."
    echo ""
    
    print_info "Root Cause:"
    echo "  IAM role missing KMS permissions"
    echo "  KMS key policy doesn't allow IAM role"
    echo "  S3 bucket uses KMS encryption but role can't access key"
    echo ""
    
    print_resolution "Add KMS permissions to IAM role and key policy"
    echo ""
    print_info "1. Add KMS permissions to IAM role policy:"
    echo "  - kms:Decrypt"
    echo "  - kms:GenerateDataKey"
    echo "  - kms:DescribeKey"
    echo ""
    print_info "2. Update KMS key policy to allow IAM role:"
    print_command "aws kms put-key-policy --key-id <key-id> --policy-name default --policy file://key-policy.json"
    echo ""
    print_info "Key policy should include:"
    echo '  {'
    echo '    "Sid": "Allow Harbor Role to use key",'
    echo '    "Effect": "Allow",'
    echo '    "Principal": {"AWS": "arn:aws:iam::ACCOUNT:role/HarborS3Role"},'
    echo '    "Action": ["kms:Decrypt", "kms:GenerateDataKey"],'
    echo '    "Resource": "*"'
    echo '  }'
    echo ""
    
    print_info "Verification:"
    print_command "aws kms get-key-policy --key-id <key-id> --policy-name default"
    echo ""
}

# Scenario 8: Token expiration issues
scenario_token_expiration() {
    print_header "Scenario 8: Token Expiration Issues"
    
    print_error_scenario "Service account token expired or not refreshing"
    echo ""
    
    print_info "Symptom:"
    echo "  Pod works initially but fails after some time"
    echo "  Error: 'ExpiredToken' or 'InvalidToken'"
    echo ""
    
    print_info "Example Error Message:"
    echo "  An error occurred (ExpiredToken) when calling the PutObject operation:"
    echo "  The provided token has expired."
    echo ""
    
    print_info "Root Cause:"
    echo "  Token not being refreshed by AWS SDK"
    echo "  Application caching credentials instead of using SDK"
    echo "  Projected token volume not mounted correctly"
    echo ""
    
    print_resolution "Ensure proper token projection and SDK usage"
    echo ""
    print_info "1. Verify projected token volume in pod spec:"
    print_command "kubectl get pod <pod-name> -n harbor -o yaml | grep -A 10 'projected'"
    echo ""
    print_info "2. Ensure AWS SDK is used (not manual credential handling)"
    print_info "3. Check token file exists in pod:"
    print_command "kubectl exec <pod-name> -n harbor -- ls -la /var/run/secrets/eks.amazonaws.com/serviceaccount/"
    echo ""
    print_info "4. Restart pod if needed:"
    print_command "kubectl delete pod <pod-name> -n harbor"
    echo ""
}

# Scenario 9: Wrong namespace
scenario_wrong_namespace() {
    print_header "Scenario 9: Wrong Namespace"
    
    print_error_scenario "Service account in wrong namespace"
    echo ""
    
    print_info "Symptom:"
    echo "  Pod cannot assume IAM role"
    echo "  Error: 'AccessDenied' even with correct service account name"
    echo ""
    
    print_info "Root Cause:"
    echo "  Service account exists in different namespace than expected"
    echo "  Trust policy specifies specific namespace"
    echo "  Namespace mismatch between trust policy and actual deployment"
    echo ""
    
    print_resolution "Ensure service account is in correct namespace"
    echo ""
    print_command "# Check which namespace service account is in"
    print_command "kubectl get serviceaccount harbor-registry --all-namespaces"
    echo ""
    print_command "# Create service account in correct namespace if needed"
    print_command "kubectl create serviceaccount harbor-registry -n harbor"
    print_command "kubectl annotate serviceaccount harbor-registry -n harbor \\"
    print_command "  eks.amazonaws.com/role-arn=arn:aws:iam::ACCOUNT:role/HarborS3Role"
    echo ""
    
    print_info "Verification:"
    print_command "kubectl get serviceaccount harbor-registry -n harbor"
    echo ""
}

# Scenario 10: Debugging checklist
scenario_debugging_checklist() {
    print_header "Scenario 10: General Debugging Checklist"
    
    print_info "When troubleshooting IRSA issues, check these items in order:"
    echo ""
    
    echo "1. ✓ EKS cluster has OIDC provider enabled"
    print_command "aws eks describe-cluster --name <cluster> --query 'cluster.identity.oidc.issuer'"
    echo ""
    
    echo "2. ✓ IAM OIDC provider exists"
    print_command "aws iam list-open-id-connect-providers"
    echo ""
    
    echo "3. ✓ IAM role exists"
    print_command "aws iam get-role --role-name HarborS3Role"
    echo ""
    
    echo "4. ✓ IAM role has correct trust policy"
    print_command "aws iam get-role --role-name HarborS3Role --query 'Role.AssumeRolePolicyDocument'"
    echo ""
    
    echo "5. ✓ IAM role has required permissions"
    print_command "aws iam list-attached-role-policies --role-name HarborS3Role"
    echo ""
    
    echo "6. ✓ Service account exists in correct namespace"
    print_command "kubectl get serviceaccount harbor-registry -n harbor"
    echo ""
    
    echo "7. ✓ Service account has IRSA annotation"
    print_command "kubectl get serviceaccount harbor-registry -n harbor -o yaml | grep eks.amazonaws.com"
    echo ""
    
    echo "8. ✓ Pod uses correct service account"
    print_command "kubectl get pod <pod> -n harbor -o jsonpath='{.spec.serviceAccountName}'"
    echo ""
    
    echo "9. ✓ Pod has projected token volume"
    print_command "kubectl get pod <pod> -n harbor -o yaml | grep -A 5 projected"
    echo ""
    
    echo "10. ✓ Pod can assume IAM role"
    print_command "kubectl exec <pod> -n harbor -- aws sts get-caller-identity"
    echo ""
    
    echo "11. ✓ Pod can access S3"
    print_command "kubectl exec <pod> -n harbor -- aws s3 ls s3://$S3_BUCKET"
    echo ""
}

# Main execution
main() {
    print_header "Error Scenario Demonstrations"
    
    echo "This guide demonstrates common IRSA misconfigurations, error messages,"
    echo "and resolution steps."
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Get S3 bucket
    get_s3_bucket
    
    # Run all scenarios
    scenario_missing_irsa_annotation
    scenario_wrong_iam_role_arn
    scenario_trust_policy_mismatch
    scenario_missing_s3_permissions
    scenario_oidc_not_configured
    scenario_pod_not_using_sa
    scenario_kms_access_denied
    scenario_token_expiration
    scenario_wrong_namespace
    scenario_debugging_checklist
    
    print_header "Summary"
    echo ""
    echo "This guide covered 10 common error scenarios:"
    echo "  1. Missing IRSA annotation"
    echo "  2. Wrong IAM role ARN"
    echo "  3. Trust policy mismatch"
    echo "  4. Missing S3 permissions"
    echo "  5. OIDC provider not configured"
    echo "  6. Pod not using service account"
    echo "  7. KMS key access denied"
    echo "  8. Token expiration issues"
    echo "  9. Wrong namespace"
    echo "  10. General debugging checklist"
    echo ""
    echo "For more information, see:"
    echo "  - docs/harbor-irsa-deployment.md"
    echo "  - docs/iam-role-policy-setup.md"
    echo "  - docs/oidc-provider-setup.md"
    echo ""
}

# Run main function
main "$@"
