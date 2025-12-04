# Harbor IRSA Workshop: Complete Lab Guide
## Securing Container Registries on Amazon EKS

**Version:** 1.0  
**Last Updated:** December 2025  
**Duration:** 3-4 hours  
**Level:** Intermediate to Advanced

---

## Table of Contents

1. [Workshop Overview](#workshop-overview)
2. [Prerequisites and Setup](#prerequisites-and-setup)
3. [Learning Objectives](#learning-objectives)
4. [Part 1: Understanding the Security Problem](#part-1-understanding-the-security-problem)
5. [Part 2: The Insecure Approach](#part-2-the-insecure-approach)
6. [Part 3: The Secure IRSA Solution](#part-3-the-secure-irsa-solution)
7. [Part 4: Infrastructure as Code](#part-4-infrastructure-as-code)
8. [Part 5: Validation and Testing](#part-5-validation-and-testing)
9. [Part 6: Security Hardening](#part-6-security-hardening)
10. [Part 7: Audit and Compliance](#part-7-audit-and-compliance)
11. [Troubleshooting Guide](#troubleshooting-guide)
12. [Conclusion and Next Steps](#conclusion-and-next-steps)
13. [Appendix: Reference Materials](#appendix-reference-materials)

---

## Workshop Overview

### What You'll Build

In this hands-on workshop, you'll deploy Harbor container registry on Amazon EKS using two different approaches:

1. **Insecure Approach**: Using IAM user tokens (to understand the risks)
2. **Secure Approach**: Using IAM Roles for Service Accounts (IRSA)

By the end, you'll understand why IRSA is the security best practice for AWS access from Kubernetes.

### Why This Matters

Container registries like Harbor need to store images in S3. Many teams use static IAM credentials, creating serious security vulnerabilities:

- **Credential Theft**: Base64-encoded secrets are easily extracted
- **No Rotation**: Static credentials never expire
- **Overprivileged Access**: Broad permissions increase blast radius
- **Poor Audit Trail**: Cannot trace actions to specific pods

IRSA solves all these problems with temporary, automatically-rotated credentials bound to specific Kubernetes service accounts.


### Architecture Comparison

#### Insecure Architecture (IAM User Tokens)

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS Account                          │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │              Amazon EKS Cluster                     │    │
│  │                                                     │    │
│  │  ┌──────────────────────────────────────────┐     │    │
│  │  │         harbor namespace                  │     │    │
│  │  │                                           │     │    │
│  │  │  ┌─────────────────────────────────┐    │     │    │
│  │  │  │  Kubernetes Secret              │    │     │    │
│  │  │  │  (Base64 encoded)               │    │     │    │
│  │  │  │  - AWS_ACCESS_KEY_ID            │    │     │    │
│  │  │  │  - AWS_SECRET_ACCESS_KEY        │    │     │    │
│  │  │  └──────────────┬──────────────────┘    │     │    │
│  │  │                 │                        │     │    │
│  │  │                 ▼                        │     │    │
│  │  │  ┌─────────────────────────────────┐    │     │    │
│  │  │  │     Harbor Registry Pod         │    │     │    │
│  │  │  │  Environment Variables:         │    │     │    │
│  │  │  │  AWS_ACCESS_KEY_ID (from secret)│    │     │    │
│  │  │  └──────────────┬──────────────────┘    │     │    │
│  │  └─────────────────┼───────────────────────┘     │    │
│  └────────────────────┼─────────────────────────────┘    │
│                       │ Static Credentials                 │
│                       ▼                                    │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  IAM User → S3 Bucket (No encryption)               │  │
│  └──────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘

RISKS: ❌ Credential theft ❌ No rotation ❌ Overprivileged ❌ Poor audit
```

#### Secure Architecture (IRSA)

```
┌──────────────────────────────────────────────────────────────────────┐
│                            AWS Account                                │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                   Amazon EKS Cluster                         │    │
│  │                                                              │    │
│  │  ┌────────────────────────────────────────────────────┐    │    │
│  │  │  Service Account: harbor-registry                  │    │    │
│  │  │  Annotation: eks.amazonaws.com/role-arn            │    │    │
│  │  └──────────────┬─────────────────────────────────────┘    │    │
│  │                 │                                            │    │
│  │                 ▼                                            │    │
│  │  ┌──────────────────────────────────────────┐              │    │
│  │  │  Harbor Pod (no static credentials)      │              │    │
│  │  │  - Projected service account token       │              │    │
│  │  └──────────────┬───────────────────────────┘              │    │
│  │                 │                                            │    │
│  │  ┌──────────────┴───────────────────────────┐              │    │
│  │  │  OIDC Provider (EKS-managed)             │              │    │
│  │  │  Issues JWT tokens (auto-rotated)        │              │    │
│  │  └──────────────┬───────────────────────────┘              │    │
│  └─────────────────┼────────────────────────────────────────────    │
│                    │ JWT Token (temporary)                          │
│                    ▼                                                │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  IAM OIDC Provider → IAM Role (least privilege)             │   │
│  │  ↓                                                           │   │
│  │  S3 Bucket (SSE-KMS) ← KMS CMK                              │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘

BENEFITS: ✅ No static creds ✅ Auto-rotation ✅ Least privilege ✅ Audit trail
```


---

## Prerequisites and Setup

### Required Tools

Before starting this workshop, ensure you have the following tools installed:

| Tool | Version | Installation |
|------|---------|--------------|
| **AWS CLI** | v2.x | `https://aws.amazon.com/cli/` |
| **kubectl** | v1.28+ | `https://kubernetes.io/docs/tasks/tools/` |
| **Terraform** | v1.5+ | `https://www.terraform.io/downloads` |
| **Helm** | v3.x | `https://helm.sh/docs/intro/install/` |
| **jq** | Latest | `https://stedolan.github.io/jq/` |

### AWS Account Requirements

- **AWS Account** with administrative access
- **IAM permissions** to create:
  - EKS clusters
  - IAM roles and policies
  - S3 buckets
  - KMS keys
  - VPC resources

### Estimated Costs

Running this workshop will incur AWS charges:

- **EKS Cluster**: ~$0.10/hour
- **EC2 Worker Nodes**: ~$0.08/hour (2 × t3.medium)
- **S3 Storage**: ~$0.023/GB
- **KMS Key**: ~$1/month (prorated)

**Total estimated cost**: ~$1.50-2.00 for a 4-hour workshop

💡 **Cost Tip**: Delete all resources immediately after completing the workshop.

### Environment Setup

1. **Configure AWS CLI**:
```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, and default region
```

2. **Set environment variables**:
```bash
export AWS_REGION=us-east-1
export CLUSTER_NAME=harbor-irsa-workshop
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo "AWS Region: $AWS_REGION"
```

3. **Verify prerequisites**:
```bash
# Check AWS CLI
aws --version

# Check kubectl
kubectl version --client

# Check Terraform
terraform version

# Check Helm
helm version

# Verify AWS credentials
aws sts get-caller-identity
```


---

## Learning Objectives

By completing this workshop, you will be able to:

1. ✅ **Explain** the security risks of static IAM credentials in Kubernetes
2. ✅ **Implement** IRSA for secure AWS service access from EKS pods
3. ✅ **Configure** least-privilege IAM policies for specific workload requirements
4. ✅ **Deploy** Harbor container registry with S3 backend using IRSA
5. ✅ **Validate** security controls through automated testing
6. ✅ **Analyze** CloudTrail logs for audit and compliance
7. ✅ **Apply** defense-in-depth with KMS encryption
8. ✅ **Troubleshoot** common IRSA configuration issues

---

## Part 1: Understanding the Security Problem

### The Challenge: AWS Access from Kubernetes

When applications running in Kubernetes need to access AWS services (like S3), they need AWS credentials. There are two main approaches:

1. **Static IAM User Credentials** (Insecure)
2. **IAM Roles for Service Accounts** (Secure)

### Why Static Credentials Are Dangerous

#### Risk 1: Credential Theft

Kubernetes secrets are only base64-encoded, not encrypted. Anyone with kubectl access can extract credentials:

```bash
# Extract credentials from Kubernetes secret
kubectl get secret harbor-s3-credentials -n harbor -o json | \
  jq -r '.data.AWS_ACCESS_KEY_ID' | base64 -d

kubectl get secret harbor-s3-credentials -n harbor -o json | \
  jq -r '.data.AWS_SECRET_ACCESS_KEY' | base64 -d
```

**Impact**: Attacker gains full AWS access with stolen credentials.

#### Risk 2: No Automatic Rotation

Static IAM user credentials never expire unless manually rotated:

- Most teams never rotate credentials
- Rotation requires application restart
- Old credentials remain valid indefinitely

**Impact**: Compromised credentials can be used for months or years.

#### Risk 3: Overprivileged Access

Teams often grant broad permissions for convenience:

```json
{
  "Effect": "Allow",
  "Action": "s3:*",
  "Resource": "*"
}
```

**Impact**: Attacker can access all S3 buckets, not just Harbor's bucket.

#### Risk 4: Poor Audit Trail

All actions appear as a single IAM user in CloudTrail:

```json
{
  "userIdentity": {
    "type": "IAMUser",
    "userName": "harbor-s3-user"
  }
}
```

**Impact**: Cannot determine which pod or container performed an action.


### STRIDE Threat Model Analysis

Let's analyze the insecure approach using the STRIDE framework:

| Threat Category | Threat Description | Impact | Likelihood | Mitigation |
|----------------|-------------------|--------|------------|------------|
| **Spoofing** | Attacker steals IAM credentials from Kubernetes secret | High | High | None in insecure approach |
| **Tampering** | Attacker modifies S3 objects using stolen credentials | High | High | None - overprivileged access |
| **Repudiation** | Actions cannot be traced to specific pod | Medium | High | None - poor attribution |
| **Information Disclosure** | Credentials exposed via kubectl | High | High | None - secrets accessible |
| **Denial of Service** | Attacker deletes all S3 objects | High | Medium | None - S3FullAccess allows deletion |
| **Elevation of Privilege** | Credentials used for unintended AWS actions | High | High | None - broad permissions |

**Conclusion**: The insecure approach has no effective mitigations for any STRIDE threat category.

---

## Part 2: The Insecure Approach

### ⚠️ Educational Purpose Only

This section demonstrates the insecure approach for educational purposes. **Never use this in production!**

### Step 1: Create IAM User with Access Keys

```bash
# Create IAM user
aws iam create-user --user-name harbor-s3-user

# Create access key
aws iam create-access-key --user-name harbor-s3-user > harbor-credentials.json

# Extract credentials
export AWS_ACCESS_KEY_ID=$(jq -r '.AccessKey.AccessKeyId' harbor-credentials.json)
export AWS_SECRET_ACCESS_KEY=$(jq -r '.AccessKey.SecretAccessKey' harbor-credentials.json)

echo "Access Key ID: $AWS_ACCESS_KEY_ID"
```

### Step 2: Attach Overprivileged Policy

```bash
# Attach S3 full access (overprivileged!)
aws iam attach-user-policy \
  --user-name harbor-s3-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

### Step 3: Create Kubernetes Secret

```bash
# Create namespace
kubectl create namespace harbor

# Create secret with credentials
kubectl create secret generic harbor-s3-credentials \
  --from-literal=AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  --from-literal=AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  --namespace harbor
```

### Step 4: Deploy Harbor with Static Credentials

Create `harbor-values-insecure.yaml`:

```yaml
expose:
  type: loadBalancer

imageChartStorage:
  type: s3
  s3:
    region: us-east-1
    bucket: harbor-registry-insecure
    accesskey: ${AWS_ACCESS_KEY_ID}
    secretkey: ${AWS_SECRET_ACCESS_KEY}
    encrypt: false
    secure: true
```

Deploy Harbor:

```bash
# Add Harbor Helm repository
helm repo add harbor https://helm.goharbor.io
helm repo update

# Deploy Harbor
helm install harbor harbor/harbor \
  --namespace harbor \
  --values harbor-values-insecure.yaml
```


### Step 5: Demonstrate Credential Extraction

Anyone with kubectl access can extract the credentials:

```bash
# Extract AWS Access Key ID
kubectl get secret harbor-s3-credentials -n harbor -o json | \
  jq -r '.data.AWS_ACCESS_KEY_ID' | base64 -d

# Extract AWS Secret Access Key
kubectl get secret harbor-s3-credentials -n harbor -o json | \
  jq -r '.data.AWS_SECRET_ACCESS_KEY' | base64 -d

# Use stolen credentials
export AWS_ACCESS_KEY_ID=$(kubectl get secret harbor-s3-credentials -n harbor -o json | jq -r '.data.AWS_ACCESS_KEY_ID' | base64 -d)
export AWS_SECRET_ACCESS_KEY=$(kubectl get secret harbor-s3-credentials -n harbor -o json | jq -r '.data.AWS_SECRET_ACCESS_KEY' | base64 -d)

# Attacker can now access S3
aws s3 ls
```

**Result**: Credentials are trivially extracted and can be used anywhere.

### Checkpoint 1: Insecure Deployment

Verify you understand the risks:

- [ ] IAM user credentials created
- [ ] Credentials stored in Kubernetes secret
- [ ] Harbor deployed with static credentials
- [ ] Credentials successfully extracted
- [ ] STRIDE threat model reviewed

**Key Takeaway**: Base64 encoding is NOT encryption. Static credentials in Kubernetes secrets are a critical security vulnerability.

---

## Part 3: The Secure IRSA Solution

### How IRSA Works

IRSA (IAM Roles for Service Accounts) provides temporary AWS credentials to Kubernetes pods without storing static credentials:

1. **EKS OIDC Provider**: Acts as identity provider for Kubernetes
2. **Service Account**: Kubernetes identity annotated with IAM role ARN
3. **JWT Token**: Projected into pod, used to assume IAM role
4. **Temporary Credentials**: AWS STS issues short-lived credentials
5. **Automatic Rotation**: Credentials refresh before expiration

### Step 1: Enable OIDC Provider on EKS

First, create an EKS cluster with OIDC enabled:

```bash
# Create EKS cluster (if not already created)
eksctl create cluster \
  --name $CLUSTER_NAME \
  --region $AWS_REGION \
  --with-oidc \
  --nodes 2 \
  --node-type t3.medium

# Or enable OIDC on existing cluster
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $AWS_REGION \
  --approve
```

Verify OIDC provider:

```bash
# Get OIDC issuer URL
aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $AWS_REGION \
  --query "cluster.identity.oidc.issuer" \
  --output text

# List OIDC providers
aws iam list-open-id-connect-providers
```


### Step 2: Create S3 Bucket with KMS Encryption

```bash
# Set bucket name
export BUCKET_NAME="harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION}"

# Create S3 bucket
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $AWS_REGION \
  --create-bucket-configuration LocationConstraint=$AWS_REGION

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Block public access
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

### Step 3: Create KMS Customer Managed Key

```bash
# Create KMS key
KMS_KEY_ID=$(aws kms create-key \
  --description "Harbor S3 encryption key" \
  --query 'KeyMetadata.KeyId' \
  --output text)

# Create alias
aws kms create-alias \
  --alias-name alias/harbor-s3-encryption \
  --target-key-id $KMS_KEY_ID

# Enable automatic key rotation
aws kms enable-key-rotation --key-id $KMS_KEY_ID

echo "KMS Key ID: $KMS_KEY_ID"
```

### Step 4: Create IAM Role for IRSA

Get OIDC provider details:

```bash
# Get OIDC provider ARN
OIDC_PROVIDER=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $AWS_REGION \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed -e "s/^https:\/\///")

echo "OIDC Provider: $OIDC_PROVIDER"
```

Create trust policy (`trust-policy.json`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:harbor:harbor-registry",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

Create the IAM role:

```bash
# Substitute environment variables in trust policy
envsubst < trust-policy.json > trust-policy-final.json

# Create IAM role
aws iam create-role \
  --role-name HarborS3Role \
  --assume-role-policy-document file://trust-policy-final.json \
  --description "IAM role for Harbor registry S3 access via IRSA"

# Get role ARN
ROLE_ARN=$(aws iam get-role --role-name HarborS3Role --query 'Role.Arn' --output text)
echo "Role ARN: $ROLE_ARN"
```


### Step 5: Create Least-Privilege IAM Policy

Create permissions policy (`harbor-s3-policy.json`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "HarborS3Access",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
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
```

Attach policy to role:

```bash
# Substitute environment variables
envsubst < harbor-s3-policy.json > harbor-s3-policy-final.json

# Create and attach policy
aws iam put-role-policy \
  --role-name HarborS3Role \
  --policy-name HarborS3Access \
  --policy-document file://harbor-s3-policy-final.json
```

### Step 6: Configure S3 Bucket Encryption

Enable default encryption:

```bash
# Enable SSE-KMS encryption
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "'$KMS_KEY_ID'"
      },
      "BucketKeyEnabled": true
    }]
  }'
```

Create bucket policy to enforce encryption (`bucket-policy.json`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnencryptedObjectUploads",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
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
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

Apply bucket policy:

```bash
# Substitute environment variables
envsubst < bucket-policy.json > bucket-policy-final.json

# Apply bucket policy
aws s3api put-bucket-policy \
  --bucket $BUCKET_NAME \
  --policy file://bucket-policy-final.json
```


### Step 7: Update KMS Key Policy

Update KMS key policy to allow Harbor role:

```bash
# Get current key policy
aws kms get-key-policy \
  --key-id $KMS_KEY_ID \
  --policy-name default \
  --output text > kms-policy-current.json

# Add Harbor role to key policy (edit kms-policy-current.json)
# Add this statement to the policy:
```

```json
{
  "Sid": "Allow Harbor Role to use the key",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/HarborS3Role"
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
}
```

Apply updated policy:

```bash
# Apply updated key policy
aws kms put-key-policy \
  --key-id $KMS_KEY_ID \
  --policy-name default \
  --policy file://kms-policy-updated.json
```

### Step 8: Create Kubernetes Service Account

Create service account with IRSA annotation:

```yaml
# service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: harbor-registry
  namespace: harbor
  annotations:
    eks.amazonaws.com/role-arn: ${ROLE_ARN}
```

Apply the service account:

```bash
# Create namespace
kubectl create namespace harbor

# Substitute environment variables
envsubst < service-account.yaml > service-account-final.yaml

# Apply service account
kubectl apply -f service-account-final.yaml

# Verify annotation
kubectl get sa harbor-registry -n harbor -o yaml
```

### Step 9: Deploy Harbor with IRSA

Create Harbor values file (`harbor-values-irsa.yaml`):

```yaml
expose:
  type: loadBalancer
  tls:
    enabled: true
    certSource: auto

persistence:
  persistentVolumeClaim:
    registry:
      storageClass: gp3
      size: 10Gi

imageChartStorage:
  type: s3
  s3:
    region: ${AWS_REGION}
    bucket: ${BUCKET_NAME}
    encrypt: true
    secure: true
    v4auth: true
    # No accesskey or secretkey - IRSA provides credentials automatically

serviceAccount:
  create: false  # We created it manually
  name: harbor-registry

core:
  serviceAccountName: harbor-registry

registry:
  serviceAccountName: harbor-registry

jobservice:
  serviceAccountName: harbor-registry
```

Deploy Harbor:

```bash
# Substitute environment variables
envsubst < harbor-values-irsa.yaml > harbor-values-irsa-final.yaml

# Deploy Harbor
helm install harbor harbor/harbor \
  --namespace harbor \
  --values harbor-values-irsa-final.yaml \
  --wait

# Check pod status
kubectl get pods -n harbor
```


### Step 10: Verify IRSA Configuration

Check that Harbor pod has no static credentials:

```bash
# Get Harbor registry pod name
POD_NAME=$(kubectl get pods -n harbor -l component=registry -o jsonpath='{.items[0].metadata.name}')

# Check environment variables (should NOT contain AWS credentials)
kubectl exec -n harbor $POD_NAME -- env | grep AWS

# Check projected service account token
kubectl exec -n harbor $POD_NAME -- ls -la /var/run/secrets/eks.amazonaws.com/serviceaccount/

# View token (JWT)
kubectl exec -n harbor $POD_NAME -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

Test S3 access:

```bash
# Check Harbor logs for S3 operations
kubectl logs -n harbor $POD_NAME | grep -i s3

# Verify no credential errors
kubectl logs -n harbor $POD_NAME | grep -i "credential\|access denied"
```

### Checkpoint 2: Secure IRSA Deployment

Verify your IRSA implementation:

- [ ] OIDC provider enabled on EKS cluster
- [ ] S3 bucket created with KMS encryption
- [ ] KMS customer managed key created
- [ ] IAM role created with trust policy
- [ ] Least-privilege IAM policy attached
- [ ] Kubernetes service account annotated with role ARN
- [ ] Harbor deployed without static credentials
- [ ] Harbor pod can access S3 successfully

**Key Takeaway**: IRSA provides secure AWS access without storing any static credentials.

---

## Part 4: Infrastructure as Code

### Terraform Implementation

For production deployments, use Terraform to provision infrastructure reproducibly.

### Project Structure

```
terraform/
├── main.tf                 # Root module
├── variables.tf            # Input variables
├── outputs.tf              # Output values
├── terraform.tfvars        # Variable values
└── modules/
    ├── eks/                # EKS cluster module
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── irsa/               # IRSA configuration module
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── storage/            # S3 and KMS module
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### Terraform Deployment

Navigate to the terraform directory:

```bash
cd terraform
```

Initialize Terraform:

```bash
terraform init
```

Review the plan:

```bash
terraform plan
```

Apply the configuration:

```bash
terraform apply
```

Get outputs:

```bash
# Get cluster name
terraform output cluster_name

# Get OIDC provider ARN
terraform output oidc_provider_arn

# Get IAM role ARN
terraform output harbor_role_arn

# Get S3 bucket name
terraform output s3_bucket_name

# Get KMS key ID
terraform output kms_key_id
```


### Key Terraform Resources

#### EKS Module

```hcl
module "eks" {
  source = "./modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = "1.28"
  vpc_cidr        = "10.0.0.0/16"
  
  node_groups = {
    general = {
      desired_size = 2
      min_size     = 1
      max_size     = 4
      instance_types = ["t3.medium"]
    }
  }
  
  enable_irsa = true
  
  tags = var.tags
}
```

#### IRSA Module

```hcl
module "irsa" {
  source = "./modules/irsa"

  cluster_name         = module.eks.cluster_name
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  
  role_name            = "HarborS3Role"
  service_account_name = "harbor-registry"
  namespace            = "harbor"
  
  s3_bucket_arn        = module.storage.s3_bucket_arn
  kms_key_arn          = module.storage.kms_key_arn
  
  tags = var.tags
}
```

#### Storage Module

```hcl
module "storage" {
  source = "./modules/storage"

  bucket_name = "harbor-registry-storage-${data.aws_caller_identity.current.account_id}-${var.region}"
  
  enable_versioning    = true
  enable_encryption    = true
  kms_key_description  = "Harbor S3 encryption key"
  enable_key_rotation  = true
  
  harbor_role_arn = module.irsa.role_arn
  
  tags = var.tags
}
```

### Checkpoint 3: Infrastructure as Code

Verify Terraform deployment:

- [ ] Terraform initialized successfully
- [ ] Terraform plan shows expected resources
- [ ] Terraform apply completed without errors
- [ ] All outputs available
- [ ] EKS cluster accessible via kubectl
- [ ] Resources properly tagged

**Key Takeaway**: Infrastructure as Code enables reproducible, version-controlled deployments.

---

## Part 5: Validation and Testing

### Test 1: Verify No Static Credentials

Confirm Harbor pods contain no AWS credentials:

```bash
# Get all Harbor pods
kubectl get pods -n harbor

# Check each pod for AWS credentials
for pod in $(kubectl get pods -n harbor -o jsonpath='{.items[*].metadata.name}'); do
  echo "Checking pod: $pod"
  kubectl exec -n harbor $pod -- env | grep -E "AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY" || echo "✅ No static credentials found"
done
```

### Test 2: Verify S3 Access Works

Test that Harbor can write to S3:

```bash
# Push a test image to Harbor
docker pull nginx:alpine
docker tag nginx:alpine harbor.example.com/library/nginx:test
docker push harbor.example.com/library/nginx:test

# Verify image stored in S3
aws s3 ls s3://$BUCKET_NAME/docker/registry/v2/repositories/
```


### Test 3: Verify Access Control Enforcement

Test that unauthorized service accounts are denied:

```bash
# Create unauthorized service account
kubectl create sa unauthorized-sa -n harbor

# Create test pod with unauthorized SA
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: unauthorized-test
  namespace: harbor
spec:
  serviceAccountName: unauthorized-sa
  containers:
  - name: aws-cli
    image: amazon/aws-cli
    command: ["sleep", "3600"]
EOF

# Wait for pod to start
kubectl wait --for=condition=Ready pod/unauthorized-test -n harbor --timeout=60s

# Try to access S3 (should fail)
kubectl exec -n harbor unauthorized-test -- aws s3 ls s3://$BUCKET_NAME/

# Expected output: An error occurred (AccessDenied)
```

### Test 4: Verify Automatic Credential Rotation

Monitor credential expiration and rotation:

```bash
# Get Harbor registry pod
POD_NAME=$(kubectl get pods -n harbor -l component=registry -o jsonpath='{.items[0].metadata.name}')

# Check token expiration
kubectl exec -n harbor $POD_NAME -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token | \
  cut -d'.' -f2 | base64 -d 2>/dev/null | jq -r '.exp' | \
  xargs -I {} date -d @{}

# Token should expire in ~24 hours and auto-rotate
```

### Test 5: Verify CloudTrail Logging

Check CloudTrail for IRSA identity attribution:

```bash
# Query CloudTrail for S3 events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::S3::Bucket \
  --max-results 10 \
  --query 'Events[*].[EventTime,Username,EventName]' \
  --output table

# Look for assumed role session with pod identity
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 5 \
  --output json | jq '.Events[0].CloudTrailEvent' | jq -r . | jq .
```

Expected CloudTrail entry:

```json
{
  "userIdentity": {
    "type": "AssumedRole",
    "principalId": "AROAXXXXXXXXX:eks-harbor-harbor-registry-xxxxx",
    "arn": "arn:aws:sts::ACCOUNT:assumed-role/HarborS3Role/eks-harbor-harbor-registry-xxxxx",
    "accountId": "ACCOUNT",
    "sessionContext": {
      "sessionIssuer": {
        "type": "Role",
        "principalId": "AROAXXXXXXXXX",
        "arn": "arn:aws:iam::ACCOUNT:role/HarborS3Role",
        "accountId": "ACCOUNT",
        "userName": "HarborS3Role"
      },
      "webIdFederationData": {
        "federatedProvider": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks.region.amazonaws.com/id/CLUSTER_ID",
        "attributes": {
          "sub": "system:serviceaccount:harbor:harbor-registry"
        }
      }
    }
  }
}
```

**Key Observation**: The `sub` field shows the exact Kubernetes namespace and service account!


### Test 6: Verify KMS Encryption

Confirm S3 objects are encrypted with KMS:

```bash
# List objects in S3 bucket
aws s3api list-objects-v2 --bucket $BUCKET_NAME --max-items 5

# Get encryption details for an object
OBJECT_KEY=$(aws s3api list-objects-v2 --bucket $BUCKET_NAME --max-items 1 --query 'Contents[0].Key' --output text)

aws s3api head-object \
  --bucket $BUCKET_NAME \
  --key "$OBJECT_KEY" \
  --query 'ServerSideEncryption,SSEKMSKeyId'

# Expected output: "aws:kms" and KMS key ARN
```

### Checkpoint 4: Validation Complete

Verify all tests passed:

- [ ] No static credentials in any Harbor pods
- [ ] Harbor successfully writes to S3
- [ ] Unauthorized service accounts denied access
- [ ] Credentials automatically rotate
- [ ] CloudTrail shows pod-level identity
- [ ] S3 objects encrypted with KMS

**Key Takeaway**: Comprehensive validation proves IRSA security properties.

---

## Part 6: Security Hardening

### KMS Key Policy Hardening

Best practices for KMS key policies:

1. **Principle of Least Privilege**: Only grant necessary permissions
2. **Condition Keys**: Add additional restrictions
3. **Key Rotation**: Enable automatic rotation
4. **Audit Logging**: Monitor key usage in CloudTrail

Enhanced KMS key policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow Harbor Role to use the key",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT:role/HarborS3Role"
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "s3.REGION.amazonaws.com"
        },
        "StringLike": {
          "kms:EncryptionContext:aws:s3:arn": "arn:aws:s3:::BUCKET_NAME/*"
        }
      }
    },
    {
      "Sid": "Deny key usage outside S3",
      "Effect": "Deny",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT:role/HarborS3Role"
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
  ]
}
```


### S3 Bucket Policy Hardening

Enhanced S3 bucket policy with additional security controls:

```json
{
  "Version": "2012-10-17",
  "Statement": [
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
    },
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
    },
    {
      "Sid": "DenyIncorrectKMSKey",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::BUCKET_NAME/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption-aws-kms-key-id": "arn:aws:kms:REGION:ACCOUNT:key/KEY_ID"
        }
      }
    },
    {
      "Sid": "RequireBucketOwnerFullControl",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::BUCKET_NAME/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    }
  ]
}
```

### IAM Guardrails

Implement organizational controls:

1. **Permission Boundaries**: Limit maximum permissions for IRSA roles
2. **Service Control Policies (SCPs)**: Enforce organization-wide restrictions
3. **IAM Access Analyzer**: Detect unintended access
4. **Tag-Based Access Control**: Enforce tagging requirements

Example permission boundary:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowedServices",
      "Effect": "Allow",
      "Action": [
        "s3:*",
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyDangerousActions",
      "Effect": "Deny",
      "Action": [
        "iam:*",
        "organizations:*",
        "account:*"
      ],
      "Resource": "*"
    }
  ]
}
```

Apply permission boundary:

```bash
aws iam put-role-permissions-boundary \
  --role-name HarborS3Role \
  --permissions-boundary arn:aws:iam::ACCOUNT:policy/IRSAPermissionBoundary
```


### Namespace Isolation

Implement Kubernetes network policies for defense-in-depth:

```yaml
# network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: harbor-isolation
  namespace: harbor
spec:
  podSelector:
    matchLabels:
      app: harbor
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: harbor
    - podSelector: {}
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443  # HTTPS to AWS APIs
    - protocol: TCP
      port: 53   # DNS
    - protocol: UDP
      port: 53   # DNS
```

Apply network policy:

```bash
kubectl apply -f network-policy.yaml
```

### RBAC Restrictions

Limit who can view service accounts:

```yaml
# rbac-restrictions.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: harbor-sa-viewer
  namespace: harbor
rules:
- apiGroups: [""]
  resources: ["serviceaccounts"]
  resourceNames: ["harbor-registry"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: harbor-sa-viewer-binding
  namespace: harbor
subjects:
- kind: Group
  name: harbor-admins
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: harbor-sa-viewer
  apiGroup: rbac.authorization.k8s.io
```

### Checkpoint 5: Security Hardening

Verify hardening measures:

- [ ] KMS key policy includes condition keys
- [ ] S3 bucket policy enforces encryption
- [ ] Permission boundary applied to IAM role
- [ ] Network policies restrict pod communication
- [ ] RBAC limits service account access

**Key Takeaway**: Defense-in-depth requires multiple layers of security controls.

---

## Part 7: Audit and Compliance

### CloudTrail Log Analysis

Query CloudTrail for IRSA-related events:

```bash
# Find AssumeRoleWithWebIdentity events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 10 \
  --output json | jq -r '.Events[] | .CloudTrailEvent' | jq .

# Find S3 access events by Harbor role
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=HarborS3Role \
  --max-results 10 \
  --output table
```


### Comparing Audit Trails

**IAM User Approach** (Poor Attribution):

```json
{
  "userIdentity": {
    "type": "IAMUser",
    "userName": "harbor-s3-user",
    "principalId": "AIDAXXXXXXXXX"
  },
  "eventName": "PutObject",
  "requestParameters": {
    "bucketName": "harbor-registry-insecure",
    "key": "docker/registry/v2/..."
  }
}
```

**Problem**: Cannot determine which pod or container performed the action.

**IRSA Approach** (Excellent Attribution):

```json
{
  "userIdentity": {
    "type": "AssumedRole",
    "principalId": "AROAXXXXXXXXX:eks-harbor-harbor-registry-xxxxx",
    "arn": "arn:aws:sts::ACCOUNT:assumed-role/HarborS3Role/eks-harbor-harbor-registry-xxxxx",
    "sessionContext": {
      "webIdFederationData": {
        "federatedProvider": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks.region.amazonaws.com/id/CLUSTER_ID",
        "attributes": {
          "sub": "system:serviceaccount:harbor:harbor-registry"
        }
      }
    }
  },
  "eventName": "PutObject",
  "requestParameters": {
    "bucketName": "harbor-registry-storage-ACCOUNT-REGION",
    "key": "docker/registry/v2/..."
  }
}
```

**Benefit**: Clear attribution to specific namespace and service account!

### Permission Tracking

Query IAM policies and service account bindings:

```bash
# List IAM policies attached to role
aws iam list-role-policies --role-name HarborS3Role

# Get inline policy document
aws iam get-role-policy \
  --role-name HarborS3Role \
  --policy-name HarborS3Access

# Get trust policy
aws iam get-role \
  --role-name HarborS3Role \
  --query 'Role.AssumeRolePolicyDocument'

# List service accounts in namespace
kubectl get sa -n harbor

# Get service account details
kubectl get sa harbor-registry -n harbor -o yaml
```

### Incident Investigation Workflow

When investigating suspicious S3 access:

1. **Identify the event in CloudTrail**:
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteObject \
  --start-time 2025-12-01T00:00:00Z \
  --end-time 2025-12-03T23:59:59Z
```

2. **Extract the session name** from `principalId`:
```
eks-harbor-harbor-registry-xxxxx
```

3. **Correlate with Kubernetes pod**:
```bash
# List pods using the service account
kubectl get pods -n harbor --field-selector spec.serviceAccountName=harbor-registry

# Check pod logs
kubectl logs -n harbor <pod-name> --since=24h
```

4. **Review pod events**:
```bash
kubectl get events -n harbor --field-selector involvedObject.name=<pod-name>
```

5. **Identify the user who created/modified the pod**:
```bash
kubectl get pod <pod-name> -n harbor -o yaml | grep -A 5 "annotations:"
```


### Compliance Reporting

Generate compliance reports:

```bash
# Count IRSA role assumptions in last 24 hours
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ) \
  --query 'Events | length(@)'

# List all S3 access by Harbor role
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=HarborS3Role \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ) \
  --query 'Events[*].[EventTime,EventName,Username]' \
  --output table

# Verify KMS key usage
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::KMS::Key \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ) \
  --query 'Events[*].[EventTime,EventName,Username]' \
  --output table
```

### Checkpoint 6: Audit and Compliance

Verify audit capabilities:

- [ ] CloudTrail logs show IRSA identity
- [ ] Can trace S3 access to specific pods
- [ ] IAM policies documented and queryable
- [ ] Service account bindings verified
- [ ] Incident investigation workflow tested
- [ ] Compliance reports generated

**Key Takeaway**: IRSA provides comprehensive audit trails for compliance and security investigations.

---

## Troubleshooting Guide

### Issue 1: Pod Cannot Assume IAM Role

**Symptoms**:
- Pod logs show "Unable to locate credentials"
- S3 operations fail with authentication errors

**Diagnosis**:
```bash
# Check service account annotation
kubectl get sa harbor-registry -n harbor -o yaml | grep eks.amazonaws.com/role-arn

# Verify OIDC provider exists
aws iam list-open-id-connect-providers

# Check IAM role trust policy
aws iam get-role --role-name HarborS3Role --query 'Role.AssumeRolePolicyDocument'
```

**Solutions**:
1. Verify service account has correct annotation
2. Ensure OIDC provider is registered in IAM
3. Check trust policy matches namespace and service account name
4. Verify `aud` claim is set to `sts.amazonaws.com`

### Issue 2: S3 Access Denied

**Symptoms**:
- Harbor logs show 403 Forbidden errors
- S3 operations fail with AccessDenied

**Diagnosis**:
```bash
# Check IAM role permissions
aws iam get-role-policy --role-name HarborS3Role --policy-name HarborS3Access

# Verify S3 bucket policy
aws s3api get-bucket-policy --bucket $BUCKET_NAME

# Check KMS key policy
aws kms get-key-policy --key-id $KMS_KEY_ID --policy-name default
```

**Solutions**:
1. Verify IAM policy includes required S3 actions
2. Check S3 bucket policy doesn't deny access
3. Ensure KMS key policy allows Harbor role
4. Verify bucket name matches in IAM policy


### Issue 3: KMS Decryption Failures

**Symptoms**:
- S3 operations fail with KMS errors
- Logs show "Access denied to KMS key"

**Diagnosis**:
```bash
# Check KMS key policy
aws kms get-key-policy --key-id $KMS_KEY_ID --policy-name default | jq .

# Verify IAM role has KMS permissions
aws iam get-role-policy --role-name HarborS3Role --policy-name HarborS3Access | jq .

# Test KMS access
aws kms describe-key --key-id $KMS_KEY_ID
```

**Solutions**:
1. Add Harbor role to KMS key policy
2. Ensure IAM policy includes `kms:Decrypt` and `kms:GenerateDataKey`
3. Add condition key: `kms:ViaService: s3.REGION.amazonaws.com`
4. Verify KMS key is in same region as S3 bucket

### Issue 4: OIDC Provider Not Found

**Symptoms**:
- IAM role creation fails
- Trust policy validation errors

**Diagnosis**:
```bash
# Check if OIDC provider exists
aws iam list-open-id-connect-providers

# Get EKS cluster OIDC issuer
aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer"

# Verify OIDC provider URL matches
```

**Solutions**:
1. Enable OIDC on EKS cluster:
```bash
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $AWS_REGION \
  --approve
```

2. Verify OIDC provider ARN in trust policy matches registered provider

### Issue 5: Token Expiration Issues

**Symptoms**:
- Intermittent authentication failures
- Credentials work then stop working

**Diagnosis**:
```bash
# Check token expiration
POD_NAME=$(kubectl get pods -n harbor -l component=registry -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n harbor $POD_NAME -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token | \
  cut -d'.' -f2 | base64 -d 2>/dev/null | jq -r '.exp' | xargs -I {} date -d @{}
```

**Solutions**:
1. Verify AWS SDK is configured to auto-refresh credentials
2. Check pod has projected service account token volume
3. Ensure token expiration is set appropriately (default 86400s)
4. Restart pod if token projection is not working

### Issue 6: Wrong Service Account Used

**Symptoms**:
- Access denied despite correct IAM configuration
- Trust policy validation fails

**Diagnosis**:
```bash
# Check which service account pod is using
kubectl get pod <pod-name> -n harbor -o jsonpath='{.spec.serviceAccountName}'

# Verify service account annotation
kubectl get sa <sa-name> -n harbor -o yaml
```

**Solutions**:
1. Update pod spec to use correct service account
2. Verify Helm values specify correct `serviceAccountName`
3. Ensure service account exists before deploying pods


### Common Error Messages

| Error Message | Cause | Solution |
|--------------|-------|----------|
| `Unable to locate credentials` | Service account not annotated or OIDC not configured | Check SA annotation and OIDC provider |
| `AccessDenied: Access Denied` | IAM policy missing permissions | Review and update IAM policy |
| `InvalidAccessKeyId` | Pod using wrong credentials | Verify no static credentials in pod |
| `SignatureDoesNotMatch` | Clock skew or wrong region | Check pod time sync and region config |
| `KMS.AccessDeniedException` | KMS key policy doesn't allow role | Update KMS key policy |
| `NoSuchBucket` | Bucket name mismatch | Verify bucket name in config |
| `InvalidToken` | Token expired or invalid | Check token projection and expiration |

---

## Conclusion and Next Steps

### What You've Accomplished

Congratulations! You've completed a comprehensive workshop on securing Harbor container registry with IRSA. You now understand:

✅ **Security Risks**: Why static IAM credentials are dangerous  
✅ **IRSA Implementation**: How to configure IAM Roles for Service Accounts  
✅ **Least Privilege**: How to create minimal IAM policies  
✅ **Encryption**: How to use KMS for data protection  
✅ **Validation**: How to test security controls  
✅ **Audit**: How to trace actions in CloudTrail  
✅ **Troubleshooting**: How to diagnose common issues  

### Key Takeaways

1. **Never use static IAM credentials in Kubernetes** - they're easily stolen and never rotate
2. **IRSA provides temporary, automatically-rotated credentials** - bound to specific service accounts
3. **Least privilege is essential** - grant only required permissions
4. **Defense-in-depth matters** - combine IRSA with KMS, bucket policies, and network policies
5. **Audit trails are critical** - IRSA enables pod-level attribution in CloudTrail

### Comparison Summary

| Dimension | IAM User Tokens | IRSA |
|-----------|----------------|------|
| **Credential Storage** | Static keys in secrets | No stored credentials |
| **Rotation** | Manual (rarely done) | Automatic (every 24h) |
| **Privilege Level** | Often overprivileged | Least privilege |
| **Access Control** | Any pod can use | Bound to specific SA |
| **Audit Trail** | IAM user only | Pod-level identity |
| **Theft Risk** | High | Low |
| **Operational Complexity** | Low | Medium |
| **Security Posture** | ❌ Poor | ✅ Excellent |

### Next Steps

#### Apply to Your Workloads

Use IRSA for any Kubernetes workload that needs AWS access:

- **Databases**: RDS, DynamoDB access
- **Storage**: S3, EFS access
- **Messaging**: SQS, SNS, Kinesis
- **Secrets**: Secrets Manager, Parameter Store
- **Monitoring**: CloudWatch, X-Ray

#### Expand Your Knowledge

- **AWS Security Best Practices**: [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- **Kubernetes Security**: [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- **Container Security**: [NIST SP 800-190](https://csrc.nist.gov/publications/detail/sp/800-190/final)


#### Share Your Knowledge

- Write a blog post about your experience
- Present at your team's tech talk
- Contribute improvements to this workshop
- Help others implement IRSA

### Cleanup Instructions

To avoid ongoing AWS charges, delete all resources:

```bash
# Delete Harbor deployment
helm uninstall harbor -n harbor

# Delete namespace
kubectl delete namespace harbor

# Delete Terraform resources (if used)
cd terraform
terraform destroy

# Or manually delete resources:

# Delete S3 bucket (must be empty first)
aws s3 rm s3://$BUCKET_NAME --recursive
aws s3api delete-bucket --bucket $BUCKET_NAME

# Delete KMS key (schedule deletion)
aws kms schedule-key-deletion --key-id $KMS_KEY_ID --pending-window-in-days 7

# Delete IAM role
aws iam delete-role-policy --role-name HarborS3Role --policy-name HarborS3Access
aws iam delete-role --role-name HarborS3Role

# Delete OIDC provider
OIDC_PROVIDER_ARN=$(aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[0].Arn' --output text)
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn $OIDC_PROVIDER_ARN

# Delete EKS cluster
eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION
```

---

## Appendix: Reference Materials

### A. IAM Policy Examples

#### Minimal S3 Read-Only Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::BUCKET_NAME",
        "arn:aws:s3:::BUCKET_NAME/*"
      ]
    }
  ]
}
```

#### S3 with CloudWatch Logs

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::BUCKET_NAME",
        "arn:aws:s3:::BUCKET_NAME/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
```

### B. Kubernetes Manifests

#### Service Account with IRSA

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-service-account
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/AppRole
```

#### Pod Using Service Account

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-pod
  namespace: default
spec:
  serviceAccountName: app-service-account
  containers:
  - name: app
    image: myapp:latest
    env:
    - name: AWS_REGION
      value: us-east-1
```


### C. AWS CLI Commands Reference

#### EKS Commands

```bash
# Create EKS cluster
eksctl create cluster --name CLUSTER_NAME --region REGION --with-oidc

# Get cluster info
aws eks describe-cluster --name CLUSTER_NAME

# Update kubeconfig
aws eks update-kubeconfig --name CLUSTER_NAME --region REGION

# List clusters
aws eks list-clusters

# Delete cluster
eksctl delete cluster --name CLUSTER_NAME
```

#### IAM Commands

```bash
# Create role
aws iam create-role --role-name ROLE_NAME --assume-role-policy-document file://trust-policy.json

# Attach policy
aws iam put-role-policy --role-name ROLE_NAME --policy-name POLICY_NAME --policy-document file://policy.json

# Get role
aws iam get-role --role-name ROLE_NAME

# List roles
aws iam list-roles

# Delete role
aws iam delete-role-policy --role-name ROLE_NAME --policy-name POLICY_NAME
aws iam delete-role --role-name ROLE_NAME
```

#### S3 Commands

```bash
# Create bucket
aws s3api create-bucket --bucket BUCKET_NAME --region REGION

# Enable versioning
aws s3api put-bucket-versioning --bucket BUCKET_NAME --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption --bucket BUCKET_NAME --server-side-encryption-configuration '...'

# List objects
aws s3 ls s3://BUCKET_NAME/

# Delete bucket
aws s3 rm s3://BUCKET_NAME --recursive
aws s3api delete-bucket --bucket BUCKET_NAME
```

#### KMS Commands

```bash
# Create key
aws kms create-key --description "Description"

# Create alias
aws kms create-alias --alias-name alias/NAME --target-key-id KEY_ID

# Enable rotation
aws kms enable-key-rotation --key-id KEY_ID

# Get key policy
aws kms get-key-policy --key-id KEY_ID --policy-name default

# Schedule deletion
aws kms schedule-key-deletion --key-id KEY_ID --pending-window-in-days 7
```

### D. Terraform Module Examples

#### EKS Module Usage

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "harbor-irsa-workshop"
  cluster_version = "1.28"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  eks_managed_node_groups = {
    general = {
      desired_size = 2
      min_size     = 1
      max_size     = 4

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
    }
  }

  tags = {
    Environment = "workshop"
    Project     = "harbor-irsa"
  }
}
```


#### IRSA Module Usage

```hcl
module "irsa_harbor" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "HarborS3Role"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["harbor:harbor-registry"]
    }
  }

  role_policy_arns = {
    policy = aws_iam_policy.harbor_s3_access.arn
  }

  tags = {
    Environment = "workshop"
    Project     = "harbor-irsa"
  }
}
```

### E. Helm Values Reference

#### Complete Harbor Values

```yaml
expose:
  type: loadBalancer
  tls:
    enabled: true
    certSource: auto
  loadBalancer:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"

externalURL: https://harbor.example.com

persistence:
  enabled: true
  persistentVolumeClaim:
    registry:
      storageClass: gp3
      size: 100Gi
    chartmuseum:
      storageClass: gp3
      size: 10Gi
    jobservice:
      storageClass: gp3
      size: 10Gi
    database:
      storageClass: gp3
      size: 10Gi
    redis:
      storageClass: gp3
      size: 10Gi

imageChartStorage:
  type: s3
  s3:
    region: us-east-1
    bucket: harbor-registry-storage-ACCOUNT-REGION
    encrypt: true
    secure: true
    v4auth: true
    chunksize: "5242880"
    rootdirectory: /harbor

serviceAccount:
  create: false
  name: harbor-registry

core:
  serviceAccountName: harbor-registry
  replicas: 2
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

registry:
  serviceAccountName: harbor-registry
  replicas: 2
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

jobservice:
  serviceAccountName: harbor-registry
  replicas: 2
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

trivy:
  enabled: true
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 1Gi
      cpu: 1000m
```

### F. Security Checklist

Use this checklist to verify your IRSA implementation:

#### IRSA Configuration
- [ ] OIDC provider enabled on EKS cluster
- [ ] OIDC provider registered in IAM
- [ ] IAM role created with trust policy
- [ ] Trust policy restricts to specific namespace and service account
- [ ] Trust policy includes `aud` condition for `sts.amazonaws.com`
- [ ] Service account annotated with role ARN
- [ ] Pods use annotated service account

#### IAM Permissions
- [ ] IAM policy follows least privilege
- [ ] Policy restricts to specific S3 bucket
- [ ] Policy includes only required S3 actions
- [ ] KMS permissions included if using encryption
- [ ] KMS permissions restricted with `kms:ViaService` condition
- [ ] No wildcard permissions granted
- [ ] Permission boundary applied (if required)

#### Encryption
- [ ] S3 bucket has default encryption enabled
- [ ] KMS customer managed key created
- [ ] KMS key rotation enabled
- [ ] KMS key policy restricts usage to Harbor role
- [ ] S3 bucket policy enforces encryption
- [ ] S3 bucket policy requires TLS

#### Access Control
- [ ] S3 bucket public access blocked
- [ ] S3 bucket versioning enabled
- [ ] Network policies restrict pod communication
- [ ] RBAC limits service account access
- [ ] Unauthorized service accounts denied access

#### Audit and Monitoring
- [ ] CloudTrail enabled in region
- [ ] CloudTrail logs show IRSA identity
- [ ] Can trace actions to specific pods
- [ ] CloudWatch alarms configured
- [ ] IAM Access Analyzer enabled

#### Validation
- [ ] No static credentials in pods
- [ ] Harbor successfully accesses S3
- [ ] Unauthorized access denied
- [ ] Credentials automatically rotate
- [ ] All tests passing


### G. Additional Resources

#### AWS Documentation
- [IAM Roles for Service Accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Amazon EKS Security Best Practices](https://docs.aws.amazon.com/eks/latest/userguide/best-practices-security.html)
- [AWS KMS Best Practices](https://docs.aws.amazon.com/kms/latest/developerguide/best-practices.html)
- [S3 Security Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [CloudTrail User Guide](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/)

#### Harbor Documentation
- [Harbor Installation Guide](https://goharbor.io/docs/latest/install-config/)
- [Harbor S3 Storage Configuration](https://goharbor.io/docs/latest/install-config/configure-yml-file/#storage)
- [Harbor Security](https://goharbor.io/docs/latest/administration/security/)

#### Kubernetes Documentation
- [Service Accounts](https://kubernetes.io/docs/concepts/security/service-accounts/)
- [Configure Service Accounts for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)

#### Security Frameworks
- [STRIDE Threat Modeling](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats)
- [MITRE ATT&CK Framework](https://attack.mitre.org/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NIST Container Security](https://csrc.nist.gov/publications/detail/sp/800-190/final)

#### Tools and Utilities
- [eksctl](https://eksctl.io/) - EKS cluster management
- [kubectl](https://kubernetes.io/docs/reference/kubectl/) - Kubernetes CLI
- [Helm](https://helm.sh/) - Kubernetes package manager
- [Terraform](https://www.terraform.io/) - Infrastructure as Code
- [AWS CLI](https://aws.amazon.com/cli/) - AWS command line interface

#### Community Resources
- [AWS Containers Blog](https://aws.amazon.com/blogs/containers/)
- [Kubernetes Blog](https://kubernetes.io/blog/)
- [Harbor Community](https://github.com/goharbor/harbor)
- [CNCF Security TAG](https://github.com/cncf/tag-security)

### H. Glossary

| Term | Definition |
|------|------------|
| **IRSA** | IAM Roles for Service Accounts - AWS feature for Kubernetes workload identity |
| **OIDC** | OpenID Connect - Identity federation protocol |
| **JWT** | JSON Web Token - Compact token format for identity claims |
| **Service Account** | Kubernetes identity for pods |
| **Trust Policy** | IAM policy defining who can assume a role |
| **Permissions Policy** | IAM policy defining what actions are allowed |
| **KMS** | AWS Key Management Service |
| **CMK** | Customer Managed Key - KMS key you control |
| **SSE-KMS** | Server-Side Encryption with KMS |
| **CloudTrail** | AWS audit logging service |
| **AssumeRoleWithWebIdentity** | STS API for OIDC-based role assumption |
| **Projected Volume** | Kubernetes volume type for service account tokens |
| **Least Privilege** | Security principle of minimal permissions |
| **Defense in Depth** | Layered security approach |

---

## Workshop Completion Certificate

**Congratulations!**

You have successfully completed the **Harbor IRSA Workshop: Securing Container Registries on Amazon EKS**.

**Skills Acquired:**
- ✅ IRSA implementation and configuration
- ✅ Kubernetes security best practices
- ✅ AWS IAM least privilege policies
- ✅ KMS encryption for data protection
- ✅ CloudTrail audit log analysis
- ✅ Infrastructure as Code with Terraform
- ✅ Security validation and testing

**Date Completed:** _________________

**Instructor/Facilitator:** _________________

---

## Feedback and Contributions

We welcome your feedback and contributions to improve this workshop!

### Provide Feedback
- **GitHub Issues**: Report bugs or suggest improvements
- **Pull Requests**: Contribute fixes or enhancements
- **Discussions**: Share your experience and ask questions

### Contact Information
- **GitHub Repository**: https://github.com/yourusername/secure-harbor-irsa-on-eks
- **Email**: your.email@example.com
- **LinkedIn**: Your LinkedIn Profile
- **Medium**: Your Medium Profile

---

**Thank you for completing this workshop!**

We hope you found it valuable and will apply these security best practices in your production environments.

**Remember**: Security is not a one-time task but an ongoing practice. Stay vigilant, keep learning, and always follow the principle of least privilege.

**Happy securing! 🔒🚀**

---

*This lab guide is part of the Harbor IRSA Workshop project.*  
*Version 1.0 | December 2025*  
*Licensed under MIT License*

