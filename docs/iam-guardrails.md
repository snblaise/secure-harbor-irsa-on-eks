# IAM Guardrails for IRSA Deployments

## Overview

This guide documents IAM guardrails and governance controls that provide defense-in-depth for IRSA deployments. While IRSA significantly improves security over static IAM user credentials, implementing additional IAM guardrails ensures that even if an IRSA role is compromised or misconfigured, the blast radius is limited and organizational security policies are enforced.

IAM guardrails include permission boundaries, Service Control Policies (SCPs), IAM policy validation, and monitoring controls that work together to create multiple layers of protection.

## Table of Contents

1. [Understanding IAM Guardrails](#understanding-iam-guardrails)
2. [Permission Boundaries for IRSA Roles](#permission-boundaries-for-irsa-roles)
3. [Service Control Policy (SCP) Considerations](#service-control-policy-scp-considerations)
4. [IAM Policy Validation Procedures](#iam-policy-validation-procedures)
5. [IAM Access Analyzer](#iam-access-analyzer)
6. [Monitoring and Alerting](#monitoring-and-alerting)
7. [Best Practices Summary](#best-practices-summary)
8. [Troubleshooting](#troubleshooting)

## Understanding IAM Guardrails

### What Are IAM Guardrails?

IAM guardrails are preventive and detective controls that establish boundaries around IAM permissions. They work as safety nets that:

- **Prevent** overly permissive policies from being created
- **Limit** the maximum permissions any role can have
- **Detect** policy violations and misconfigurations
- **Alert** security teams to suspicious activity
- **Enforce** organizational security standards

### Defense in Depth Layers

For Harbor IRSA deployments, we implement multiple security layers:

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: Service Control Policies (SCPs)                   │
│  Organization-wide restrictions (e.g., deny region access)   │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│  Layer 2: Permission Boundaries                              │
│  Maximum permissions any IRSA role can have                  │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│  Layer 3: IAM Role Permissions Policy                       │
│  Least-privilege S3 and KMS access for Harbor               │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│  Layer 4: IAM Role Trust Policy                             │
│  Restricts to specific namespace and service account        │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│  Layer 5: Resource Policies (S3 Bucket, KMS Key)            │
│  Additional restrictions at resource level                   │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│  Layer 6: Monitoring and Detection                          │
│  CloudTrail, IAM Access Analyzer, GuardDuty                 │
└─────────────────────────────────────────────────────────────┘
```

### Why Guardrails Matter for IRSA

Even with IRSA's security improvements, guardrails provide additional protection:

✅ **Prevent privilege escalation**: Even if trust policy is misconfigured, permission boundary limits damage  
✅ **Enforce organizational policies**: SCPs ensure compliance with company-wide security rules  
✅ **Detect misconfigurations**: IAM Access Analyzer identifies overly permissive policies  
✅ **Limit blast radius**: If a role is compromised, guardrails contain the impact  
✅ **Audit compliance**: Automated validation ensures policies meet security standards  

## Permission Boundaries for IRSA Roles

### What is a Permission Boundary?

A permission boundary is an advanced IAM feature that sets the **maximum permissions** an IAM entity (user or role) can have. Even if a role's permissions policy grants broad access, the permission boundary restricts what actions can actually be performed.

**Key Concept**: The effective permissions are the **intersection** of:
- Permissions policy (what the role is granted)
- Permission boundary (maximum allowed permissions)
- SCPs (organization-wide restrictions)

### Why Use Permission Boundaries for IRSA?

Permission boundaries provide an additional safety net:

1. **Prevent misconfiguration**: If someone accidentally grants `s3:*`, the boundary limits it
2. **Enforce least privilege**: Ensures roles can't exceed organizational limits
3. **Delegation safety**: Allows teams to create roles within defined boundaries
4. **Compliance**: Demonstrates defense-in-depth for auditors

### Creating a Permission Boundary for Harbor IRSA

#### Step 1: Define the Permission Boundary Policy

Create a permission boundary that defines the maximum permissions any Harbor-related IRSA role can have:

```bash
cat > harbor-irsa-permission-boundary.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3AccessToHarborBuckets",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning",
        "s3:ListBucketVersions"
      ],
      "Resource": [
        "arn:aws:s3:::harbor-*",
        "arn:aws:s3:::harbor-*/*"
      ]
    },
    {
      "Sid": "AllowKMSForS3Encryption",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": [
            "s3.*.amazonaws.com"
          ]
        },
        "StringLike": {
          "kms:ResourceAliases": "alias/harbor-*"
        }
      }
    },
    {
      "Sid": "AllowCloudWatchLogsForHarbor",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/harbor/*"
    },
    {
      "Sid": "DenyDangerousActions",
      "Effect": "Deny",
      "Action": [
        "iam:*",
        "organizations:*",
        "account:*",
        "s3:DeleteBucket",
        "s3:PutBucketPolicy",
        "s3:DeleteBucketPolicy",
        "kms:ScheduleKeyDeletion",
        "kms:DeleteAlias",
        "kms:PutKeyPolicy"
      ],
      "Resource": "*"
    }
  ]
}
EOF
```

#### Step 2: Create the Permission Boundary Policy

```bash
# Set environment variables
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="us-east-1"

# Create the permission boundary policy
aws iam create-policy \
  --policy-name HarborIRSAPermissionBoundary \
  --policy-document file://harbor-irsa-permission-boundary.json \
  --description "Permission boundary for all Harbor IRSA roles - defines maximum allowed permissions" \
  --tags Key=Purpose,Value=PermissionBoundary Key=Application,Value=Harbor

# Capture the policy ARN
export PERMISSION_BOUNDARY_ARN=$(aws iam list-policies \
  --query "Policies[?PolicyName=='HarborIRSAPermissionBoundary'].Arn" \
  --output text)

echo "Permission Boundary ARN: ${PERMISSION_BOUNDARY_ARN}"
```

#### Step 3: Apply Permission Boundary to Existing Harbor Role

If you already created the Harbor IRSA role, apply the permission boundary:

```bash
export HARBOR_ROLE_NAME="HarborS3Role"

# Apply permission boundary to existing role
aws iam put-role-permissions-boundary \
  --role-name ${HARBOR_ROLE_NAME} \
  --permissions-boundary ${PERMISSION_BOUNDARY_ARN}

echo "✅ Permission boundary applied to ${HARBOR_ROLE_NAME}"
```

#### Step 4: Create New Roles with Permission Boundary

When creating new IRSA roles, include the permission boundary from the start:

```bash
# Create role with permission boundary
aws iam create-role \
  --role-name HarborS3Role \
  --assume-role-policy-document file://harbor-trust-policy.json \
  --permissions-boundary ${PERMISSION_BOUNDARY_ARN} \
  --description "IAM role for Harbor registry with permission boundary" \
  --tags Key=Environment,Value=workshop Key=Application,Value=harbor
```

#### Step 5: Verify Permission Boundary

```bash
# Check if permission boundary is applied
aws iam get-role --role-name ${HARBOR_ROLE_NAME} \
  --query 'Role.PermissionsBoundary' \
  --output json

# Expected output:
# {
#     "PermissionsBoundaryType": "Policy",
#     "PermissionsBoundaryArn": "arn:aws:iam::123456789012:policy/HarborIRSAPermissionBoundary"
# }
```

### Understanding Permission Boundary Behavior

#### Example 1: Boundary Restricts Overly Broad Policy

**Scenario**: Someone accidentally grants `s3:*` on all resources.

**Permissions Policy** (too broad):
```json
{
  "Effect": "Allow",
  "Action": "s3:*",
  "Resource": "*"
}
```

**Permission Boundary** (restricts):
```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
  "Resource": ["arn:aws:s3:::harbor-*", "arn:aws:s3:::harbor-*/*"]
}
```

**Effective Permissions** (intersection):
- ✅ Can perform GetObject, PutObject, DeleteObject, ListBucket on `harbor-*` buckets
- ❌ Cannot perform other S3 actions (e.g., DeleteBucket, PutBucketPolicy)
- ❌ Cannot access non-Harbor buckets

#### Example 2: Boundary Prevents Privilege Escalation

**Scenario**: Permissions policy tries to grant IAM permissions.

**Permissions Policy**:
```json
{
  "Effect": "Allow",
  "Action": "iam:CreateRole",
  "Resource": "*"
}
```

**Permission Boundary** (denies):
```json
{
  "Effect": "Deny",
  "Action": "iam:*",
  "Resource": "*"
}
```

**Effective Permissions**:
- ❌ Cannot create IAM roles (denied by boundary)
- ❌ Cannot perform any IAM actions

### Permission Boundary Best Practices

✅ **Apply to all IRSA roles**: Consistent boundaries across all workload roles  
✅ **Use explicit deny for dangerous actions**: Prevent IAM, Organizations, Account modifications  
✅ **Scope to application**: Use resource patterns like `harbor-*` to limit scope  
✅ **Include monitoring permissions**: Allow CloudWatch Logs for observability  
✅ **Document the boundary**: Explain why each permission is included  
✅ **Test thoroughly**: Verify roles work correctly with boundary applied  
✅ **Version control**: Store boundary policies in Git with change history  

❌ **Don't use wildcards excessively**: Be specific about allowed actions  
❌ **Don't forget to apply**: Boundary must be explicitly attached to roles  
❌ **Don't make it too restrictive**: Ensure legitimate operations still work  

## Service Control Policy (SCP) Considerations

### What are Service Control Policies?

Service Control Policies (SCPs) are AWS Organizations features that set **maximum permissions** for all IAM entities in an AWS account or organizational unit (OU). SCPs work at the organization level and affect all users and roles, including IRSA roles.

**Key Differences from Permission Boundaries**:
- **SCPs**: Apply to entire accounts/OUs, managed at organization level
- **Permission Boundaries**: Apply to individual roles, managed at account level

### SCP Architecture for Multi-Account Harbor Deployments

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Organization                          │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Root OU                                            │    │
│  │  SCP: DenyLeaveOrganization                         │    │
│  └──────────────────┬──────────────────────────────────┘    │
│                     │                                        │
│     ┌───────────────┴───────────────┐                       │
│     │                               │                       │
│  ┌──▼─────────────────┐  ┌──────────▼──────────────┐       │
│  │  Workloads OU      │  │  Security OU             │       │
│  │  SCP: DenyRegions  │  │  SCP: AllowAll           │       │
│  └──┬─────────────────┘  └──────────────────────────┘       │
│     │                                                        │
│  ┌──▼─────────────────────────────────────────┐            │
│  │  Dev Account (123456789012)                 │            │
│  │  - Harbor EKS Cluster                       │            │
│  │  - IRSA Roles (with permission boundaries)  │            │
│  │  - Affected by: DenyLeaveOrg + DenyRegions  │            │
│  └──────────────────────────────────────────────┘            │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Recommended SCPs for Harbor IRSA Deployments

#### SCP 1: Deny Unapproved Regions

Restrict Harbor deployments to approved AWS regions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnapprovedRegions",
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:RequestedRegion": [
            "us-east-1",
            "us-west-2",
            "eu-west-1"
          ]
        },
        "ArnNotLike": {
          "aws:PrincipalArn": [
            "arn:aws:iam::*:role/OrganizationAccountAccessRole",
            "arn:aws:iam::*:role/AWSControlTowerExecution"
          ]
        }
      }
    }
  ]
}
```

**Why this matters**: Prevents Harbor from being deployed in regions that don't meet compliance requirements (e.g., data residency).

#### SCP 2: Require Encryption for S3

Enforce encryption for all S3 operations:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnencryptedS3Uploads",
      "Effect": "Deny",
      "Action": "s3:PutObject",
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption": [
            "aws:kms",
            "AES256"
          ]
        }
      }
    },
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Action": "s3:*",
      "Resource": "*",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

