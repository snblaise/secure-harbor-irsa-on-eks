#!/bin/bash
# Credential Extraction Test for Insecure Path
# Validates: Requirements 6.1
#
# This test demonstrates how static IAM user credentials can be extracted from 
# Kubernetes secrets in the insecure deployment approach. This is an educational 
# demonstration of the security risks associated with storing AWS credentials in 
# Kubernetes secrets.

set -e
set -u

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test configuration
NAMESPACE="harbor-insecure"
SECRET_NAME="harbor-s3-credentials"

# Functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_pass() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

print_fail() {
    echo -e "${RED}  ✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}  ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}  ⚠ $1${NC}"
}

print_security_risk() {
    echo -e "${RED}  🔴 SECURITY RISK: $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    if ! command -v kubectl &> /dev/null; then
        print_fail "kubectl is not installed"
        echo ""
        echo "Install kubectl:"
        echo "  macOS: brew install kubectl"
        echo "  Linux: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
    print_pass "kubectl is installed"
    
    if ! kubectl cluster-info &> /dev/null; then
        print_fail "Cannot connect to Kubernetes cluster"
        echo ""
        echo "Make sure you have a Kubernetes cluster running and kubectl is configured."
        exit 1
    fi
    print_pass "Connected to Kubernetes cluster"
    
    if ! command -v base64 &> /dev/null; then
        print_fail "base64 is not installed"
        exit 1
    fi
    print_pass "base64 is installed"
    
    echo ""
}

# Create insecure namespace and secret for demonstration
create_insecure_demo() {
    print_header "Creating Insecure Demo Environment"
    
    print_info "This creates a demonstration of the INSECURE approach"
    print_info "DO NOT use this pattern in production!"
    echo ""
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        print_info "Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE"
        print_pass "Namespace created"
    else
        print_info "Namespace $NAMESPACE already exists"
    fi
    
    # Create a demo secret with fake credentials
    print_info "Creating Kubernetes secret with AWS credentials (INSECURE)"
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $NAMESPACE
type: Opaque
data:
  AWS_ACCESS_KEY_ID: $(echo -n "AKIAIOSFODNN7EXAMPLE" | base64)
  AWS_SECRET_ACCESS_KEY: $(echo -n "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" | base64)
EOF
    
    print_pass "Secret created with base64-encoded credentials"
    print_security_risk "Credentials are stored in Kubernetes and can be extracted!"
    echo ""
}

# Demonstrate credential extraction
demonstrate_credential_extraction() {
    print_header "Demonstrating Credential Extraction"
    
    print_warning "This demonstrates how easily credentials can be stolen"
    print_warning "Any user with kubectl access to the namespace can do this"
    echo ""
    
    # Step 1: List secrets
    print_info "Step 1: List secrets in namespace"
    echo ""
    echo "Command: kubectl get secrets -n $NAMESPACE"
    echo ""
    kubectl get secrets -n "$NAMESPACE"
    echo ""
    print_security_risk "Attacker can see that a secret named '$SECRET_NAME' exists"
    echo ""
    
    # Step 2: Get secret details
    print_info "Step 2: Retrieve secret data"
    echo ""
    echo "Command: kubectl get secret $SECRET_NAME -n $NAMESPACE -o yaml"
    echo ""
    kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o yaml
    echo ""
    print_security_risk "Secret data is visible (base64-encoded, but NOT encrypted)"
    echo ""
    
    # Step 3: Extract and decode credentials
    print_info "Step 3: Extract and decode AWS_ACCESS_KEY_ID"
    echo ""
    echo "Command: kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 --decode"
    echo ""
    local access_key=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 --decode)
    echo "Extracted AWS_ACCESS_KEY_ID: $access_key"
    echo ""
    print_security_risk "Credentials extracted in plaintext!"
    echo ""
    
    print_info "Step 4: Extract and decode AWS_SECRET_ACCESS_KEY"
    echo ""
    echo "Command: kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 --decode"
    echo ""
    local secret_key=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 --decode)
    echo "Extracted AWS_SECRET_ACCESS_KEY: $secret_key"
    echo ""
    print_security_risk "Full credentials compromised!"
    echo ""
}

# Demonstrate one-liner extraction
demonstrate_one_liner() {
    print_header "One-Liner Credential Theft"
    
    print_warning "An attacker can extract credentials with a single command"
    echo ""
    
    print_info "Extract both credentials at once:"
    echo ""
    echo "Command:"
    echo "kubectl get secret $SECRET_NAME -n $NAMESPACE -o json | jq -r '.data | map_values(@base64d)'"
    echo ""
    
    if command -v jq &> /dev/null; then
        kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o json | jq -r '.data | map_values(@base64d)'
        echo ""
        print_security_risk "Complete credential theft in one command!"
    else
        print_warning "jq not installed, skipping one-liner demo"
    fi
    echo ""
}

# Explain security implications
explain_security_implications() {
    print_header "Security Implications"
    
    echo -e "${RED}This insecure approach has multiple critical vulnerabilities:${NC}"
    echo ""
    
    echo "1. ${RED}Base64 is NOT encryption${NC}"
    echo "   - Base64 encoding provides NO security"
    echo "   - Anyone can decode base64 with standard tools"
    echo "   - Credentials are effectively stored in plaintext"
    echo ""
    
    echo "2. ${RED}Broad access to secrets${NC}"
    echo "   - Any user with 'kubectl get secrets' permission can extract credentials"
    echo "   - Developers, operators, CI/CD systems often have this access"
    echo "   - Compromised developer laptop = compromised AWS credentials"
    echo ""
    
    echo "3. ${RED}No automatic rotation${NC}"
    echo "   - Credentials remain valid indefinitely"
    echo "   - If stolen, attacker has persistent access"
    echo "   - Manual rotation is error-prone and often forgotten"
    echo ""
    
    echo "4. ${RED}Credential sprawl${NC}"
    echo "   - Same credentials might be copied to multiple places"
    echo "   - Hard to track where credentials are used"
    echo "   - Difficult to revoke access completely"
    echo ""
    
    echo "5. ${RED}Poor audit trail${NC}"
    echo "   - All AWS actions appear as the IAM user"
    echo "   - Cannot distinguish which pod/container made the request"
    echo "   - Difficult to investigate security incidents"
    echo ""
    
    echo "6. ${RED}Overprivileged access${NC}"
    echo "   - IAM user often has broad permissions (e.g., S3FullAccess)"
    echo "   - Violates principle of least privilege"
    echo "   - Increases blast radius of credential compromise"
    echo ""
}

