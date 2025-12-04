# Architecture Diagrams: ASCII Art Version

This document provides ASCII art versions of the architecture diagrams for environments where Mermaid diagrams may not render properly.

## Table of Contents

1. [Insecure Architecture (IAM User Tokens)](#insecure-architecture-iam-user-tokens)
2. [Secure Architecture (IRSA)](#secure-architecture-irsa)
3. [Comparison Summary](#comparison-summary)

---

## Insecure Architecture (IAM User Tokens)

### Overview Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS Account                                     │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │                      Amazon EKS Cluster                             │    │
│  │                                                                     │    │
│  │  ┌──────────────────────────────────────────────────────────┐     │    │
│  │  │                  harbor namespace                         │     │    │
│  │  │                                                           │     │    │
│  │  │  ┌─────────────────────────────────────────────────┐    │     │    │
│  │  │  │      Kubernetes Secret (Base64 Encoded)         │    │     │    │
│  │  │  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │    │     │    │
│  │  │  │  apiVersion: v1                                 │    │     │    │
│  │  │  │  kind: Secret                                   │    │     │    │
│  │  │  │  data:                                          │    │     │    │
│  │  │  │    AWS_ACCESS_KEY_ID: QUtJQUlPU0ZPRE5ON...    │    │     │    │
│  │  │  │    AWS_SECRET_ACCESS_KEY: d0phbHJYVXRu...     │    │     │    │
│  │  │  │                                                 │    │     │    │
│  │  │  │  ⚠️  Base64 is NOT encryption!                 │    │     │    │
│  │  │  └──────────────────┬──────────────────────────────┘    │     │    │
│  │  │                     │                                    │     │    │
│  │  │                     │ Mounted as Environment Variables   │     │    │
│  │  │                     ▼                                    │     │    │
│  │  │  ┌─────────────────────────────────────────────────┐    │     │    │
│  │  │  │         Harbor Registry Pod                     │    │     │    │
│  │  │  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │    │     │    │
│  │  │  │  Environment Variables:                         │    │     │    │
│  │  │  │    AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE      │    │     │    │
│  │  │  │    AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/...     │    │     │    │
│  │  │  │                                                 │    │     │    │
│  │  │  │  Harbor Application:                            │    │     │    │
│  │  │  │    - Core                                       │    │     │    │
│  │  │  │    - Registry                                   │    │     │    │
│  │  │  │    - JobService                                 │    │     │    │
│  │  │  └──────────────────┬──────────────────────────────┘    │     │    │
│  │  └─────────────────────┼───────────────────────────────────┘     │    │
│  └────────────────────────┼─────────────────────────────────────────┘    │
│                           │                                               │
│                           │ Static IAM User Credentials                   │
│                           │ (Long-lived, never rotated)                   │
│                           ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                        IAM User                                  │    │
│  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │    │
│  │  Username: harbor-s3-user                                       │    │
│  │  Access Key ID: AKIAIOSFODNN7EXAMPLE                            │    │
│  │  Secret Access Key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY    │    │
│  │                                                                  │    │
│  │  Attached Policies:                                             │    │
│  │    - AmazonS3FullAccess (Overprivileged!)                       │    │
│  │                                                                  │    │
│  │  ⚠️  SECURITY RISKS:                                              │    │
│  │    • Credentials valid indefinitely                               │    │
│  │    • No automatic rotation                                        │    │
│  │    • Overly broad permissions                                     │    │
│  └──────────────────────┬───────────────────────────────────────────┘    │
│                         │                                                 │
│                         │ S3 API Calls (All actions appear as IAM user)  │
│                         ▼                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                      S3 Bucket                                   │    │
│  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │    │
│  │  Bucket Name: harbor-registry-storage                            │    │
│  │  Encryption: None or SSE-S3 (AWS-managed keys)                   │    │
│  │  Versioning: Disabled                                            │    │
│  │  Public Access: Not explicitly blocked                           │    │
│  │                                                                   │    │
│  │  Bucket Policy: Permissive or missing                            │    │
│  │                                                                   │    │
│  │  Contents:                                                        │    │
│  │    /docker/                                                       │    │
│  │      /registry/                                                   │    │
│  │        /v2/                                                       │    │
│  │          /blobs/                                                  │    │
│  │          /manifests/                                              │    │
│  │                                                                   │    │
│  │  ⚠️  SECURITY RISKS:                                             │    │
│  │    • No customer-managed encryption                               │    │
│  │    • Weak or missing bucket policies                              │    │
│  │    • No versioning for data protection                            │    │
│  └───────────────────────────────────────────────────────────────────┘    │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘

### Attack Vector: Credential Extraction

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Attacker with kubectl Access                      │
└──────────────────────────────┬───────────────────────────────────────┘
                               │
                               │ 1. List secrets
                               │ $ kubectl get secrets -n harbor
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  NAME                     TYPE     DATA   AGE                        │
│  harbor-s3-credentials    Opaque   2      5d                         │
└──────────────────────────────┬───────────────────────────────────────┘
                               │
                               │ 2. Extract secret
                               │ $ kubectl get secret harbor-s3-credentials \
                               │   -n harbor -o yaml
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  data:                                                               │
│    AWS_ACCESS_KEY_ID: QUtJQUlPU0ZPRE5ON0VYQU1QTEU=                 │
│    AWS_SECRET_ACCESS_KEY: d0phbHJYVXRuRkVNSS9LN01ERU5HL2...        │
└──────────────────────────────┬───────────────────────────────────────┘
                               │
                               │ 3. Decode base64
                               │ $ echo "QUtJQUlPU0ZPRE5ON0VYQU1QTEU=" | \
                               │   base64 -d
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  AKIAIOSFODNN7EXAMPLE                                               │
│  wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY                           │
│                                                                      │
│  ✅ Credentials extracted in seconds!                               │
│  ✅ Valid indefinitely until manually rotated                       │
│  ✅ Can be used from anywhere (not bound to pod/namespace)          │
└──────────────────────────────┬───────────────────────────────────────┘
                               │
                               │ 4. Use stolen credentials
                               │ $ export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
                               │ $ export AWS_SECRET_ACCESS_KEY=wJalr...
                               │ $ aws s3 ls s3://harbor-registry-storage/
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Unauthorized S3 Access Successful!                                 │
│  - List all objects                                                 │
│  - Download container images                                        │
│  - Delete critical data                                             │
│  - Exfiltrate sensitive information                                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Secure Architecture (IRSA)

### Overview Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              AWS Account                                      │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      Amazon EKS Cluster                              │    │
│  │                                                                      │    │
│  │  ┌────────────────────────────────────────────────────────────┐    │    │
│  │  │                  harbor namespace                           │    │    │
│  │  │                                                             │    │    │
│  │  │  ┌───────────────────────────────────────────────────┐    │    │    │
│  │  │  │    Kubernetes Service Account                     │    │    │    │
│  │  │  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │    │    │    │
│  │  │  │  apiVersion: v1                                   │    │    │    │
│  │  │  │  kind: ServiceAccount                             │    │    │    │
│  │  │  │  metadata:                                        │    │    │    │
│  │  │  │    name: harbor-registry                          │    │    │    │
│  │  │  │    namespace: harbor                              │    │    │    │
│  │  │  │    annotations:                                   │    │    │    │
│  │  │  │      eks.amazonaws.com/role-arn:                  │    │    │    │
│  │  │  │        arn:aws:iam::123456789012:role/HarborS3    │    │    │    │
│  │  │  │                                                   │    │    │    │
│  │  │  │  ✅ No static credentials stored!                │    │    │    │
│  │  │  └──────────────────┬────────────────────────────────┘    │    │    │
│  │  │                     │                                      │    │    │
│  │  │                     │ Bound to Pod                         │    │    │
│  │  │                     ▼                                      │    │    │
│  │  │  ┌───────────────────────────────────────────────────┐    │    │    │
│  │  │  │         Harbor Registry Pod                       │    │    │    │
│  │  │  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │    │    │    │
│  │  │  │  spec:                                            │    │    │    │
│  │  │  │    serviceAccountName: harbor-registry            │    │    │    │
│  │  │  │                                                   │    │    │    │
│  │  │  │  Projected Volume (auto-mounted):                 │    │    │    │
│  │  │  │    /var/run/secrets/eks.amazonaws.com/            │    │    │    │
│  │  │  │      serviceaccount/token                         │    │    │    │
│  │  │  │                                                   │    │    │    │
│  │  │  │  JWT Token Properties:                            │    │    │    │
│  │  │  │    - Audience: sts.amazonaws.com                  │    │    │    │
│  │  │  │    - Expiry: 86400s (24 hours)                    │    │    │    │
│  │  │  │    - Subject: system:serviceaccount:harbor:...    │    │    │    │
│  │  │  │                                                   │    │    │    │
│  │  │  │  AWS SDK Auto-Discovery:                          │    │    │    │
│  │  │  │    ✅ Finds token automatically                   │    │    │    │
│  │  │  │    ✅ Calls AssumeRoleWithWebIdentity             │    │    │    │
│  │  │  │    ✅ Refreshes before expiration                 │    │    │    │
│  │  │  └──────────────────┬────────────────────────────────┘    │    │    │
│  │  └─────────────────────┼─────────────────────────────────────┘    │    │
│  │                        │                                           │    │
│  │  ┌─────────────────────┼─────────────────────────────────────┐    │    │
│  │  │  EKS OIDC Provider  │                                     │    │    │
│  │  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │    │    │
│  │  │  Issues JWT tokens bound to:                           │    │    │
│  │  │    - Namespace: harbor                                 │    │    │
│  │  │    - ServiceAccount: harbor-registry                   │    │    │
│  │  │    - Expiry: 86400s (auto-rotated)                     │    │    │
│  │  │                                                         │    │    │
│  │  │  Token Claims:                                          │    │    │
│  │  │    {                                                    │    │    │
│  │  │      "iss": "https://oidc.eks.us-east-1.amazonaws...", │    │    │
│  │  │      "sub": "system:serviceaccount:harbor:harbor-...", │    │    │
│  │  │      "aud": ["sts.amazonaws.com"],                     │    │    │
│  │  │      "exp": 1234567890                                 │    │    │
│  │  │    }                                                    │    │    │
│  │  └─────────────────────┬─────────────────────────────────────┘    │    │
│  └────────────────────────┼──────────────────────────────────────────┘    │
│                           │                                                │
│                           │ JWT Token (temporary, auto-rotated)            │
│                           ▼                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    IAM OIDC Provider                                 │    │
│  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │    │
│  │  Provider URL:                                                       │    │
│  │    https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E... │    │
│  │                                                                      │    │
│  │  Thumbprint: 9e99a48a9960b14926bb7f3b02e22da2b0ab7280               │    │
│  │                                                                      │    │
│  │  Validates JWT tokens from EKS cluster                              │    │
│  │  Enables AssumeRoleWithWebIdentity                                  │    │
│  └──────────────────────┬───────────────────────────────────────────────┘    │
│                         │                                                    │
│                         │ Token Validation & Role Assumption                 │
│                         ▼                                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    IAM Role: HarborS3Role                            │    │
│  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │    │
│  │  Trust Policy (restricts to specific SA):                           │    │
│  │  {                                                                   │    │
│  │    "Version": "2012-10-17",                                          │    │
│  │    "Statement": [{                                                   │    │
│  │      "Effect": "Allow",                                              │    │
│  │      "Principal": {                                                  │    │
│  │        "Federated": "arn:aws:iam::123456789012:oidc-provider/..."   │    │
│  │      },                                                              │    │
│  │      "Action": "sts:AssumeRoleWithWebIdentity",                     │    │
│  │      "Condition": {                                                  │    │
│  │        "StringEquals": {                                             │    │
│  │          "oidc.eks....:sub":                                         │    │
│  │            "system:serviceaccount:harbor:harbor-registry",           │    │
│  │          "oidc.eks....:aud": "sts.amazonaws.com"                     │    │
│  │        }                                                             │    │
│  │      }                                                               │    │
│  │    }]                                                                │    │
│  │  }                                                                   │    │
│  │                                                                      │    │
│  │  Permissions Policy (least privilege):                              │    │
│  │  {                                                                   │    │
│  │    "Version": "2012-10-17",                                          │    │
│  │    "Statement": [                                                    │    │
│  │      {                                                               │    │
│  │        "Sid": "HarborS3Access",                                      │    │
│  │        "Effect": "Allow",                                            │    │
│  │        "Action": [                                                   │    │
│  │          "s3:PutObject",                                             │    │
│  │          "s3:GetObject",                                             │    │
│  │          "s3:DeleteObject",                                          │    │
│  │          "s3:ListBucket"                                             │    │
│  │        ],                                                            │    │
│  │        "Resource": [                                                 │    │
│  │          "arn:aws:s3:::harbor-registry-storage-123456789012-...",   │    │
│  │          "arn:aws:s3:::harbor-registry-storage-123456789012-.../*"  │    │
│  │        ]                                                             │    │
│  │      },                                                              │    │
│  │      {                                                               │    │
│  │        "Sid": "HarborKMSAccess",                                     │    │
│  │        "Effect": "Allow",                                            │    │
│  │        "Action": [                                                   │    │
│  │          "kms:Decrypt",                                              │    │
│  │          "kms:GenerateDataKey"                                       │    │
│  │        ],                                                            │    │
│  │        "Resource": "arn:aws:kms:us-east-1:123456789012:key/..."     │    │
│  │      }                                                               │    │
│  │    ]                                                                 │    │
│  │  }                                                                   │    │
│  │                                                                      │    │
│  │  ✅ SECURITY BENEFITS:                                              │    │
│  │    • Bound to specific namespace + service account                  │    │
│  │    • Least privilege permissions                                    │    │
│  │    • Temporary credentials (1 hour validity)                        │    │
│  │    • Automatic rotation                                             │    │
│  └──────────────────────┬───────────────────────────────────────────────┘    │
│                         │                                                    │
│                         │ Temporary AWS Credentials                          │
│                         │ (AccessKeyId, SecretAccessKey, SessionToken)       │
│                         ▼                                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    S3 Bucket                                         │    │
│  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │    │
│  │  Bucket Name: harbor-registry-storage-123456789012-us-east-1        │    │
│  │                                                                      │    │
│  │  Encryption: SSE-KMS with Customer Managed Key                      │    │
│  │  Versioning: Enabled                                                │    │
│  │  Public Access: Blocked (all 4 settings)                            │    │
│  │                                                                      │    │
│  │  Bucket Policy:                                                      │    │
│  │  {                                                                   │    │
│  │    "Statement": [                                                    │    │
│  │      {                                                               │    │
│  │        "Sid": "DenyUnencryptedObjectUploads",                       │    │
│  │        "Effect": "Deny",                                             │    │
│  │        "Principal": "*",                                             │    │
│  │        "Action": "s3:PutObject",                                     │    │
│  │        "Resource": "arn:aws:s3:::harbor-registry-storage-.../*",    │    │
│  │        "Condition": {                                                │    │
│  │          "StringNotEquals": {                                        │    │
│  │            "s3:x-amz-server-side-encryption": "aws:kms"             │    │
│  │          }                                                           │    │
│  │        }                                                             │    │
│  │      },                                                              │    │
│  │      {                                                               │    │
│  │        "Sid": "DenyInsecureTransport",                              │    │
│  │        "Effect": "Deny",                                             │    │
│  │        "Principal": "*",                                             │    │
│  │        "Action": "s3:*",                                             │    │
│  │        "Resource": "arn:aws:s3:::harbor-registry-storage-.../*",    │    │
│  │        "Condition": {                                                │    │
│  │          "Bool": { "aws:SecureTransport": "false" }                 │    │
│  │        }                                                             │    │
│  │      }                                                               │    │
│  │    ]                                                                 │    │
│  │  }                                                                   │    │
│  │                                                                      │    │
│  │  ✅ SECURITY BENEFITS:                                              │    │
│  │    • Customer-managed encryption keys                               │    │
│  │    • Enforced encryption for all uploads                            │    │
│  │    • TLS-only access                                                │    │
│  │    • Versioning for data protection                                 │    │
│  └──────────────────────┬───────────────────────────────────────────────┘    │
│                         │                                                    │
│                         │ Encryption/Decryption Operations                   │
│                         ▼                                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    KMS Customer Managed Key                          │    │
│  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │    │
│  │  Key ID: 12345678-1234-1234-1234-123456789012                       │    │
│  │  Alias: alias/harbor-s3-encryption                                  │    │
│  │  Key Rotation: Enabled (automatic annual rotation)                  │    │
│  │                                                                      │    │
│  │  Key Policy:                                                         │    │
│  │  {                                                                   │    │
│  │    "Statement": [                                                    │    │
│  │      {                                                               │    │
│  │        "Sid": "Allow Harbor Role to use the key",                   │    │
│  │        "Effect": "Allow",                                            │    │
│  │        "Principal": {                                                │    │
│  │          "AWS": "arn:aws:iam::123456789012:role/HarborS3Role"       │    │
│  │        },                                                            │    │
│  │        "Action": [                                                   │    │
│  │          "kms:Decrypt",                                              │    │
│  │          "kms:GenerateDataKey"                                       │    │
│  │        ],                                                            │    │
│  │        "Resource": "*",                                              │    │
│  │        "Condition": {                                                │    │
│  │          "StringEquals": {                                           │    │
│  │            "kms:ViaService": "s3.us-east-1.amazonaws.com"           │    │
│  │          }                                                           │    │
│  │        }                                                             │    │
│  │      }                                                               │    │
│  │    ]                                                                 │    │
│  │  }                                                                   │    │
│  │                                                                      │    │
│  │  ✅ SECURITY BENEFITS:                                              │    │
│  │    • Customer control over encryption keys                          │    │
│  │    • Restricted to specific IAM role                                │    │
│  │    • Automatic key rotation                                         │    │
│  │    • Detailed CloudTrail audit logs                                 │    │
│  └──────────────────────────────────────────────────────────────────────┘    │
│                                                                               │
└───────────────────────────────────────────────────────────────────────────────┘
```

### IRSA Authentication Flow

```
┌──────────────┐
│ Administrator│
└──────┬───────┘
       │
       │ 1. Create Service Account with role-arn annotation
       ▼
┌─────────────────────────────────────────────────────────────┐
│ kubectl apply -f service-account.yaml                       │
│                                                              │
│ apiVersion: v1                                               │
│ kind: ServiceAccount                                         │
│ metadata:                                                    │
│   name: harbor-registry                                      │
│   namespace: harbor                                          │
│   annotations:                                               │
│     eks.amazonaws.com/role-arn:                              │
│       arn:aws:iam::123456789012:role/HarborS3Role           │
└──────────────────────────┬───────────────────────────────────┘
                           │
       ┌───────────────────┘
       │ 2. Create IAM OIDC Provider
       ▼
┌─────────────────────────────────────────────────────────────┐
│ aws iam create-open-id-connect-provider \                   │
│   --url https://oidc.eks.us-east-1.amazonaws.com/id/... \   │
│   --client-id-list sts.amazonaws.com \                      │
│   --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab... │
└──────────────────────────┬───────────────────────────────────┘
                           │
       ┌───────────────────┘
       │ 3. Create IAM Role with Trust Policy
       ▼
┌─────────────────────────────────────────────────────────────┐
│ Trust Policy restricts to specific namespace + SA:          │
│                                                              │
│ "Condition": {                                               │
│   "StringEquals": {                                          │
│     "oidc.eks....:sub":                                      │
│       "system:serviceaccount:harbor:harbor-registry"         │
│   }                                                          │
│ }                                                            │
└──────────────────────────┬───────────────────────────────────┘
                           │
       ┌───────────────────┘
       │ 4. Deploy Harbor Pod
       ▼
┌─────────────────────────────────────────────────────────────┐
│ Harbor Pod Starts                                            │
│   spec:                                                      │
│     serviceAccountName: harbor-registry                      │
└──────────────────────────┬───────────────────────────────────┘
                           │
       ┌───────────────────┘
       │ 5. Kubernetes projects JWT token into pod
       ▼
┌─────────────────────────────────────────────────────────────┐
│ /var/run/secrets/eks.amazonaws.com/serviceaccount/token     │
│                                                              │
│ JWT Token Claims:                                            │
│ {                                                            │
│   "iss": "https://oidc.eks.us-east-1.amazonaws.com/id/...", │
│   "sub": "system:serviceaccount:harbor:harbor-registry",    │
│   "aud": ["sts.amazonaws.com"],                             │
│   "exp": 1234567890,                                         │
│   "iat": 1234481490                                          │
│ }                                                            │
└──────────────────────────┬───────────────────────────────────┘
                           │
       ┌───────────────────┘
       │ 6. AWS SDK discovers token
       ▼
┌─────────────────────────────────────────────────────────────┐
│ AWS SDK Credential Chain:                                    │
│   1. Environment variables (not found)                       │
│   2. Shared credentials file (not found)                     │
│   3. Web identity token file (FOUND!)                        │
│      AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/...       │
│      AWS_ROLE_ARN=arn:aws:iam::123456789012:role/HarborS3   │
└──────────────────────────┬───────────────────────────────────┘
                           │
       ┌───────────────────┘
       │ 7. SDK calls AssumeRoleWithWebIdentity
       ▼
┌─────────────────────────────────────────────────────────────┐
│ POST https://sts.amazonaws.com/                              │
│ Action=AssumeRoleWithWebIdentity                             │
│ RoleArn=arn:aws:iam::123456789012:role/HarborS3Role         │
│ WebIdentityToken=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...    │
│ RoleSessionName=harbor-registry-pod-12345                    │
└──────────────────────────┬───────────────────────────────────┘
                           │
       ┌───────────────────┘
       │ 8. IAM validates JWT
       ▼
┌─────────────────────────────────────────────────────────────┐
│ IAM OIDC Provider Validation:                                │
│   ✓ JWT signature valid (using OIDC provider public key)    │
│   ✓ Issuer matches registered OIDC provider                 │
│   ✓ Audience is sts.amazonaws.com                           │
│   ✓ Token not expired                                        │
│   ✓ Subject matches trust policy condition                  │
└──────────────────────────┬───────────────────────────────────┘
                           │
       ┌───────────────────┘
       │ 9. STS issues temporary credentials
       ▼
┌─────────────────────────────────────────────────────────────┐
│ Temporary AWS Credentials (valid for 1 hour):               │
│                                                              │
│ {                                                            │
│   "Credentials": {                                           │
│     "AccessKeyId": "ASIATEMP...",                            │
│     "SecretAccessKey": "wJalr...",                           │
│     "SessionToken": "FwoGZXIvYXdzEBYaD...",                  │
│     "Expiration": "2024-12-03T15:30:00Z"                     │
│   },                                                         │
│   "AssumedRoleUser": {                                       │
│     "AssumedRoleId": "AROAEXAMPLE:harbor-registry-pod-..."  │
│     "Arn": "arn:aws:sts::123456789012:assumed-role/..."     │
│   }                                                          │
│ }                                                            │
└──────────────────────────┬───────────────────────────────────┘
                           │
       ┌───────────────────┘
       │ 10. Harbor makes S3 API call
       ▼
┌─────────────────────────────────────────────────────────────┐
│ PUT /docker/registry/v2/blobs/sha256:abc123... HTTP/1.1     │
│ Host: harbor-registry-storage-123456789012.s3.amazonaws.com │
│ Authorization: AWS4-HMAC-SHA256 Credential=ASIATEMP.../...  │
│ x-amz-security-token: FwoGZXIvYXdzEBYaD...                   │
│ x-amz-server-side-encryption: aws:kms                        │
│ x-amz-server-side-encryption-aws-kms-key-id: 12345678-...   │
└──────────────────────────┬───────────────────────────────────┘
                           │
       ┌───────────────────┘
       │ 11. S3 requests encryption key from KMS
       ▼
┌─────────────────────────────────────────────────────────────┐
│ KMS GenerateDataKey Request:                                 │
│   KeyId: 12345678-1234-1234-1234-123456789012               │
│   EncryptionContext: {                                       │
│     "aws:s3:arn": "arn:aws:s3:::harbor-registry-storage..." │
│   }                                                          │
│                                                              │
│ KMS verifies:                                                │
│   ✓ Caller (HarborS3Role) has kms:GenerateDataKey           │
│   ✓ Request via S3 service (kms:ViaService condition)       │
└──────────────────────────┬───────────────────────────────────┘
                           │
       ┌───────────────────┘
       │ 12. KMS returns data encryption key
       ▼
┌─────────────────────────────────────────────────────────────┐
│ Data Encryption Key:                                         │
│   Plaintext: [32 bytes]                                      │
│   CiphertextBlob: [encrypted DEK]                            │
└──────────────────────────┬───────────────────────────────────┘
                           │
       ┌───────────────────┘
       │ 13. S3 encrypts and stores object
       ▼
┌─────────────────────────────────────────────────────────────┐
│ Object stored in S3:                                         │
│   - Data encrypted with DEK                                  │
│   - DEK encrypted with CMK                                   │
│   - Metadata includes encryption info                        │
│                                                              │
│ CloudTrail logs:                                             │
│   - S3 PutObject event                                       │
│   - Principal: arn:aws:sts::123456789012:assumed-role/...   │
│   - Source: harbor-registry pod                              │
│   - KMS GenerateDataKey event                                │
└──────────────────────────┬───────────────────────────────────┘
                           │
       ┌───────────────────┘
       │ 14. Success response to Harbor
       ▼
┌─────────────────────────────────────────────────────────────┐
│ HTTP/1.1 200 OK                                              │
│ ETag: "abc123..."                                            │
│ x-amz-server-side-encryption: aws:kms                        │
│ x-amz-server-side-encryption-aws-kms-key-id: 12345678-...   │
└──────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ ✅ AUTOMATIC CREDENTIAL ROTATION                            │
│                                                              │
│ Before token expires (24 hours):                            │
│   - Kubernetes automatically refreshes JWT token            │
│   - AWS SDK detects new token                               │
│   - SDK calls AssumeRoleWithWebIdentity again               │
│   - New temporary credentials issued                        │
│   - Harbor continues operating seamlessly                   │
│                                                              │
│ No manual intervention required!                            │
└──────────────────────────────────────────────────────────────┘
```

---

## Comparison Summary

### Security Posture Comparison

```
┌─────────────────────────────────────────────────────────────────────┐
│                    INSECURE vs SECURE                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  CREDENTIAL STORAGE                                                  │
│  ═══════════════════                                                 │
│  Insecure:  ❌ Static keys in Kubernetes secrets (base64)           │
│  Secure:    ✅ No stored credentials, JWT tokens only               │
│                                                                      │
│  CREDENTIAL LIFETIME                                                 │
│  ═══════════════════════                                             │
│  Insecure:  ❌ Indefinite (until manually rotated)                  │
│  Secure:    ✅ 24 hours (auto-rotated)                              │
│                                                                      │
│  ROTATION MECHANISM                                                  │
│  ══════════════════════                                              │
│  Insecure:  ❌ Manual (rarely done in practice)                     │
│  Secure:    ✅ Automatic (transparent to application)               │
│                                                                      │
│  PRIVILEGE LEVEL                                                     │
│  ═══════════════════                                                 │
│  Insecure:  ❌ Often overprivileged (S3FullAccess)                  │
│  Secure:    ✅ Least privilege (specific bucket + actions)          │
│                                                                      │
│  ACCESS CONTROL                                                      │
│  ══════════════════                                                  │
│  Insecure:  ❌ Any pod can use credentials                          │
│  Secure:    ✅ Bound to specific namespace + service account        │
│                                                                      │
│  CREDENTIAL THEFT RISK                                               │
│  ══════════════════════                                              │
│  Insecure:  ❌ HIGH - base64 easily decoded                         │
│  Secure:    ✅ LOW - short-lived, scoped tokens                     │
│                                                                      │
│  AUDIT TRAIL                                                         │
│  ═══════════                                                         │
│  Insecure:  ❌ Poor - all actions as IAM user                       │
│  Secure:    ✅ Excellent - pod-level identity in CloudTrail         │
│                                                                      │
│  ENCRYPTION AT REST                                                  │
│  ══════════════════════                                              │
│  Insecure:  ❌ Often none or default SSE-S3                         │
│  Secure:    ✅ SSE-KMS with customer-managed key                    │
│                                                                      │
│  OPERATIONAL COMPLEXITY                                              │
│  ══════════════════════════                                          │
│  Insecure:  ⚠️  Low (but insecure)                                  │
│  Secure:    ⚠️  Medium (but secure)                                 │
│                                                                      │
│  BLAST RADIUS                                                        │
│  ════════════                                                        │
│  Insecure:  ❌ HIGH - credentials work anywhere                     │
│  Secure:    ✅ LOW - scoped to specific workload                    │
│                                                                      │
│  COMPLIANCE                                                          │
│  ══════════                                                          │
│  Insecure:  ❌ Difficult - static credentials problematic           │
│  Secure:    ✅ Easy - automatic rotation, audit trail               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Takeaways

```
╔═══════════════════════════════════════════════════════════════════╗
║                    WHY IRSA IS ESSENTIAL                           ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                    ║
║  1. NO STATIC CREDENTIALS                                         ║
║     • Eliminates the #1 security risk in Kubernetes              ║
║     • No credentials to steal, leak, or misuse                    ║
║     • JWT tokens are short-lived and scoped                       ║
║                                                                    ║
║  2. AUTOMATIC ROTATION                                            ║
║     • Credentials refresh every 24 hours automatically            ║
║     • No manual intervention required                             ║
║     • Continuous security without operational burden              ║
║                                                                    ║
║  3. LEAST PRIVILEGE                                               ║
║     • Fine-grained IAM policies per workload                      ║
║     • Access limited to specific S3 bucket and actions            ║
║     • Bound to specific namespace and service account             ║
║                                                                    ║
║  4. EXCELLENT AUDIT TRAIL                                         ║
║     • CloudTrail shows pod-level identity                         ║
║     • Can trace every action to specific pod/namespace            ║
║     • Compliance-ready audit logs                                 ║
║                                                                    ║
║  5. DEFENSE IN DEPTH                                              ║
║     • Multiple security layers (OIDC, IAM, KMS, S3 policies)      ║
║     • Encryption at rest with customer-managed keys               ║
║     • TLS-only access enforced                                    ║
║                                                                    ║
╚═══════════════════════════════════════════════════════════════════╝
```

---

**⚠️ IMPORTANT**: The insecure architecture is shown for educational purposes only. **NEVER use IAM user tokens in production Kubernetes environments.** Always use IRSA for secure AWS service access from EKS pods.

**Next Steps**:
- Review the [Mermaid diagram version](architecture-diagrams.md) for interactive diagrams
- Proceed to [Insecure Deployment Guide](02-insecure-deployment.md) to understand the risks
- Then implement [Secure IRSA Deployment](04-irsa-fundamentals.md)
