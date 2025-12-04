# IAM Role and Policy Configuration for Harbor IRSA

## Overview

This guide walks you through creating the IAM role and policies that enable Harbor to access S3 and KMS securely using IRSA. We'll implement least-privilege access controls that restrict Harbor to only the permissions it needs, bound to a specific Kubernetes service account and namespace.

## Table of Contents

1. [Understanding IAM Roles for IRSA](#understanding-iam-roles-for-irsa)
2. [Prerequisites](#prerequisites)
3. [Step 1: Create IAM Permissions Policy](#step-1-create-iam-permissions-policy)
4. [Step 2: Create IAM Trust Policy](#step-2-create-iam-trust-policy)
5. [Step 3: Create IAM Role](#step-3-create-iam-role)
6. [Step 4: Verify Role Configuration](#step-4-verify-role-configuration)
7. [Understanding Least Privilege](#understanding-least-privilege)
8. [Troubleshooting](#troubleshooting)

## Understanding IAM Roles for IRSA

### How IRSA Works

When a pod uses IRSA, the following happens:

1. **Pod starts** with a service account that has an IAM role annotation
2. **Kubernetes projects** a JWT token into the pod at `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
3. **AWS SDK** automatically discovers this token
4. **SDK calls** AWS STS `AssumeRoleWithWebIdentity` with the JWT token
5. **STS validates** the token against the OIDC provider
6. **STS checks** the IAM role's trust policy to ensure the service account is allowed
7. **STS issues** temporary AWS credentials (valid for 1 hour, auto-renewed)
8. **Pod uses** these credentials to access AWS services

### Two Required Policies

Every IRSA role needs two policies:

1. **Trust Policy** (who can assume this role)
   - Specifies the OIDC provider
   - Restricts to specific namespace and service account
   - Validates the audience claim

2. **Permissions Policy** (what the role can do)
   - Grants specific AWS service permissions
   - Follows least-privilege principle
   - Scoped to specific resources

## Prerequisites

Before starting, ensure you have:

- **OIDC provider** configured (see [OIDC Provider Setup](./oidc-provider-setup.md))
- **AWS CLI** v2.x installed and configured
- **S3 bucket** name decided (we'll use `harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION}`)
- **KMS key** ARN (we'll create this or you can use an existing one)
- **IAM permissions** to create roles and policies

### Environment Variables

Set these from the previous OIDC setup:

```bash
export CLUSTER_NAME="harbor-irsa-workshop"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export OIDC_PROVIDER_ID=$(aws eks describe-cluster \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed 's|https://||')

# New variables for Harbor
export HARBOR_NAMESPACE="harbor"
export HARBOR_SERVICE_ACCOUNT="harbor-registry"
export HARBOR_ROLE_NAME="HarborS3Role"
export S3_BUCKET_NAME="harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION}"

echo "OIDC Provider: ${OIDC_PROVIDER_ID}"
echo "Harbor Namespace: ${HARBOR_NAMESPACE}"
echo "Harbor Service Account: ${HARBOR_SERVICE_ACCOUNT}"
echo "IAM Role Name: ${HARBOR_ROLE_NAME}"
echo "S3 Bucket: ${S3_BUCKET_NAME}"
```

## Step 1: Create IAM Permissions Policy

The permissions policy defines what AWS actions Harbor can perform. We'll follow the principle of least privilege.

### 1.1 Understand Harbor's S3 Requirements

Harbor needs these S3 operations:
- **PutObject**: Upload container image layers
- **GetObject**: Download container image layers
- **DeleteObject**: Remove old or unused layers
- **ListBucket**: List objects in the bucket
- **GetBucketLocation**: Determine bucket region

Harbor also needs KMS operations for encryption:
- **Decrypt**: Decrypt objects when reading
- **GenerateDataKey**: Generate data keys for encryption
- **DescribeKey**: Get key metadata

### 1.2 Create Permissions Policy Document

Create a file `harbor-s3-permissions-policy.json`:

```bash
cat > harbor-s3-permissions-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "HarborS3BucketAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}"
    },
    {
      "Sid": "HarborS3ObjectAccess",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*"
    },
    {
      "Sid": "HarborKMSAccess",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "s3.${AWS_REGION}.amazonaws.com"
        }
      }
    }
  ]
}
EOF
```

### 1.3 Understanding the Policy

Let's break down each statement:

**Statement 1: Bucket-Level Operations**
```json
{
  "Sid": "HarborS3BucketAccess",
  "Effect": "Allow",
  "Action": [
    "s3:ListBucket",        // List objects in bucket
    "s3:GetBucketLocation"  // Get bucket region
  ],
  "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}"  // Bucket itself (no /*)
}
```

**Statement 2: Object-Level Operations**
```json
{
  "Sid": "HarborS3ObjectAccess",
  "Effect": "Allow",
  "Action": [
    "s3:PutObject",    // Upload new objects
    "s3:GetObject",    // Download objects
    "s3:DeleteObject"  // Remove objects
  ],
  "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*"  // All objects in bucket
}
```

**Statement 3: KMS Operations (with Condition)**
```json
{
  "Sid": "HarborKMSAccess",
  "Effect": "Allow",
  "Action": [
    "kms:Decrypt",           // Decrypt objects
    "kms:GenerateDataKey",   // Generate encryption keys
    "kms:DescribeKey"        // Get key metadata
  ],
  "Resource": "arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/*",
  "Condition": {
    "StringEquals": {
      "kms:ViaService": "s3.${AWS_REGION}.amazonaws.com"  // Only via S3
    }
  }
}
```

The condition `kms:ViaService` ensures KMS can only be used through S3, not directly.

### 1.4 Create the IAM Policy

```bash
# Create the IAM policy
aws iam create-policy \
  --policy-name HarborS3AccessPolicy \
  --policy-document file://harbor-s3-permissions-policy.json \
  --description "Least-privilege S3 and KMS access for Harbor registry" \
  --tags Key=Environment,Value=workshop Key=Application,Value=harbor

# Capture the policy ARN
export HARBOR_POLICY_ARN=$(aws iam list-policies \
  --query "Policies[?PolicyName=='HarborS3AccessPolicy'].Arn" \
  --output text)

echo "Policy ARN: ${HARBOR_POLICY_ARN}"
```

**Expected output:**
```
Policy ARN: arn:aws:iam::123456789012:policy/HarborS3AccessPolicy
```

### 1.5 Verify Policy Creation

```bash
# Get policy details
aws iam get-policy --policy-arn ${HARBOR_POLICY_ARN}

# Get policy version (to see the actual policy document)
aws iam get-policy-version \
  --policy-arn ${HARBOR_POLICY_ARN} \
  --version-id v1
```

## Step 2: Create IAM Trust Policy

The trust policy defines **who** can assume this role. For IRSA, we restrict it to a specific Kubernetes service account in a specific namespace.

### 2.1 Understanding Trust Policy Components

A trust policy for IRSA must include:

1. **Principal**: The OIDC provider (federated identity)
2. **Action**: `sts:AssumeRoleWithWebIdentity`
3. **Condition**: Restricts to specific service account and namespace

### 2.2 Create Trust Policy Document

Create a file `harbor-trust-policy.json`:

```bash
cat > harbor-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_ID}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER_ID}:sub": "system:serviceaccount:${HARBOR_NAMESPACE}:${HARBOR_SERVICE_ACCOUNT}",
          "${OIDC_PROVIDER_ID}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF
```

### 2.3 Understanding the Trust Policy

Let's break down each component:

**Principal (Who)**
```json
"Principal": {
  "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_ID}"
}
```
This specifies that the OIDC provider is the trusted entity.

**Action (What)**
```json
"Action": "sts:AssumeRoleWithWebIdentity"
```
This is the STS action that exchanges the JWT token for AWS credentials.

**Condition (When)**
```json
"Condition": {
  "StringEquals": {
    "${OIDC_PROVIDER_ID}:sub": "system:serviceaccount:${HARBOR_NAMESPACE}:${HARBOR_SERVICE_ACCOUNT}",
    "${OIDC_PROVIDER_ID}:aud": "sts.amazonaws.com"
  }
}
```

Two conditions must be met:

1. **`:sub` (Subject)**: The JWT token's subject must match the exact service account
   - Format: `system:serviceaccount:<namespace>:<service-account-name>`
   - Example: `system:serviceaccount:harbor:harbor-registry`
   - This ensures only the Harbor service account can assume the role

2. **`:aud` (Audience)**: The JWT token's audience must be `sts.amazonaws.com`
   - This ensures the token was intended for AWS STS
   - Prevents token reuse for other purposes

### 2.4 Why This is Secure

This trust policy provides strong security guarantees:

✅ **Namespace isolation**: Only service accounts in the `harbor` namespace can assume the role  
✅ **Service account binding**: Only the `harbor-registry` service account can assume the role  
✅ **No wildcards**: Exact string matching prevents privilege escalation  
✅ **Audience validation**: Ensures tokens are intended for AWS  
✅ **OIDC validation**: AWS validates the JWT signature against the OIDC provider  

### 2.5 View the Generated Trust Policy

```bash
# View the trust policy
cat harbor-trust-policy.json | jq .

