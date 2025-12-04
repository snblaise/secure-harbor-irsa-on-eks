# KMS Key Policy Hardening Guide

## Overview

This guide provides comprehensive best practices for hardening AWS KMS Customer Managed Keys (CMKs) used with Harbor's S3 backend storage. We'll cover least-privilege key policies, advanced condition keys for defense-in-depth, automatic key rotation, and monitoring strategies to ensure your encryption keys are properly secured.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Understanding KMS Key Policies](#understanding-kms-key-policies)
3. [Least-Privilege Key Policy Design](#least-privilege-key-policy-design)
4. [Advanced Condition Keys](#advanced-condition-keys)
5. [Key Rotation Configuration](#key-rotation-configuration)
6. [Monitoring and Auditing](#monitoring-and-auditing)
7. [Key Policy Validation](#key-policy-validation)
8. [Common Misconfigurations](#common-misconfigurations)
9. [Troubleshooting](#troubleshooting)
10. [Security Checklist](#security-checklist)

## Prerequisites

Before implementing these hardening measures, ensure you have:

- **Existing KMS CMK** created for Harbor S3 encryption
- **AWS CLI** v2.x installed and configured
- **IAM permissions** to modify KMS key policies
- **Harbor IAM role ARN** from IRSA configuration
- **Understanding** of your organization's compliance requirements

### Required IAM Permissions

Your AWS user/role needs these permissions to manage KMS key policies:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:GetKeyPolicy",
        "kms:PutKeyPolicy",
        "kms:DescribeKey",
        "kms:GetKeyRotationStatus",
        "kms:EnableKeyRotation",
        "kms:ListResourceTags",
        "kms:TagResource"
      ],
      "Resource": "arn:aws:kms:*:*:key/*"
    }
  ]
}
```


### Environment Variables

Set these variables for the examples in this guide:

```bash
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export KMS_KEY_ID="your-kms-key-id"  # From s3-kms-setup.md
export HARBOR_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/HarborS3Role"
export S3_BUCKET_NAME="harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION}"

echo "AWS Region: ${AWS_REGION}"
echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "KMS Key ID: ${KMS_KEY_ID}"
echo "Harbor Role ARN: ${HARBOR_ROLE_ARN}"
```

## Understanding KMS Key Policies

### Key Policy vs IAM Policy

KMS uses a unique permission model that combines key policies and IAM policies:

**Key Policy (Resource-based policy)**
- Attached directly to the KMS key
- **Required** - every key must have a key policy
- Can grant permissions to principals in other AWS accounts
- Evaluated first in permission decisions

**IAM Policy (Identity-based policy)**
- Attached to IAM users, groups, or roles
- **Optional** - only works if key policy allows it
- Cannot grant cross-account access
- Evaluated second in permission decisions

**Critical Concept**: Unlike other AWS services, KMS key policies are **not optional**. If a key policy doesn't explicitly allow an action, it's denied—even if an IAM policy allows it.

### Key Policy Structure

A KMS key policy consists of:

```json
{
  "Version": "2012-10-17",
  "Id": "key-policy-identifier",
  "Statement": [
    {
      "Sid": "Statement identifier",
      "Effect": "Allow" | "Deny",
      "Principal": { "AWS": "arn:..." | "Service": "..." },
      "Action": ["kms:*"],
      "Resource": "*",
      "Condition": { ... }
    }
  ]
}
```

**Key Components:**
- **Sid**: Statement identifier (optional but recommended)
- **Effect**: Allow or Deny
- **Principal**: Who can perform the action
- **Action**: Which KMS operations are allowed
- **Resource**: Always "*" for key policies (refers to the key itself)
- **Condition**: Optional constraints on when the policy applies


## Least-Privilege Key Policy Design

### Principle of Least Privilege

The least-privilege principle states that principals should have only the minimum permissions necessary to perform their intended functions. For KMS keys, this means:

1. **Separate administrative and usage permissions**
2. **Grant only required KMS actions** (not `kms:*`)
3. **Restrict principals** to specific roles/services
4. **Use conditions** to further limit access
5. **Avoid wildcard principals** (`"Principal": "*"`)

### Hardened Key Policy Template

Here's a production-ready, least-privilege key policy for Harbor:

```json
{
  "Version": "2012-10-17",
  "Id": "harbor-s3-kms-hardened-policy",
  "Statement": [
    {
      "Sid": "Enable IAM Policies",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT_ID:root"
      },
      "Action": "kms:*",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:CallerAccount": "ACCOUNT_ID"
        }
      }
    },
    {
      "Sid": "Allow Key Administrators",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::ACCOUNT_ID:role/KMSAdminRole",
          "arn:aws:iam::ACCOUNT_ID:user/security-admin"
        ]
      },
      "Action": [
        "kms:Create*",
        "kms:Describe*",
        "kms:Enable*",
        "kms:List*",
        "kms:Put*",
        "kms:Update*",
        "kms:Revoke*",
        "kms:Disable*",
        "kms:Get*",
        "kms:Delete*",
        "kms:TagResource",
        "kms:UntagResource",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Allow Harbor Role Encryption Operations",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT_ID:role/HarborS3Role"
      },
      "Action": [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "s3.REGION.amazonaws.com",
          "kms:EncryptionContext:aws:s3:arn": "arn:aws:s3:::BUCKET_NAME/*"
        }
      }
    },
    {
      "Sid": "Allow S3 Service to Use Key",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "s3.REGION.amazonaws.com"
        },
        "ArnLike": {
          "kms:EncryptionContext:aws:s3:arn": "arn:aws:s3:::BUCKET_NAME/*"
        }
      }
    },
    {
      "Sid": "Deny Key Usage Outside S3",
      "Effect": "Deny",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT_ID:role/HarborS3Role"
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "kms:ViaService": "s3.REGION.amazonaws.com"
        }
      }
    },
    {
      "Sid": "Deny Unencrypted S3 Operations",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "kms:Decrypt",
      "Resource": "*",
      "Condition": {
        "Null": {
          "kms:EncryptionContext:aws:s3:arn": "true"
        }
      }
    }
  ]
}
```


### Understanding Each Statement

#### Statement 1: Enable IAM Policies

```json
{
  "Sid": "Enable IAM Policies",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::ACCOUNT_ID:root"
  },
  "Action": "kms:*",
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "kms:CallerAccount": "ACCOUNT_ID"
    }
  }
}
```

**Purpose**: Allows IAM policies to grant permissions to the key.

**Why it's needed**: Without this statement, IAM policies cannot grant KMS permissions—only the key policy can.

**Security consideration**: The `root` principal doesn't grant access to all users. It enables IAM policy evaluation. The condition restricts this to the same account.

**Hardening**: Added `kms:CallerAccount` condition to prevent cross-account access via IAM policies.

#### Statement 2: Key Administrators

```json
{
  "Sid": "Allow Key Administrators",
  "Effect": "Allow",
  "Principal": {
    "AWS": [
      "arn:aws:iam::ACCOUNT_ID:role/KMSAdminRole",
      "arn:aws:iam::ACCOUNT_ID:user/security-admin"
    ]
  },
  "Action": [
    "kms:Create*",
    "kms:Describe*",
    "kms:Enable*",
    "kms:List*",
    "kms:Put*",
    "kms:Update*",
    "kms:Revoke*",
    "kms:Disable*",
    "kms:Get*",
    "kms:Delete*",
    "kms:TagResource",
    "kms:UntagResource",
    "kms:ScheduleKeyDeletion",
    "kms:CancelKeyDeletion"
  ],
  "Resource": "*"
}
```

**Purpose**: Grants administrative permissions to manage the key.

**Key actions**:
- **Create/Update**: Modify key properties and policies
- **Enable/Disable**: Control key state
- **Delete**: Schedule key deletion (requires 7-30 day waiting period)
- **Tag**: Manage key metadata

**Security consideration**: Administrators can manage the key but **cannot** use it for encryption/decryption (unless explicitly granted).

**Best practice**: Use a dedicated admin role, not individual users.

#### Statement 3: Harbor Role Encryption Operations

```json
{
  "Sid": "Allow Harbor Role Encryption Operations",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::ACCOUNT_ID:role/HarborS3Role"
  },
  "Action": [
    "kms:Decrypt",
    "kms:DescribeKey",
    "kms:GenerateDataKey"
  ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "kms:ViaService": "s3.REGION.amazonaws.com",
      "kms:EncryptionContext:aws:s3:arn": "arn:aws:s3:::BUCKET_NAME/*"
    }
  }
}
```

**Purpose**: Allows Harbor to encrypt/decrypt S3 objects.

**Key actions**:
- **GenerateDataKey**: Create data keys for encrypting new objects
- **Decrypt**: Decrypt data keys to read existing objects
- **DescribeKey**: Get key metadata (required by AWS SDKs)

**Conditions**:
- **kms:ViaService**: Key can only be used through S3 service (not direct KMS API calls)
- **kms:EncryptionContext:aws:s3:arn**: Key can only encrypt/decrypt objects in the specific bucket

**Security benefit**: Even if Harbor role credentials are compromised, they cannot:
- Use the key directly via KMS API
- Encrypt/decrypt data in other S3 buckets
- Use the key for other AWS services


#### Statement 4: S3 Service Principal

```json
{
  "Sid": "Allow S3 Service to Use Key",
  "Effect": "Allow",
  "Principal": {
    "Service": "s3.amazonaws.com"
  },
  "Action": [
    "kms:Decrypt",
    "kms:GenerateDataKey"
  ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "kms:ViaService": "s3.REGION.amazonaws.com"
    },
    "ArnLike": {
      "kms:EncryptionContext:aws:s3:arn": "arn:aws:s3:::BUCKET_NAME/*"
    }
  }
}
```

**Purpose**: Allows S3 service to use the key for server-side encryption.

**Why it's needed**: S3 needs permission to call KMS on behalf of the Harbor role.

**Conditions**:
- **kms:ViaService**: Ensures requests come through S3 service
- **kms:EncryptionContext:aws:s3:arn**: Restricts to specific bucket

**Security benefit**: S3 can only use the key for the Harbor bucket, not other buckets.

#### Statement 5: Deny Direct KMS Usage (Defense in Depth)

```json
{
  "Sid": "Deny Key Usage Outside S3",
  "Effect": "Deny",
  "Principal": {
    "AWS": "arn:aws:iam::ACCOUNT_ID:role/HarborS3Role"
  },
  "Action": [
    "kms:Decrypt",
    "kms:GenerateDataKey"
  ],
  "Resource": "*",
  "Condition": {
    "StringNotEquals": {
      "kms:ViaService": "s3.REGION.amazonaws.com"
    }
  }
}
```

**Purpose**: Explicitly denies Harbor role from using the key outside of S3.

**Why it's important**: Explicit denies override any allows, providing defense in depth.

**Security benefit**: Even if someone adds an overly permissive IAM policy to the Harbor role, this deny prevents direct KMS API access.

**Example attack prevented**: Attacker cannot run `aws kms decrypt --ciphertext-blob ...` using Harbor role credentials.

#### Statement 6: Deny Operations Without Encryption Context

```json
{
  "Sid": "Deny Unencrypted S3 Operations",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "kms:Decrypt",
  "Resource": "*",
  "Condition": {
    "Null": {
      "kms:EncryptionContext:aws:s3:arn": "true"
    }
  }
}
```

**Purpose**: Requires encryption context for all decrypt operations.

**Why it's important**: Encryption context provides additional authenticated data (AAD) that must match for decryption to succeed.

**Security benefit**: Prevents decryption of data without proper S3 context, adding another layer of protection.

### Creating the Hardened Policy

Save the hardened policy to a file:

```bash
cat > kms-hardened-policy.json << EOF
{
  "Version": "2012-10-17",
  "Id": "harbor-s3-kms-hardened-policy",
  "Statement": [
    {
      "Sid": "Enable IAM Policies",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
      },
      "Action": "kms:*",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:CallerAccount": "${AWS_ACCOUNT_ID}"
        }
      }
    },
    {
      "Sid": "Allow Key Administrators",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/KMSAdminRole"
      },
      "Action": [
        "kms:Create*",
        "kms:Describe*",
        "kms:Enable*",
        "kms:List*",
        "kms:Put*",
        "kms:Update*",
        "kms:Revoke*",
        "kms:Disable*",
        "kms:Get*",
        "kms:Delete*",
        "kms:TagResource",
        "kms:UntagResource",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Allow Harbor Role Encryption Operations",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${HARBOR_ROLE_ARN}"
      },
      "Action": [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "s3.${AWS_REGION}.amazonaws.com",
          "kms:EncryptionContext:aws:s3:arn": "arn:aws:s3:::${S3_BUCKET_NAME}/*"
        }
      }
    },
    {
      "Sid": "Allow S3 Service to Use Key",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "s3.${AWS_REGION}.amazonaws.com"
        },
        "ArnLike": {
          "kms:EncryptionContext:aws:s3:arn": "arn:aws:s3:::${S3_BUCKET_NAME}/*"
        }
      }
    },
    {
      "Sid": "Deny Key Usage Outside S3",
      "Effect": "Deny",
      "Principal": {
        "AWS": "${HARBOR_ROLE_ARN}"
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "kms:ViaService": "s3.${AWS_REGION}.amazonaws.com"
        }
      }
    },
    {
      "Sid": "Deny Unencrypted S3 Operations",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "kms:Decrypt",
      "Resource": "*",
      "Condition": {
        "Null": {
          "kms:EncryptionContext:aws:s3:arn": "true"
        }
      }
    }
  ]
}
EOF

