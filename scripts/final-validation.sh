#!/bin/bash

# Final Workshop Validation Script
# This script performs comprehensive validation of the Harbor IRSA Workshop
# It checks documentation, code examples, tests, and deliverables

# Note: We don't use 'set -e' because we want to continue checking all items
# even if some checks fail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Function to print section headers
print_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Function to print check results
check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED_CHECKS++))
    ((TOTAL_CHECKS++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED_CHECKS++))
    ((TOTAL_CHECKS++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNING_CHECKS++))
    ((TOTAL_CHECKS++))
}

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Harbor IRSA Workshop - Final Validation                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Project Root: $PROJECT_ROOT"
echo ""

# ============================================================================
# 1. DOCUMENTATION VALIDATION
# ============================================================================
print_section "1. Documentation Validation"

# Check main README
if [ -f "README.md" ]; then
    if grep -q "IAM Roles for Service Accounts" README.md && \
       grep -q "Quick Start" README.md && \
       grep -q "Architecture Overview" README.md; then
        check_pass "Main README.md exists and contains required sections"
    else
        check_fail "Main README.md missing required sections"
    fi
else
    check_fail "Main README.md not found"
fi

# Check workshop lab guide
if [ -f "docs/WORKSHOP_LAB_GUIDE.md" ]; then
    check_pass "Workshop Lab Guide exists"
else
    check_fail "Workshop Lab Guide not found"
fi

# Check learning objectives
if [ -f "docs/LEARNING_OBJECTIVES.md" ]; then
    check_pass "Learning Objectives document exists"
else
    check_fail "Learning Objectives document not found"
fi

# Check validation checkpoints
if [ -f "docs/VALIDATION_CHECKPOINTS.md" ]; then
    check_pass "Validation Checkpoints document exists"
else
    check_fail "Validation Checkpoints document not found"
fi

# Check troubleshooting guide
if [ -f "docs/TROUBLESHOOTING_GUIDE.md" ]; then
    check_pass "Troubleshooting Guide exists"
else
    check_fail "Troubleshooting Guide not found"
fi

# Check architecture documentation
required_docs=(
    "docs/architecture-diagrams.md"
    "docs/architecture-comparison.md"
    "docs/insecure-deployment-guide.md"
    "docs/insecure-threat-model.md"
    "docs/credential-extraction-demo.md"
    "docs/oidc-provider-setup.md"
    "docs/iam-role-policy-setup.md"
    "docs/s3-kms-setup.md"
    "docs/harbor-irsa-deployment.md"
)

for doc in "${required_docs[@]}"; do
    if [ -f "$doc" ]; then
        check_pass "$(basename "$doc") exists"
    else
        check_fail "$(basename "$doc") not found"
    fi
done

# Check hardening guides
hardening_docs=(
    "docs/kms-key-policy-hardening.md"
    "docs/s3-bucket-policy-hardening.md"
    "docs/iam-guardrails.md"
    "docs/namespace-isolation-guide.md"
)

for doc in "${hardening_docs[@]}"; do
    if [ -f "$doc" ]; then
        check_pass "$(basename "$doc") exists"
    else
        check_fail "$(basename "$doc") not found"
    fi
done

# Check audit documentation
audit_docs=(
    "docs/cloudtrail-log-analysis.md"
    "docs/permission-tracking-guide.md"
    "docs/incident-investigation-guide.md"
)

for doc in "${audit_docs[@]}"; do
    if [ -f "$doc" ]; then
        check_pass "$(basename "$doc") exists"
    else
        check_fail "$(basename "$doc") not found"
    fi
done

# ============================================================================
# 2. INFRASTRUCTURE CODE VALIDATION
# ============================================================================
print_section "2. Infrastructure Code Validation"

# Check Terraform root files
if [ -f "terraform/main.tf" ]; then
    check_pass "Terraform main.tf exists"
else
    check_fail "Terraform main.tf not found"
fi

if [ -f "terraform/variables.tf" ]; then
    check_pass "Terraform variables.tf exists"
