# S3 and KMS Setup for Harbor Backend Storage

## Overview

This guide walks you through setting up Amazon S3 bucket with AWS KMS encryption for Harbor's backend storage. We'll implement security best practices including encryption at rest, encryption in transit, versioning, and restrictive bucket policies.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Step 1: Create KMS Customer Managed Key](#step-1-create-kms-customer-managed-key)
3. [Step 2: Create S3 Bucket](#step-2-create-s3-bucket)
4. [Step 3: Configure S3 Bucket Encryption](#step-3-configure-s3-bucket-encryption)
5. [Step 4: Create S3 Bucket Policy](#step-4-create-s3-bucket-policy)
6. [Step 5: Enable S3 Bucket Versioning](#step-5-enable-s3-bucket-versioning)
7. [Step 6: Configure S3 Lifecycle Policies](#step-6-configure-s3-lifecycle-policies)
8. [Step 7: Verify Configuration](#step-7-verify-configuration)
9. [Understanding Encryption](#understanding-encryption)
10. [Troubleshooting](#troubleshooting)

## Prerequisites

Before starting, ensure you have:

- **AWS CLI** v2.x installed and configured
- **IAM permissions** to create KMS keys and S3 buckets
- **IAM role ARN** from the previous step (HarborS3Role)

### Required IAM Permissions

Your AWS user/role needs these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:CreateKey",
        "kms:CreateAlias",
        "kms:DescribeKey",
        "kms:PutKeyPolicy",
        "kms:EnableKeyRotation",
        "kms:TagResource",
        "s3:CreateBucket",
        "s3:PutBucketEncryption",
        "s3:PutBucketVersioning",
        "s3:PutBucketPolicy",
        "s3:PutBucketPublicAccessBlock",
        "s3:PutLifecycleConfiguration"
      ],
      "Resource": "*"
    }
  ]
}
```

### Environment Variables

Set these from previous steps:

```bash
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export HARBOR_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/HarborS3Role"
export S3_BUCKET_NAME="harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION}"
export KMS_KEY_ALIAS="alias/harbor-s3-encryption"

echo "AWS Region: ${AWS_REGION}"
echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "Harbor Role ARN: ${HARBOR_ROLE_ARN}"
echo "S3 Bucket Name: ${S3_BUCKET_NAME}"
echo "KMS Key Alias: ${KMS_KEY_ALIAS}"
```

## Step 1: Create KMS Customer Managed Key

### 1.1 Understanding KMS Key Types

AWS offers three types of encryption keys for S3:

1. **SSE-S3** (AWS-managed keys)
   - ❌ AWS controls the keys
   - ❌ Cannot audit key usage
   - ❌ Cannot control key policies

2. **SSE-KMS with AWS-managed key** (aws/s3)
   - ⚠️ AWS controls the key
   - ✅ Can audit usage in CloudTrail
   - ❌ Cannot control key policies

3. **SSE-KMS with Customer Managed Key (CMK)** ✅ RECOMMENDED
   - ✅ You control the key
   - ✅ Full audit trail in CloudTrail
   - ✅ Custom key policies
   - ✅ Automatic rotation
   - ✅ Can disable/delete if needed

We'll use option 3 for maximum security and control.

### 1.2 Create KMS Key Policy

First, create a key policy that allows:
- Root account full access (for administration)
- Harbor IAM role to use the key for encryption/decryption
- S3 service to use the key

Create a file `kms-key-policy.json`:

```bash
cat > kms-key-policy.json << EOF
{
  "Version": "2012-10-17",
  "Id": "harbor-s3-kms-key-policy",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow Harbor Role to use the key",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${HARBOR_ROLE_ARN}"
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "s3.${AWS_REGION}.amazonaws.com"
        }
      }
    },
    {
      "Sid": "Allow S3 to use the key",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Allow CloudWatch Logs",
      "Effect": "Allow",
      "Principal": {
        "Service": "logs.${AWS_REGION}.amazonaws.com"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:DescribeKey"
      ],
      "Resource": "*",
      "Condition": {
        "ArnLike": {
          "kms:EncryptionContext:aws:logs:arn": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:*"
        }
      }
    }
  ]
}
EOF
```

### 1.3 Understanding the Key Policy

Let's break down each statement:

**Statement 1: Root Account Access**
```json
{
  "Sid": "Enable IAM User Permissions",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::123456789012:root"
  },
  "Action": "kms:*",
  "Resource": "*"
}
```
- Allows account administrators to manage the key
- Required for key administration via IAM policies
- Does NOT grant access to all users (IAM policies still apply)

**Statement 2: Harbor Role Access (with Condition)**
```json
{
  "Sid": "Allow Harbor Role to use the key",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::123456789012:role/HarborS3Role"
  },
  "Action": [
    "kms:Decrypt",           // Decrypt objects when reading
    "kms:GenerateDataKey",   // Generate data keys for encryption
    "kms:DescribeKey"        // Get key metadata
  ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "kms:ViaService": "s3.us-east-1.amazonaws.com"  // Only via S3
    }
  }
}
```
- Grants Harbor role permission to encrypt/decrypt
- **Condition restricts usage to S3 service only**
- Prevents direct KMS API calls (defense in depth)

**Statement 3: S3 Service Access**
```json
{
  "Sid": "Allow S3 to use the key",
  "Effect": "Allow",
  "Principal": {
    "Service": "s3.amazonaws.com"
  },
  "Action": [
    "kms:Decrypt",
    "kms:GenerateDataKey"
  ],
  "Resource": "*"
}
```
- Allows S3 service to use the key for encryption operations
- Required for SSE-KMS to work

### 1.4 Create the KMS Key

```bash
# Create KMS customer managed key
export KMS_KEY_ID=$(aws kms create-key \
  --description "KMS key for Harbor S3 bucket encryption" \
  --key-usage ENCRYPT_DECRYPT \
  --origin AWS_KMS \
  --policy file://kms-key-policy.json \
  --tags TagKey=Environment,TagValue=workshop TagKey=Application,TagValue=harbor \
  --query 'KeyMetadata.KeyId' \
  --output text)