echo "✅ Hardened KMS policy created"
```

Apply the hardened policy:

```bash
# Apply the hardened policy to your KMS key
aws kms put-key-policy \
  --key-id ${KMS_KEY_ID} \
  --policy-name default \
  --policy file://kms-hardened-policy.json

echo "✅ Hardened KMS policy applied"
```


## Advanced Condition Keys

KMS supports numerous condition keys that provide fine-grained access control. Here are the most important ones for hardening:

### 1. kms:ViaService

**Purpose**: Restricts key usage to specific AWS services.

**Syntax**:
```json
"Condition": {
  "StringEquals": {
    "kms:ViaService": "s3.us-east-1.amazonaws.com"
  }
}
```

**Use case**: Ensure Harbor can only use the key through S3, not directly via KMS API.

**Security benefit**: Prevents credential theft from being used to decrypt arbitrary data.

### 2. kms:EncryptionContext

**Purpose**: Requires specific encryption context for operations.

**Syntax**:
```json
"Condition": {
  "StringEquals": {
    "kms:EncryptionContext:aws:s3:arn": "arn:aws:s3:::bucket-name/*"
  }
}
```

**Use case**: Bind encryption operations to specific S3 objects.

**Security benefit**: Data encrypted for one bucket cannot be decrypted using keys from another bucket.

**How it works**: Encryption context is additional authenticated data (AAD) that must match for decryption to succeed.

### 3. kms:CallerAccount

**Purpose**: Restricts operations to specific AWS accounts.

**Syntax**:
```json
"Condition": {
  "StringEquals": {
    "kms:CallerAccount": "123456789012"
  }
}
```

**Use case**: Prevent cross-account access even when using root principal.

**Security benefit**: Adds defense against confused deputy attacks.

### 4. kms:EncryptionContextKeys

**Purpose**: Requires specific encryption context keys to be present.

**Syntax**:
```json
"Condition": {
  "ForAllValues:StringEquals": {
    "kms:EncryptionContextKeys": ["aws:s3:arn"]
  }
}
```

**Use case**: Ensure all operations include required context.

**Security benefit**: Prevents operations without proper context.

### 5. aws:PrincipalOrgID

**Purpose**: Restricts access to principals within a specific AWS Organization.

**Syntax**:
```json
"Condition": {
  "StringEquals": {
    "aws:PrincipalOrgID": "o-xxxxxxxxxx"
  }
}
```

**Use case**: Allow access only from accounts in your organization.

**Security benefit**: Prevents access from external accounts even if they know the key ARN.

### 6. aws:SourceIp

**Purpose**: Restricts operations to specific IP addresses or ranges.

**Syntax**:
```json
"Condition": {
  "IpAddress": {
    "aws:SourceIp": ["10.0.0.0/8", "172.16.0.0/12"]
  }
}
```

**Use case**: Limit key usage to specific networks (e.g., VPC CIDR ranges).

**Security benefit**: Prevents key usage from outside your network.

**Caution**: May break S3 access if Harbor pods use NAT gateways with dynamic IPs.

### 7. aws:SourceVpce

**Purpose**: Restricts operations to specific VPC endpoints.

**Syntax**:
```json
"Condition": {
  "StringEquals": {
    "aws:SourceVpce": "vpce-1234567890abcdef0"
  }
}
```

**Use case**: Ensure key is only used through specific VPC endpoints.

**Security benefit**: Prevents key usage from outside your VPC.

### 8. kms:GrantIsForAWSResource

**Purpose**: Restricts grant creation to AWS services.

**Syntax**:
```json
"Condition": {
  "Bool": {
    "kms:GrantIsForAWSResource": "true"
  }
}
```

**Use case**: Allow grants only when created by AWS services (like S3).

**Security benefit**: Prevents principals from creating grants for themselves.


### Advanced Hardened Policy with Multiple Conditions

Here's an example combining multiple condition keys for maximum security:

```json
{
  "Sid": "Allow Harbor Role with Advanced Conditions",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::ACCOUNT_ID:role/HarborS3Role"
  },
  "Action": [
    "kms:Decrypt",
    "kms:DescribeKey",
    "kms:GenerateDataKey"
  ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "kms:ViaService": "s3.REGION.amazonaws.com",
      "kms:EncryptionContext:aws:s3:arn": "arn:aws:s3:::BUCKET_NAME/*",
      "kms:CallerAccount": "ACCOUNT_ID",
      "aws:PrincipalOrgID": "o-xxxxxxxxxx"
    },
    "ForAllValues:StringEquals": {
      "kms:EncryptionContextKeys": ["aws:s3:arn"]
    },
    "IpAddress": {
      "aws:SourceIp": ["10.0.0.0/8"]
    }
  }
}
```

**This policy ensures**:
- ✅ Key used only through S3 service
- ✅ Key used only for specific bucket
- ✅ Caller is from the correct account
- ✅ Caller is from the correct organization
- ✅ Encryption context is always provided
- ✅ Requests come from VPC CIDR range

## Key Rotation Configuration

### Understanding Key Rotation

AWS KMS supports two types of key rotation:

1. **Automatic Key Rotation** (Recommended)
   - AWS rotates the key material annually
   - Old key material retained for decryption
   - No application changes required
   - Free (no additional cost)

2. **Manual Key Rotation**
   - You create a new CMK
   - Update applications to use new key
   - Manage key aliases
   - More operational overhead

### Enable Automatic Key Rotation

```bash
# Enable automatic annual key rotation
aws kms enable-key-rotation --key-id ${KMS_KEY_ID}