else
    check_fail "Terraform variables.tf not found"
fi

if [ -f "terraform/outputs.tf" ]; then
    check_pass "Terraform outputs.tf exists"
else
    check_fail "Terraform outputs.tf not found"
fi

if [ -f "terraform/terraform.tfvars.example" ]; then
    check_pass "Terraform tfvars example exists"
else
    check_fail "Terraform tfvars example not found"
fi

# Check Terraform modules
terraform_modules=(
    "terraform/modules/eks-cluster"
    "terraform/modules/irsa"
    "terraform/modules/s3-kms"
    "terraform/modules/harbor-helm"
)

for module in "${terraform_modules[@]}"; do
    if [ -d "$module" ]; then
        check_pass "Terraform module $(basename "$module") exists"
        
        # Check for main.tf in module
        if [ -f "$module/main.tf" ]; then
            check_pass "  └─ $(basename "$module")/main.tf exists"
        else
            check_fail "  └─ $(basename "$module")/main.tf not found"
        fi
    else
        check_fail "Terraform module $(basename "$module") not found"
    fi
done

# Validate Terraform syntax (if terraform is installed)
if command -v terraform &> /dev/null; then
    cd terraform
    if terraform fmt -check -recursive > /dev/null 2>&1; then
        check_pass "Terraform code is properly formatted"
    else
        check_warn "Terraform code formatting issues detected"
    fi
    
    if terraform validate > /dev/null 2>&1; then
        check_pass "Terraform configuration is valid"
    else
        check_warn "Terraform validation issues (may need init)"
    fi
    cd "$PROJECT_ROOT"
else
    check_warn "Terraform not installed, skipping syntax validation"
fi

# ============================================================================
# 3. EXAMPLE CONFIGURATIONS VALIDATION
# ============================================================================
print_section "3. Example Configurations Validation"

# Check example directory
if [ -d "examples/secure" ]; then
    check_pass "Secure examples directory exists"
else
    check_fail "Secure examples directory not found"
fi

# Check for example files
example_files=(
    "examples/secure/harbor-values-irsa.yaml"
    "examples/secure/service-account.yaml"
    "examples/secure/iam-role-trust-policy.json"
    "examples/secure/iam-role-permissions-policy.json"
)

for example in "${example_files[@]}"; do
    if [ -f "$example" ]; then
        check_pass "$(basename "$example") exists"
        
        # Validate YAML/JSON syntax
        case "$example" in
            *.yaml|*.yml)
                if command -v yamllint &> /dev/null; then
                    if yamllint -d relaxed "$example" > /dev/null 2>&1; then
                        check_pass "  └─ YAML syntax valid"
                    else
                        check_warn "  └─ YAML syntax issues detected"
                    fi
                fi
                ;;
            *.json)
                if command -v jq &> /dev/null; then
                    if jq empty "$example" > /dev/null 2>&1; then
                        check_pass "  └─ JSON syntax valid"
                    else
                        check_fail "  └─ JSON syntax invalid"
                    fi
                fi
                ;;
        esac
    else
        check_fail "$(basename "$example") not found"
    fi
done

# ============================================================================
# 4. VALIDATION TESTS VALIDATION
# ============================================================================
print_section "4. Validation Tests Validation"

# Check validation tests directory
if [ -d "validation-tests" ]; then
    check_pass "Validation tests directory exists"
else
    check_fail "Validation tests directory not found"
fi

# Check for test scripts
test_scripts=(
    "validation-tests/test-irsa-access-validation.sh"
    "validation-tests/test-irsa-access-control.sh"
    "validation-tests/test-access-denial.sh"
    "validation-tests/test-credential-extraction-insecure.sh"
    "validation-tests/test-log-verification.sh"
    "validation-tests/test-no-static-credentials.sh"
    "validation-tests/test-credential-rotation.sh"
    "validation-tests/test-error-scenarios.sh"
    "validation-tests/test-infrastructure-best-practices.sh"
)

