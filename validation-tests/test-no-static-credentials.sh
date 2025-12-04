#!/bin/bash
# Feature: harbor-irsa-workshop, Property 4: No Static Credentials in Pod Specifications
# Validates: Requirements 7.5
#
# Property: For any pod specification in the secure IRSA deployment path, the pod should 
# not contain AWS credentials in environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY), 
# volumes, or configMaps. All AWS authentication should occur through IRSA projected service 
# account tokens.

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

# Credential patterns to search for
CREDENTIAL_PATTERNS=(
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "aws_access_key_id"
    "aws_secret_access_key"
    "accesskey"
    "secretkey"
    "access_key"
    "secret_key"
)

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

# Test YAML file for static credentials
test_yaml_file_for_credentials() {
    local file=$1
    local iteration=$2
    local filename=$(basename "$file")
    
    print_info "Iteration $iteration: Testing file: $filename"
    
    local found_credentials=false
    local credential_locations=()
    
    # Test 1: Check for AWS credential environment variables
    for pattern in "${CREDENTIAL_PATTERNS[@]}"; do
        if grep -i -q "$pattern" "$file"; then
            # Check if it's in a comment or documentation
            local matches=$(grep -i -n "$pattern" "$file" | grep -v "^[[:space:]]*#" | grep -v "DO NOT" | grep -v "NO STATIC" | grep -v "✅ NO" || true)
            
            if [ -n "$matches" ]; then
                # Check if it's actually defining a credential value (not just a comment)
                while IFS= read -r line; do
                    # Skip lines that are clearly documentation
                    if echo "$line" | grep -q -E "(# |DO NOT|NO STATIC|✅|REPLACE|CHANGE|example)"; then
                        continue
                    fi
                    
                    # Check if this is an actual credential definition
                    if echo "$line" | grep -q -E "(value:|valueFrom:|data:|stringData:)"; then
                        found_credentials=true
                        credential_locations+=("$pattern found at: $line")
                    fi
                done <<< "$matches"
            fi
        fi
    done
    
    if [ "$found_credentials" = true ]; then
        print_fail "File $filename contains static credential definitions"
        for location in "${credential_locations[@]}"; do
            echo -e "${RED}    $location${NC}"
        done
    else
        print_pass "File $filename does not contain static credentials"
    fi
    
    # Test 2: Check for IRSA annotation (should be present in service accounts)
    if echo "$filename" | grep -q "service-account"; then
        if grep -q "eks.amazonaws.com/role-arn" "$file"; then
            print_pass "Service account has IRSA annotation"
        else
            print_fail "Service account missing IRSA annotation"
        fi
    fi
    
    # Test 3: Check for explicit credential-free configuration in Helm values
    if echo "$filename" | grep -q -E "(values|harbor).*\.yaml"; then
        # Check that accesskey/secretkey are NOT defined in S3 configuration
        if grep -A 20 "type: s3" "$file" | grep -q -E "^\s+(accesskey|secretkey):"; then
            # Make sure it's not a comment
            if grep -A 20 "type: s3" "$file" | grep -E "^\s+(accesskey|secretkey):" | grep -v "#" | grep -q "."; then
                print_fail "Helm values contain S3 accesskey/secretkey configuration"
                found_credentials=true
            fi
        fi
        
        if [ "$found_credentials" = false ]; then
            # Check for positive indicators of IRSA usage
            if grep -q "# ✅ NO STATIC CREDENTIALS" "$file" || \
               grep -q "DO NOT specify accesskey or secretkey" "$file" || \
               grep -q "IRSA provides credentials automatically" "$file"; then
                print_pass "Helm values explicitly document credential-free configuration"
            fi
        fi
    fi
    
    # Test 4: Check for Kubernetes secrets containing AWS credentials
    if echo "$filename" | grep -q "secret"; then
        if grep -q "kind: Secret" "$file"; then
            # Check if secret contains AWS credential keys
            if grep -A 10 "kind: Secret" "$file" | grep -q -E "(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY)"; then
                print_fail "Kubernetes Secret contains AWS credentials"
                found_credentials=true
            else
                print_pass "Kubernetes Secret does not contain AWS credentials"
            fi
        fi
    fi
    
    # Test 5: Check for environment variables in pod specs
    if grep -q -E "(kind: Pod|kind: Deployment|kind: StatefulSet)" "$file"; then
        # Look for env sections with AWS credentials
        if grep -A 5 "env:" "$file" | grep -q -E "(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY)"; then
            # Make sure it's not in a comment
            if grep -A 5 "env:" "$file" | grep -E "(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY)" | grep -v "#" | grep -q "."; then
                print_fail "Pod specification contains AWS credential environment variables"
                found_credentials=true
            fi
        fi
    fi
    
    return 0
}