# Verify rotation is enabled
aws kms get-key-rotation-status --key-id ${KMS_KEY_ID}
```

**Expected output**:
```json
{
    "KeyRotationEnabled": true
}
```

### How Automatic Rotation Works

1. **Year 1**: Key created with key material version 1
2. **Year 2**: AWS creates key material version 2
   - New encryptions use version 2
   - Old data encrypted with version 1 can still be decrypted
3. **Year 3**: AWS creates key material version 3
   - New encryptions use version 3
   - Old data (versions 1 and 2) can still be decrypted
4. **And so on...**

**Key points**:
- Key ARN and key ID never change
- All old key material is retained
- Decryption works for all versions
- No application changes needed
- Rotation happens automatically

### Rotation Best Practices

**DO**:
- ✅ Enable automatic rotation for all CMKs
- ✅ Monitor rotation status in CloudWatch
- ✅ Document rotation schedule
- ✅ Test decryption of old data after rotation
- ✅ Use CloudTrail to audit rotation events

**DON'T**:
- ❌ Disable rotation without documented reason
- ❌ Manually rotate unless absolutely necessary
- ❌ Delete old key material (AWS manages this)
- ❌ Assume rotation breaks old data (it doesn't)

### Monitoring Key Rotation

Create a CloudWatch alarm for rotation status:

```bash
# Create SNS topic for alerts
export SNS_TOPIC_ARN=$(aws sns create-topic \
  --name kms-rotation-alerts \
  --query 'TopicArn' \
  --output text)