echo "KMS Key ID: ${KMS_KEY_ID}"

# Get the full key ARN
export KMS_KEY_ARN=$(aws kms describe-key \
  --key-id ${KMS_KEY_ID} \
  --query 'KeyMetadata.Arn' \
  --output text)

echo "KMS Key ARN: ${KMS_KEY_ARN}"
```

**Expected output:**
```
KMS Key ID: 12345678-1234-1234-1234-123456789012
KMS Key ARN: arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012
```

### 1.5 Create KMS Key Alias

Aliases make keys easier to reference:

```bash
# Create alias for the key
aws kms create-alias \
  --alias-name ${KMS_KEY_ALIAS} \
  --target-key-id ${KMS_KEY_ID}

echo "✅ KMS key alias created: ${KMS_KEY_ALIAS}"
```

### 1.6 Enable Automatic Key Rotation

```bash
# Enable automatic annual key rotation
aws kms enable-key-rotation --key-id ${KMS_KEY_ID}

# Verify rotation is enabled
aws kms get-key-rotation-status --key-id ${KMS_KEY_ID}
```

**Expected output:**
```json
{
    "KeyRotationEnabled": true
}
```

✅ **Checkpoint**: KMS key created with automatic rotation enabled.

### 1.7 Save KMS Key Information

```bash
# Save key information for later use
cat > kms-key-info.txt << EOF
KMS Key ID: ${KMS_KEY_ID}
KMS Key ARN: ${KMS_KEY_ARN}
KMS Key Alias: ${KMS_KEY_ALIAS}
EOF