**Why this matters**: Ensures Harbor's S3 storage is always encrypted, even if bucket policy is misconfigured.

#### SCP 3: Prevent IAM Privilege Escalation

Prevent IRSA roles from modifying IAM:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyIAMPrivilegeEscalation",
      "Effect": "Deny",
      "Action": [
        "iam:CreateAccessKey",
        "iam:CreateUser",
        "iam:CreateRole",
        "iam:AttachUserPolicy",
        "iam:AttachRolePolicy",
        "iam:PutUserPolicy",
        "iam:PutRolePolicy",
        "iam:UpdateAssumeRolePolicy",
        "iam:DeleteRolePermissionsBoundary",
        "iam:DeleteUserPermissionsBoundary"
      ],
      "Resource": "*",
      "Condition": {
        "ArnNotLike": {
          "aws:PrincipalArn": [
            "arn:aws:iam::*:role/Admin*",
            "arn:aws:iam::*:role/OrganizationAccountAccessRole"
          ]
        }
      }
    }
  ]
}
```

**Why this matters**: Even if an IRSA role is compromised, it cannot create new credentials or escalate privileges.

#### SCP 4: Require MFA for Sensitive Operations

Require MFA for operations that could affect Harbor:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RequireMFAForSensitiveOperations",
      "Effect": "Deny",
      "Action": [
        "s3:DeleteBucket",
        "kms:ScheduleKeyDeletion",
        "kms:DeleteAlias",
        "eks:DeleteCluster",
        "iam:DeleteRole"
      ],
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {
          "aws:MultiFactorAuthPresent": "false"
        },
        "ArnNotLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:role/*"
        }
      }
    }
  ]
}
```