# Subscribe your email
aws sns subscribe \
  --topic-arn ${SNS_TOPIC_ARN} \
  --protocol email \
  --notification-endpoint your-email@example.com

# Create CloudWatch alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "KMS-Key-Rotation-Disabled-${KMS_KEY_ID}" \
  --alarm-description "Alert when KMS key rotation is disabled" \
  --metric-name KeyRotationEnabled \
  --namespace AWS/KMS \
  --statistic Average \
  --period 86400 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=KeyId,Value=${KMS_KEY_ID} \
  --alarm-actions ${SNS_TOPIC_ARN}

echo "✅ CloudWatch alarm created for key rotation monitoring"
```

### Manual Rotation (Advanced)

If you need to manually rotate a key (e.g., for compliance or after suspected compromise):

```bash
# 1. Create new CMK
export NEW_KEY_ID=$(aws kms create-key \
  --description "Harbor S3 encryption key (rotated)" \
  --key-usage ENCRYPT_DECRYPT \
  --origin AWS_KMS \
  --policy file://kms-hardened-policy.json \
  --query 'KeyMetadata.KeyId' \
  --output text)

# 2. Update key alias to point to new key
aws kms update-alias \
  --alias-name alias/harbor-s3-encryption \
  --target-key-id ${NEW_KEY_ID}

# 3. Update S3 bucket default encryption
aws s3api put-bucket-encryption \
  --bucket ${S3_BUCKET_NAME} \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "'${NEW_KEY_ID}'"
      },
      "BucketKeyEnabled": true
    }]
  }'

# 4. Keep old key enabled for decrypting existing objects
# DO NOT delete or disable the old key

