#!/bin/bash

################################################################################
# Credential Extraction Demonstration Script
# 
# Purpose: Educational demonstration of how easily AWS credentials can be
#          extracted from Kubernetes secrets in the insecure deployment approach.
#
# WARNING: This script is for EDUCATIONAL PURPOSES ONLY.
#          Only use on systems you own or have explicit permission to test.
#
# Usage: ./extract-credentials.sh [namespace] [secret-name]
#
# Example: ./extract-credentials.sh harbor harbor-s3-credentials
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="${1:-harbor}"
SECRET_NAME="${2:-harbor-s3-credentials}"

# Function to print colored output
print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Main script
clear
print_header "Credential Extraction Demonstration"

echo "Target Namespace: ${NAMESPACE}"
echo "Target Secret: ${SECRET_NAME}"
echo ""

print_warning "This demonstration shows the security risks of storing AWS credentials in Kubernetes secrets."
echo ""

# Check prerequisites
print_info "Checking prerequisites..."
echo ""

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi
print_success "kubectl found"

# Check if aws CLI is installed
if ! command -v aws &> /dev/null; then
    print_warning "AWS CLI not found - will skip credential validation"
    AWS_CLI_AVAILABLE=false
else
    print_success "AWS CLI found"
    AWS_CLI_AVAILABLE=true
fi

# Check if jq is installed (optional)
if ! command -v jq &> /dev/null; then
    print_warning "jq not found - JSON output will not be formatted"
    JQ_AVAILABLE=false
else
    print_success "jq found"
    JQ_AVAILABLE=true
fi

echo ""

# Check kubectl connectivity
print_info "Checking cluster connectivity..."
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    print_info "Make sure kubectl is configured correctly"
    exit 1
fi
print_success "Connected to cluster"
echo ""

# Check if namespace exists
print_info "Checking if namespace '${NAMESPACE}' exists..."
if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
    print_error "Namespace '${NAMESPACE}' not found"
    echo ""
    echo "Available namespaces:"
    kubectl get namespaces
    exit 1
fi
print_success "Namespace found"
echo ""

# Check if secret exists
print_info "Checking if secret '${SECRET_NAME}' exists..."
if ! kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} &> /dev/null; then
    print_error "Secret '${SECRET_NAME}' not found in namespace '${NAMESPACE}'"
    echo ""
    echo "Available secrets in namespace '${NAMESPACE}':"
    kubectl get secrets -n ${NAMESPACE}
    exit 1
fi
print_success "Secret found"
echo ""

# Show how easy it is to view the secret
print_header "Step 1: Viewing Secret Metadata"
echo "Command: kubectl get secret ${SECRET_NAME} -n ${NAMESPACE}"
echo ""
kubectl get secret ${SECRET_NAME} -n ${NAMESPACE}
echo ""
read -p "Press Enter to continue..."
echo ""

# Extract credentials
print_header "Step 2: Extracting Credentials"
echo "This demonstrates how base64 encoding is NOT encryption..."
echo ""

print_info "Extracting AWS_ACCESS_KEY_ID..."
ACCESS_KEY=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath='{.data.accesskey}' 2>/dev/null | base64 -d 2>/dev/null)

if [ -z "$ACCESS_KEY" ]; then
    print_error "Could not extract access key. Secret may have different structure."
    echo ""
    echo "Secret structure:"
    kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o yaml
    exit 1
fi

print_success "Extracted: ${ACCESS_KEY}"
echo ""

print_info "Extracting AWS_SECRET_ACCESS_KEY..."
SECRET_KEY=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath='{.data.secretkey}' 2>/dev/null | base64 -d 2>/dev/null)

if [ -z "$SECRET_KEY" ]; then
    print_error "Could not extract secret key. Secret may have different structure."
    exit 1
fi

# Mask the secret key for display (show first 8 and last 4 characters)
MASKED_SECRET="${SECRET_KEY:0:8}...${SECRET_KEY: -4}"
print_success "Extracted: ${MASKED_SECRET}"
echo ""

print_warning "Complete credentials extracted in less than 10 seconds!"
echo ""
read -p "Press Enter to continue..."
echo ""

# Display extracted credentials
print_header "Step 3: Extracted Credentials"
echo "AWS_ACCESS_KEY_ID:     ${ACCESS_KEY}"
echo "AWS_SECRET_ACCESS_KEY: ${MASKED_SECRET}"
echo ""
print_warning "These credentials are now available to the attacker!"
echo ""
read -p "Press Enter to continue..."
echo ""

# Test credentials if AWS CLI is available
if [ "$AWS_CLI_AVAILABLE" = true ]; then
    print_header "Step 4: Testing Credentials"
    echo "Attempting to use stolen credentials..."
    echo ""
    
    export AWS_ACCESS_KEY_ID="${ACCESS_KEY}"
    export AWS_SECRET_ACCESS_KEY="${SECRET_KEY}"
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
    
    print_info "Calling AWS STS GetCallerIdentity..."
    if IDENTITY=$(aws sts get-caller-identity 2>&1); then
        print_success "Credentials are VALID and ACTIVE!"
        echo ""
        echo "Identity Information:"
        if [ "$JQ_AVAILABLE" = true ]; then
            echo "${IDENTITY}" | jq .
        else
            echo "${IDENTITY}"
        fi
        echo ""
        
        # Try to list S3 buckets
        print_info "Attempting to list S3 buckets..."
        if S3_BUCKETS=$(aws s3 ls 2>&1); then
            print_success "Can list S3 buckets!"
            echo ""
            echo "Accessible S3 Buckets:"
            echo "${S3_BUCKETS}"
            echo ""
            
            # Check for Harbor bucket
            HARBOR_BUCKET="harbor-registry-storage"
            if echo "${S3_BUCKETS}" | grep -q "${HARBOR_BUCKET}"; then
                print_warning "Found Harbor registry bucket: ${HARBOR_BUCKET}"
                echo ""
                print_info "Checking bucket access..."
                if aws s3 ls s3://${HARBOR_BUCKET}/ &> /dev/null; then
                    print_success "Can access Harbor S3 bucket!"
                    echo ""
                    echo "Sample contents (first 10 items):"
                    aws s3 ls s3://${HARBOR_BUCKET}/harbor/ --recursive 2>/dev/null | head -10 || echo "No contents or access denied"
                fi
            fi
        else
            print_warning "Cannot list S3 buckets (may lack permissions)"
            echo "Error: ${S3_BUCKETS}"
        fi
    else
        print_error "Credentials are invalid or inactive"
        echo "Error: ${IDENTITY}"
    fi
    echo ""
    read -p "Press Enter to continue..."
    echo ""