for test in "${test_scripts[@]}"; do
    if [ -f "$test" ]; then
        check_pass "$(basename "$test") exists"
        
        # Check if executable
        if [ -x "$test" ]; then
            check_pass "  └─ Script is executable"
        else
            check_warn "  └─ Script is not executable (chmod +x needed)"
        fi
        
        # Check for shebang
        if head -n 1 "$test" | grep -q "^#!/bin/bash"; then
            check_pass "  └─ Has proper shebang"
        else
            check_warn "  └─ Missing or incorrect shebang"
        fi
    else
        check_fail "$(basename "$test") not found"
    fi
done

# ============================================================================
# 5. DEPLOYMENT SCRIPTS VALIDATION
# ============================================================================
print_section "5. Deployment Scripts Validation"

# Check scripts directory
if [ -d "scripts" ]; then
    check_pass "Scripts directory exists"
else
    check_fail "Scripts directory not found"
fi

# Check for deployment scripts
deployment_scripts=(
    "scripts/deploy-infrastructure.sh"
    "scripts/cleanup-infrastructure.sh"
    "scripts/validate-deployment.sh"
    "scripts/extract-credentials.sh"
)

for script in "${deployment_scripts[@]}"; do
    if [ -f "$script" ]; then
        check_pass "$(basename "$script") exists"
        
        # Check if executable
        if [ -x "$script" ]; then
            check_pass "  └─ Script is executable"
        else
            check_warn "  └─ Script is not executable (chmod +x needed)"
        fi
    else
        check_fail "$(basename "$script") not found"
    fi
done

# ============================================================================
# 6. PROFESSIONAL DELIVERABLES VALIDATION
# ============================================================================
print_section "6. Professional Deliverables Validation"

# Check Medium article
if [ -f "docs/MEDIUM_ARTICLE.md" ]; then
    if grep -q "# " docs/MEDIUM_ARTICLE.md && \
       [ $(wc -l < docs/MEDIUM_ARTICLE.md) -gt 100 ]; then
        check_pass "Medium article exists and has substantial content"
    else
        check_warn "Medium article exists but may need more content"
    fi
else
    check_fail "Medium article not found"
fi

# Check LinkedIn post
if [ -f "docs/LINKEDIN_POST.md" ]; then
    if [ $(wc -l < docs/LINKEDIN_POST.md) -gt 10 ]; then
        check_pass "LinkedIn post exists and has content"
    else
        check_warn "LinkedIn post exists but may need more content"
    fi
else
    check_fail "LinkedIn post not found"
fi

# ============================================================================
# 7. LICENSE AND METADATA VALIDATION
# ============================================================================
print_section "7. License and Metadata Validation"

# Check LICENSE file
if [ -f "LICENSE" ]; then
    check_pass "LICENSE file exists"
else
    check_warn "LICENSE file not found"
fi

# Check .gitignore
if [ -f ".gitignore" ]; then
    if grep -q "tfstate\|.terraform" .gitignore; then
        check_pass ".gitignore exists with Terraform entries"
    else
        check_warn ".gitignore exists but may be missing Terraform entries"
    fi
else
    check_warn ".gitignore not found"
fi

# ============================================================================
# 8. CONTENT QUALITY CHECKS
# ============================================================================
print_section "8. Content Quality Checks"

# Check for broken internal links in README
if command -v grep &> /dev/null; then
    broken_links=0
    while IFS= read -r link; do
        # Extract file path from markdown link
        file_path=$(echo "$link" | sed -n 's/.*(\([^)]*\)).*/\1/p' | sed 's/#.*//')
        if [ -n "$file_path" ] && [ ! -f "$file_path" ]; then
            ((broken_links++))
        fi
    done < <(grep -o '\[.*\](.*\.md[^)]*)' README.md 2>/dev/null || true)
    
    if [ $broken_links -eq 0 ]; then
        check_pass "No broken internal links detected in README"
    else
        check_warn "Found $broken_links potential broken links in README"
    fi
fi