echo "✅ Manual key rotation complete"
echo "Old key ID: ${KMS_KEY_ID}"
echo "New key ID: ${NEW_KEY_ID}"
```

**Important**: After manual rotation:
- Keep the old key enabled
- Old objects are still encrypted with old key
- New objects use new key
- Both keys needed for full access


## Monitoring and Auditing

### CloudTrail Logging

All KMS API calls are logged to CloudTrail. Enable CloudTrail logging for comprehensive audit trails:

```bash
# Verify CloudTrail is enabled
aws cloudtrail describe-trails --region ${AWS_REGION}

# Create a trail if needed
aws cloudtrail create-trail \
  --name harbor-kms-audit-trail \
  --s3-bucket-name my-cloudtrail-bucket \
  --is-multi-region-trail \
  --enable-log-file-validation

# Start logging
aws cloudtrail start-logging --name harbor-kms-audit-trail

echo "✅ CloudTrail logging enabled"
```

### Key CloudTrail Events to Monitor

**Encryption Operations**:
- `GenerateDataKey`: New object encrypted
- `Decrypt`: Existing object decrypted
- `DescribeKey`: Key metadata accessed

**Administrative Operations**:
- `PutKeyPolicy`: Key policy modified
- `DisableKey`: Key disabled
- `ScheduleKeyDeletion`: Key deletion scheduled
- `EnableKeyRotation`: Rotation enabled/disabled

**Suspicious Activities**:
- `Decrypt` failures (access denied)
- `GenerateDataKey` from unexpected principals
- Policy changes outside maintenance windows
- Key usage from unexpected IP addresses

### Query CloudTrail Logs

Find all KMS operations for your key:

```bash
# Query last 7 days of KMS events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=${KMS_KEY_ID} \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --max-results 50 \
  --query 'Events[*].[EventTime,EventName,Username]' \
  --output table
```

Find failed decrypt attempts:

```bash
# Find access denied events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=${KMS_KEY_ID} \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --query 'Events[?contains(CloudTrailEvent, `AccessDenied`)]' \
  --output json | jq -r '.[] | .CloudTrailEvent' | jq .
```

### CloudWatch Metrics

KMS publishes metrics to CloudWatch:

**Available Metrics**:
- `NumberOfDecryptCalls`: Decrypt API calls
- `NumberOfEncryptCalls`: Encrypt API calls
- `NumberOfGenerateDataKeyCalls`: GenerateDataKey calls

Create a dashboard:

```bash
# Create CloudWatch dashboard
aws cloudwatch put-dashboard \
  --dashboard-name HarborKMSMetrics \
  --dashboard-body '{
    "widgets": [
      {
        "type": "metric",
        "properties": {
          "metrics": [
            ["AWS/KMS", "NumberOfDecryptCalls", {"stat": "Sum"}],
            [".", "NumberOfGenerateDataKeyCalls", {"stat": "Sum"}]
          ],
          "period": 300,
          "stat": "Sum",
          "region": "'${AWS_REGION}'",
          "title": "KMS API Calls"
        }
      }
    ]
  }'

echo "✅ CloudWatch dashboard created"
```

### Set Up Alerts

Create alerts for suspicious activity:

```bash
# Alert on high number of decrypt failures
aws cloudwatch put-metric-alarm \
  --alarm-name "KMS-High-Decrypt-Failures" \
  --alarm-description "Alert on high number of KMS decrypt failures" \
  --metric-name UserErrorCount \
  --namespace AWS/KMS \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=KeyId,Value=${KMS_KEY_ID} \
  --alarm-actions ${SNS_TOPIC_ARN}

echo "✅ CloudWatch alarm created for decrypt failures"
```

### AWS Config Rules

Use AWS Config to monitor KMS key compliance:

```bash
# Enable AWS Config (if not already enabled)
aws configservice put-configuration-recorder \
  --configuration-recorder name=default,roleARN=arn:aws:iam::${AWS_ACCOUNT_ID}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig \
  --recording-group allSupported=true,includeGlobalResourceTypes=true

# Start recording
aws configservice start-configuration-recorder --configuration-recorder-name default

# Add KMS key rotation rule
aws configservice put-config-rule \
  --config-rule '{
    "ConfigRuleName": "kms-cmk-rotation-enabled",
    "Description": "Checks that key rotation is enabled for customer managed keys",
    "Source": {
      "Owner": "AWS",
      "SourceIdentifier": "CMK_BACKING_KEY_ROTATION_ENABLED"
    },
    "Scope": {
      "ComplianceResourceTypes": ["AWS::KMS::Key"]
    }
  }'

echo "✅ AWS Config rule created for key rotation"
```


## Key Policy Validation

### Validate Policy Syntax

Before applying a key policy, validate the JSON syntax:

```bash
# Validate JSON syntax
cat kms-hardened-policy.json | jq . > /dev/null && echo "✅ Valid JSON" || echo "❌ Invalid JSON"

# Check for common issues
cat kms-hardened-policy.json | jq '
  if .Version != "2012-10-17" then
    "⚠️  Warning: Policy version should be 2012-10-17"
  elif (.Statement | length) == 0 then
    "❌ Error: Policy has no statements"
  elif (.Statement[] | select(.Effect == "Allow" and .Principal == "*" and (.Condition | not))) then
    "⚠️  Warning: Overly permissive statement found"
  else
    "✅ Policy structure looks good"
  end
'
```

### Test Policy Before Applying

Use IAM Policy Simulator to test the policy:

```bash
# Simulate decrypt operation
aws iam simulate-principal-policy \
  --policy-source-arn ${HARBOR_ROLE_ARN} \
  --action-names kms:Decrypt \
  --resource-arns arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/${KMS_KEY_ID} \
  --context-entries "ContextKeyName=kms:ViaService,ContextKeyValues=s3.${AWS_REGION}.amazonaws.com,ContextKeyType=string"