**Why this matters**: Prevents accidental or malicious deletion of critical Harbor infrastructure by human users without MFA.

### SCP Best Practices for IRSA

✅ **Start with deny lists**: Use SCPs to deny dangerous actions, not to grant permissions  
✅ **Test in non-production**: Apply SCPs to test accounts first  
✅ **Exclude admin roles**: Allow break-glass access for administrators  
✅ **Document exceptions**: Clearly explain why certain principals are excluded  
✅ **Layer with permission boundaries**: SCPs + boundaries provide defense in depth  
✅ **Monitor SCP changes**: Alert on any modifications to SCPs  

❌ **Don't use SCPs for allow lists**: SCPs should restrict, not grant  
❌ **Don't lock yourself out**: Always exclude admin/break-glass roles  
❌ **Don't apply without testing**: SCPs affect all principals in the account  

### Checking if SCPs Affect Your Account

```bash
# Check if your account is part of an organization
aws organizations describe-organization 2>/dev/null

# If in an organization, list SCPs affecting your account
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# List policies attached to the account
aws organizations list-policies-for-target \
  --target-id ${AWS_ACCOUNT_ID} \
  --filter SERVICE_CONTROL_POLICY

# Get details of a specific SCP
aws organizations describe-policy \
  --policy-id p-xxxxxxxx
```

**Note**: You need Organizations permissions to view SCPs. If you don't have access, contact your AWS administrator.

## IAM Policy Validation Procedures

### Automated Policy Validation

AWS provides several tools to validate IAM policies before and after deployment.

#### 1. IAM Policy Validator (AWS CLI)

Validate policy syntax and identify errors:

```bash
# Validate a policy document
aws accessanalyzer validate-policy \
  --policy-document file://harbor-s3-permissions-policy.json \
  --policy-type IDENTITY_POLICY \
  --region us-east-1

# Expected output for valid policy:
# {
#     "findings": []
# }
```

**Common findings**:
- **ERROR**: Policy syntax errors that prevent the policy from working
- **SECURITY_WARNING**: Potential security issues (e.g., overly broad permissions)
- **WARNING**: Best practice violations
- **SUGGESTION**: Recommendations for improvement

#### 2. Custom Policy Validation Script

Create a validation script for Harbor IRSA policies:

```bash
cat > validate-harbor-policy.sh << 'EOF'
#!/bin/bash

set -e

POLICY_FILE=$1
POLICY_TYPE=${2:-IDENTITY_POLICY}

if [ -z "$POLICY_FILE" ]; then
  echo "Usage: $0 <policy-file> [policy-type]"
  echo "Example: $0 harbor-s3-permissions-policy.json IDENTITY_POLICY"
  exit 1
fi

echo "🔍 Validating policy: $POLICY_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Validate JSON syntax
echo "✓ Checking JSON syntax..."
jq empty "$POLICY_FILE" 2>/dev/null || {
  echo "❌ Invalid JSON syntax"
  exit 1
}

# 2. Validate with AWS Access Analyzer
echo "✓ Validating with AWS Access Analyzer..."
FINDINGS=$(aws accessanalyzer validate-policy \
  --policy-document file://"$POLICY_FILE" \
  --policy-type "$POLICY_TYPE" \
  --region us-east-1 \
  --query 'findings' \
  --output json)

FINDING_COUNT=$(echo "$FINDINGS" | jq 'length')

if [ "$FINDING_COUNT" -eq 0 ]; then
  echo "✅ No findings - policy is valid!"
else
  echo "⚠️  Found $FINDING_COUNT issue(s):"
  echo "$FINDINGS" | jq -r '.[] | "  - [\(.findingType)] \(.findingDetails)"'
  
  # Check for errors
  ERROR_COUNT=$(echo "$FINDINGS" | jq '[.[] | select(.findingType == "ERROR")] | length')
  if [ "$ERROR_COUNT" -gt 0 ]; then
    echo "❌ Policy has errors and will not work"
    exit 1
  fi
fi

# 3. Check for overly permissive patterns
echo "✓ Checking for overly permissive patterns..."
WILDCARDS=$(jq -r '.Statement[].Action | if type == "array" then .[] else . end' "$POLICY_FILE" | grep -c '\*' || true)
if [ "$WILDCARDS" -gt 0 ]; then
  echo "⚠️  Found $WILDCARDS wildcard action(s) - review for least privilege"
fi

WILDCARD_RESOURCES=$(jq -r '.Statement[].Resource | if type == "array" then .[] else . end' "$POLICY_FILE" | grep -c '^\*$' || true)
if [ "$WILDCARD_RESOURCES" -gt 0 ]; then
  echo "⚠️  Found $WILDCARD_RESOURCES wildcard resource(s) - consider scoping to specific resources"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Validation complete"
EOF

chmod +x validate-harbor-policy.sh
```

**Usage**:
```bash
# Validate permissions policy
./validate-harbor-policy.sh harbor-s3-permissions-policy.json IDENTITY_POLICY

# Validate trust policy
./validate-harbor-policy.sh harbor-trust-policy.json RESOURCE_POLICY
```

#### 3. Policy Simulator

Test what actions a role can perform before deploying:

```bash
# Simulate S3 PutObject action
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/HarborS3Role \
  --action-names s3:PutObject \
  --resource-arns arn:aws:s3:::harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION}/test-object

# Expected output:
# {
#     "EvaluationResults": [
#         {
#             "EvalActionName": "s3:PutObject",
#             "EvalResourceName": "arn:aws:s3:::harbor-registry-storage-123456789012-us-east-1/test-object",
#             "EvalDecision": "allowed",
#             ...
#         }
#     ]
# }

# Test denied action (should be denied)
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/HarborS3Role \
  --action-names iam:CreateUser \
  --resource-arns "*"

# Expected: EvalDecision: "implicitDeny" or "explicitDeny"
```

#### 4. Continuous Policy Validation

Set up automated validation in CI/CD:

```yaml
# .github/workflows/validate-iam-policies.yml
name: Validate IAM Policies

on:
  pull_request:
    paths:
      - 'iam-policies/**/*.json'
  push:
    branches:
      - main

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1
      
      - name: Validate IAM Policies
        run: |
          for policy in iam-policies/*.json; do
            echo "Validating $policy..."
            aws accessanalyzer validate-policy \
              --policy-document file://$policy \
              --policy-type IDENTITY_POLICY \
              --region us-east-1
          done
      
      - name: Check for Security Warnings
        run: |
          for policy in iam-policies/*.json; do
            FINDINGS=$(aws accessanalyzer validate-policy \
              --policy-document file://$policy \
              --policy-type IDENTITY_POLICY \
              --region us-east-1 \
              --query 'findings[?findingType==`SECURITY_WARNING`]' \
              --output json)
            
            if [ "$(echo $FINDINGS | jq 'length')" -gt 0 ]; then
              echo "Security warnings found in $policy"
              echo $FINDINGS | jq .
              exit 1
            fi
          done
```

