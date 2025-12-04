# Validation Tests

This directory contains property-based tests that validate the security properties and best practices of the Harbor IRSA workshop infrastructure.

## Overview

These tests use a bash-based property testing approach to verify that the workshop infrastructure follows security best practices and that the secure IRSA deployment path does not contain static credentials.

## Prerequisites

- **jq**: JSON processor for parsing AWS CLI and kubectl output
- **AWS CLI**: For testing AWS resources (optional, only needed for infrastructure tests)
- **kubectl**: For testing deployed Kubernetes resources (optional, only needed for deployed pod tests)

Install prerequisites:

```bash
# macOS
brew install jq awscli kubectl

# Ubuntu/Debian
apt-get install jq awscli kubectl

# RHEL/CentOS
yum install jq awscli kubectl
```

## Available Tests

### 1. Credential Extraction Test (Insecure Path)

**File**: `test-credential-extraction-insecure.sh`

**Purpose**: Demonstrates how static IAM user credentials can be extracted from Kubernetes secrets in the insecure deployment approach.

**Validates**: Requirements 6.1

**What it tests**:
- How to extract credentials from Kubernetes secrets
- Base64 decoding of credentials
- Security implications of storing credentials in secrets
- One-liner credential theft techniques
- Comparison with IRSA secure approach

**Usage**:

```bash
# Run the demonstration
./test-credential-extraction-insecure.sh

# Run with cleanup
./test-credential-extraction-insecure.sh --cleanup
```

**Requirements**:
- kubectl must be installed and configured
- Kubernetes cluster must be accessible
- Creates a demo namespace with fake credentials

### 2. IRSA Access Validation Test

**File**: `test-irsa-access-validation.sh`

**Purpose**: Verifies that Harbor pods can access S3 using IRSA without static credentials.

**Validates**: Requirements 4.7

**What it tests**:
- No static credentials present in pod
- AWS SDK can discover credentials via IRSA
- S3 operations succeed with temporary credentials
- Credentials automatically rotate
- Pod uses assumed role (not IAM user)

**Usage**:

```bash
# Run the test
./test-irsa-access-validation.sh

# Run without cleanup (keep test pod)
./test-irsa-access-validation.sh --no-cleanup
```

**Requirements**:
- Harbor namespace and service account must exist
- Service account must have IRSA annotation
- S3 bucket must be accessible
- IAM role must have S3 permissions

### 3. IRSA Access Control Enforcement Test (Property-Based)

**File**: `test-irsa-access-control.sh`

**Property**: For any Kubernetes service account and namespace combination, S3 access should be granted if and only if the service account is `harbor-registry` in the `harbor` namespace with the correct IAM role annotation.

**Validates**: Requirements 4.7, 4.8, 6.3

**What it tests**:
- Authorized service account CAN access S3
- Unauthorized service accounts CANNOT access S3
- Wrong namespace with correct SA name CANNOT access S3
- Correct namespace with wrong SA name CANNOT access S3
- Trust policy properly restricts access

**Usage**:

```bash
# Run the property test (10 iterations)
./test-irsa-access-control.sh
```

**Requirements**:
- Harbor namespace and service account must exist
- S3 bucket must be accessible
- IAM role trust policy must be configured

### 4. Automatic Credential Rotation Test (Property-Based)

**File**: `test-credential-rotation.sh`

**Property**: For any Harbor pod using IRSA, the AWS credentials (temporary session token) should automatically refresh before expiration without manual intervention or pod restart.

**Validates**: Requirements 6.2

**What it tests**:
- Credentials are temporary (session-based)
- S3 access maintained continuously
- No manual intervention required
- No pod restart required
- Token has valid expiration time

**Usage**:

```bash
# Run the property test (monitors for 5 minutes per iteration)
./test-credential-rotation.sh

# Run without cleanup
./test-credential-rotation.sh --no-cleanup
```

**Requirements**:
- Harbor namespace and service account must exist
- Service account must have IRSA annotation
- S3 bucket must be accessible

### 5. Access Denial Test

**File**: `test-access-denial.sh`