# Expected output: "allowed"
```

### Verify Policy After Applying

After applying the policy, verify it's correct:

```bash
# Get current key policy
aws kms get-key-policy \
  --key-id ${KMS_KEY_ID} \
  --policy-name default \
  --query Policy \
  --output text | jq . > current-policy.json

# Compare with intended policy
diff kms-hardened-policy.json current-policy.json

# If no output, policies match
echo "✅ Policy applied correctly"
```

### Test Key Access

Test that Harbor role can use the key through S3:

```bash
# Assume Harbor role (if testing from admin account)
# Skip this if you're already using Harbor role credentials

# Test encryption by uploading a file
echo "Test content" > test-encryption.txt

aws s3 cp test-encryption.txt s3://${S3_BUCKET_NAME}/test-encryption.txt \
  --sse aws:kms \
  --sse-kms-key-id ${KMS_KEY_ID}

# Verify object is encrypted
aws s3api head-object \
  --bucket ${S3_BUCKET_NAME} \
  --key test-encryption.txt \
  --query '[ServerSideEncryption,SSEKMSKeyId]' \
  --output table

# Test decryption by downloading
aws s3 cp s3://${S3_BUCKET_NAME}/test-encryption.txt test-decrypted.txt

# Verify content matches
diff test-encryption.txt test-decrypted.txt && echo "✅ Encryption/decryption working"

# Clean up
rm test-encryption.txt test-decrypted.txt
aws s3 rm s3://${S3_BUCKET_NAME}/test-encryption.txt
```

### Test Access Denial

Verify that direct KMS API calls are denied:

```bash
# Try to decrypt directly (should fail)
# First, get an encrypted data key
ENCRYPTED_DATA_KEY=$(aws kms generate-data-key \
  --key-id ${KMS_KEY_ID} \
  --key-spec AES_256 \
  --query 'CiphertextBlob' \
  --output text)

# Try to decrypt it directly (should be denied by policy)
aws kms decrypt \
  --ciphertext-blob fileb://<(echo ${ENCRYPTED_DATA_KEY} | base64 -d) \
  --key-id ${KMS_KEY_ID} 2>&1 | grep -q "AccessDeniedException" && \
  echo "✅ Direct KMS access correctly denied" || \
  echo "❌ Warning: Direct KMS access not denied"
```

## Common Misconfigurations

### 1. Overly Permissive Root Principal

**Misconfiguration**:
```json
{
  "Sid": "Enable IAM Policies",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::123456789012:root"
  },
  "Action": "kms:*",
  "Resource": "*"
}
```

**Problem**: Without conditions, this allows any IAM principal in the account to use the key.

**Fix**: Add `kms:CallerAccount` condition:
```json
{
  "Sid": "Enable IAM Policies",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::123456789012:root"
  },
  "Action": "kms:*",
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "kms:CallerAccount": "123456789012"
    }
  }
}
```

### 2. Missing ViaService Condition

**Misconfiguration**:
```json
{
  "Sid": "Allow Harbor Role",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::123456789012:role/HarborS3Role"
  },
  "Action": ["kms:Decrypt", "kms:GenerateDataKey"],
  "Resource": "*"
}
```

**Problem**: Harbor role can use the key directly via KMS API, not just through S3.

**Fix**: Add `kms:ViaService` condition:
```json
{
  "Sid": "Allow Harbor Role",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::123456789012:role/HarborS3Role"
  },
  "Action": ["kms:Decrypt", "kms:GenerateDataKey"],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "kms:ViaService": "s3.us-east-1.amazonaws.com"
    }
  }
}
```

### 3. Missing Encryption Context

**Misconfiguration**:
```json
{
  "Sid": "Allow Harbor Role",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::123456789012:role/HarborS3Role"
  },
  "Action": ["kms:Decrypt", "kms:GenerateDataKey"],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "kms:ViaService": "s3.us-east-1.amazonaws.com"
    }
  }
}
```

**Problem**: Key can be used for any S3 bucket, not just the Harbor bucket.

**Fix**: Add encryption context condition:
```json
{
  "Sid": "Allow Harbor Role",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::123456789012:role/HarborS3Role"
  },
  "Action": ["kms:Decrypt", "kms:GenerateDataKey"],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "kms:ViaService": "s3.us-east-1.amazonaws.com",
      "kms:EncryptionContext:aws:s3:arn": "arn:aws:s3:::harbor-bucket/*"
    }
  }
}
```


### 4. Granting kms:* to Service Roles

**Misconfiguration**:
```json
{
  "Sid": "Allow Harbor Role",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::123456789012:role/HarborS3Role"
  },
  "Action": "kms:*",
  "Resource": "*"
}
```

**Problem**: Harbor role can perform administrative operations like deleting the key.

**Fix**: Grant only required actions:
```json
{
  "Sid": "Allow Harbor Role",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::123456789012:role/HarborS3Role"
  },
  "Action": [
    "kms:Decrypt",
    "kms:DescribeKey",
    "kms:GenerateDataKey"
  ],
  "Resource": "*"
}
```

### 5. No Explicit Deny Statements

**Misconfiguration**: Only using Allow statements without Deny statements.

**Problem**: Allows can be overridden by other policies; no defense in depth.

**Fix**: Add explicit Deny statements for critical restrictions:
```json
{
  "Sid": "Deny Key Usage Outside S3",
  "Effect": "Deny",
  "Principal": {
    "AWS": "arn:aws:iam::123456789012:role/HarborS3Role"
  },
  "Action": ["kms:Decrypt", "kms:GenerateDataKey"],
  "Resource": "*",
  "Condition": {
    "StringNotEquals": {
      "kms:ViaService": "s3.us-east-1.amazonaws.com"
    }
  }
}
```

### 6. Rotation Not Enabled

**Misconfiguration**: Creating a key without enabling automatic rotation.

**Problem**: Key material never rotates, increasing risk if compromised.

**Fix**: Always enable rotation:
```bash
aws kms enable-key-rotation --key-id ${KMS_KEY_ID}
```

### 7. No CloudTrail Logging

**Misconfiguration**: Not enabling CloudTrail for KMS events.

**Problem**: No audit trail of key usage.

**Fix**: Enable CloudTrail:
```bash
aws cloudtrail create-trail \
  --name kms-audit-trail \
  --s3-bucket-name my-cloudtrail-bucket \
  --is-multi-region-trail