### Manual Policy Review Checklist

Before deploying any IRSA policy, review:

**Permissions Policy**:
- [ ] Actions are scoped to minimum required (no `*` unless necessary)
- [ ] Resources are specific (no `"Resource": "*"` unless required)
- [ ] Conditions are used to further restrict access
- [ ] No administrative actions (IAM, Organizations, Account)
- [ ] Encryption is enforced where applicable
- [ ] Policy follows naming conventions

**Trust Policy**:
- [ ] OIDC provider ARN is correct
- [ ] Namespace is specified in `:sub` condition
- [ ] Service account is specified in `:sub` condition
- [ ] Audience (`:aud`) is set to `sts.amazonaws.com`
- [ ] No wildcards in conditions
- [ ] StringEquals (not StringLike) is used for exact matching

**Permission Boundary** (if applicable):
- [ ] Boundary is attached to the role
- [ ] Boundary allows all necessary actions
- [ ] Boundary denies dangerous actions
- [ ] Boundary is versioned and tracked in Git

## IAM Access Analyzer

### What is IAM Access Analyzer?

IAM Access Analyzer helps you identify resources that are shared with external entities and validates IAM policies. For IRSA deployments, it provides:

1. **External access findings**: Identifies if S3 buckets or KMS keys are accessible outside your account
2. **Policy validation**: Checks policies for errors and security issues
3. **Unused access**: Identifies permissions that are granted but never used

### Setting Up IAM Access Analyzer

#### Step 1: Enable IAM Access Analyzer

```bash
# Create an analyzer for your account
aws accessanalyzer create-analyzer \
  --analyzer-name harbor-irsa-analyzer \
  --type ACCOUNT \
  --tags Key=Application,Value=Harbor Key=Purpose,Value=SecurityAnalysis

# Get analyzer ARN
export ANALYZER_ARN=$(aws accessanalyzer list-analyzers \
  --query "analyzers[?name=='harbor-irsa-analyzer'].arn" \
  --output text)

echo "Analyzer ARN: ${ANALYZER_ARN}"
```

#### Step 2: Review Findings

```bash
# List all findings
aws accessanalyzer list-findings \
  --analyzer-arn ${ANALYZER_ARN} \
  --output table

# Get details of a specific finding
aws accessanalyzer get-finding \
  --analyzer-arn ${ANALYZER_ARN} \
  --id <finding-id>

# Filter findings by resource type
aws accessanalyzer list-findings \
  --analyzer-arn ${ANALYZER_ARN} \
  --filter resourceType=AWS::S3::Bucket \
  --output json
```

#### Step 3: Analyze Harbor S3 Bucket

```bash
# Check if Harbor S3 bucket has external access
export S3_BUCKET_NAME="harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION}"

aws accessanalyzer list-findings \
  --analyzer-arn ${ANALYZER_ARN} \
  --filter "resourceType=AWS::S3::Bucket,resource=arn:aws:s3:::${S3_BUCKET_NAME}" \
  --output json

# Expected: No findings (bucket should not be externally accessible)
```

#### Step 4: Analyze KMS Key

```bash
# Check if KMS key has external access
export KMS_KEY_ID="12345678-1234-1234-1234-123456789012"

aws accessanalyzer list-findings \
  --analyzer-arn ${ANALYZER_ARN} \
  --filter "resourceType=AWS::KMS::Key,resource=arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/${KMS_KEY_ID}" \
  --output json

# Expected: No findings (key should only be accessible by Harbor role)
```

### Automated Access Analyzer Monitoring

Create a Lambda function to monitor Access Analyzer findings:

```python
# lambda/access-analyzer-monitor.py
import boto3
import json
import os

analyzer_client = boto3.client('accessanalyzer')
sns_client = boto3.client('sns')

ANALYZER_ARN = os.environ['ANALYZER_ARN']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']

def lambda_handler(event, context):
    """Monitor IAM Access Analyzer findings and alert on new issues"""
    
    # List active findings
    response = analyzer_client.list_findings(
        analyzerArn=ANALYZER_ARN,
        filter={
            'status': {
                'eq': ['ACTIVE']
            }
        }
    )
    
    findings = response.get('findings', [])
    
    if findings:
        # Alert on active findings
        message = f"⚠️ IAM Access Analyzer Alert\n\n"
        message += f"Found {len(findings)} active finding(s):\n\n"
        
        for finding in findings:
            message += f"- Resource: {finding['resource']}\n"
            message += f"  Type: {finding['resourceType']}\n"
            message += f"  Principal: {finding.get('principal', {}).get('AWS', 'N/A')}\n"
            message += f"  Condition: {finding.get('condition', 'N/A')}\n\n"
        
        # Send SNS notification
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject='IAM Access Analyzer Alert - Harbor IRSA',
            Message=message
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Alerted on {len(findings)} findings')
        }
    
    return {
        'statusCode': 200,
        'body': json.dumps('No active findings')
    }
```