echo "KMS key information saved to kms-key-info.txt"
```

## Step 2: Create S3 Bucket

### 2.1 Understanding S3 Bucket Naming

S3 bucket names must be:
- Globally unique across all AWS accounts
- 3-63 characters long
- Lowercase letters, numbers, and hyphens only
- Not formatted as an IP address

We use the pattern: `harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION}`

This ensures uniqueness and identifies the purpose, account, and region.

### 2.2 Create the S3 Bucket

```bash
# Create S3 bucket
if [ "${AWS_REGION}" = "us-east-1" ]; then
  # us-east-1 doesn't need LocationConstraint
  aws s3api create-bucket \
    --bucket ${S3_BUCKET_NAME} \
    --region ${AWS_REGION}
else
  # Other regions require LocationConstraint
  aws s3api create-bucket \
    --bucket ${S3_BUCKET_NAME} \
    --region ${AWS_REGION} \
    --create-bucket-configuration LocationConstraint=${AWS_REGION}
fi

echo "✅ S3 bucket created: ${S3_BUCKET_NAME}"
```

### 2.3 Block Public Access

**CRITICAL SECURITY STEP**: Block all public access to the bucket.

```bash
# Block all public access
aws s3api put-public-access-block \
  --bucket ${S3_BUCKET_NAME} \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "✅ Public access blocked"
```

This prevents:
- Public ACLs from being applied
- Public bucket policies from being applied
- Cross-account access via ACLs
- Public access through any means

### 2.4 Add Bucket Tags

```bash
# Tag the bucket
aws s3api put-bucket-tagging \
  --bucket ${S3_BUCKET_NAME} \
  --tagging "TagSet=[
    {Key=Environment,Value=workshop},
    {Key=Application,Value=harbor},
    {Key=ManagedBy,Value=manual},
    {Key=Purpose,Value=container-registry-storage}
  ]"

echo "✅ Bucket tags applied"
```

## Step 3: Configure S3 Bucket Encryption

### 3.1 Enable Default Encryption with KMS

```bash
# Configure default encryption with KMS CMK
aws s3api put-bucket-encryption \
  --bucket ${S3_BUCKET_NAME} \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "aws:kms",
          "KMSMasterKeyID": "'${KMS_KEY_ARN}'"
        },
        "BucketKeyEnabled": true
      }
    ]
  }'