# Test deployed pods in Kubernetes cluster (if available)
test_deployed_pods() {
    local namespace=$1
    local iteration=$2
    
    print_info "Iteration $iteration: Testing deployed pods in namespace: $namespace"
    
    # Check if kubectl is available and cluster is accessible
    if ! command -v kubectl &> /dev/null; then
        print_warning "kubectl not available, skipping deployed pod tests"
        return 0
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        print_warning "Kubernetes cluster not accessible, skipping deployed pod tests"
        return 0
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        print_warning "Namespace $namespace does not exist, skipping deployed pod tests"
        return 0
    fi
    
    # Get all pods in namespace
    local pods=$(kubectl get pods -n "$namespace" -o name 2>/dev/null || echo "")
    
    if [ -z "$pods" ]; then
        print_warning "No pods found in namespace $namespace"
        return 0
    fi
    
    # Test each pod
    while IFS= read -r pod; do
        local pod_name=$(echo "$pod" | cut -d'/' -f2)
        print_info "  Checking pod: $pod_name"
        
        # Get pod spec as JSON
        local pod_spec=$(kubectl get "$pod" -n "$namespace" -o json 2>/dev/null || echo "")
        
        if [ -z "$pod_spec" ]; then
            print_warning "  Could not retrieve pod spec for $pod_name"
            continue
        fi
        
        # Test 1: Check for AWS credential environment variables
        local has_access_key=$(echo "$pod_spec" | jq -r '.spec.containers[].env[]? | select(.name=="AWS_ACCESS_KEY_ID") | .name' 2>/dev/null || echo "")
        local has_secret_key=$(echo "$pod_spec" | jq -r '.spec.containers[].env[]? | select(.name=="AWS_SECRET_ACCESS_KEY") | .name' 2>/dev/null || echo "")
        
        if [ -n "$has_access_key" ] || [ -n "$has_secret_key" ]; then
            print_fail "  Pod $pod_name has AWS credential environment variables"
        else
            print_pass "  Pod $pod_name has no AWS credential environment variables"
        fi
        
        # Test 2: Check for service account with IRSA annotation
        local service_account=$(echo "$pod_spec" | jq -r '.spec.serviceAccountName' 2>/dev/null || echo "")
        
        if [ -n "$service_account" ] && [ "$service_account" != "null" ] && [ "$service_account" != "default" ]; then
            # Check if service account has IRSA annotation
            local sa_annotation=$(kubectl get serviceaccount "$service_account" -n "$namespace" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
            
            if [ -n "$sa_annotation" ]; then
                print_pass "  Pod $pod_name uses service account with IRSA annotation"
            else
                print_warning "  Pod $pod_name uses service account without IRSA annotation"
            fi
        fi
        
        # Test 3: Check for projected service account token volume
        local has_projected_token=$(echo "$pod_spec" | jq -r '.spec.volumes[]? | select(.projected.sources[]?.serviceAccountToken) | .name' 2>/dev/null || echo "")
        
        if [ -n "$has_projected_token" ]; then
            print_pass "  Pod $pod_name has projected service account token volume"
        fi
        
        # Test 4: Check for secrets mounted as volumes
        local secret_volumes=$(echo "$pod_spec" | jq -r '.spec.volumes[]? | select(.secret) | .secret.secretName' 2>/dev/null || echo "")
        
        if [ -n "$secret_volumes" ]; then
            while IFS= read -r secret_name; do
                # Check if secret contains AWS credentials
                local secret_keys=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys[]' 2>/dev/null || echo "")
                
                if echo "$secret_keys" | grep -q -E "(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|accesskey|secretkey)"; then
                    print_fail "  Pod $pod_name mounts secret $secret_name containing AWS credentials"
                fi
            done <<< "$secret_volumes"
        fi
        
    done <<< "$pods"
}

# Run property tests on YAML files
run_yaml_file_tests() {
    print_header "Testing YAML Files for Static Credentials"
    
    print_info "Property: Pod specifications should not contain static AWS credentials"
    print_info "Running $MIN_ITERATIONS iterations on secure deployment files..."
    echo ""
    
    # Find all YAML files in secure examples
    local yaml_files=()
    
    if [ -d "$PROJECT_ROOT/examples/secure" ]; then
        while IFS= read -r file; do
            yaml_files+=("$file")
        done < <(find "$PROJECT_ROOT/examples/secure" -type f -name "*.yaml" -o -name "*.yml")
    fi
    
    if [ ${#yaml_files[@]} -eq 0 ]; then
        print_warning "No YAML files found in examples/secure directory"
        return 1
    fi
    
    print_info "Found ${#yaml_files[@]} YAML files to test"
    echo ""
    
    # Run multiple iterations
    for ((i=1; i<=MIN_ITERATIONS; i++)); do
        CURRENT_ITERATION=$i
        
        echo -e "${BLUE}--- Iteration $i/$MIN_ITERATIONS ---${NC}"
        
        # Test each YAML file
        for yaml_file in "${yaml_files[@]}"; do
            test_yaml_file_for_credentials "$yaml_file" "$i"
        done
        
        echo ""
    done
}

# Run property tests on deployed pods
run_deployed_pod_tests() {
    print_header "Testing Deployed Pods for Static Credentials"
    
    print_info "Property: Deployed pods should not contain static AWS credentials"
    print_info "Running tests on harbor namespace..."
    echo ""
    
    # Run multiple iterations
    for ((i=1; i<=MIN_ITERATIONS; i++)); do
        CURRENT_ITERATION=$i
        
        echo -e "${BLUE}--- Iteration $i/$MIN_ITERATIONS ---${NC}"
        
        # Test harbor namespace
        test_deployed_pods "harbor" "$i"
        
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
        echo "No static credentials found in pod specifications:"
        echo "  ✓ No AWS_ACCESS_KEY_ID environment variables"
        echo "  ✓ No AWS_SECRET_ACCESS_KEY environment variables"
        echo "  ✓ No static credentials in Kubernetes secrets"
        echo "  ✓ IRSA annotations present on service accounts"
        echo "  ✓ Credential-free S3 configuration"
        return 0
    else
        echo -e "${RED}✗ Some property tests failed${NC}"
        echo ""
        echo "Static credentials were found in pod specifications."
        echo "Review the failures above and remove all static credentials."
        echo "Use IRSA (IAM Roles for Service Accounts) instead."
        return 1
    fi
}

# Main execution
main() {
    print_header "No Static Credentials Property Test"
    
    # Check prerequisites
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}jq is not installed${NC}"
        exit 1
    fi
    
    print_info "Testing secure deployment configurations for static credentials..."
    print_info "Project root: $PROJECT_ROOT"
    echo ""
    
    # Run YAML file tests
    run_yaml_file_tests
    
    # Run deployed pod tests (if cluster is available)
    run_deployed_pod_tests
    
    # Display summary
    display_summary
}

# Run main function
main "$@"