# Or without jq:
cat harbor-trust-policy.json
```

## Step 3: Create IAM Role

Now we'll create the IAM role with both the trust policy and permissions policy.

### 3.1 Create the Role

```bash
# Create IAM role with trust policy
aws iam create-role \
  --role-name ${HARBOR_ROLE_NAME} \
  --assume-role-policy-document file://harbor-trust-policy.json \
  --description "IAM role for Harbor registry to access S3 via IRSA" \
  --tags Key=Environment,Value=workshop Key=Application,Value=harbor Key=ManagedBy,Value=manual

# Capture the role ARN
export HARBOR_ROLE_ARN=$(aws iam get-role \
  --role-name ${HARBOR_ROLE_NAME} \
  --query 'Role.Arn' \
  --output text)

echo "Role ARN: ${HARBOR_ROLE_ARN}"
```

**Expected output:**
```
Role ARN: arn:aws:iam::123456789012:role/HarborS3Role
```

### 3.2 Attach Permissions Policy to Role

```bash
# Attach the permissions policy to the role
aws iam attach-role-policy \
  --role-name ${HARBOR_ROLE_NAME} \
  --policy-arn ${HARBOR_POLICY_ARN}

echo "✅ Permissions policy attached to role"
```

### 3.3 Verify Role Creation

```bash
# Get role details
aws iam get-role --role-name ${HARBOR_ROLE_NAME}

# List attached policies
aws iam list-attached-role-policies --role-name ${HARBOR_ROLE_NAME}
```

**Expected output:**
```json
{
    "AttachedPolicies": [
        {
            "PolicyName": "HarborS3AccessPolicy",
            "PolicyArn": "arn:aws:iam::123456789012:policy/HarborS3AccessPolicy"
        }
    ]
}
```

## Step 4: Verify Role Configuration

### 4.1 Verify Trust Policy

```bash
# Get the trust policy (assume role policy document)
aws iam get-role \
  --role-name ${HARBOR_ROLE_NAME} \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json | jq .
```

Verify:
- [ ] Principal is your OIDC provider
- [ ] Action is `sts:AssumeRoleWithWebIdentity`
- [ ] Condition includes correct namespace and service account
- [ ] Condition includes audience `sts.amazonaws.com`

### 4.2 Verify Permissions Policy

```bash
# Get the permissions policy
aws iam get-policy-version \
  --policy-arn ${HARBOR_POLICY_ARN} \
  --version-id v1 \
  --query 'PolicyVersion.Document' \
  --output json | jq .