echo "✅ Bucket encryption configured with KMS"
```

### 3.2 Understanding Bucket Key

`BucketKeyEnabled: true` provides:
- **Cost savings**: Reduces KMS API calls by ~99%
- **Performance**: Faster encryption operations
- **How it works**: S3 generates a bucket-level key from KMS, then uses it to generate object keys

### 3.3 Verify Encryption Configuration

```bash
# Get bucket encryption configuration
aws s3api get-bucket-encryption --bucket ${S3_BUCKET_NAME}
```

**Expected output:**
```json
{
    "ServerSideEncryptionConfiguration": {
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "aws:kms",
                    "KMSMasterKeyID": "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
                },
                "BucketKeyEnabled": true
            }
        ]
    }
}
```

## Step 4: Create S3 Bucket Policy

### 4.1 Understanding Bucket Policies

Bucket policies provide additional security layers:
1. **Deny unencrypted uploads**: Reject objects without encryption
2. **Deny insecure transport**: Reject non-HTTPS requests
3. **Restrict to specific IAM role**: Only Harbor role can access

### 4.2 Create Bucket Policy Document

Create a file `s3-bucket-policy.json`:

```bash
cat > s3-bucket-policy.json << EOF
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
      "Sid": "DenyIncorrectEncryptionHeader",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption-aws-kms-key-id": "${KMS_KEY_ARN}"
        }
      }
    }
  ]
}
EOF
```

### 4.3 Understanding Each Policy Statement

**Statement 1: Deny Unencrypted Uploads**
```json
{
  "Sid": "DenyUnencryptedObjectUploads",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::bucket-name/*",
  "Condition": {
    "StringNotEquals": {
      "s3:x-amz-server-side-encryption": "aws:kms"
    }
  }
}
```
- Denies any PutObject request without KMS encryption
- Applies to all principals (even administrators)
- Explicit deny overrides any allow

**Statement 2: Deny Insecure Transport**
```json
{
  "Sid": "DenyInsecureTransport",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": ["arn:aws:s3:::bucket-name", "arn:aws:s3:::bucket-name/*"],
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```
- Denies all S3 operations over HTTP (non-TLS)
- Enforces encryption in transit
- Applies to bucket and all objects

**Statement 3: Deny Incorrect KMS Key**
```json
{
  "Sid": "DenyIncorrectEncryptionHeader",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::bucket-name/*",
  "Condition": {
    "StringNotEquals": {
      "s3:x-amz-server-side-encryption-aws-kms-key-id": "arn:aws:kms:..."
    }
  }
}
```
- Ensures only our specific KMS key is used
- Prevents use of other KMS keys
- Additional defense in depth

### 4.4 Apply Bucket Policy

```bash
# Apply bucket policy
aws s3api put-bucket-policy \
  --bucket ${S3_BUCKET_NAME} \
  --policy file://s3-bucket-policy.json

echo "✅ Bucket policy applied"
```

### 4.5 Verify Bucket Policy

```bash
# Get bucket policy
aws s3api get-bucket-policy \
  --bucket ${S3_BUCKET_NAME} \
  --query Policy \
  --output text | jq .
```

## Step 5: Enable S3 Bucket Versioning

### 5.1 Why Enable Versioning?

Versioning provides:
- **Data protection**: Recover from accidental deletions
- **Audit trail**: Track all changes to objects
- **Compliance**: Meet regulatory requirements
- **Rollback capability**: Restore previous versions

### 5.2 Enable Versioning

```bash
# Enable versioning
aws s3api put-bucket-versioning \
  --bucket ${S3_BUCKET_NAME} \
  --versioning-configuration Status=Enabled

echo "✅ Bucket versioning enabled"
```

### 5.3 Verify Versioning

```bash
# Check versioning status
aws s3api get-bucket-versioning --bucket ${S3_BUCKET_NAME}
```

**Expected output:**
```json
{
    "Status": "Enabled"
}
```

## Step 6: Configure S3 Lifecycle Policies

### 6.1 Understanding Lifecycle Policies

Lifecycle policies help manage costs by:
- Transitioning old versions to cheaper storage classes
- Deleting old versions after a retention period
- Cleaning up incomplete multipart uploads

### 6.2 Create Lifecycle Policy

```bash
# Create lifecycle policy
aws s3api put-bucket-lifecycle-configuration \
  --bucket ${S3_BUCKET_NAME} \
  --lifecycle-configuration '{
    "Rules": [
      {
        "Id": "DeleteOldVersions",
        "Status": "Enabled",
        "NoncurrentVersionExpiration": {
          "NoncurrentDays": 90
        }
      },
      {
        "Id": "CleanupIncompleteMultipartUploads",
        "Status": "Enabled",
        "AbortIncompleteMultipartUpload": {
          "DaysAfterInitiation": 7
        }
      },
      {
        "Id": "TransitionOldVersionsToIA",
        "Status": "Enabled",
        "NoncurrentVersionTransitions": [
          {
            "NoncurrentDays": 30,
            "StorageClass": "STANDARD_IA"
          }
        ]
      }
    ]
  }'

echo "✅ Lifecycle policies configured"
```

### 6.3 Understanding Lifecycle Rules

**Rule 1: Delete Old Versions**
- Deletes non-current versions after 90 days
- Reduces storage costs
- Maintains recent versions for recovery

**Rule 2: Cleanup Incomplete Uploads**
- Aborts multipart uploads after 7 days
- Prevents storage charges for incomplete uploads
- Cleans up failed upload attempts

**Rule 3: Transition to Infrequent Access**
- Moves old versions to cheaper storage after 30 days
- Reduces costs while maintaining availability
- STANDARD_IA is 50% cheaper than STANDARD

### 6.4 Verify Lifecycle Configuration

```bash
# Get lifecycle configuration
aws s3api get-bucket-lifecycle-configuration --bucket ${S3_BUCKET_NAME}
```

## Step 7: Verify Configuration

### 7.1 Comprehensive Bucket Check

```bash
# Create verification script
cat > verify-s3-config.sh << 'EOF'
#!/bin/bash

BUCKET=$1

echo "=== S3 Bucket Configuration Verification ==="
echo "Bucket: ${BUCKET}"
echo ""

echo "1. Bucket Encryption:"
aws s3api get-bucket-encryption --bucket ${BUCKET} 2>/dev/null || echo "❌ Not configured"
echo ""

echo "2. Public Access Block:"
aws s3api get-public-access-block --bucket ${BUCKET}
echo ""

echo "3. Bucket Versioning:"
aws s3api get-bucket-versioning --bucket ${BUCKET}
echo ""

echo "4. Bucket Policy:"
aws s3api get-bucket-policy --bucket ${BUCKET} --query Policy --output text | jq . 2>/dev/null || echo "❌ Not configured"
echo ""

echo "5. Lifecycle Configuration:"
aws s3api get-bucket-lifecycle-configuration --bucket ${BUCKET} 2>/dev/null || echo "❌ Not configured"
echo ""

echo "6. Bucket Tags:"
aws s3api get-bucket-tagging --bucket ${BUCKET}
echo ""

echo "=== Verification Complete ==="
EOF

chmod +x verify-s3-config.sh

# Run verification
./verify-s3-config.sh ${S3_BUCKET_NAME}
```

### 7.2 Test Encryption

```bash
# Test uploading an object (should be encrypted automatically)
echo "Test content" > test-file.txt

aws s3 cp test-file.txt s3://${S3_BUCKET_NAME}/test-file.txt

# Verify object is encrypted
aws s3api head-object \
  --bucket ${S3_BUCKET_NAME} \
  --key test-file.txt \
  --query 'ServerSideEncryption'

# Should output: "aws:kms"

# Clean up test file
rm test-file.txt
aws s3 rm s3://${S3_BUCKET_NAME}/test-file.txt
```

### 7.3 Test Bucket Policy (Deny HTTP)

```bash
# Try to access bucket over HTTP (should fail)
curl -I http://${S3_BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com/

# Should return 403 Forbidden due to bucket policy
```

## Understanding Encryption

### Encryption at Rest (SSE-KMS)

When Harbor uploads an object to S3:

1. **Harbor sends** PutObject request with encryption header
2. **S3 requests** data key from KMS using the CMK
3. **KMS generates** data key and returns:
   - Plaintext data key (used immediately)
   - Encrypted data key (stored with object)
4. **S3 encrypts** object using plaintext data key
5. **S3 stores** encrypted object + encrypted data key
6. **S3 deletes** plaintext data key from memory

When Harbor downloads an object:

1. **Harbor sends** GetObject request
2. **S3 retrieves** encrypted object + encrypted data key
3. **S3 calls KMS** to decrypt the data key
4. **KMS decrypts** data key (checks key policy)
5. **S3 decrypts** object using plaintext data key
6. **S3 returns** decrypted object to Harbor
7. **S3 deletes** plaintext data key from memory

### Encryption in Transit (TLS)

All communication uses HTTPS/TLS:
- Harbor ↔ S3: TLS 1.2+
- S3 ↔ KMS: TLS 1.2+
- Bucket policy enforces TLS

### Defense in Depth

Multiple layers of encryption:
1. **TLS in transit**: Data encrypted while moving
2. **KMS at rest**: Data encrypted while stored
3. **Bucket policy**: Enforces encryption requirements
4. **IAM policies**: Controls who can decrypt
5. **Key policy**: Controls who can use KMS key

## Troubleshooting

### Issue 1: Bucket Name Already Exists

**Symptom:**
```
An error occurred (BucketAlreadyExists) when calling the CreateBucket operation: The requested bucket name is not available.
```

**Solution:**
S3 bucket names are globally unique. Change the bucket name:
```bash
export S3_BUCKET_NAME="harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION}-$(date +%s)"
```

### Issue 2: KMS Key Policy Errors

**Symptom:**
```
An error occurred (MalformedPolicyDocumentException) when calling the CreateKey operation
```

**Solution:**
Validate JSON syntax:
```bash
cat kms-key-policy.json | jq .
```

### Issue 3: Cannot Upload Objects

**Symptom:**
```
An error occurred (AccessDenied) when calling the PutObject operation: Access Denied
```

**Solution:**
Check:
1. IAM role has S3 permissions
2. Bucket policy allows the role
3. KMS key policy allows the role
4. Using HTTPS (not HTTP)

### Issue 4: KMS Decryption Failures

**Symptom:**
```
An error occurred (AccessDenied) when calling the GetObject operation: User is not authorized to perform: kms:Decrypt
```

**Solution:**
Verify KMS key policy includes Harbor role:
```bash
aws kms get-key-policy \
  --key-id ${KMS_KEY_ID} \
  --policy-name default \
  --query Policy \
  --output text | jq .
```

### Issue 5: Bucket Policy Conflicts

**Symptom:**
```
An error occurred (MalformedPolicy) when calling the PutBucketPolicy operation
```

**Solution:**
Validate policy JSON:
```bash
cat s3-bucket-policy.json | jq .
```

## Verification Checklist

Before proceeding to Harbor deployment, verify:

- [ ] KMS customer managed key created
- [ ] KMS key policy allows Harbor role
- [ ] KMS automatic rotation enabled
- [ ] S3 bucket created with unique name
- [ ] Public access blocked on bucket
- [ ] Default encryption configured with KMS
- [ ] Bucket policy enforces encryption and TLS
- [ ] Bucket versioning enabled
- [ ] Lifecycle policies configured
- [ ] Test object can be uploaded and encrypted
- [ ] Bucket tags applied

## Cost Considerations

### KMS Costs

- **Key storage**: $1/month per CMK
- **API requests**: $0.03 per 10,000 requests
- **With Bucket Key**: ~99% reduction in KMS requests

**Estimated monthly cost**: ~$1-2 for typical Harbor usage

### S3 Costs

- **Storage**: $0.023/GB for STANDARD
- **Requests**: $0.005 per 1,000 PUT requests
- **Data transfer**: $0.09/GB out to internet

**Estimated monthly cost**: $5-20 depending on image storage

### Cost Optimization Tips

1. **Enable Bucket Key**: Reduces KMS costs by 99%
2. **Use lifecycle policies**: Transition old versions to cheaper storage
3. **Delete old versions**: Remove unnecessary data
4. **Monitor usage**: Use AWS Cost Explorer

## Next Steps

Now that your S3 bucket and KMS key are configured, you can proceed to:

1. **[Deploy Harbor with IRSA](./harbor-irsa-deployment.md)** - Deploy Harbor using this storage backend
2. **[Validate Configuration](../validation-tests/02-irsa-validation.sh)** - Test S3 and KMS access
3. **[Review Security Best Practices](./security-best-practices.md)** - Additional hardening

## Summary

You've successfully configured secure S3 backend storage for Harbor! Here's what you accomplished:

✅ Created KMS customer managed key with automatic rotation  
✅ Configured KMS key policy with least-privilege access  
✅ Created S3 bucket with globally unique name  
✅ Blocked all public access to bucket  
✅ Enabled default encryption with KMS CMK  
✅ Applied bucket policy enforcing encryption and TLS  
✅ Enabled bucket versioning for data protection  
✅ Configured lifecycle policies for cost optimization  
✅ Verified all security configurations  

Your S3 bucket now provides:
- **Encryption at rest** with customer-managed KMS key
- **Encryption in transit** enforced by bucket policy
- **Defense in depth** with multiple security layers
- **Data protection** through versioning
- **Cost optimization** through lifecycle policies
- **Audit trail** through CloudTrail integration

---

**Next**: [Harbor Deployment with IRSA](./harbor-irsa-deployment.md)
