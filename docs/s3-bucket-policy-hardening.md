# S3 Bucket Policy Hardening Guide

## Overview

This guide provides comprehensive best practices for hardening S3 bucket policies used with Harbor container registry storage. While the basic S3 setup guide covers initial configuration, this document focuses on advanced security controls including encryption enforcement, TLS-only access requirements, public access blocking, and defense-in-depth strategies.

Properly hardened S3 bucket policies ensure that even if IAM roles are misconfigured or compromised, the bucket itself enforces critical security requirements at the resource level.

## Table of Contents

1. [Understanding S3 Bucket Policies](#understanding-s3-bucket-policies)
2. [Encryption Enforcement Policies](#encryption-enforcement-policies)
3. [TLS-Only Access Requirements](#tls-only-access-requirements)
4. [Public Access Block Configuration](#public-access-block-configuration)
5. [Additional Hardening Controls](#additional-hardening-controls)
6. [Complete Hardened Bucket Policy](#complete-hardened-bucket-policy)
7. [Testing and Validation](#testing-and-validation)
8. [Monitoring and Compliance](#monitoring-and-compliance)
9. [Troubleshooting](#troubleshooting)
10. [Best Practices Summary](#best-practices-summary)

## Understanding S3 Bucket Policies

### What is a Bucket Policy?

An S3 bucket policy is a resource-based policy that defines who can access your bucket and what actions they can perform. Unlike IAM policies (which are attached to users/roles), bucket policies are attached directly to the S3 bucket.

**Key Characteristics**:
- **Resource-based**: Attached to the bucket, not to IAM principals
- **Cross-account capable**: Can grant access to principals in other AWS accounts
- **Explicit deny wins**: Deny statements override any allow statements
- **Evaluated with IAM policies**: Effective permissions are the union of IAM and bucket policies (unless denied)

### Why Bucket Policies Matter for Harbor

Bucket policies provide defense-in-depth for Harbor storage:

1. **Resource-level enforcement**: Security controls at the bucket level, independent of IAM
2. **Explicit deny statements**: Cannot be overridden by IAM policies
3. **Encryption enforcement**: Reject unencrypted uploads at the bucket level
4. **Transport security**: Require TLS for all connections
5. **Audit and compliance**: Demonstrate security controls to auditors


### Defense in Depth Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: Network Security                                   │
│  - VPC Endpoints for S3                                      │
│  - Security Groups                                           │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│  Layer 2: IAM Role Policy                                    │
│  - Least-privilege S3 permissions                           │
│  - Scoped to specific bucket                                │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│  Layer 3: S3 Bucket Policy (THIS GUIDE) ✅                  │
│  - Encryption enforcement                                    │
│  - TLS-only access                                          │
│  - Public access denial                                     │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│  Layer 4: S3 Bucket Configuration                           │
│  - Default encryption enabled                               │
│  - Versioning enabled                                       │
│  - Public access block enabled                              │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│  Layer 5: KMS Key Policy                                    │
│  - Controls who can use encryption key                      │
│  - Audit trail via CloudTrail                               │
└─────────────────────────────────────────────────────────────┘
```

## Encryption Enforcement Policies

### Why Enforce Encryption at the Bucket Level?

Even with default encryption enabled on the bucket, it's possible to upload objects without encryption if the client explicitly requests no encryption. Bucket policies provide an additional layer that **denies** unencrypted uploads.

### Policy 1: Deny Unencrypted Object Uploads

This policy denies any `PutObject` request that doesn't include server-side encryption:

```json
{
  "Sid": "DenyUnencryptedObjectUploads",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::BUCKET_NAME/*",
  "Condition": {
    "StringNotEquals": {
      "s3:x-amz-server-side-encryption": "aws:kms"
    }
  }
}
```

**How it works**:
- `"Effect": "Deny"`: Explicit denial (cannot be overridden)
- `"Principal": "*"`: Applies to all principals, including administrators
- `"Action": "s3:PutObject"`: Only affects object uploads
- `"Resource": ".../*"`: Applies to all objects in the bucket
- `"Condition"`: Checks the encryption header in the request

**What it prevents**:
- ❌ Uploads with no encryption header
- ❌ Uploads with SSE-S3 encryption (we require KMS)
- ❌ Uploads with AES256 encryption (we require KMS)

**What it allows**:
- ✅ Uploads with `x-amz-server-side-encryption: aws:kms`


### Policy 2: Enforce Specific KMS Key

This policy ensures that only a specific KMS key is used for encryption:

```json
{
  "Sid": "DenyIncorrectEncryptionKey",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::BUCKET_NAME/*",
  "Condition": {
    "StringNotEqualsIfExists": {
      "s3:x-amz-server-side-encryption-aws-kms-key-id": "arn:aws:kms:REGION:ACCOUNT_ID:key/KEY_ID"
    }
  }
}
```

**How it works**:
- `StringNotEqualsIfExists`: Checks if the KMS key ID header exists and doesn't match
- Prevents use of wrong KMS keys (e.g., default aws/s3 key)
- Ensures all objects use your customer-managed key

**Why this matters**:
- Prevents accidental use of AWS-managed keys
- Ensures consistent key policy enforcement
- Maintains audit trail through specific key
- Allows key rotation without changing bucket policy

### Policy 3: Deny Unencrypted Multipart Uploads

Multipart uploads require special handling:

```json
{
  "Sid": "DenyUnencryptedMultipartUploads",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::BUCKET_NAME/*",
  "Condition": {
    "Null": {
      "s3:x-amz-server-side-encryption": "true"
    }
  }
}
```

**How it works**:
- `"Null": "true"`: Checks if the encryption header is missing
- Applies to both regular and multipart uploads
- Ensures no objects slip through without encryption

### Testing Encryption Enforcement

```bash
# Set environment variables
export S3_BUCKET_NAME="harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION}"
export KMS_KEY_ARN="arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/${KMS_KEY_ID}"

# Test 1: Try to upload without encryption (should fail)
echo "test content" > test-unencrypted.txt
aws s3 cp test-unencrypted.txt s3://${S3_BUCKET_NAME}/test-unencrypted.txt \
  --no-server-side-encryption 2>&1 | grep -i "access denied"

# Expected: Access Denied error

# Test 2: Upload with correct KMS encryption (should succeed)
aws s3 cp test-unencrypted.txt s3://${S3_BUCKET_NAME}/test-encrypted.txt \
  --server-side-encryption aws:kms \
  --ssekms-key-id ${KMS_KEY_ARN}

# Expected: Success

# Test 3: Verify object is encrypted
aws s3api head-object \
  --bucket ${S3_BUCKET_NAME} \
  --key test-encrypted.txt \
  --query '{Encryption: ServerSideEncryption, KeyId: SSEKMSKeyId}'

# Expected output:
# {
#     "Encryption": "aws:kms",
#     "KeyId": "arn:aws:kms:us-east-1:123456789012:key/..."
# }

# Cleanup
rm test-unencrypted.txt
aws s3 rm s3://${S3_BUCKET_NAME}/test-encrypted.txt
```


## TLS-Only Access Requirements

### Why Enforce TLS?

Transport Layer Security (TLS) encrypts data in transit between Harbor and S3. Without TLS enforcement:
- ❌ Data could be transmitted in plaintext over HTTP
- ❌ Credentials could be intercepted (man-in-the-middle attacks)
- ❌ Data could be modified in transit
- ❌ Compliance requirements may be violated

### Policy 4: Deny All Non-TLS Requests

This is one of the most important security policies:

```json
{
  "Sid": "DenyInsecureTransport",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": [
    "arn:aws:s3:::BUCKET_NAME",
    "arn:aws:s3:::BUCKET_NAME/*"
  ],
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```

**How it works**:
- `"Action": "s3:*"`: Applies to ALL S3 operations (read, write, list, delete)
- `"Resource"`: Includes both bucket and objects
- `"aws:SecureTransport": "false"`: Checks if request is over HTTP (not HTTPS)
- Applies to all principals, including root account

**What it prevents**:
- ❌ HTTP requests (port 80)
- ❌ Unencrypted connections
- ❌ Downgrade attacks

**What it allows**:
- ✅ HTTPS requests (port 443)
- ✅ TLS 1.2 and higher
- ✅ Encrypted connections

### Policy 5: Enforce Minimum TLS Version

For additional security, enforce TLS 1.2 or higher:

```json
{
  "Sid": "DenyOutdatedTLS",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": [
    "arn:aws:s3:::BUCKET_NAME",
    "arn:aws:s3:::BUCKET_NAME/*"
  ],
  "Condition": {
    "NumericLessThan": {
      "s3:TlsVersion": "1.2"
    }
  }
}
```

**How it works**:
- Denies requests using TLS 1.0 or 1.1
- Ensures modern encryption standards
- Protects against known TLS vulnerabilities

**Why TLS 1.2+**:
- TLS 1.0 and 1.1 have known vulnerabilities (POODLE, BEAST)
- PCI DSS requires TLS 1.2+ as of June 2018
- Many compliance frameworks mandate TLS 1.2+

### Testing TLS Enforcement

```bash
# Test 1: Try HTTP access (should fail)
curl -I http://${S3_BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com/

# Expected: Connection refused or 403 Forbidden

# Test 2: Try HTTPS access (should work for authenticated requests)
aws s3 ls s3://${S3_BUCKET_NAME}/ --region ${AWS_REGION}

# Expected: Success (list objects)

# Test 3: Verify TLS version used by AWS CLI
aws s3 ls s3://${S3_BUCKET_NAME}/ --debug 2>&1 | grep -i "ssl\|tls"

# Expected: Should show TLS 1.2 or higher

# Test 4: Try to force TLS 1.1 (should fail if policy is applied)
# Note: AWS CLI doesn't easily allow forcing old TLS versions
# This would require custom client code
```

### Harbor Configuration for TLS

Ensure Harbor is configured to use HTTPS for S3:

```yaml
# harbor-values.yaml
persistence:
  imageChartStorage:
    type: s3
    s3:
      region: us-east-1
      bucket: harbor-registry-storage-123456789012-us-east-1
      # Ensure HTTPS is used (default behavior)
      secure: true
      # Optional: Specify TLS version
      # v4auth: true
```


## Public Access Block Configuration

### Understanding S3 Public Access Block

S3 Public Access Block provides four settings that prevent public access to your buckets and objects. These settings work at both the account level and bucket level.

**The Four Settings**:

1. **BlockPublicAcls**: Prevents new public ACLs from being applied
2. **IgnorePublicAcls**: Ignores all public ACLs (even existing ones)
3. **BlockPublicPolicy**: Prevents public bucket policies
4. **RestrictPublicBuckets**: Restricts access to buckets with public policies

### Why Public Access Block Matters

Harbor storage buckets should **never** be publicly accessible:
- Container images may contain proprietary code
- Registry metadata could reveal infrastructure details
- Public access violates least-privilege principle
- Compliance frameworks require private storage

### Enabling Public Access Block

#### Method 1: AWS CLI

```bash
# Enable all public access block settings
aws s3api put-public-access-block \
  --bucket ${S3_BUCKET_NAME} \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "✅ Public access block enabled"
```

#### Method 2: Terraform

```hcl
resource "aws_s3_bucket_public_access_block" "harbor_storage" {
  bucket = aws_s3_bucket.harbor_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

#### Method 3: CloudFormation

```yaml
HarborBucketPublicAccessBlock:
  Type: AWS::S3::BucketPublicAccessBlock
  Properties:
    Bucket: !Ref HarborStorageBucket
    BlockPublicAcls: true
    BlockPublicPolicy: true
    IgnorePublicAcls: true
    RestrictPublicBuckets: true
```

### Verifying Public Access Block

```bash
# Check public access block configuration
aws s3api get-public-access-block --bucket ${S3_BUCKET_NAME}

# Expected output:
# {
#     "PublicAccessBlockConfiguration": {
#         "BlockPublicAcls": true,
#         "IgnorePublicAcls": true,
#         "BlockPublicPolicy": true,
#         "RestrictPublicBuckets": true
#     }
# }
```

### Policy 6: Explicit Deny for Public Access

Even with Public Access Block enabled, add an explicit deny in the bucket policy:

```json
{
  "Sid": "DenyPublicAccess",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": [
    "arn:aws:s3:::BUCKET_NAME",
    "arn:aws:s3:::BUCKET_NAME/*"
  ],
  "Condition": {
    "StringNotEquals": {
      "aws:PrincipalAccount": "ACCOUNT_ID"
    }
  }
}
```

**How it works**:
- Denies all S3 actions from principals outside your AWS account
- `aws:PrincipalAccount`: Checks the account ID of the requester
- Provides defense-in-depth with Public Access Block

### Testing Public Access Block

```bash
# Test 1: Try to make bucket public (should fail)
aws s3api put-bucket-acl \
  --bucket ${S3_BUCKET_NAME} \
  --acl public-read 2>&1

# Expected: AccessDenied error

# Test 2: Try to add public bucket policy (should fail)
cat > public-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*"
    }
  ]
}
EOF

aws s3api put-bucket-policy \
  --bucket ${S3_BUCKET_NAME} \
  --policy file://public-policy.json 2>&1

# Expected: AccessDenied error

# Test 3: Verify bucket is not publicly accessible
aws s3api get-bucket-policy-status --bucket ${S3_BUCKET_NAME}

# Expected output:
# {
#     "PolicyStatus": {
#         "IsPublic": false
#     }
# }

# Cleanup
rm public-policy.json
```


## Additional Hardening Controls

### Policy 7: Restrict to Specific IAM Role

Limit bucket access to only the Harbor IRSA role:

```json
{
  "Sid": "AllowOnlyHarborRole",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": [
    "arn:aws:s3:::BUCKET_NAME",
    "arn:aws:s3:::BUCKET_NAME/*"
  ],
  "Condition": {
    "StringNotLike": {
      "aws:PrincipalArn": [
        "arn:aws:iam::ACCOUNT_ID:role/HarborS3Role",
        "arn:aws:iam::ACCOUNT_ID:root"
      ]
    }
  }
}
```

**How it works**:
- Denies access from any principal except Harbor role and root account
- Root account exception allows administrators to manage the bucket
- Provides additional layer beyond IAM policies

**Note**: Be careful with this policy - it can lock out legitimate access. Test thoroughly before applying.

### Policy 8: Deny Deletion of Bucket

Prevent accidental bucket deletion:

```json
{
  "Sid": "DenyBucketDeletion",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:DeleteBucket",
  "Resource": "arn:aws:s3:::BUCKET_NAME"
}
```

**How it works**:
- Explicitly denies bucket deletion for all principals
- Requires removing this policy before bucket can be deleted
- Protects against accidental or malicious deletion

**When to use**: Production environments where bucket deletion should require multiple steps.

### Policy 9: Require MFA for Destructive Operations

Require multi-factor authentication for object deletion:

```json
{
  "Sid": "RequireMFAForDeletion",
  "Effect": "Deny",
  "Principal": "*",
  "Action": [
    "s3:DeleteObject",
    "s3:DeleteObjectVersion"
  ],
  "Resource": "arn:aws:s3:::BUCKET_NAME/*",
  "Condition": {
    "BoolIfExists": {
      "aws:MultiFactorAuthPresent": "false"
    },
    "StringNotLike": {
      "aws:PrincipalArn": "arn:aws:iam::ACCOUNT_ID:role/*"
    }
  }
}
```

**How it works**:
- Requires MFA for object deletion by human users
- Excludes IAM roles (which can't use MFA)
- Protects against accidental deletion by administrators

### Policy 10: Restrict to VPC Endpoint

Require all access to come through a VPC endpoint:

```json
{
  "Sid": "DenyAccessOutsideVPC",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": [
    "arn:aws:s3:::BUCKET_NAME",
    "arn:aws:s3:::BUCKET_NAME/*"
  ],
  "Condition": {
    "StringNotEquals": {
      "aws:SourceVpce": "vpce-1234567890abcdef0"
    }
  }
}
```

**How it works**:
- Denies access unless request comes from specific VPC endpoint
- Ensures traffic stays within AWS network
- Prevents internet-based access

**When to use**: When Harbor is deployed in a VPC with S3 VPC endpoint configured.

### Policy 11: Logging and Monitoring Requirements

Ensure CloudTrail logging cannot be disabled:

```json
{
  "Sid": "DenyDisablingLogging",
  "Effect": "Deny",
  "Principal": "*",
  "Action": [
    "s3:PutBucketLogging",
    "s3:DeleteBucketPolicy"
  ],
  "Resource": "arn:aws:s3:::BUCKET_NAME",
  "Condition": {
    "StringNotLike": {
      "aws:PrincipalArn": "arn:aws:iam::ACCOUNT_ID:role/SecurityAdmin"
    }
  }
}
```

**How it works**:
- Prevents disabling of bucket logging
- Prevents deletion of bucket policy (which could remove logging requirements)
- Only allows security administrators to make changes


## Complete Hardened Bucket Policy

### Full Production-Ready Policy

Here's a complete, production-ready bucket policy combining all hardening controls:

```bash
# Set environment variables
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="us-east-1"
export S3_BUCKET_NAME="harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION}"
export KMS_KEY_ARN="arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/${KMS_KEY_ID}"
export HARBOR_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/HarborS3Role"

# Create hardened bucket policy
cat > harbor-bucket-policy-hardened.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnencryptedObjectUploads",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption": "aws:kms"
        }
      }
    },
    {
      "Sid": "DenyIncorrectEncryptionKey",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*",
      "Condition": {
        "StringNotEqualsIfExists": {
          "s3:x-amz-server-side-encryption-aws-kms-key-id": "${KMS_KEY_ARN}"
        }
      }
    },
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET_NAME}",
        "arn:aws:s3:::${S3_BUCKET_NAME}/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    },
    {
      "Sid": "DenyOutdatedTLS",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET_NAME}",
        "arn:aws:s3:::${S3_BUCKET_NAME}/*"
      ],
      "Condition": {
        "NumericLessThan": {
          "s3:TlsVersion": "1.2"
        }
      }
    },
    {
      "Sid": "AllowHarborRoleAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${HARBOR_ROLE_ARN}"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET_NAME}",
        "arn:aws:s3:::${S3_BUCKET_NAME}/*"
      ]
    },
    {
      "Sid": "DenyBucketDeletion",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:DeleteBucket",
      "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}"
    }
  ]
}
EOF
```

### Applying the Hardened Policy

```bash
# Validate the policy JSON
cat harbor-bucket-policy-hardened.json | jq .

# Apply the bucket policy
aws s3api put-bucket-policy \
  --bucket ${S3_BUCKET_NAME} \
  --policy file://harbor-bucket-policy-hardened.json

echo "✅ Hardened bucket policy applied"

# Verify the policy was applied
aws s3api get-bucket-policy \
  --bucket ${S3_BUCKET_NAME} \
  --query Policy \
  --output text | jq .
```

### Policy Explanation

**Statement 1-2: Encryption Enforcement**
- Denies uploads without KMS encryption
- Ensures correct KMS key is used
- Cannot be overridden by IAM policies

**Statement 3-4: Transport Security**
- Requires HTTPS/TLS for all operations
- Enforces TLS 1.2 or higher
- Protects data in transit

**Statement 5: Harbor Role Access**
- Explicitly allows Harbor IRSA role
- Grants only necessary S3 permissions
- Scoped to specific bucket

**Statement 6: Deletion Protection**
- Prevents bucket deletion
- Requires policy removal first
- Protects against accidents


## Testing and Validation

### Comprehensive Testing Script

Create a script to validate all bucket policy controls:

```bash
cat > test-bucket-policy.sh << 'EOF'
#!/bin/bash

set -e

BUCKET_NAME=$1
KMS_KEY_ARN=$2

if [ -z "$BUCKET_NAME" ] || [ -z "$KMS_KEY_ARN" ]; then
  echo "Usage: $0 <bucket-name> <kms-key-arn>"
  exit 1
fi

echo "🔍 Testing S3 Bucket Policy Hardening"
echo "Bucket: ${BUCKET_NAME}"
echo "KMS Key: ${KMS_KEY_ARN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test 1: Encryption enforcement
echo ""
echo "Test 1: Encryption Enforcement"
echo "Attempting to upload without encryption (should fail)..."
echo "test" > test-file.txt
if aws s3 cp test-file.txt s3://${BUCKET_NAME}/test-unencrypted.txt --no-server-side-encryption 2>&1 | grep -q "AccessDenied\|Forbidden"; then
  echo "✅ PASS: Unencrypted upload blocked"
else
  echo "❌ FAIL: Unencrypted upload allowed"
fi

# Test 2: Correct encryption
echo ""
echo "Test 2: Correct Encryption"
echo "Uploading with KMS encryption (should succeed)..."
if aws s3 cp test-file.txt s3://${BUCKET_NAME}/test-encrypted.txt \
  --server-side-encryption aws:kms \
  --ssekms-key-id ${KMS_KEY_ARN} 2>&1; then
  echo "✅ PASS: Encrypted upload succeeded"
else
  echo "❌ FAIL: Encrypted upload failed"
fi

# Test 3: Verify encryption
echo ""
echo "Test 3: Verify Object Encryption"
ENCRYPTION=$(aws s3api head-object \
  --bucket ${BUCKET_NAME} \
  --key test-encrypted.txt \
  --query 'ServerSideEncryption' \
  --output text 2>/dev/null)

if [ "$ENCRYPTION" = "aws:kms" ]; then
  echo "✅ PASS: Object is encrypted with KMS"
else
  echo "❌ FAIL: Object encryption incorrect: $ENCRYPTION"
fi

# Test 4: Public access block
echo ""
echo "Test 4: Public Access Block"
PUBLIC_BLOCK=$(aws s3api get-public-access-block \
  --bucket ${BUCKET_NAME} \
  --query 'PublicAccessBlockConfiguration' \
  --output json 2>/dev/null)

if echo "$PUBLIC_BLOCK" | jq -e '.BlockPublicAcls == true and .IgnorePublicAcls == true and .BlockPublicPolicy == true and .RestrictPublicBuckets == true' > /dev/null; then
  echo "✅ PASS: All public access block settings enabled"
else
  echo "❌ FAIL: Public access block not fully configured"
  echo "$PUBLIC_BLOCK" | jq .
fi

# Test 5: Bucket policy exists
echo ""
echo "Test 5: Bucket Policy Validation"
if aws s3api get-bucket-policy --bucket ${BUCKET_NAME} --query Policy --output text | jq . > /dev/null 2>&1; then
  echo "✅ PASS: Bucket policy exists and is valid JSON"
else
  echo "❌ FAIL: Bucket policy missing or invalid"
fi

# Test 6: Check for TLS enforcement
echo ""
echo "Test 6: TLS Enforcement Check"
POLICY=$(aws s3api get-bucket-policy --bucket ${BUCKET_NAME} --query Policy --output text)
if echo "$POLICY" | jq -e '.Statement[] | select(.Condition.Bool."aws:SecureTransport" == "false")' > /dev/null 2>&1; then
  echo "✅ PASS: TLS enforcement policy found"
else
  echo "⚠️  WARNING: TLS enforcement policy not found"
fi

# Test 7: Check for encryption enforcement
echo ""
echo "Test 7: Encryption Enforcement Check"
if echo "$POLICY" | jq -e '.Statement[] | select(.Condition.StringNotEquals."s3:x-amz-server-side-encryption")' > /dev/null 2>&1; then
  echo "✅ PASS: Encryption enforcement policy found"
else
  echo "⚠️  WARNING: Encryption enforcement policy not found"
fi

# Cleanup
echo ""
echo "Cleaning up test files..."
rm -f test-file.txt
aws s3 rm s3://${BUCKET_NAME}/test-encrypted.txt 2>/dev/null || true
aws s3 rm s3://${BUCKET_NAME}/test-unencrypted.txt 2>/dev/null || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Testing complete"
EOF

chmod +x test-bucket-policy.sh
```

### Running the Tests

```bash
# Run comprehensive tests
./test-bucket-policy.sh ${S3_BUCKET_NAME} ${KMS_KEY_ARN}
```

### Expected Output

```
🔍 Testing S3 Bucket Policy Hardening
Bucket: harbor-registry-storage-123456789012-us-east-1
KMS Key: arn:aws:kms:us-east-1:123456789012:key/...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Test 1: Encryption Enforcement
Attempting to upload without encryption (should fail)...
✅ PASS: Unencrypted upload blocked

Test 2: Correct Encryption
Uploading with KMS encryption (should succeed)...
✅ PASS: Encrypted upload succeeded

Test 3: Verify Object Encryption
✅ PASS: Object is encrypted with KMS

Test 4: Public Access Block
✅ PASS: All public access block settings enabled

Test 5: Bucket Policy Validation
✅ PASS: Bucket policy exists and is valid JSON

Test 6: TLS Enforcement Check
✅ PASS: TLS enforcement policy found

Test 7: Encryption Enforcement Check
✅ PASS: Encryption enforcement policy found

Cleaning up test files...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Testing complete
```


## Monitoring and Compliance

### CloudTrail Logging

Ensure all S3 API calls are logged:

```bash
# Verify CloudTrail is logging S3 data events
aws cloudtrail get-event-selectors \
  --trail-name <your-trail-name> \
  --query 'EventSelectors[].DataResources[]' \
  --output json

# Expected: Should include S3 data events for your bucket
```

### CloudWatch Metrics and Alarms

Create alarms for suspicious activity:

```bash
# Create alarm for unauthorized access attempts
aws cloudwatch put-metric-alarm \
  --alarm-name harbor-s3-unauthorized-access \
  --alarm-description "Alert on unauthorized S3 access attempts" \
  --metric-name 4xxErrors \
  --namespace AWS/S3 \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=BucketName,Value=${S3_BUCKET_NAME} \
  --alarm-actions arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:security-alerts

# Create alarm for bucket policy changes
aws cloudwatch put-metric-alarm \
  --alarm-name harbor-s3-policy-changes \
  --alarm-description "Alert on S3 bucket policy modifications" \
  --metric-name S3PolicyChanges \
  --namespace CustomMetrics \
  --statistic Sum \
  --period 60 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:security-alerts
```

### AWS Config Rules

Use AWS Config to continuously monitor bucket configuration:

```bash
# Enable AWS Config rule for S3 bucket encryption
aws configservice put-config-rule \
  --config-rule '{
    "ConfigRuleName": "s3-bucket-server-side-encryption-enabled",
    "Description": "Checks that S3 buckets have encryption enabled",
    "Source": {
      "Owner": "AWS",
      "SourceIdentifier": "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
    },
    "Scope": {
      "ComplianceResourceTypes": ["AWS::S3::Bucket"]
    }
  }'

# Enable rule for public access block
aws configservice put-config-rule \
  --config-rule '{
    "ConfigRuleName": "s3-bucket-public-read-prohibited",
    "Description": "Checks that S3 buckets do not allow public read access",
    "Source": {
      "Owner": "AWS",
      "SourceIdentifier": "S3_BUCKET_PUBLIC_READ_PROHIBITED"
    },
    "Scope": {
      "ComplianceResourceTypes": ["AWS::S3::Bucket"]
    }
  }'

# Enable rule for TLS enforcement
aws configservice put-config-rule \
  --config-rule '{
    "ConfigRuleName": "s3-bucket-ssl-requests-only",
    "Description": "Checks that S3 buckets have policies requiring SSL",
    "Source": {
      "Owner": "AWS",
      "SourceIdentifier": "S3_BUCKET_SSL_REQUESTS_ONLY"
    },
    "Scope": {
      "ComplianceResourceTypes": ["AWS::S3::Bucket"]
    }
  }'
```

### Compliance Reporting

Generate compliance reports:

```bash
# Check Config compliance for Harbor bucket
aws configservice describe-compliance-by-resource \
  --resource-type AWS::S3::Bucket \
  --resource-id ${S3_BUCKET_NAME} \
  --output table

# Get detailed compliance information
aws configservice get-compliance-details-by-resource \
  --resource-type AWS::S3::Bucket \
  --resource-id ${S3_BUCKET_NAME} \
  --output json | jq '.EvaluationResults[] | {Rule: .EvaluationResultIdentifier.EvaluationResultQualifier.ConfigRuleName, Compliance: .ComplianceType}'
```

### Security Hub Integration

Enable Security Hub findings for S3:

```bash
# Enable S3 security standards in Security Hub
aws securityhub batch-enable-standards \
  --standards-subscription-requests '[
    {
      "StandardsArn": "arn:aws:securityhub:us-east-1::standards/aws-foundational-security-best-practices/v/1.0.0"
    }
  ]'

# View S3-related findings
aws securityhub get-findings \
  --filters '{
    "ResourceType": [{"Value": "AwsS3Bucket", "Comparison": "EQUALS"}],
    "ResourceId": [{"Value": "'${S3_BUCKET_NAME}'", "Comparison": "EQUALS"}]
  }' \
  --output json | jq '.Findings[] | {Title: .Title, Severity: .Severity.Label, Compliance: .Compliance.Status}'
```


## Troubleshooting

### Issue 1: Access Denied After Applying Policy

**Symptom:**
```
An error occurred (AccessDenied) when calling the PutObject operation: Access Denied
```

**Possible Causes:**
1. Bucket policy is too restrictive
2. IAM role doesn't have necessary permissions
3. KMS key policy doesn't allow the role
4. Request doesn't meet policy conditions (e.g., no encryption header)

**Solution:**
```bash
# Check if Harbor role is in the bucket policy
aws s3api get-bucket-policy \
  --bucket ${S3_BUCKET_NAME} \
  --query Policy \
  --output text | jq '.Statement[] | select(.Principal.AWS)'

# Verify IAM role has S3 permissions
aws iam get-role-policy \
  --role-name HarborS3Role \
  --policy-name HarborS3Access

# Check KMS key policy
aws kms get-key-policy \
  --key-id ${KMS_KEY_ID} \
  --policy-name default \
  --query Policy \
  --output text | jq .

# Test with explicit encryption
aws s3 cp test.txt s3://${S3_BUCKET_NAME}/test.txt \
  --server-side-encryption aws:kms \
  --ssekms-key-id ${KMS_KEY_ARN}
```

### Issue 2: Cannot Apply Bucket Policy

**Symptom:**
```
An error occurred (MalformedPolicy) when calling the PutBucketPolicy operation: Policy has invalid resource
```

**Possible Causes:**
1. JSON syntax error
2. Invalid ARN format
3. Missing required fields
4. Conflicting statements

**Solution:**
```bash
# Validate JSON syntax
cat harbor-bucket-policy-hardened.json | jq .

# Check for common issues
jq '.Statement[] | {Sid: .Sid, Effect: .Effect, Principal: .Principal, Action: .Action, Resource: .Resource}' \
  harbor-bucket-policy-hardened.json

# Validate with AWS Access Analyzer
aws accessanalyzer validate-policy \
  --policy-document file://harbor-bucket-policy-hardened.json \
  --policy-type RESOURCE_POLICY \
  --resource-type AWS::S3::Bucket \
  --region us-east-1
```

### Issue 3: Public Access Block Conflicts

**Symptom:**
```
An error occurred (InvalidBucketState) when calling the PutBucketPolicy operation: The bucket policy conflicts with the public access block configuration
```

**Solution:**
```bash
# Check public access block settings
aws s3api get-public-access-block --bucket ${S3_BUCKET_NAME}

# If you need to allow specific public access (not recommended for Harbor):
# Temporarily disable specific settings
aws s3api put-public-access-block \
  --bucket ${S3_BUCKET_NAME} \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=true"

# Better: Remove public statements from policy instead
```

### Issue 4: TLS Version Errors

**Symptom:**
Harbor cannot connect to S3, or you see TLS handshake errors.

**Solution:**
```bash
# Check Harbor's TLS configuration
kubectl get configmap harbor-core -n harbor -o yaml | grep -i tls

# Verify AWS CLI is using TLS 1.2+
aws s3 ls s3://${S3_BUCKET_NAME}/ --debug 2>&1 | grep -i "ssl\|tls"

# If using older clients, temporarily remove TLS version restriction:
# (Not recommended - upgrade clients instead)
# Remove the "DenyOutdatedTLS" statement from bucket policy
```

### Issue 5: Locked Out of Bucket

**Symptom:**
Cannot access bucket after applying restrictive policy, even as administrator.

**Solution:**
```bash
# Use root account credentials to remove policy
# (This is why we include root in policy exceptions)

# If using root account:
aws s3api delete-bucket-policy --bucket ${S3_BUCKET_NAME}

# Then reapply corrected policy
aws s3api put-bucket-policy \
  --bucket ${S3_BUCKET_NAME} \
  --policy file://harbor-bucket-policy-corrected.json

# Prevention: Always include root account exception in deny statements
```

### Issue 6: KMS Key Not Found

**Symptom:**
```
An error occurred (KMS.NotFoundException) when calling the PutObject operation: Key 'arn:aws:kms:...' does not exist
```

**Solution:**
```bash
# Verify KMS key exists
aws kms describe-key --key-id ${KMS_KEY_ID}

# Check if key is in correct region
aws kms list-keys --region ${AWS_REGION}

# Verify key ARN in bucket policy matches actual key
aws s3api get-bucket-policy \
  --bucket ${S3_BUCKET_NAME} \
  --query Policy \
  --output text | jq '.Statement[] | select(.Condition."StringNotEqualsIfExists")'
```

### Issue 7: Harbor Pod Cannot Access S3

**Symptom:**
Harbor logs show S3 access denied errors.

**Solution:**
```bash
# Check if service account has correct annotation
kubectl get sa harbor -n harbor -o yaml | grep eks.amazonaws.com/role-arn

# Verify IRSA role can assume
aws sts assume-role \
  --role-arn ${HARBOR_ROLE_ARN} \
  --role-session-name test

# Check if pod has AWS credentials
kubectl exec -it <harbor-pod> -n harbor -- env | grep AWS

# Test S3 access from pod
kubectl exec -it <harbor-pod> -n harbor -- \
  aws s3 ls s3://${S3_BUCKET_NAME}/
```


## Best Practices Summary

### Essential Hardening Controls

✅ **Always Implement**:
1. **Encryption enforcement**: Deny unencrypted uploads
2. **TLS requirement**: Deny non-HTTPS requests
3. **Public access block**: Enable all four settings
4. **Specific KMS key**: Enforce use of customer-managed key
5. **CloudTrail logging**: Enable S3 data events

✅ **Strongly Recommended**:
1. **TLS version enforcement**: Require TLS 1.2+
2. **Bucket deletion protection**: Deny DeleteBucket
3. **VPC endpoint restriction**: Limit to VPC traffic (if applicable)
4. **AWS Config monitoring**: Continuous compliance checking
5. **CloudWatch alarms**: Alert on policy changes

⚠️ **Consider for Production**:
1. **MFA for deletion**: Require MFA for destructive operations
2. **Role restriction**: Limit to specific IAM roles
3. **Logging protection**: Prevent disabling of logging
4. **Versioning**: Enable for data recovery
5. **Lifecycle policies**: Manage costs and retention

### Policy Development Workflow

1. **Start with basics**: Encryption + TLS + Public Access Block
2. **Test thoroughly**: Verify Harbor can still access bucket
3. **Add restrictions gradually**: One policy statement at a time
4. **Monitor impact**: Check CloudTrail logs for denied requests
5. **Document exceptions**: Explain why certain principals are excluded
6. **Version control**: Store policies in Git with change history
7. **Automate validation**: Use CI/CD to test policy changes

### Security Checklist

Before deploying to production, verify:

- [ ] Bucket policy enforces KMS encryption
- [ ] Bucket policy requires TLS 1.2+
- [ ] Public Access Block enabled (all four settings)
- [ ] Specific KMS key is enforced
- [ ] Harbor IRSA role has necessary permissions
- [ ] KMS key policy allows Harbor role
- [ ] CloudTrail logging enabled for S3 data events
- [ ] CloudWatch alarms configured for policy changes
- [ ] AWS Config rules monitoring bucket compliance
- [ ] Bucket versioning enabled
- [ ] Lifecycle policies configured
- [ ] Testing script passes all checks
- [ ] Documentation updated with policy details
- [ ] Runbook created for troubleshooting

### Compliance Mapping

**PCI DSS**:
- Requirement 3.4: Encryption at rest ✅ (KMS enforcement)
- Requirement 4.1: Encryption in transit ✅ (TLS enforcement)
- Requirement 10.2: Audit logging ✅ (CloudTrail)

**HIPAA**:
- 164.312(a)(2)(iv): Encryption ✅ (KMS + TLS)
- 164.312(b): Audit controls ✅ (CloudTrail + CloudWatch)
- 164.308(a)(4): Access controls ✅ (IAM + Bucket Policy)

**SOC 2**:
- CC6.1: Logical access controls ✅ (IAM + Bucket Policy)
- CC6.6: Encryption ✅ (KMS + TLS)
- CC7.2: Monitoring ✅ (CloudWatch + Config)

**GDPR**:
- Article 32: Security of processing ✅ (Encryption + Access Controls)
- Article 25: Data protection by design ✅ (Defense in depth)

### Cost Optimization

**Bucket Policy Costs**: $0 (no additional charge)

**Related Costs**:
- KMS: ~$1/month per key + $0.03 per 10,000 requests
- CloudTrail: ~$2/100,000 events
- AWS Config: ~$2/active rule/region/month
- CloudWatch: ~$0.30/alarm/month

**Cost Savings**:
- Enable S3 Bucket Keys: Reduces KMS costs by 99%
- Use lifecycle policies: Transition old data to cheaper storage
- Optimize logging: Log only necessary events

### Maintenance and Updates

**Monthly**:
- Review CloudWatch alarms for anomalies
- Check AWS Config compliance reports
- Verify no unauthorized policy changes

**Quarterly**:
- Review and update bucket policy as needed
- Test disaster recovery procedures
- Audit access logs for suspicious activity

**Annually**:
- Comprehensive security review
- Update documentation
- Review and update compliance mappings
- Test all troubleshooting procedures


## Quick Reference

### Essential Commands

```bash
# Apply hardened bucket policy
aws s3api put-bucket-policy \
  --bucket ${S3_BUCKET_NAME} \
  --policy file://harbor-bucket-policy-hardened.json

# Enable public access block
aws s3api put-public-access-block \
  --bucket ${S3_BUCKET_NAME} \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Verify bucket policy
aws s3api get-bucket-policy \
  --bucket ${S3_BUCKET_NAME} \
  --query Policy \
  --output text | jq .

# Test encryption enforcement
aws s3 cp test.txt s3://${S3_BUCKET_NAME}/test.txt \
  --server-side-encryption aws:kms \
  --ssekms-key-id ${KMS_KEY_ARN}

# Check compliance
aws configservice describe-compliance-by-resource \
  --resource-type AWS::S3::Bucket \
  --resource-id ${S3_BUCKET_NAME}
```

### Policy Template Variables

Replace these in the policy templates:

- `BUCKET_NAME`: Your S3 bucket name
- `ACCOUNT_ID`: Your AWS account ID
- `REGION`: AWS region (e.g., us-east-1)
- `KMS_KEY_ARN`: Full ARN of your KMS key
- `HARBOR_ROLE_ARN`: ARN of Harbor IRSA role
- `VPC_ENDPOINT_ID`: VPC endpoint ID (if using)

### Common Policy Patterns

**Deny unencrypted uploads**:
```json
{
  "Effect": "Deny",
  "Action": "s3:PutObject",
  "Condition": {
    "StringNotEquals": {
      "s3:x-amz-server-side-encryption": "aws:kms"
    }
  }
}
```

**Require TLS**:
```json
{
  "Effect": "Deny",
  "Action": "s3:*",
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```

**Allow specific role**:
```json
{
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::ACCOUNT_ID:role/HarborS3Role"
  },
  "Action": ["s3:GetObject", "s3:PutObject"]
}
```

## Additional Resources

### AWS Documentation

- [S3 Bucket Policies](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-policies.html)
- [S3 Security Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [S3 Encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingEncryption.html)
- [S3 Public Access Block](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html)
- [IAM Policy Conditions](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_condition.html)

### Related Workshop Guides

- [S3 and KMS Setup](./s3-kms-setup.md) - Initial bucket and key configuration
- [IAM Role Policy Setup](./iam-role-policy-setup.md) - Harbor IRSA role configuration
- [KMS Key Policy Hardening](./kms-key-policy-hardening.md) - KMS key security controls
- [IAM Guardrails](./iam-guardrails.md) - Additional IAM security layers
- [Harbor IRSA Deployment](./harbor-irsa-deployment.md) - Deploy Harbor with hardened storage

### Tools and Scripts

- [test-bucket-policy.sh](../scripts/test-bucket-policy.sh) - Comprehensive policy testing
- [validate-deployment.sh](../scripts/validate-deployment.sh) - End-to-end validation
- [AWS Policy Generator](https://awspolicygen.s3.amazonaws.com/policygen.html) - Generate policies
- [IAM Policy Simulator](https://policysim.aws.amazon.com/) - Test policy effects

## Summary

You've learned how to harden S3 bucket policies for Harbor container registry storage. This guide covered:

✅ **Encryption Enforcement**: Deny unencrypted uploads and enforce specific KMS keys  
✅ **TLS Requirements**: Require HTTPS and modern TLS versions for all access  
✅ **Public Access Block**: Prevent any public access to Harbor storage  
✅ **Additional Controls**: Deletion protection, VPC restrictions, and monitoring  
✅ **Testing and Validation**: Comprehensive testing scripts and procedures  
✅ **Compliance**: Mapping to PCI DSS, HIPAA, SOC 2, and GDPR requirements  
✅ **Troubleshooting**: Common issues and solutions  

**Key Takeaways**:

1. **Defense in Depth**: Bucket policies provide resource-level security independent of IAM
2. **Explicit Deny**: Deny statements in bucket policies cannot be overridden
3. **Encryption Everywhere**: Enforce encryption at rest (KMS) and in transit (TLS)
4. **Test Thoroughly**: Validate policies before production deployment
5. **Monitor Continuously**: Use CloudWatch, Config, and Security Hub for ongoing compliance

**Next Steps**:

1. Apply the hardened bucket policy to your Harbor storage bucket
2. Run the testing script to validate all controls
3. Configure monitoring and alerting
4. Document your specific policy decisions
5. Proceed to [Harbor IRSA Deployment](./harbor-irsa-deployment.md)

---

**Workshop Navigation**:
- **Previous**: [S3 and KMS Setup](./s3-kms-setup.md)
- **Next**: [Harbor IRSA Deployment](./harbor-irsa-deployment.md)
- **Home**: [Workshop README](../README.md)