aws cloudtrail start-logging --name kms-audit-trail
```

## Troubleshooting

### Issue 1: Access Denied When Uploading to S3

**Symptom**:
```
An error occurred (AccessDenied) when calling the PutObject operation: Access Denied
```

**Possible causes**:
1. Harbor role not in key policy
2. Missing `kms:GenerateDataKey` permission
3. Encryption context mismatch
4. ViaService condition too restrictive

**Diagnosis**:
```bash
# Check if Harbor role is in key policy
aws kms get-key-policy \
  --key-id ${KMS_KEY_ID} \
  --policy-name default \
  --query Policy \
  --output text | jq '.Statement[] | select(.Principal.AWS | contains("HarborS3Role"))'

# Check CloudTrail for detailed error
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=${KMS_KEY_ID} \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --query 'Events[?contains(CloudTrailEvent, `errorCode`)]' \
  --output json | jq -r '.[] | .CloudTrailEvent' | jq .
```

**Solution**: Verify key policy includes Harbor role with correct permissions and conditions.

### Issue 2: Access Denied When Downloading from S3

**Symptom**:
```
An error occurred (AccessDenied) when calling the GetObject operation: Access Denied
```

**Possible causes**:
1. Missing `kms:Decrypt` permission
2. Encryption context mismatch
3. Object encrypted with different key

**Diagnosis**:
```bash
# Check which key was used to encrypt the object
aws s3api head-object \
  --bucket ${S3_BUCKET_NAME} \
  --key your-object-key \
  --query 'SSEKMSKeyId' \
  --output text

# Verify Harbor role has decrypt permission
aws kms get-key-policy \
  --key-id ${KMS_KEY_ID} \
  --policy-name default \
  --query Policy \
  --output text | jq '.Statement[] | select(.Action | contains("kms:Decrypt"))'
```

**Solution**: Ensure Harbor role has `kms:Decrypt` permission in key policy.

### Issue 3: Direct KMS API Calls Succeed (Should Fail)

**Symptom**: Harbor role can call KMS API directly, bypassing S3.

**Possible causes**:
1. Missing `kms:ViaService` condition
2. No explicit Deny statement
3. Overly permissive IAM policy

**Diagnosis**:
```bash
# Test direct KMS access
aws kms generate-data-key \
  --key-id ${KMS_KEY_ID} \
  --key-spec AES_256

# If this succeeds, the policy is too permissive
```

**Solution**: Add `kms:ViaService` condition and explicit Deny statement.

### Issue 4: Key Rotation Not Working

**Symptom**: Key rotation status shows disabled or rotation hasn't occurred.

**Diagnosis**:
```bash
# Check rotation status
aws kms get-key-rotation-status --key-id ${KMS_KEY_ID}

# Check key age
aws kms describe-key --key-id ${KMS_KEY_ID} --query 'KeyMetadata.CreationDate'
```

**Solution**:
```bash
# Enable rotation
aws kms enable-key-rotation --key-id ${KMS_KEY_ID}

# Note: First rotation occurs 365 days after key creation
```

### Issue 5: CloudTrail Not Logging KMS Events

**Symptom**: No KMS events appearing in CloudTrail.

**Diagnosis**:
```bash
# Check if CloudTrail is enabled
aws cloudtrail describe-trails --region ${AWS_REGION}

# Check trail status
aws cloudtrail get-trail-status --name your-trail-name
```

**Solution**:
```bash
# Start logging if stopped
aws cloudtrail start-logging --name your-trail-name

# Verify KMS events are being logged
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::KMS::Key \
  --max-results 10