```

Verify:
- [ ] S3 bucket actions are scoped to your specific bucket
- [ ] KMS actions include condition for `kms:ViaService`
- [ ] No wildcard resources (except for KMS keys with condition)
- [ ] Only necessary actions are granted

### 4.3 Test Role Assumption (Optional)

You can test if the role can be assumed (though it will fail without a valid JWT token):

```bash
# This should fail with "An error occurred (InvalidIdentityToken)"
# because we don't have a valid service account token yet
aws sts assume-role-with-web-identity \
  --role-arn ${HARBOR_ROLE_ARN} \
  --role-session-name test-session \
  --web-identity-token "invalid-token" \
  2>&1 | grep -q "InvalidIdentityToken" && echo "✅ Role exists and requires valid token"
```

### 4.4 Save Role ARN for Later

```bash
# Save the role ARN to a file for use in Harbor deployment
echo ${HARBOR_ROLE_ARN} > harbor-role-arn.txt

echo "Role ARN saved to harbor-role-arn.txt"
```

## Understanding Least Privilege

### What We Did Right

Our IAM configuration follows least privilege principles:

✅ **Scoped to specific bucket**: Not `s3:*` on all buckets  
✅ **Minimal actions**: Only PutObject, GetObject, DeleteObject, ListBucket  
✅ **No administrative actions**: Cannot modify bucket policies or ACLs  
✅ **KMS scoped to S3**: Can only use KMS through S3 service  
✅ **Namespace binding**: Only one service account can assume role  
✅ **No wildcards in trust policy**: Exact string matching  

### What We Avoided

❌ **Overprivileged policies**: Not using `s3:*` or `AmazonS3FullAccess`  
❌ **Wildcard resources**: Not using `"Resource": "*"`  
❌ **Broad trust policies**: Not allowing all service accounts  
❌ **Missing conditions**: Not skipping the `:sub` and `:aud` conditions  
❌ **Direct KMS access**: Not allowing KMS operations outside S3 context  

### Comparison: Insecure vs Secure

| Aspect | Insecure (IAM User) | Secure (IRSA) |
|--------|---------------------|---------------|
| **Permissions** | `s3:*` on all buckets | Specific actions on one bucket |
| **Scope** | Account-wide | Single namespace + service account |
| **Rotation** | Never | Automatic (every hour) |
| **Credential Storage** | Kubernetes secret | No storage (projected token) |
| **Audit Trail** | IAM user name | Pod identity in CloudTrail |
| **Revocation** | Delete access key | Delete role or update trust policy |

## Troubleshooting

### Issue 1: Policy Already Exists

**Symptom:**
```
An error occurred (EntityAlreadyExists) when calling the CreatePolicy operation: A policy called HarborS3AccessPolicy already exists.
```

**Solution:**
The policy already exists. Get its ARN:
```bash
export HARBOR_POLICY_ARN=$(aws iam list-policies \
  --query "Policies[?PolicyName=='HarborS3AccessPolicy'].Arn" \
  --output text)
```

### Issue 2: Role Already Exists

**Symptom:**
```
An error occurred (EntityAlreadyExists) when calling the CreateRole operation: Role with name HarborS3Role already exists.
```

**Solution:**
The role already exists. You can either:
1. Use the existing role: `export HARBOR_ROLE_ARN=$(aws iam get-role --role-name ${HARBOR_ROLE_NAME} --query 'Role.Arn' --output text)`
2. Delete and recreate: `aws iam delete-role --role-name ${HARBOR_ROLE_NAME}` (after detaching policies)

### Issue 3: Cannot Attach Policy to Role

**Symptom:**
```
An error occurred (NoSuchEntity) when calling the AttachRolePolicy operation: Policy arn:aws:iam::123456789012:policy/HarborS3AccessPolicy does not exist
```

**Solution:**
Verify the policy ARN is correct:
```bash
aws iam list-policies --query "Policies[?PolicyName=='HarborS3AccessPolicy']"
```

### Issue 4: Trust Policy Validation Error

**Symptom:**
```
An error occurred (MalformedPolicyDocument) when calling the CreateRole operation: The policy is not valid JSON
```

**Solution:**
Validate your JSON:
```bash
cat harbor-trust-policy.json | jq .
```

If jq reports an error, fix the JSON syntax.

### Issue 5: OIDC Provider Not Found

**Symptom:**
```
An error occurred (InvalidInput) when calling the CreateRole operation: The provided principal is not valid
```

**Solution:**
Verify the OIDC provider exists:
```bash
aws iam list-open-id-connect-providers
```

If not found, go back to [OIDC Provider Setup](./oidc-provider-setup.md).

## Advanced Configuration

### Adding Additional Permissions

If Harbor needs additional AWS services (e.g., CloudWatch Logs):

```bash
# Create additional policy statement
cat > harbor-cloudwatch-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "HarborCloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/harbor/*"
    }
  ]
}
EOF

