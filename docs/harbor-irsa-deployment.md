# Harbor Deployment with IRSA on EKS

## Overview

This guide walks you through deploying Harbor container registry on Amazon EKS using IAM Roles for Service Accounts (IRSA) for secure, credential-free access to S3 backend storage. This is the secure, production-ready approach that eliminates static credentials.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Step 1: Create Kubernetes Namespace](#step-1-create-kubernetes-namespace)
3. [Step 2: Create Kubernetes Service Account](#step-2-create-kubernetes-service-account)
4. [Step 3: Prepare Harbor Helm Values](#step-3-prepare-harbor-helm-values)
5. [Step 4: Deploy Harbor with Helm](#step-4-deploy-harbor-with-helm)
6. [Step 5: Verify Deployment](#step-5-verify-deployment)
7. [Step 6: Validate IRSA Configuration](#step-6-validate-irsa-configuration)
8. [Step 7: Access Harbor UI](#step-7-access-harbor-ui)
9. [Troubleshooting](#troubleshooting)

## Prerequisites

Before starting, ensure you have completed:

- ✅ [OIDC Provider Setup](./oidc-provider-setup.md)
- ✅ [IAM Role and Policy Configuration](./iam-role-policy-setup.md)
- ✅ [S3 and KMS Setup](./s3-kms-setup.md)

### Required Tools

- **kubectl** v1.28+ configured for your EKS cluster
- **Helm** v3.x installed
- **AWS CLI** v2.x installed and configured

### Environment Variables

Set these from previous steps:

```bash
export CLUSTER_NAME="harbor-irsa-workshop"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export HARBOR_NAMESPACE="harbor"
export HARBOR_SERVICE_ACCOUNT="harbor-registry"
export HARBOR_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/HarborS3Role"
export S3_BUCKET_NAME="harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION}"

echo "Harbor Namespace: ${HARBOR_NAMESPACE}"
echo "Service Account: ${HARBOR_SERVICE_ACCOUNT}"
echo "IAM Role ARN: ${HARBOR_ROLE_ARN}"
echo "S3 Bucket: ${S3_BUCKET_NAME}"
```

## Step 1: Create Kubernetes Namespace

### 1.1 Create the Namespace

```bash
# Create namespace for Harbor
kubectl create namespace ${HARBOR_NAMESPACE}

# Verify namespace creation
kubectl get namespace ${HARBOR_NAMESPACE}
```

**Expected output:**
```
NAME     STATUS   AGE
harbor   Active   5s
```

### 1.2 Label the Namespace (Optional)

Adding labels helps with organization and policy enforcement:

```bash
# Add labels to namespace
kubectl label namespace ${HARBOR_NAMESPACE} \
  app=harbor \
  security=irsa-enabled \
  environment=workshop

# Verify labels
kubectl get namespace ${HARBOR_NAMESPACE} --show-labels
```

## Step 2: Create Kubernetes Service Account

The service account is the key component that links Kubernetes to AWS IAM through IRSA.

### 2.1 Create Service Account with IAM Role Annotation

Create a file `harbor-service-account.yaml`:

```bash
cat > harbor-service-account.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${HARBOR_SERVICE_ACCOUNT}
  namespace: ${HARBOR_NAMESPACE}
  annotations:
    eks.amazonaws.com/role-arn: ${HARBOR_ROLE_ARN}
  labels:
    app: harbor
    component: registry
EOF
```

### 2.2 Understanding the Service Account

Let's examine the key components:

```yaml
metadata:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/HarborS3Role
```

This annotation is **critical** for IRSA:
- **Key**: `eks.amazonaws.com/role-arn`
- **Value**: The ARN of the IAM role created earlier
- **Purpose**: Tells the EKS pod identity webhook to inject AWS credentials

When a pod uses this service account:
1. EKS mutating webhook intercepts pod creation
2. Webhook injects environment variables (`AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE`)
3. Webhook mounts projected service account token at `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
4. AWS SDK automatically discovers and uses these credentials

### 2.3 Apply the Service Account

```bash
# Create the service account
kubectl apply -f harbor-service-account.yaml

# Verify service account creation
kubectl get serviceaccount ${HARBOR_SERVICE_ACCOUNT} -n ${HARBOR_NAMESPACE}

# View service account details including annotation
kubectl describe serviceaccount ${HARBOR_SERVICE_ACCOUNT} -n ${HARBOR_NAMESPACE}
```

**Expected output:**
```
Name:                harbor-registry
Namespace:           harbor
Labels:              app=harbor
                     component=registry
Annotations:         eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/HarborS3Role
Image pull secrets:  <none>
Mountable secrets:   <none>
Tokens:              <none>
Events:              <none>
```

✅ **Checkpoint**: Verify the `eks.amazonaws.com/role-arn` annotation is present and correct.

## Step 3: Prepare Harbor Helm Values

Harbor's Helm chart requires specific configuration to use IRSA instead of static credentials.

### 3.1 Add Harbor Helm Repository

```bash
# Add Harbor Helm repository
helm repo add harbor https://helm.goharbor.io

# Update Helm repositories
helm repo update

# Verify Harbor chart is available
helm search repo harbor/harbor
```

**Expected output:**
```
NAME            CHART VERSION   APP VERSION     DESCRIPTION
harbor/harbor   1.13.1          2.9.1           An open source trusted cloud native registry...
```

### 3.2 Create Harbor Helm Values File

Create a file `harbor-irsa-values.yaml`:

```bash
cat > harbor-irsa-values.yaml << EOF
# Harbor Helm Values - SECURE IRSA CONFIGURATION
# This configuration uses IRSA for credential-free S3 access

# Expose Harbor via LoadBalancer
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

# External URL (will be updated after LoadBalancer is created)
externalURL: https://harbor.${AWS_REGION}.elb.amazonaws.com

# Persistence configuration
persistence:
  enabled: true
  resourcePolicy: "keep"
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

# ============================================
# S3 Storage Backend - IRSA CONFIGURATION
# ============================================
imageChartStorage:
  # Disable local filesystem storage
  disableredirect: false
  
  # Use S3 as backend storage
  type: s3
  
  s3:
    # S3 bucket configuration
    region: ${AWS_REGION}
    bucket: ${S3_BUCKET_NAME}
    
    # ✅ NO STATIC CREDENTIALS!
    # IRSA provides credentials automatically via service account
    # accesskey: NOT SPECIFIED
    # secretkey: NOT SPECIFIED
    
    # S3 endpoint (leave empty for standard AWS S3)
    regionendpoint: ""
    
    # ✅ ENCRYPTION ENABLED
    # Use SSE-KMS encryption with customer-managed key
    encrypt: true
    
    # ✅ SECURE TRANSPORT
    # Always use HTTPS
    secure: true
    
    # Use AWS Signature Version 4 for authentication
    v4auth: true
    
    # Chunk size for multipart uploads (5MB)
    chunksize: "5242880"
    
    # Root directory in S3 bucket
    rootdirectory: /harbor
    
    # S3 storage class
    storageclass: STANDARD
    
    # Multipart upload configuration
    multipartcopychunksize: "33554432"
    multipartcopymaxconcurrency: 100
    multipartcopythresholdsize: "33554432"

# Harbor admin password (change this!)
harborAdminPassword: "Harbor12345"

# ============================================
# SERVICE ACCOUNT CONFIGURATION - CRITICAL!
# ============================================
# This links Harbor pods to the IAM role via IRSA
serviceAccount:
  # Do not create a new service account (we created it manually)
  create: false
  
  # Use the service account we created with IAM role annotation
  name: ${HARBOR_SERVICE_ACCOUNT}

# Configure each Harbor component to use the service account
core:
  serviceAccountName: ${HARBOR_SERVICE_ACCOUNT}

registry:
  serviceAccountName: ${HARBOR_SERVICE_ACCOUNT}

jobservice:
  serviceAccountName: ${HARBOR_SERVICE_ACCOUNT}

# Disable Notary (not needed for this workshop)
notary:
  enabled: false

# Enable Trivy vulnerability scanning
trivy:
  enabled: true

# Use internal PostgreSQL database
database:
  type: internal
  internal:
    serviceAccountName: ${HARBOR_SERVICE_ACCOUNT}

# Use internal Redis
redis:
  type: internal
  internal:
    serviceAccountName: ${HARBOR_SERVICE_ACCOUNT}

# Disable metrics for this workshop
metrics:
  enabled: false

# Resource limits (adjust based on your needs)
core:
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

registry:
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

jobservice:
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m
EOF
```

### 3.3 Understanding the Key Configuration

Let's highlight the critical IRSA-specific settings:

**No Static Credentials:**
```yaml
imageChartStorage:
  type: s3
  s3:
    region: us-east-1
    bucket: harbor-registry-storage-123456789012-us-east-1
    # ✅ NO accesskey or secretkey specified!
    # IRSA provides credentials automatically
```

**Service Account Configuration:**
```yaml
serviceAccount:
  create: false  # We created it manually with IAM annotation
  name: harbor-registry  # Use our IRSA-enabled service account

# Apply to all components
core:
  serviceAccountName: harbor-registry
registry:
  serviceAccountName: harbor-registry
jobservice:
  serviceAccountName: harbor-registry
```

**Encryption Enabled:**
```yaml
s3:
  encrypt: true  # Use SSE-KMS encryption
  secure: true   # Use HTTPS
```

## Step 4: Deploy Harbor with Helm

### 4.1 Validate Configuration

Before deploying, validate the Helm values:

```bash
# Dry-run to check for errors
helm install harbor harbor/harbor \
  --namespace ${HARBOR_NAMESPACE} \
  --values harbor-irsa-values.yaml \
  --dry-run \
  --debug
```

Review the output for any errors or warnings.

### 4.2 Install Harbor

```bash
# Install Harbor
helm install harbor harbor/harbor \
  --namespace ${HARBOR_NAMESPACE} \
  --values harbor-irsa-values.yaml \
  --version 1.13.1 \
  --timeout 10m

echo "✅ Harbor installation initiated"
```

**Expected output:**
```
NAME: harbor
LAST DEPLOYED: Mon Jan 15 10:45:00 2024
NAMESPACE: harbor
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Please wait for several minutes for Harbor deployment to complete.
Then you should be able to visit the Harbor portal at https://harbor.us-east-1.elb.amazonaws.com
```

### 4.3 Monitor Deployment Progress

```bash
# Watch pod status
kubectl get pods -n ${HARBOR_NAMESPACE} -w

# Or check status periodically
watch kubectl get pods -n ${HARBOR_NAMESPACE}
```

Wait for all pods to reach `Running` status. This may take 5-10 minutes.

**Expected output (after completion):**
```
NAME                                    READY   STATUS    RESTARTS   AGE
harbor-core-7d8f9c8b5d-x7k2m           1/1     Running   0          5m
harbor-database-0                       1/1     Running   0          5m
harbor-jobservice-6b9d8f7c5d-9h4k3     1/1     Running   0          5m
harbor-portal-5c8d7b6f4d-2n8m9         1/1     Running   0          5m
harbor-redis-0                          1/1     Running   0          5m
harbor-registry-7f9d8c6b5d-4k7n2       2/2     Running   0          5m
harbor-trivy-0                          1/1     Running   0          5m
```

### 4.4 Check for Errors

If any pods are not running:

```bash
# Check pod events
kubectl describe pod <pod-name> -n ${HARBOR_NAMESPACE}

# Check pod logs
kubectl logs <pod-name> -n ${HARBOR_NAMESPACE}

# For registry pod (has 2 containers)
kubectl logs <registry-pod-name> -n ${HARBOR_NAMESPACE} -c registry
kubectl logs <registry-pod-name> -n ${HARBOR_NAMESPACE} -c registryctl
```

## Step 5: Verify Deployment

### 5.1 Check All Resources

```bash
# Check all Harbor resources
kubectl get all -n ${HARBOR_NAMESPACE}

# Check services
kubectl get svc -n ${HARBOR_NAMESPACE}

# Check persistent volume claims
kubectl get pvc -n ${HARBOR_NAMESPACE}
```

### 5.2 Get LoadBalancer URL

```bash
# Get the LoadBalancer external hostname
export HARBOR_URL=$(kubectl get svc harbor -n ${HARBOR_NAMESPACE} \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Harbor URL: https://${HARBOR_URL}"

# Save for later use
echo ${HARBOR_URL} > harbor-url.txt
```

**Note**: It may take a few minutes for the LoadBalancer DNS to propagate.

### 5.3 Update External URL (Optional)

If you want to update Harbor's external URL configuration:

```bash
# Update the Helm release with the actual LoadBalancer URL
helm upgrade harbor harbor/harbor \
  --namespace ${HARBOR_NAMESPACE} \
  --reuse-values \
  --set externalURL=https://${HARBOR_URL}
```

## Step 6: Validate IRSA Configuration

This is the critical step to verify IRSA is working correctly.

### 6.1 Verify Service Account Token Projection

Check that the service account token is mounted in the pod:

```bash
# Get a registry pod name
REGISTRY_POD=$(kubectl get pod -n ${HARBOR_NAMESPACE} \
  -l component=registry \
  -o jsonpath='{.items[0].metadata.name}')

echo "Registry Pod: ${REGISTRY_POD}"

# Check for projected service account token
kubectl exec -n ${HARBOR_NAMESPACE} ${REGISTRY_POD} -c registry -- \
  ls -la /var/run/secrets/eks.amazonaws.com/serviceaccount/

# View the token (it's a JWT)
kubectl exec -n ${HARBOR_NAMESPACE} ${REGISTRY_POD} -c registry -- \
  cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token | head -c 100
```

**Expected output:**
```
total 0
drwxrwxrwt 3 root root  120 Jan 15 10:45 .
drwxr-xr-x 3 root root 4096 Jan 15 10:45 ..
drwxr-xr-x 2 root root   80 Jan 15 10:45 ..2024_01_15_10_45_00.123456789
lrwxrwxrwx 1 root root   31 Jan 15 10:45 ..data -> ..2024_01_15_10_45_00.123456789
lrwxrwxrwx 1 root root   13 Jan 15 10:45 token -> ..data/token

eyJhbGciOiJSUzI1NiIsImtpZCI6IjEyMzQ1Njc4OTAifQ.eyJhdWQiOlsic3RzLmFtYXpvbmF3cy5jb20iXSwi...
```

✅ **Checkpoint**: The token file exists and contains a JWT.

### 6.2 Verify AWS Environment Variables

Check that EKS injected the necessary environment variables:

```bash
# Check AWS-related environment variables
kubectl exec -n ${HARBOR_NAMESPACE} ${REGISTRY_POD} -c registry -- \
  env | grep AWS

# Should see:
# AWS_ROLE_ARN=arn:aws:iam::123456789012:role/HarborS3Role
# AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
# AWS_REGION=us-east-1 (if set)
```

**Expected output:**
```
AWS_ROLE_ARN=arn:aws:iam::123456789012:role/HarborS3Role
AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

✅ **Checkpoint**: Both environment variables are present.

### 6.3 Verify No Static Credentials

Confirm that NO static credentials are present:

```bash
# Check for static credentials (should return nothing)
kubectl exec -n ${HARBOR_NAMESPACE} ${REGISTRY_POD} -c registry -- \
  env | grep -E "AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY"

# If this returns nothing, that's GOOD! No static credentials.
```

✅ **Checkpoint**: No static credentials found.

### 6.4 Test S3 Access from Pod

Test that the pod can actually access S3 using IRSA:

```bash
# Install AWS CLI in the pod (if not already present)
kubectl exec -n ${HARBOR_NAMESPACE} ${REGISTRY_POD} -c registry -- \
  sh -c "command -v aws || (apk add --no-cache aws-cli 2>/dev/null || apt-get update && apt-get install -y awscli)"

# Test S3 access
kubectl exec -n ${HARBOR_NAMESPACE} ${REGISTRY_POD} -c registry -- \
  aws s3 ls s3://${S3_BUCKET_NAME}/

# Test S3 write
kubectl exec -n ${HARBOR_NAMESPACE} ${REGISTRY_POD} -c registry -- \
  sh -c "echo 'IRSA test' | aws s3 cp - s3://${S3_BUCKET_NAME}/test-irsa.txt"

# Verify file was created
kubectl exec -n ${HARBOR_NAMESPACE} ${REGISTRY_POD} -c registry -- \
  aws s3 ls s3://${S3_BUCKET_NAME}/test-irsa.txt
```

**Expected output:**
```
2024-01-15 10:50:00         10 test-irsa.txt
```

✅ **Checkpoint**: Pod can read and write to S3 without static credentials!

### 6.5 Check Harbor Registry Logs

Verify Harbor is using S3 successfully:

```bash
# Check registry logs for S3 operations
kubectl logs -n ${HARBOR_NAMESPACE} ${REGISTRY_POD} -c registry --tail=50

# Look for messages like:
# "storage driver: s3"
# "region: us-east-1"
# "bucket: harbor-registry-storage-..."
```

## Step 7: Access Harbor UI

### 7.1 Get Admin Credentials

```bash
# Default admin username
echo "Username: admin"

# Get admin password (from Helm values or secret)
echo "Password: Harbor12345"  # Or retrieve from secret:
kubectl get secret harbor-core -n ${HARBOR_NAMESPACE} \
  -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d
echo
```

### 7.2 Access Harbor Portal

```bash
# Get Harbor URL
echo "Harbor URL: https://${HARBOR_URL}"

# Open in browser (macOS)
open "https://${HARBOR_URL}"

# Or copy URL to clipboard
echo "https://${HARBOR_URL}" | pbcopy
```

**Note**: You may see a certificate warning because we're using a self-signed certificate. This is expected for the workshop.

### 7.3 Test Harbor Functionality

Once logged in:

1. **Create a new project**: Click "New Project" and create a test project
2. **Push a test image**:

```bash
# Log in to Harbor
docker login ${HARBOR_URL} -u admin -p Harbor12345

# Pull a small test image
docker pull nginx:alpine

# Tag for Harbor
docker tag nginx:alpine ${HARBOR_URL}/library/nginx:test

# Push to Harbor (this will use S3 via IRSA!)
docker push ${HARBOR_URL}/library/nginx:test
```

3. **Verify in S3**: Check that the image layers are stored in S3:

```bash
# List objects in S3 bucket
aws s3 ls s3://${S3_BUCKET_NAME}/harbor/ --recursive | head -20
```

You should see Docker image layers stored in S3!

## Troubleshooting

### Issue 1: Pods Not Starting

**Symptom:**
```
harbor-registry-xxx   0/2     Init:0/1   0          2m
```

**Solution:**
Check pod events and logs:
```bash
kubectl describe pod <pod-name> -n ${HARBOR_NAMESPACE}
kubectl logs <pod-name> -n ${HARBOR_NAMESPACE} -c <container-name>
```

Common causes:
- PVC not binding (check storage class)
- Image pull errors (check image pull secrets)
- Resource constraints (check node capacity)

### Issue 2: Cannot Access S3

**Symptom:**
```
Error: AccessDenied: Access Denied
```

**Solution:**
Verify IRSA configuration:

```bash
# Check service account annotation
kubectl get sa ${HARBOR_SERVICE_ACCOUNT} -n ${HARBOR_NAMESPACE} -o yaml

# Verify IAM role trust policy
aws iam get-role --role-name HarborS3Role --query 'Role.AssumeRolePolicyDocument'

# Check IAM role permissions
aws iam list-attached-role-policies --role-name HarborS3Role
```

### Issue 3: Service Account Token Not Mounted

**Symptom:**
```
Error: WebIdentityErr: failed to retrieve credentials
```

**Solution:**
Verify the pod is using the correct service account:

```bash
# Check pod's service account
kubectl get pod ${REGISTRY_POD} -n ${HARBOR_NAMESPACE} \
  -o jsonpath='{.spec.serviceAccountName}'

# Should output: harbor-registry
```

If incorrect, update Helm values and upgrade:
```bash
helm upgrade harbor harbor/harbor \
  --namespace ${HARBOR_NAMESPACE} \
  --reuse-values \
  --set registry.serviceAccountName=${HARBOR_SERVICE_ACCOUNT}
```

### Issue 4: KMS Decryption Errors

**Symptom:**
```
Error: AccessDenied: User is not authorized to perform: kms:Decrypt
```

**Solution:**
Verify KMS key policy allows the IAM role:

```bash
# Get KMS key policy
aws kms get-key-policy \
  --key-id <key-id> \
  --policy-name default \
  --query Policy \
  --output text | jq .
```

Ensure the policy includes the Harbor IAM role.

### Issue 5: LoadBalancer Not Getting External IP

**Symptom:**
```
harbor   LoadBalancer   10.100.200.50   <pending>   80:30002/TCP,443:30003/TCP   10m
```

**Solution:**
Check AWS Load Balancer Controller:

```bash
# Check if AWS Load Balancer Controller is installed
kubectl get deployment -n kube-system aws-load-balancer-controller

# Check service annotations
kubectl describe svc harbor -n ${HARBOR_NAMESPACE}
```

If the controller is not installed, you may need to install it or use `type: NodePort` instead.

## Verification Checklist

Before considering the deployment complete, verify:

- [ ] All Harbor pods are running
- [ ] Service account has IAM role annotation
- [ ] Pods have AWS environment variables injected
- [ ] Service account token is mounted in pods
- [ ] No static credentials in pod environment
- [ ] Pods can access S3 bucket
- [ ] Harbor UI is accessible
- [ ] Can push/pull images through Harbor
- [ ] Images are stored in S3 bucket
- [ ] S3 objects are encrypted with KMS

## Next Steps

Now that Harbor is deployed with IRSA, you can:

1. **[Run Validation Tests](../validation-tests/02-irsa-validation.sh)** - Comprehensive IRSA validation
2. **[Test Access Controls](../validation-tests/03-access-control.sh)** - Verify unauthorized access is denied
3. **[Review Audit Logs](../validation-tests/04-audit-logs.sh)** - Check CloudTrail for IRSA identity
4. **[Implement Security Hardening](./security-best-practices.md)** - Additional security measures

## Summary

You've successfully deployed Harbor on EKS with IRSA! Here's what you accomplished:

✅ Created Kubernetes namespace and service account with IAM role annotation  
✅ Configured Harbor Helm values for IRSA (no static credentials)  
✅ Deployed Harbor using Helm  
✅ Verified IRSA configuration (token projection, environment variables)  
✅ Tested S3 access from Harbor pods  
✅ Confirmed no static credentials are present  
✅ Validated Harbor can push/pull images using S3 backend  

Harbor is now running securely with:
- **No static credentials** stored anywhere
- **Automatic credential rotation** every hour
- **Least-privilege IAM policies** for S3 and KMS access
- **Strong identity binding** to specific service account
- **Encryption at rest** with KMS customer-managed keys
- **Full audit trail** in CloudTrail

---

**Next**: [Validation Tests](../validation-tests/02-irsa-validation.sh)