**Purpose**: Creates unauthorized service accounts and attempts S3 access from unauthorized pods to verify access is properly denied.

**Validates**: Requirements 4.8

**What it tests**:
- Unauthorized pods cannot get AWS credentials
- Unauthorized pods cannot list S3 bucket
- Unauthorized pods cannot write to S3 bucket
- No AWS credentials in pod environment
- Service accounts without IRSA annotation are denied
- Default service account is properly restricted
- Error messages are informative

**Usage**:

```bash
# Run the test
./test-access-denial.sh

# Run without cleanup
./test-access-denial.sh --no-cleanup
```

**Requirements**:
- Kubernetes cluster must be accessible
- S3 bucket must be configured
- Creates temporary test namespace

### 6. Log Verification Test

**File**: `test-log-verification.sh`

**Purpose**: Collects and analyzes CloudTrail logs showing IRSA identity and Kubernetes logs for service account token projection.

**Validates**: Requirements 6.4, 6.5

**What it tests**:
- Service account token projection is configured
- CloudTrail shows IRSA identity attribution
- Audit trail allows tracing to specific pods
- Log analysis procedures
- Incident investigation capabilities

**Usage**:

```bash
# Run the test
./test-log-verification.sh
```

**Requirements**:
- Harbor namespace and service account must exist
- AWS CLI must be installed (for CloudTrail queries)
- CloudTrail must be enabled
- Recent S3 operations for log analysis

### 7. Error Scenario Demonstrations

**File**: `test-error-scenarios.sh`

**Purpose**: Demonstrates common misconfigurations, shows error messages and logs, and provides resolution steps.

**Validates**: Requirements 6.6

**What it covers**:
- Missing IRSA annotation
- Wrong IAM role ARN
- Trust policy mismatch
- Missing S3 permissions
- OIDC provider not configured
- Pod not using service account
- KMS key access denied
- Token expiration issues
- Wrong namespace
- General debugging checklist

**Usage**:

```bash
# Run the demonstrations
./test-error-scenarios.sh
```

**Requirements**:
- kubectl must be installed
- Demonstrates error scenarios (no actual deployment needed)

### 8. Infrastructure Best Practices Test

**File**: `test-infrastructure-best-practices.sh`

**Property**: For any AWS resource created by the workshop infrastructure code (S3 buckets, KMS keys, IAM roles), the resource should have appropriate tags (Environment, Project, ManagedBy), encryption enabled where applicable, and follow AWS security best practices.

**Validates**: Requirements 5.6

**What it tests**:
- S3 bucket has required tags
- S3 bucket has KMS encryption enabled
- S3 bucket has versioning enabled
- S3 bucket has public access blocked
- S3 bucket policy enforces encryption and TLS
- KMS key has required tags
- KMS key rotation is enabled
- KMS key is customer managed
- IAM role has required tags
- IAM role uses IRSA (AssumeRoleWithWebIdentity)
- IAM role has conditions for namespace/service account restriction
- IAM role follows least privilege principles
- EKS cluster has required tags (if applicable)
- EKS cluster has OIDC provider enabled
- EKS cluster has encryption enabled

**Usage**:

```bash
# Run the test (requires deployed infrastructure)
./test-infrastructure-best-practices.sh
```

**Requirements**:
- Infrastructure must be deployed via Terraform
- AWS CLI must be configured with appropriate credentials
- Terraform outputs must be available

### 9. No Static Credentials Test

**File**: `test-no-static-credentials.sh`

**Property**: For any pod specification in the secure IRSA deployment path, the pod should not contain AWS credentials in environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY), volumes, or configMaps. All AWS authentication should occur through IRSA projected service account tokens.

**Validates**: Requirements 7.5

**What it tests**:
- YAML files do not contain AWS credential environment variables
- YAML files do not contain static credentials in S3 configuration
- Service accounts have IRSA annotations
- Helm values explicitly document credential-free configuration
- Kubernetes secrets do not contain AWS credentials
- Pod specifications do not have AWS credential environment variables
- Deployed pods use service accounts with IRSA annotations
- Deployed pods have projected service account token volumes
- Deployed pods do not mount secrets containing AWS credentials