# Show how credentials would be used
demonstrate_credential_usage() {
    print_header "How Stolen Credentials Can Be Used"
    
    print_warning "Once extracted, credentials can be used anywhere"
    echo ""
    
    print_info "Attacker can export credentials and use AWS CLI:"
    echo ""
    
    local access_key=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 --decode)
    local secret_key=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 --decode)
    
    echo "export AWS_ACCESS_KEY_ID=\"$access_key\""
    echo "export AWS_SECRET_ACCESS_KEY=\"$secret_key\""
    echo ""
    echo "# Now attacker can run any AWS command:"
    echo "aws s3 ls"
    echo "aws s3 cp s3://harbor-bucket/sensitive-data.tar.gz ."
    echo "aws s3 rm s3://harbor-bucket/critical-image.tar --recursive"
    echo "aws iam list-users"
    echo "aws ec2 describe-instances"
    echo ""
    
    print_security_risk "Attacker has full AWS access with stolen credentials!"
    echo ""
    
    print_info "Credentials can also be:"
    echo "  - Used from attacker's own infrastructure"
    echo "  - Sold on dark web marketplaces"
    echo "  - Used for cryptomining"
    echo "  - Used to pivot to other AWS resources"
    echo "  - Exfiltrated and used months later"
    echo ""
}

# Show IRSA alternative
show_irsa_alternative() {
    print_header "The Secure Alternative: IRSA"
    
    echo -e "${GREEN}IAM Roles for Service Accounts (IRSA) solves these problems:${NC}"
    echo ""
    
    echo "✅ ${GREEN}No static credentials${NC}"
    echo "   - No credentials stored in Kubernetes secrets"
    echo "   - Nothing to extract or steal"
    echo "   - Credentials never leave AWS infrastructure"
    echo ""
    
    echo "✅ ${GREEN}Automatic rotation${NC}"
    echo "   - Temporary credentials expire every 24 hours"
    echo "   - Automatically refreshed by AWS SDK"
    echo "   - No manual rotation required"
    echo ""
    
    echo "✅ ${GREEN}Fine-grained access control${NC}"
    echo "   - IAM role bound to specific namespace + service account"
    echo "   - Only authorized pods can assume the role"
    echo "   - Least privilege IAM policies"
    echo ""
    
    echo "✅ ${GREEN}Excellent audit trail${NC}"
    echo "   - CloudTrail shows which pod made each request"
    echo "   - Full identity attribution"
    echo "   - Easy incident investigation"
    echo ""
    
    echo "✅ ${GREEN}Defense in depth${NC}"
    echo "   - Multiple layers of security"
    echo "   - Encryption at rest with KMS"
    echo "   - Network policies"
    echo "   - Pod security standards"
    echo ""
}

# Cleanup demo environment
cleanup_demo() {
    print_header "Cleanup"
    
    print_info "Removing demo environment..."
    
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        kubectl delete namespace "$NAMESPACE" --wait=false
        print_pass "Namespace $NAMESPACE deleted"
    fi
    
    echo ""
    print_info "Demo environment cleaned up"
}

# Main execution
main() {
    print_header "Credential Extraction Test - Insecure Path"
    
    echo -e "${YELLOW}⚠️  WARNING: This is an educational demonstration${NC}"
    echo -e "${YELLOW}⚠️  This shows the INSECURE approach - DO NOT use in production${NC}"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Create demo environment
    create_insecure_demo
    
    # Demonstrate credential extraction
    demonstrate_credential_extraction
    
    # Show one-liner extraction
    demonstrate_one_liner
    
    # Demonstrate credential usage
    demonstrate_credential_usage
    
    # Explain security implications
    explain_security_implications
    
    # Show IRSA alternative
    show_irsa_alternative
    
    # Cleanup
    print_header "Cleanup Options"
    echo ""
    echo "To remove the demo environment, run:"
    echo "  kubectl delete namespace $NAMESPACE"
    echo ""
    echo "Or run this script with --cleanup flag:"
    echo "  $0 --cleanup"
    echo ""
    
    if [ "${1:-}" = "--cleanup" ]; then
        cleanup_demo
    fi
    
    print_header "Summary"
    echo ""
    echo -e "${RED}❌ Insecure Approach: Static IAM user credentials in Kubernetes secrets${NC}"
    echo "   - Credentials easily extracted with kubectl"
    echo "   - No automatic rotation"
    echo "   - Poor audit trail"
    echo "   - High security risk"
    echo ""
    echo -e "${GREEN}✅ Secure Approach: IRSA (IAM Roles for Service Accounts)${NC}"
    echo "   - No static credentials"
    echo "   - Automatic rotation"
    echo "   - Fine-grained access control"
    echo "   - Excellent audit trail"
    echo ""
    echo "For more information, see:"
    echo "  - docs/insecure-deployment-guide.md"
    echo "  - docs/harbor-irsa-deployment.md"
    echo "  - docs/insecure-threat-model.md"
    echo ""
}

# Run main function
main "$@"