# Check for TODO or FIXME comments (excluding this validation script)
if grep -r "TODO\|FIXME" docs/ terraform/ validation-tests/ scripts/ 2>/dev/null | grep -v ".git" | grep -v "final-validation.sh" > /dev/null; then
    check_warn "Found TODO/FIXME comments in code (may need attention)"
else
    check_pass "No TODO/FIXME comments found"
fi

# Check for placeholder text
if grep -r "PLACEHOLDER\|CHANGEME\|REPLACEME" docs/ terraform/ 2>/dev/null | grep -v ".git" > /dev/null; then
    check_warn "Found placeholder text that may need updating"
else
    check_pass "No placeholder text found"
fi

# ============================================================================
# 9. PROPERTY-BASED TESTS VALIDATION
# ============================================================================
print_section "9. Property-Based Tests Validation"

# Check that property tests have proper annotations
pbt_tests=(
    "validation-tests/test-irsa-access-control.sh"
    "validation-tests/test-credential-rotation.sh"
    "validation-tests/test-infrastructure-best-practices.sh"
    "validation-tests/test-no-static-credentials.sh"
)

for test in "${pbt_tests[@]}"; do
    if [ -f "$test" ]; then
        # Check for property annotation
        if grep -q "Feature:.*Property" "$test"; then
            check_pass "$(basename "$test") has property annotation"
        else
            check_warn "$(basename "$test") missing property annotation"
        fi
        
        # Check for requirements validation
        if grep -q "Validates: Requirements" "$test"; then
            check_pass "  └─ Has requirements validation comment"
        else
            check_warn "  └─ Missing requirements validation comment"
        fi
    fi
done

# ============================================================================
# 10. WORKSHOP COMPLETENESS CHECK
# ============================================================================
print_section "10. Workshop Completeness Check"

# Count documentation files
doc_count=$(find docs/ -name "*.md" -type f 2>/dev/null | wc -l)
if [ $doc_count -ge 20 ]; then
    check_pass "Comprehensive documentation ($doc_count files)"
else
    check_warn "Documentation may be incomplete ($doc_count files)"
fi

# Count validation tests
test_count=$(find validation-tests/ -name "*.sh" -type f 2>/dev/null | wc -l)
if [ $test_count -ge 8 ]; then
    check_pass "Comprehensive test suite ($test_count tests)"
else
    check_warn "Test suite may be incomplete ($test_count tests)"
fi

# Check Terraform modules
module_count=$(find terraform/modules/ -name "main.tf" -type f 2>/dev/null | wc -l)
if [ $module_count -ge 4 ]; then
    check_pass "Complete Terraform infrastructure ($module_count modules)"
else
    check_warn "Terraform infrastructure may be incomplete ($module_count modules)"
fi

# ============================================================================
# FINAL SUMMARY
# ============================================================================
print_section "Validation Summary"

echo ""
echo -e "Total Checks:   ${BLUE}$TOTAL_CHECKS${NC}"
echo -e "Passed:         ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Failed:         ${RED}$FAILED_CHECKS${NC}"
echo -e "Warnings:       ${YELLOW}$WARNING_CHECKS${NC}"
echo ""

# Calculate success rate
if [ $TOTAL_CHECKS -gt 0 ]; then
    success_rate=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    echo -e "Success Rate:   ${BLUE}${success_rate}%${NC}"
    echo ""
fi

# Final verdict
if [ $FAILED_CHECKS -eq 0 ]; then
    if [ $WARNING_CHECKS -eq 0 ]; then
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✓ WORKSHOP VALIDATION PASSED - ALL CHECKS SUCCESSFUL     ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        exit 0
    else
        echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  ⚠ WORKSHOP VALIDATION PASSED WITH WARNINGS               ║${NC}"
        echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "The workshop is complete but has some warnings that should be reviewed."
        exit 0
    fi
else
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ✗ WORKSHOP VALIDATION FAILED - ISSUES FOUND              ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Please address the failed checks above before considering the workshop complete."
    exit 1
fi