**Usage**:

```bash
# Run the test (works without deployed infrastructure)
./test-no-static-credentials.sh
```

**Requirements**:
- jq must be installed
- kubectl is optional (for testing deployed pods)
- If kubectl is available and cluster is accessible, it will also test deployed pods

## Test Configuration

Both tests run **10 iterations** by default to ensure comprehensive coverage. This can be modified by editing the `MIN_ITERATIONS` variable in each script.

## Understanding Test Output

### Color Coding

- 🔵 **Blue**: Informational messages
- ✅ **Green**: Passed tests
- ❌ **Red**: Failed tests
- ⚠️ **Yellow**: Warnings (non-critical issues)

### Test Results

Each test displays:
- Number of passed tests
- Number of failed tests
- Total tests run
- Pass rate percentage

### Exit Codes

- **0**: All tests passed
- **1**: One or more tests failed

## Running All Tests

To run all validation tests:

```bash
# Educational demonstrations (no infrastructure required)
./test-credential-extraction-insecure.sh
./test-error-scenarios.sh

# Validation tests (require deployed infrastructure)
./test-irsa-access-validation.sh
./test-access-denial.sh
./test-log-verification.sh

# Property-based tests (require deployed infrastructure)
./test-irsa-access-control.sh
./test-credential-rotation.sh
./test-infrastructure-best-practices.sh
./test-no-static-credentials.sh
```

Or create a comprehensive test runner:

```bash
#!/bin/bash
echo "Running all validation tests..."

# Educational demonstrations
echo "=== Educational Demonstrations ==="
./test-credential-extraction-insecure.sh
./test-error-scenarios.sh

# Validation tests
echo "=== Validation Tests ==="
./test-irsa-access-validation.sh
./test-access-denial.sh
./test-log-verification.sh

# Property-based tests
echo "=== Property-Based Tests ==="
./test-irsa-access-control.sh
./test-credential-rotation.sh
./test-infrastructure-best-practices.sh
./test-no-static-credentials.sh

echo "All tests completed!"
```

## Continuous Integration

These tests can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Run Validation Tests
  run: |
    cd validation-tests
    ./test-infrastructure-best-practices.sh
    ./test-no-static-credentials.sh
```

## Troubleshooting

### Test fails with "jq is not installed"

Install jq using your package manager (see Prerequisites section).

### Test fails with "AWS CLI is not installed"

Install AWS CLI using your package manager or from https://aws.amazon.com/cli/

### Test fails with "Terraform directory not found"

Ensure you're running the test from the correct directory and that the Terraform infrastructure exists.

### Test fails with "Could not retrieve resource identifiers from Terraform"

Ensure infrastructure is deployed:

```bash
cd ../terraform
terraform init
terraform apply
```

### Test shows warnings about Kubernetes cluster not accessible

This is normal if you don't have a Kubernetes cluster running. The test will skip deployed pod tests and only test YAML files.

## Property-Based Testing Approach

These tests follow property-based testing principles:

1. **Universal Properties**: Tests verify properties that should hold for ALL instances, not just specific examples
2. **Multiple Iterations**: Each test runs 10 iterations to ensure consistency
3. **Comprehensive Coverage**: Tests check multiple aspects of each resource
4. **Clear Failure Messages**: When tests fail, they provide specific information about what went wrong

## Contributing

When adding new validation tests:

1. Follow the existing test structure
2. Use property-based testing principles
3. Include clear comments explaining what the test validates
4. Reference the specific requirement from the design document
5. Make tests idempotent (can be run multiple times safely)
6. Provide helpful error messages
7. Update this README with the new test information

## Related Documentation

- [Design Document](../.kiro/specs/harbor-irsa-workshop/design.md) - Contains correctness properties
- [Requirements Document](../.kiro/specs/harbor-irsa-workshop/requirements.md) - Contains acceptance criteria
- [Workshop Lab Guide](../docs/WORKSHOP_LAB_GUIDE.md) - Complete workshop instructions