### Unused Access Analysis

Identify permissions that are granted but never used:

```bash
# Generate unused access report for Harbor role
aws accessanalyzer start-resource-scan \
  --analyzer-arn ${ANALYZER_ARN} \
  --resource-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/HarborS3Role

# Wait for scan to complete (may take a few minutes)
sleep 60

# Get unused access findings
aws accessanalyzer list-findings \
  --analyzer-arn ${ANALYZER_ARN} \
  --filter "resourceType=AWS::IAM::Role,resource=arn:aws:iam::${AWS_ACCOUNT_ID}:role/HarborS3Role" \
  --output json | jq '.findings[] | select(.findingType == "UnusedIAMUserAccessKey" or .findingType == "UnusedIAMRole")'
```

**Action**: If permissions are unused for 90+ days, consider removing them to further reduce the attack surface.

## Monitoring and Alerting

### CloudWatch Alarms for IAM Changes

Monitor changes to Harbor IRSA roles:

```bash
# Create CloudWatch alarm for IAM role changes
aws cloudwatch put-metric-alarm \
  --alarm-name harbor-iam-role-changes \
  --alarm-description "Alert on changes to Harbor IRSA role" \
  --metric-name IAMPolicyChanges \
  --namespace AWS/CloudTrail \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:security-alerts

# Create metric filter for IAM role changes
aws logs put-metric-filter \
  --log-group-name /aws/cloudtrail/logs \
  --filter-name HarborIAMRoleChanges \
  --filter-pattern '{ ($.eventName = PutRolePolicy) || ($.eventName = DeleteRolePolicy) || ($.eventName = AttachRolePolicy) || ($.eventName = DetachRolePolicy) || ($.eventName = UpdateAssumeRolePolicy) }' \
  --metric-transformations \
    metricName=IAMPolicyChanges,metricNamespace=AWS/CloudTrail,metricValue=1
```

### CloudTrail Monitoring

Create a CloudTrail query to monitor IRSA role usage:

```bash
# Query CloudTrail for AssumeRoleWithWebIdentity events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 50 \
  --output json | jq '.Events[] | {
    time: .EventTime,
    role: .Resources[0].ResourceName,
    sourceIP: .CloudTrailEvent | fromjson | .sourceIPAddress,
    userAgent: .CloudTrailEvent | fromjson | .userAgent
  }'

# Query for failed assume role attempts (potential attacks)
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 50 \
  --output json | jq '.Events[] | select(.CloudTrailEvent | fromjson | .errorCode != null) | {
    time: .EventTime,
    role: .Resources[0].ResourceName,
    error: .CloudTrailEvent | fromjson | .errorCode,
    message: .CloudTrailEvent | fromjson | .errorMessage
  }'
```

### EventBridge Rules for Real-Time Alerting

Create EventBridge rules to alert on suspicious IAM activity:

```json
{
  "source": ["aws.iam"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventName": [
      "DeleteRolePermissionsBoundary",
      "PutRolePolicy",
      "AttachRolePolicy",
      "UpdateAssumeRolePolicy"
    ],
    "requestParameters": {
      "roleName": ["HarborS3Role"]
    }
  }
}
```

```bash
# Create EventBridge rule
aws events put-rule \
  --name harbor-iam-role-modifications \
  --description "Alert on modifications to Harbor IRSA role" \
  --event-pattern file://harbor-iam-eventbridge-pattern.json \
  --state ENABLED

# Add SNS target
aws events put-targets \
  --rule harbor-iam-role-modifications \
  --targets "Id"="1","Arn"="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:security-alerts"
```

### GuardDuty Integration

Enable GuardDuty to detect anomalous IAM behavior:

```bash
# Enable GuardDuty (if not already enabled)
aws guardduty create-detector \
  --enable \
  --finding-publishing-frequency FIFTEEN_MINUTES

# Get detector ID
export DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)

# Create filter for Harbor-related findings
aws guardduty create-filter \
  --detector-id ${DETECTOR_ID} \
  --name harbor-irsa-findings \
  --description "Filter for Harbor IRSA related GuardDuty findings" \
  --finding-criteria '{
    "Criterion": {
      "resource.accessKeyDetails.userName": {
        "Eq": ["HarborS3Role"]
      }
    }
  }' \
  --action ARCHIVE
```

**GuardDuty findings to watch for**:
- **UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration**: Credentials used from unusual location
- **PrivilegeEscalation:IAMUser/AdministrativePermissions**: Role attempting to gain admin access
- **Persistence:IAMUser/UserPermissions**: Unusual IAM permission changes

## Best Practices Summary

### Layered Security Approach

Implement all layers for defense in depth:

1. **Service Control Policies (Organization Level)**
   - Deny unapproved regions
   - Require encryption
   - Prevent IAM privilege escalation
   - Require MFA for sensitive operations

2. **Permission Boundaries (Account Level)**
   - Set maximum permissions for IRSA roles
   - Explicitly deny dangerous actions
   - Scope to application-specific resources