# Create and attach the policy
aws iam create-policy \
  --policy-name HarborCloudWatchLogsPolicy \
  --policy-document file://harbor-cloudwatch-policy.json

aws iam attach-role-policy \
  --role-name ${HARBOR_ROLE_NAME} \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/HarborCloudWatchLogsPolicy
```

### Restricting to Specific KMS Key

To restrict KMS access to a specific key (more secure):

```bash
# Get your KMS key ID
export KMS_KEY_ID="12345678-1234-1234-1234-123456789012"

# Update the policy to use specific key ARN
cat > harbor-s3-permissions-policy-v2.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "HarborS3BucketAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}"
    },
    {
      "Sid": "HarborS3ObjectAccess",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*"
    },
    {
      "Sid": "HarborKMSAccess",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/${KMS_KEY_ID}",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "s3.${AWS_REGION}.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Create new policy version
aws iam create-policy-version \
  --policy-arn ${HARBOR_POLICY_ARN} \
  --policy-document file://harbor-s3-permissions-policy-v2.json \
  --set-as-default
```

### Adding Multiple Service Accounts

To allow multiple service accounts (e.g., for different Harbor components):

```bash
cat > harbor-trust-policy-multi.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_ID}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER_ID}:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "${OIDC_PROVIDER_ID}:sub": [
            "system:serviceaccount:${HARBOR_NAMESPACE}:harbor-registry",
            "system:serviceaccount:${HARBOR_NAMESPACE}:harbor-jobservice"
          ]
        }
      }
    }
  ]
}
EOF

# Update role trust policy
aws iam update-assume-role-policy \
  --role-name ${HARBOR_ROLE_NAME} \
  --policy-document file://harbor-trust-policy-multi.json
```

## Verification Checklist

Before proceeding to Harbor deployment, verify:

- [ ] IAM permissions policy created with least-privilege S3 and KMS access
- [ ] IAM trust policy created with namespace and service account restrictions
- [ ] IAM role created and both policies attached
- [ ] Role ARN captured in environment variable
- [ ] Trust policy includes correct OIDC provider
- [ ] Trust policy includes `:sub` condition for service account
- [ ] Trust policy includes `:aud` condition for STS
- [ ] Permissions policy scoped to specific S3 bucket
- [ ] KMS permissions include `kms:ViaService` condition

## Next Steps

Now that your IAM role is configured, you can proceed to:

1. **[Configure S3 and KMS](./s3-kms-setup.md)** - Set up the storage backend with encryption
2. **[Deploy Harbor with IRSA](./harbor-irsa-deployment.md)** - Deploy Harbor using the IAM role
3. **[Validate IRSA Setup](../validation-tests/02-irsa-validation.sh)** - Test that everything works

## Summary

You've successfully created a secure IAM role for Harbor with IRSA! Here's what you accomplished:

✅ Created least-privilege IAM permissions policy for S3 and KMS  
✅ Created restrictive trust policy bound to specific service account  
✅ Created IAM role combining both policies  
✅ Verified role configuration  
✅ Understood the security benefits of this approach  

The IAM role is now ready to be assumed by the Harbor service account, providing secure, temporary, automatically-rotated credentials for S3 access.

---

**Next**: [S3 and KMS Setup](./s3-kms-setup.md)
