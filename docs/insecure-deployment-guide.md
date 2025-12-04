# Insecure Harbor Deployment Guide: IAM User Tokens

## ⚠️ WARNING: This is an Anti-Pattern

This guide demonstrates the **INSECURE** approach to deploying Harbor on EKS using long-lived IAM user access keys. This method is documented for educational purposes to illustrate security risks and why IRSA is the superior approach.

**DO NOT use this approach in production environments.**

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Step 1: Create IAM User with Access Keys](#step-1-create-iam-user-with-access-keys)
4. [Step 2: Create S3 Bucket](#step-2-create-s3-bucket)
5. [Step 3: Create Kubernetes Secret](#step-3-create-kubernetes-secret)
6. [Step 4: Deploy Harbor with Helm](#step-4-deploy-harbor-with-helm)
7. [Step 5: Verify Deployment](#step-5-verify-deployment)
8. [Security Risks](#security-risks)

## Overview

This deployment approach uses:
- **IAM User** with long-lived access keys
- **Kubernetes Secrets** storing base64-encoded credentials
- **Environment Variables** injecting credentials into Harbor pods
- **Overprivileged IAM Policies** granting broad S3 access

### Architecture

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
│  │  │  │                                 │    │     │    │
│  │  │  │  Environment Variables:         │    │     │    │
│  │  │  │  AWS_ACCESS_KEY_ID (from secret)│    │     │    │
│  │  │  │  AWS_SECRET_ACCESS_KEY          │    │     │    │
│  │  │  └──────────────┬──────────────────┘    │     │    │
│  │  └─────────────────┼───────────────────────┘     │    │
│  └────────────────────┼─────────────────────────────┘    │
│                       │                                    │
│                       │ Static Credentials                 │
│                       │ (Long-lived, never rotated)        │
│                       ▼                                    │
│  ┌─────────────────────────────────────────────────────┐  │
│  │                  IAM User                            │  │
│  │  - harbor-s3-user                                    │  │
│  │  - Attached Policy: S3FullAccess (overprivileged)   │  │
│  └──────────────────────┬───────────────────────────────┘  │
│                         │                                   │
│                         ▼                                   │
│  ┌─────────────────────────────────────────────────────┐  │
│  │              S3 Bucket                               │  │
│  │  - harbor-registry-storage                           │  │
│  │  - No encryption or default SSE-S3                   │  │
│  │  - Overly permissive bucket policy                   │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## Prerequisites

- AWS CLI configured with administrative access
- kubectl configured for your EKS cluster
- Helm 3.x installed
- An existing EKS cluster

## Step 1: Create IAM User with Access Keys

### 1.1 Create the IAM User

```bash
# Create IAM user for Harbor
aws iam create-user --user-name harbor-s3-user

# Output:
# {
#     "User": {
#         "UserName": "harbor-s3-user",
#         "UserId": "AIDAXXXXXXXXXXXXXXXXX",
#         "Arn": "arn:aws:iam::123456789012:user/harbor-s3-user",
#         "CreateDate": "2024-01-15T10:30:00Z"
#     }
# }
```

### 1.2 Create IAM Policy for S3 Access

Create a policy file `harbor-s3-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "HarborS3FullAccess",
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "arn:aws:s3:::harbor-registry-storage",
        "arn:aws:s3:::harbor-registry-storage/*"
      ]
    }
  ]
}
```

**⚠️ Security Issue**: This policy grants full S3 access (`s3:*`), which is overprivileged. Harbor only needs `PutObject`, `GetObject`, `DeleteObject`, and `ListBucket`.

Apply the policy:

```bash
# Create the IAM policy
aws iam create-policy \
  --policy-name HarborS3FullAccess \
  --policy-document file://harbor-s3-policy.json

# Attach policy to user
aws iam attach-user-policy \
  --user-name harbor-s3-user \
  --policy-arn arn:aws:iam::123456789012:policy/HarborS3FullAccess
```

### 1.3 Generate Access Keys

```bash
# Create access keys for the user
aws iam create-access-key --user-name harbor-s3-user

# Output (SAVE THESE - they won't be shown again):
# {
#     "AccessKey": {
#         "UserName": "harbor-s3-user",
#         "AccessKeyId": "AKIAIOSFODNN7EXAMPLE",
#         "Status": "Active",
#         "SecretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
#         "CreateDate": "2024-01-15T10:35:00Z"
#     }
# }
```

**⚠️ Security Issue**: These credentials are long-lived and never expire. If compromised, they remain valid until manually rotated.

### 1.4 Store Credentials Securely (Temporarily)

```bash
# Export credentials as environment variables (for next steps)
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

**⚠️ Security Issue**: Credentials are now in shell history and environment variables, increasing exposure risk.

## Step 2: Create S3 Bucket

### 2.1 Create the Bucket

```bash
# Set your AWS region
export AWS_REGION="us-east-1"

# Create S3 bucket for Harbor storage
aws s3api create-bucket \
  --bucket harbor-registry-storage \
  --region ${AWS_REGION}

# Enable versioning (optional but recommended)
aws s3api put-bucket-versioning \
  --bucket harbor-registry-storage \
  --versioning-configuration Status=Enabled
```

### 2.2 Configure Bucket (Minimal Security)

```bash
# Block public access (at least do this!)
aws s3api put-public-access-block \
  --bucket harbor-registry-storage \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

**⚠️ Security Issue**: No encryption at rest configured. Data stored in plain text or with default SSE-S3 (AWS-managed keys).

## Step 3: Create Kubernetes Secret

### 3.1 Create Harbor Namespace

```bash
# Create namespace for Harbor
kubectl create namespace harbor
```

### 3.2 Create Secret with AWS Credentials

```bash
# Create Kubernetes secret containing AWS credentials
kubectl create secret generic harbor-s3-credentials \
  --from-literal=accesskey="${AWS_ACCESS_KEY_ID}" \
  --from-literal=secretkey="${AWS_SECRET_ACCESS_KEY}" \
  --namespace=harbor

# Verify secret was created
kubectl get secret harbor-s3-credentials -n harbor

# Output:
# NAME                      TYPE     DATA   AGE
# harbor-s3-credentials     Opaque   2      5s
```

**⚠️ Security Issue**: Kubernetes secrets are only base64-encoded, not encrypted. Anyone with `kubectl` access can decode them:

```bash
# Extract and decode the credentials (demonstration of vulnerability)
kubectl get secret harbor-s3-credentials -n harbor -o jsonpath='{.data.accesskey}' | base64 -d
# Output: AKIAIOSFODNN7EXAMPLE

kubectl get secret harbor-s3-credentials -n harbor -o jsonpath='{.data.secretkey}' | base64 -d
# Output: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

### 3.3 Inspect the Secret (Educational)

```bash
# View the secret in YAML format
kubectl get secret harbor-s3-credentials -n harbor -o yaml
```

Output:
```yaml
apiVersion: v1
data:
  accesskey: <base64-encoded-access-key-id>
  secretkey: <base64-encoded-secret-access-key>
kind: Secret
metadata:
  name: harbor-s3-credentials
  namespace: harbor
type: Opaque
```

**⚠️ Security Issue**: The base64 encoding is trivially reversible. This is not encryption.

## Step 4: Deploy Harbor with Helm

### 4.1 Add Harbor Helm Repository

```bash
# Add Harbor Helm chart repository
helm repo add harbor https://helm.goharbor.io

# Update Helm repositories
helm repo update
```

### 4.2 Create Helm Values File

Create `harbor-insecure-values.yaml`:

```yaml
# Harbor Helm Values - INSECURE CONFIGURATION
# This configuration uses static IAM credentials

expose:
  type: loadBalancer
  tls:
    enabled: true
    certSource: auto
  loadBalancer:
    name: harbor
    ports:
      httpPort: 80
      httpsPort: 443

# External URL (update with your LoadBalancer DNS)
externalURL: https://harbor.example.com

# Persistence configuration
persistence:
  enabled: true
  persistentVolumeClaim:
    registry:
      storageClass: "gp3"
      size: 100Gi
    chartmuseum:
      storageClass: "gp3"
      size: 10Gi
    jobservice:
      storageClass: "gp3"
      size: 10Gi
    database:
      storageClass: "gp3"
      size: 10Gi
    redis:
      storageClass: "gp3"
      size: 10Gi
    trivy:
      storageClass: "gp3"
      size: 10Gi

# S3 Storage Backend Configuration - INSECURE
imageChartStorage:
  type: s3
  s3:
    region: us-east-1
    bucket: harbor-registry-storage
    # ⚠️ SECURITY ISSUE: Static credentials from Kubernetes secret
    accesskey: AKIAIOSFODNN7EXAMPLE
    secretkey: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
    regionendpoint: ""
    encrypt: false  # ⚠️ SECURITY ISSUE: No encryption
    secure: true    # At least use HTTPS
    v4auth: true
    chunksize: "5242880"
    rootdirectory: /harbor
    storageclass: STANDARD

# Harbor admin password
harborAdminPassword: "Harbor12345"  # ⚠️ Change this!

# Disable some components for minimal deployment
notary:
  enabled: false

trivy:
  enabled: true

# Database configuration (internal PostgreSQL)
database:
  type: internal

# Redis configuration (internal)
redis:
  type: internal

# Metrics
metrics:
  enabled: false
```

**⚠️ Security Issues in this configuration:**
1. Static credentials hardcoded in values file
2. No encryption at rest (`encrypt: false`)
3. Credentials visible in Helm release history
4. Credentials may be committed to version control
5. No credential rotation mechanism

### 4.3 Deploy Harbor

```bash
# Install Harbor using Helm
helm install harbor harbor/harbor \
  --namespace harbor \
  --values harbor-insecure-values.yaml \
  --version 1.13.0

# Wait for deployment to complete
kubectl wait --for=condition=ready pod \
  --selector=app=harbor \
  --namespace=harbor \
  --timeout=600s
```

### 4.4 Monitor Deployment

```bash
# Watch pod status
kubectl get pods -n harbor -w

# Check Harbor core logs
kubectl logs -n harbor -l component=core --tail=50

# Check registry logs
kubectl logs -n harbor -l component=registry --tail=50
```

## Step 5: Verify Deployment

### 5.1 Get LoadBalancer URL

```bash
# Get the LoadBalancer external IP/hostname
kubectl get svc harbor -n harbor

# Output:
# NAME     TYPE           CLUSTER-IP      EXTERNAL-IP                                                              PORT(S)                      AGE
# harbor   LoadBalancer   10.100.200.50   a1b2c3d4e5f6g7h8i9j0.us-east-1.elb.amazonaws.com   80:30002/TCP,443:30003/TCP   5m
```

### 5.2 Access Harbor UI

```bash
# Get the external URL
export HARBOR_URL=$(kubectl get svc harbor -n harbor -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Harbor URL: https://${HARBOR_URL}"
echo "Username: admin"
echo "Password: Harbor12345"
```

Open the URL in your browser and log in with the admin credentials.

### 5.3 Test S3 Connectivity

```bash
# Push a test image to verify S3 storage works
docker login ${HARBOR_URL} -u admin -p Harbor12345

# Tag and push a test image
docker pull nginx:alpine
docker tag nginx:alpine ${HARBOR_URL}/library/nginx:test
docker push ${HARBOR_URL}/library/nginx:test

# Verify image appears in S3
aws s3 ls s3://harbor-registry-storage/harbor/ --recursive
```

### 5.4 Verify Credentials in Pod

```bash
# Exec into Harbor registry pod
REGISTRY_POD=$(kubectl get pod -n harbor -l component=registry -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it ${REGISTRY_POD} -n harbor -- env | grep AWS

# Output shows credentials in environment:
# AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
# AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

**⚠️ Security Issue**: Credentials are visible in the pod's environment variables.

## Security Risks

### 1. Credential Exposure

**Risk**: Static credentials stored in multiple locations:
- Kubernetes secrets (base64-encoded, not encrypted)
- Helm values files (may be in version control)
- Pod environment variables (visible via `kubectl exec`)
- Shell history (from export commands)

**Impact**: Anyone with cluster access can extract and misuse credentials.

### 2. No Automatic Rotation

**Risk**: Credentials never expire or rotate automatically.

**Impact**: 
- Compromised credentials remain valid indefinitely
- Manual rotation is error-prone and often neglected
- Increased window of opportunity for attackers

### 3. Overprivileged Access

**Risk**: IAM policy grants `s3:*` (full S3 access) instead of least privilege.

**Impact**:
- Attacker can delete all objects in bucket
- Attacker can modify bucket policies
- Lateral movement to other S3 operations

### 4. Poor Audit Trail

**Risk**: All S3 actions appear as the IAM user `harbor-s3-user`.

**Impact**:
- Cannot trace actions to specific pods or namespaces
- Difficult to investigate security incidents
- Poor compliance posture

### 5. Credential Sprawl

**Risk**: Same credentials might be copied to multiple locations for convenience.

**Impact**:
- Increased attack surface
- Difficult to track all credential copies
- Rotation becomes nearly impossible

### 6. No Encryption at Rest

**Risk**: S3 bucket has no encryption configured.

**Impact**:
- Data stored in plain text
- Compliance violations (GDPR, HIPAA, PCI-DSS)
- Increased risk if AWS account is compromised

## Next Steps

Now that you understand the security risks of this approach, proceed to:

1. **[STRIDE Threat Model](./insecure-threat-model.md)** - Detailed threat analysis
2. **[Credential Extraction Demo](./credential-extraction-demo.md)** - See how easy it is to steal credentials
3. **[Secure IRSA Deployment](./secure-deployment-guide.md)** - Learn the right way to do this

## Cleanup

To remove this insecure deployment:

```bash
# Delete Harbor installation
helm uninstall harbor -n harbor

# Delete namespace
kubectl delete namespace harbor

# Delete S3 bucket (remove all objects first)
aws s3 rm s3://harbor-registry-storage --recursive
aws s3api delete-bucket --bucket harbor-registry-storage

# Delete IAM user access keys
aws iam list-access-keys --user-name harbor-s3-user --query 'AccessKeyMetadata[].AccessKeyId' --output text | \
  xargs -I {} aws iam delete-access-key --user-name harbor-s3-user --access-key-id {}

# Detach policy from user
aws iam detach-user-policy \
  --user-name harbor-s3-user \
  --policy-arn arn:aws:iam::123456789012:policy/HarborS3FullAccess

# Delete IAM policy
aws iam delete-policy --policy-arn arn:aws:iam::123456789012:policy/HarborS3FullAccess

# Delete IAM user
aws iam delete-user --user-name harbor-s3-user
```

## Summary

This insecure deployment demonstrates why IAM user tokens are problematic:

❌ Static credentials that never rotate  
❌ Credentials stored in multiple insecure locations  
❌ Overprivileged IAM policies  
❌ Poor audit trail and attribution  
❌ No encryption at rest  
❌ High risk of credential theft and misuse  

**The secure alternative using IRSA addresses all these issues.**