3. **IAM Role Policies (Role Level)**
   - Grant least-privilege permissions
   - Use specific resources (no wildcards)
   - Add conditions to further restrict

4. **Trust Policies (Role Level)**
   - Bind to specific namespace and service account
   - Use StringEquals for exact matching
   - Validate audience claim

5. **Resource Policies (Resource Level)**
   - S3 bucket policies enforce encryption
   - KMS key policies restrict usage
   - Deny insecure transport

6. **Monitoring and Detection**
   - IAM Access Analyzer for external access
   - CloudTrail for audit logs
   - GuardDuty for anomaly detection
   - EventBridge for real-time alerts

### Implementation Checklist

**Before Deployment**:
- [ ] Create permission boundary policy
- [ ] Validate all IAM policies with Access Analyzer
- [ ] Test policies with IAM Policy Simulator
- [ ] Review policies against security checklist
- [ ] Document all policy decisions
- [ ] Store policies in version control

**During Deployment**:
- [ ] Apply permission boundary to IRSA role
- [ ] Verify SCPs don't block required actions
- [ ] Enable IAM Access Analyzer
- [ ] Configure CloudTrail logging
- [ ] Set up CloudWatch alarms
- [ ] Create EventBridge rules

**After Deployment**:
- [ ] Monitor IAM Access Analyzer findings
- [ ] Review CloudTrail logs for AssumeRole events
- [ ] Check for unused permissions (90-day review)
- [ ] Validate no external access to resources
- [ ] Test access denial for unauthorized service accounts
- [ ] Document any policy exceptions

### Continuous Improvement

**Monthly**:
- Review IAM Access Analyzer findings
- Check for unused permissions
- Validate policy compliance

**Quarterly**:
- Update permission boundaries based on new requirements
- Review and update SCPs
- Audit CloudTrail logs for anomalies
- Test disaster recovery procedures

**Annually**:
- Comprehensive security audit
- Update threat model
- Review and update all documentation
- Train team on IAM best practices

## Troubleshooting

### Issue 1: Permission Boundary Blocks Required Action

**Symptom**:
Harbor pod cannot access S3, logs show `AccessDenied` error.

**Diagnosis**:
```bash
# Check if permission boundary is applied
aws iam get-role --role-name HarborS3Role \
  --query 'Role.PermissionsBoundary'

# Simulate the action
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/HarborS3Role \
  --action-names s3:PutObject \
  --resource-arns arn:aws:s3:::${S3_BUCKET_NAME}/test
```

**Solution**:
If the boundary is blocking a legitimate action, update the boundary policy:
```bash
# Update permission boundary to allow the action
aws iam create-policy-version \
  --policy-arn ${PERMISSION_BOUNDARY_ARN} \
  --policy-document file://updated-boundary.json \
  --set-as-default
```

### Issue 2: SCP Denies Required Action

**Symptom**:
All IAM principals in the account cannot perform certain actions.

**Diagnosis**:
```bash
# Check SCPs affecting your account
aws organizations list-policies-for-target \
  --target-id ${AWS_ACCOUNT_ID} \
  --filter SERVICE_CONTROL_POLICY

# Review SCP content
aws organizations describe-policy --policy-id p-xxxxxxxx
```

**Solution**:
Contact your AWS Organization administrator to:
1. Add an exception for the Harbor role
2. Modify the SCP to allow the required action
3. Move the account to a different OU with appropriate SCPs

### Issue 3: IAM Access Analyzer Shows External Access

**Symptom**:
Access Analyzer reports that S3 bucket or KMS key is accessible externally.

**Diagnosis**:
```bash
# Get finding details
aws accessanalyzer get-finding \
  --analyzer-arn ${ANALYZER_ARN} \
  --id <finding-id>
```

**Solution**:
Review the resource policy and remove external access:
```bash
# For S3 bucket - remove public access
aws s3api put-public-access-block \
  --bucket ${S3_BUCKET_NAME} \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# For KMS key - update key policy to remove external principals
aws kms put-key-policy \
  --key-id ${KMS_KEY_ID} \
  --policy-name default \
  --policy file://updated-key-policy.json
```

### Issue 4: Policy Validation Fails

**Symptom**:
`aws accessanalyzer validate-policy` returns errors or security warnings.

**Common Errors**:

**Error: "INVALID_ACTION"**
```
Action 's3:PutObjects' is not valid (should be 's3:PutObject')
```
**Solution**: Fix the typo in the action name.

**Security Warning: "PASS_ROLE_WITH_STAR_IN_RESOURCE"**
```
Using a wildcard in the resource can be overly permissive
```
**Solution**: Scope the resource to specific ARNs.

**Warning: "MISSING_CONDITION_FOR_ASSUME_ROLE"**
```
Trust policy should include conditions to restrict who can assume the role
```
**Solution**: Add `:sub` and `:aud` conditions to trust policy.

### Issue 5: Role Cannot Be Assumed

**Symptom**:
Harbor pod logs show `AccessDenied` when trying to assume role.

