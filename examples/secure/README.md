# Secure IRSA Configuration Examples

This directory contains example configuration files for deploying Harbor on EKS with IAM Roles for Service Accounts (IRSA). These are production-ready configurations that implement security best practices.

## Files Overview

### Kubernetes Resources

- **[service-account.yaml](./service-account.yaml)** - Kubernetes service account with IAM role annotation
  - Enables IRSA for Harbor pods
  - Links to IAM role via annotation
  - Used by all Harbor components

- **[harbor-values-irsa.yaml](./harbor-values-irsa.yaml)** - Harbor Helm chart values
  - Configures S3 backend storage without static credentials
  - Enables encryption and secure transport
  - References the IRSA-enabled service account

### IAM Policies

- **[iam-role-trust-policy.json](./iam-role-trust-policy.json)** - IAM role trust policy
  - Allows OIDC provider to assume the role
  - Restricts to specific namespace and service account
  - Validates audience claim

- **[iam-role-permissions-policy.json](./iam-role-permissions-policy.json)** - IAM role permissions policy
  - Grants least-privilege S3 access
  - Grants KMS access for encryption
  - Scoped to specific bucket and key

### Storage Configuration

- **[kms-key-policy.json](./kms-key-policy.json)** - KMS customer managed key policy
  - Allows Harbor role to encrypt/decrypt
  - Allows S3 service to use the key
  - Restricts usage via conditions

- **[s3-bucket-policy.json](./s3-bucket-policy.json)** - S3 bucket policy
  - Enforces encryption at rest
  - Enforces encryption in transit (TLS)
  - Denies unencrypted uploads

## Usage Instructions

### Prerequisites

1. EKS cluster with OIDC provider configured
2. AWS CLI and kubectl installed
3. Helm 3.x installed
4. IAM permissions to create roles and policies

### Step 1: Customize Configuration Files

Replace the following placeholders in all files:

- `123456789012` → Your AWS account ID
- `us-east-1` → Your AWS region
- `EXAMPLED539D4633E53DE1B71EXAMPLE` → Your EKS OIDC provider ID
- `harbor-registry-storage-123456789012-us-east-1` → Your S3 bucket name
- `12345678-1234-1234-1234-123456789012` → Your KMS key ID

### Step 2: Create KMS Key

```bash
# Create KMS key with policy
aws kms create-key \
  --description "KMS key for Harbor S3 bucket encryption" \
  --key-usage ENCRYPT_DECRYPT \
  --origin AWS_KMS \
  --policy file://kms-key-policy.json

# Create alias
aws kms create-alias \
  --alias-name alias/harbor-s3-encryption \
  --target-key-id <KEY_ID>

# Enable automatic rotation
aws kms enable-key-rotation --key-id <KEY_ID>
```

### Step 3: Create S3 Bucket

```bash
# Create bucket
aws s3api create-bucket \
  --bucket harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION} \
  --region ${AWS_REGION}

# Block public access
aws s3api put-public-access-block \
  --bucket harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION} \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION} \
  --server-side-encryption-configuration file://s3-encryption-config.json

# Apply bucket policy
aws s3api put-bucket-policy \
  --bucket harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION} \
  --policy file://s3-bucket-policy.json

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION} \
  --versioning-configuration Status=Enabled
```

### Step 4: Create IAM Role

```bash
# Create IAM permissions policy
aws iam create-policy \
  --policy-name HarborS3AccessPolicy \
  --policy-document file://iam-role-permissions-policy.json

# Create IAM role with trust policy
aws iam create-role \
  --role-name HarborS3Role \
  --assume-role-policy-document file://iam-role-trust-policy.json

# Attach permissions policy to role
aws iam attach-role-policy \
  --role-name HarborS3Role \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/HarborS3AccessPolicy
```

### Step 5: Create Kubernetes Service Account

```bash
# Create namespace
kubectl create namespace harbor

# Apply service account
kubectl apply -f service-account.yaml
```