fi

# Show additional extraction methods
print_header "Step 5: Alternative Extraction Methods"
echo "There are multiple ways to extract these credentials:"
echo ""

echo "Method 1: Direct extraction (what we just did)"
echo "  kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath='{.data.accesskey}' | base64 -d"
echo ""

echo "Method 2: View complete secret in YAML"
echo "  kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o yaml"
echo ""

echo "Method 3: Extract from pod environment variables"
echo "  kubectl exec -n ${NAMESPACE} <pod-name> -- env | grep AWS"
echo ""

echo "Method 4: View pod specification"
echo "  kubectl get pod -n ${NAMESPACE} -l component=registry -o yaml | grep -A 10 'env:'"
echo ""

echo "Method 5: Extract from Helm release"
echo "  helm get values harbor -n ${NAMESPACE}"
echo ""

read -p "Press Enter to continue..."
echo ""

# Security implications
print_header "Security Implications"
echo ""

print_warning "What an attacker can do with these credentials:"
echo "  • Download all container images (intellectual property theft)"
echo "  • Upload malicious images (supply chain attack)"
echo "  • Delete all registry data (denial of service)"
echo "  • Modify S3 bucket policies (privilege escalation)"
echo "  • Incur AWS costs (resource abuse)"
echo "  • Access other AWS services (lateral movement)"
echo ""

print_warning "Why this is so dangerous:"
echo "  • Credentials NEVER expire (valid indefinitely)"
echo "  • Work from ANYWHERE (not bound to cluster)"
echo "  • Cannot be traced to specific pods (poor audit trail)"
echo "  • Stored in MULTIPLE locations (increased exposure)"
echo "  • Extraction is UNDETECTABLE (normal kubectl operation)"
echo "  • Takes only SECONDS to extract (fast attack)"
echo ""

print_warning "Detection challenges:"
echo "  • Reading secrets is a legitimate kubectl operation"
echo "  • Kubernetes audit logs may not be enabled"
echo "  • CloudTrail shows 'harbor-s3-user', not the attacker"
echo "  • Credentials can be used offline (outside cluster)"
echo "  • No alerts for secret access in most environments"
echo ""

read -p "Press Enter to continue..."
echo ""

# Show IRSA comparison
print_header "How IRSA Eliminates This Vulnerability"
echo ""

print_success "With IRSA (IAM Roles for Service Accounts):"
echo "  ✅ NO static credentials stored in secrets"
echo "  ✅ Temporary tokens that expire in 24 hours"
echo "  ✅ Tokens bound to specific pods (cannot use elsewhere)"
echo "  ✅ Automatic credential rotation (no manual intervention)"
echo "  ✅ Full audit trail (CloudTrail shows pod identity)"
echo "  ✅ Least privilege IAM policies"
echo "  ✅ Defense in depth with multiple security layers"
echo ""

print_info "IRSA token characteristics:"
echo "  • Expires automatically (24 hour lifetime)"
echo "  • Bound to pod identity (cannot extract and reuse)"
echo "  • Automatically rotated (seamless, no downtime)"
echo "  • Fully auditable (CloudTrail shows namespace/pod/SA)"
echo "  • Least privilege (scoped to specific S3 bucket)"
echo ""

print_success "Result: Extraction methods shown above DO NOT WORK with IRSA!"
echo ""

# Recommendations
print_header "Recommendations"
echo ""

print_error "IMMEDIATE ACTIONS:"
echo "  1. Do NOT use IAM user tokens in production"
echo "  2. Migrate to IRSA as soon as possible"
echo "  3. Rotate all exposed credentials immediately"
echo "  4. Audit CloudTrail logs for suspicious activity"
echo "  5. Enable Kubernetes audit logging"
echo ""

print_success "SECURE ALTERNATIVE:"
echo "  • Implement IRSA for Harbor deployment"
echo "  • Use KMS CMK for S3 encryption"
echo "  • Apply least privilege IAM policies"
echo "  • Enable comprehensive audit logging"
echo "  • Implement defense in depth"
echo ""

print_info "For detailed IRSA implementation guide, see:"
echo "  docs/secure-deployment-guide.md"
echo ""

# Summary
print_header "Summary"
echo ""

echo "This demonstration showed that:"
echo ""
echo "  1. Extracting credentials takes less than 10 seconds"
echo "  2. Only basic kubectl knowledge is required"
echo "  3. Extraction appears as normal kubectl operation"
echo "  4. Stolen credentials work from anywhere"
echo "  5. Credentials never expire (unlimited time window)"
echo "  6. Detection is nearly impossible"
echo ""

print_error "The IAM user token approach is FUNDAMENTALLY INSECURE"
print_success "IRSA is the ONLY secure solution for production use"
echo ""

print_header "Demonstration Complete"
echo ""
print_warning "Remember: This script is for educational purposes only."
print_warning "Only use on systems you own or have explicit permission to test."
echo ""