**Diagnosis**:
```bash
# Check trust policy
aws iam get-role --role-name HarborS3Role \
  --query 'Role.AssumeRolePolicyDocument'

# Verify OIDC provider exists
aws iam list-open-id-connect-providers

# Check service account annotation
kubectl get sa harbor-registry -n harbor -o yaml
```

**Solution**:
Ensure trust policy matches the service account:
```bash
# Update trust policy if needed
aws iam update-assume-role-policy \
  --role-name HarborS3Role \
  --policy-document file://corrected-trust-policy.json
```

### Issue 6: Unused Permissions Detected

**Symptom**:
IAM Access Analyzer reports permissions that haven't been used in 90+ days.

**Diagnosis**:
```bash
# Get unused access report
aws accessanalyzer list-findings \
  --analyzer-arn ${ANALYZER_ARN} \
  --filter "resourceType=AWS::IAM::Role,resource=arn:aws:iam::${AWS_ACCOUNT_ID}:role/HarborS3Role"
```

**Solution**:
Remove unused permissions to reduce attack surface:
```bash
# Create new policy version without unused permissions
aws iam create-policy-version \
  --policy-arn ${HARBOR_POLICY_ARN} \
  --policy-document file://reduced-permissions-policy.json \
  --set-as-default

# Delete old policy versions
aws iam delete-policy-version \
  --policy-arn ${HARBOR_POLICY_ARN} \
  --version-id v1
```

## Advanced Topics

### Multi-Account IRSA with Cross-Account Access

For organizations with multiple AWS accounts, you may need Harbor in one account to access S3 in another:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/HarborS3Role"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::harbor-storage-222222222222/*",
      "Condition": {
        "StringEquals": {
          "aws:PrincipalOrgID": "o-xxxxxxxxxx"
        }
      }
    }
  ]
}
```

**Best Practice**: Use `aws:PrincipalOrgID` condition to restrict cross-account access to your organization.

### Session Tags for Fine-Grained Access Control

Use session tags to add additional context to IRSA sessions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::harbor-registry-storage-*/*",
      "Condition": {
        "StringEquals": {
          "aws:PrincipalTag/Environment": "${aws:RequestTag/Environment}"
        }
      }
    }
  ]
}
```

### Temporary Permission Elevation

For maintenance operations, create a separate role with elevated permissions:

```bash
# Create maintenance role with broader permissions
aws iam create-role \
  --role-name HarborMaintenanceRole \
  --assume-role-policy-document file://maintenance-trust-policy.json \
  --permissions-boundary ${PERMISSION_BOUNDARY_ARN}

# Attach elevated permissions
aws iam attach-role-policy \
  --role-name HarborMaintenanceRole \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/HarborMaintenancePolicy

# Use only when needed, then remove
```

### Automated Policy Remediation

Create a Lambda function to automatically remediate policy violations:

```python
# lambda/policy-remediation.py
import boto3
import json

iam_client = boto3.client('iam')

def lambda_handler(event, context):
    """Automatically remediate IAM policy violations"""
    
    # Triggered by EventBridge when policy is modified
    role_name = event['detail']['requestParameters']['roleName']
    
    # Check if permission boundary is still attached
    role = iam_client.get_role(RoleName=role_name)
    
    if 'PermissionsBoundary' not in role['Role']:
        # Re-attach permission boundary
        iam_client.put_role_permissions_boundary(
            RoleName=role_name,
            PermissionsBoundary='arn:aws:iam::123456789012:policy/HarborIRSAPermissionBoundary'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Re-attached permission boundary to {role_name}')
        }
    
    return {
        'statusCode': 200,
        'body': json.dumps('No remediation needed')
    }
```

## Summary

IAM guardrails provide essential defense-in-depth for IRSA deployments. By implementing permission boundaries, SCPs, policy validation, and continuous monitoring, you create multiple layers of protection that:

✅ **Prevent** overly permissive policies from being created  
✅ **Limit** the maximum damage from compromised roles  
✅ **Detect** policy violations and misconfigurations  
✅ **Alert** security teams to suspicious activity  
✅ **Enforce** organizational security standards  

### Key Takeaways

1. **Permission boundaries** set maximum permissions and prevent privilege escalation
2. **SCPs** enforce organization-wide security policies across all accounts
3. **Policy validation** catches errors and security issues before deployment
4. **IAM Access Analyzer** identifies external access and unused permissions
5. **Continuous monitoring** detects anomalous behavior and policy changes
6. **Layered security** provides defense in depth with multiple controls

### Next Steps

Now that you understand IAM guardrails, you can:

1. **[Review KMS Key Policies](./kms-key-policy-hardening.md)** - Harden encryption key access
2. **[Review S3 Bucket Policies](./s3-bucket-policy-hardening.md)** - Enforce storage security
3. **[Implement Monitoring](../validation-tests/)** - Set up continuous security monitoring
4. **[Complete Workshop](../README.md)** - Return to main workshop guide

---

**Related Documentation**:
- [IAM Role and Policy Setup](./iam-role-policy-setup.md)
- [OIDC Provider Setup](./oidc-provider-setup.md)
- [Harbor IRSA Deployment](./harbor-irsa-deployment.md)
- [Namespace Isolation Guide](./namespace-isolation-guide.md)