### Step 6: Deploy Harbor

```bash
# Add Harbor Helm repository
helm repo add harbor https://helm.goharbor.io
helm repo update

# Install Harbor
helm install harbor harbor/harbor \
  --namespace harbor \
  --values harbor-values-irsa.yaml \
  --version 1.13.1
```

### Step 7: Verify Deployment

```bash
# Check pods
kubectl get pods -n harbor

# Verify service account annotation
kubectl get sa harbor-registry -n harbor -o yaml

# Check for AWS environment variables in pod
kubectl exec -n harbor <registry-pod> -c registry -- env | grep AWS

# Test S3 access
kubectl exec -n harbor <registry-pod> -c registry -- \
  aws s3 ls s3://harbor-registry-storage-${AWS_ACCOUNT_ID}-${AWS_REGION}/
```

## Security Features

### No Static Credentials

✅ No AWS access keys stored in Kubernetes secrets  
✅ No credentials in environment variables  
✅ No credentials in Helm values  
✅ Credentials provided automatically via IRSA  

### Automatic Credential Rotation

✅ JWT tokens expire every 24 hours  
✅ AWS credentials expire every hour  
✅ Automatic renewal without pod restart  
✅ No manual rotation required  

### Least Privilege Access

✅ IAM policy scoped to specific S3 bucket  
✅ IAM policy limited to required actions only  
✅ KMS access restricted via conditions  
✅ Trust policy bound to specific service account  

### Encryption

✅ Encryption at rest with KMS CMK  
✅ Encryption in transit enforced by bucket policy  
✅ Automatic key rotation enabled  
✅ Bucket policy denies unencrypted uploads  

### Defense in Depth

✅ Multiple security layers (IAM, KMS, S3 policies)  
✅ Namespace isolation  
✅ Service account binding  
✅ Audit trail in CloudTrail  

## Troubleshooting

### Service Account Token Not Mounted

**Check**: Pod is using the correct service account
```bash
kubectl get pod <pod-name> -n harbor -o jsonpath='{.spec.serviceAccountName}'
```

**Fix**: Update Helm values to use correct service account

### Cannot Access S3

**Check**: IAM role trust policy
```bash
aws iam get-role --role-name HarborS3Role --query 'Role.AssumeRolePolicyDocument'
```

**Fix**: Ensure trust policy includes correct OIDC provider and service account

### KMS Decryption Errors

**Check**: KMS key policy
```bash
aws kms get-key-policy --key-id <KEY_ID> --policy-name default
```

**Fix**: Ensure key policy allows Harbor IAM role

## Additional Resources

- [OIDC Provider Setup Guide](../../docs/oidc-provider-setup.md)
- [IAM Role Configuration Guide](../../docs/iam-role-policy-setup.md)
- [S3 and KMS Setup Guide](../../docs/s3-kms-setup.md)
- [Harbor Deployment Guide](../../docs/harbor-irsa-deployment.md)

## Security Best Practices

1. **Change default passwords**: Update `harborAdminPassword` in Helm values
2. **Use specific KMS key**: Replace wildcard in permissions policy with specific key ARN
3. **Enable CloudTrail**: Monitor all S3 and KMS API calls
4. **Regular audits**: Review IAM policies and S3 bucket policies quarterly
5. **Least privilege**: Only grant permissions that Harbor actually needs
6. **Network policies**: Implement Kubernetes network policies for pod isolation
7. **Pod security**: Use Pod Security Standards to restrict pod capabilities

## Cost Optimization

- **Enable S3 Bucket Key**: Reduces KMS API calls by 99%
- **Lifecycle policies**: Transition old versions to cheaper storage
- **Delete old versions**: Remove unnecessary data after retention period
- **Monitor usage**: Use AWS Cost Explorer to track costs

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review the detailed guides in the `docs/` directory
3. Open an issue in the GitHub repository

---

**⚠️ Security Note**: These configurations implement production-ready security best practices. Do not modify security settings without understanding the implications.