```


## Security Checklist

Use this checklist to verify your KMS key is properly hardened:

### Key Policy Configuration

- [ ] Key policy uses least-privilege principle
- [ ] Separate statements for administrators and users
- [ ] Harbor role has only required actions (Decrypt, GenerateDataKey, DescribeKey)
- [ ] No `kms:*` granted to service roles
- [ ] Root principal includes `kms:CallerAccount` condition
- [ ] `kms:ViaService` condition restricts to S3
- [ ] `kms:EncryptionContext` condition restricts to specific bucket
- [ ] Explicit Deny statement prevents direct KMS API usage
- [ ] No wildcard principals without conditions
- [ ] Policy validated with IAM Policy Simulator

### Key Rotation

- [ ] Automatic key rotation enabled
- [ ] Rotation status monitored via CloudWatch
- [ ] CloudWatch alarm configured for rotation status
- [ ] Rotation documented in runbooks
- [ ] Old key material retained (never deleted)

### Monitoring and Auditing

- [ ] CloudTrail enabled for KMS events
- [ ] CloudTrail logs stored in secure S3 bucket
- [ ] CloudWatch dashboard created for KMS metrics
- [ ] CloudWatch alarms configured for:
  - [ ] High decrypt failures
  - [ ] Rotation disabled
  - [ ] Policy changes
  - [ ] Key deletion scheduled
- [ ] AWS Config rule enabled for key rotation
- [ ] Regular review of CloudTrail logs scheduled

### Access Control

- [ ] Only required principals have access
- [ ] Service accounts use IRSA (not IAM users)
- [ ] No long-lived credentials with key access
- [ ] Cross-account access explicitly denied (if not needed)
- [ ] VPC endpoint conditions added (if applicable)
- [ ] IP address restrictions added (if applicable)

### Compliance and Documentation

- [ ] Key policy documented in runbooks
- [ ] Key purpose and usage documented
- [ ] Rotation schedule documented
- [ ] Incident response procedures documented
- [ ] Compliance requirements verified (SOC2, PCI-DSS, etc.)
- [ ] Key tagged with appropriate metadata

### Testing and Validation

- [ ] Encryption/decryption tested through S3
- [ ] Direct KMS API access denied (verified)
- [ ] Access from unauthorized principals denied (verified)
- [ ] CloudTrail events verified
- [ ] Key rotation tested (after 365 days)
- [ ] Disaster recovery procedures tested

## Best Practices Summary

### DO

✅ **Use Customer Managed Keys (CMKs)** instead of AWS-managed keys for full control

✅ **Enable automatic key rotation** for all CMKs

✅ **Use least-privilege key policies** with only required actions

✅ **Add ViaService conditions** to restrict key usage to specific AWS services

✅ **Use encryption context** to bind keys to specific resources

✅ **Add explicit Deny statements** for defense in depth

✅ **Enable CloudTrail logging** for comprehensive audit trails

✅ **Monitor key usage** with CloudWatch metrics and alarms

✅ **Tag keys appropriately** for cost allocation and compliance

✅ **Document key policies** and rotation procedures

✅ **Test key access** regularly to ensure policies work as intended

✅ **Use AWS Config** to monitor compliance

### DON'T

❌ **Don't grant kms:*** to service roles—use specific actions only

❌ **Don't use wildcard principals** without strict conditions

❌ **Don't disable key rotation** without documented justification

❌ **Don't delete old key material** after rotation (AWS manages this)

❌ **Don't allow direct KMS API access** when service integration is available

❌ **Don't skip encryption context** when available

❌ **Don't ignore CloudTrail events**—monitor for suspicious activity

❌ **Don't use IAM users** for application access—use IRSA instead

❌ **Don't share keys** across unrelated applications

❌ **Don't forget to test** key policies before applying to production

## Compliance Considerations

### SOC 2

**Requirements**:
- Encryption at rest for sensitive data
- Key rotation procedures
- Access control and least privilege
- Audit logging and monitoring

**KMS Implementation**:
- ✅ CMK with automatic rotation
- ✅ Least-privilege key policy
- ✅ CloudTrail logging enabled
- ✅ CloudWatch monitoring configured

### PCI-DSS

**Requirements**:
- Strong cryptography for cardholder data
- Key management procedures
- Access control to encryption keys
- Audit trails for key usage

**KMS Implementation**:
- ✅ AES-256 encryption (FIPS 140-2 Level 2)
- ✅ Automatic key rotation
- ✅ Restrictive key policies
- ✅ CloudTrail audit logs

### HIPAA

**Requirements**:
- Encryption of ePHI at rest
- Key management and rotation
- Access controls and audit logs
- Disaster recovery procedures

**KMS Implementation**:
- ✅ CMK for ePHI encryption
- ✅ Automatic rotation enabled
- ✅ Least-privilege access
- ✅ CloudTrail logging
- ✅ Multi-region key replication (if needed)

### GDPR

**Requirements**:
- Encryption of personal data
- Right to erasure (data deletion)
- Access controls
- Audit trails

**KMS Implementation**:
- ✅ CMK for personal data encryption
- ✅ Key deletion capability (7-30 day waiting period)
- ✅ Restrictive key policies
- ✅ CloudTrail audit logs

## Next Steps

After hardening your KMS key policy, proceed to:

1. **[S3 Bucket Policy Hardening](./s3-bucket-policy-hardening.md)** - Harden S3 bucket policies
2. **[IAM Guardrails](./iam-guardrails.md)** - Implement IAM permission boundaries
3. **[Namespace Isolation](./namespace-isolation-guide.md)** - Configure Kubernetes namespace isolation
4. **[Validation Tests](../validation-tests/)** - Test your security configurations

## Summary

You've successfully hardened your KMS key policy! Here's what you accomplished:

✅ **Implemented least-privilege key policy** with separate admin and user permissions  
✅ **Added advanced condition keys** for defense in depth (ViaService, EncryptionContext)  
✅ **Enabled automatic key rotation** with monitoring and alerting  
✅ **Configured CloudTrail logging** for comprehensive audit trails  
✅ **Set up CloudWatch monitoring** with dashboards and alarms  
✅ **Added explicit Deny statements** to prevent policy override  
✅ **Validated key policy** with testing and simulation  
✅ **Documented compliance** alignment (SOC2, PCI-DSS, HIPAA, GDPR)  

Your KMS key now provides:
- **Least-privilege access** with only required permissions
- **Defense in depth** with multiple security layers
- **Automatic rotation** for key material
- **Comprehensive auditing** via CloudTrail
- **Proactive monitoring** via CloudWatch
- **Compliance alignment** with industry standards

---

**Next**: [S3 Bucket Policy Hardening](./s3-bucket-policy-hardening.md)

