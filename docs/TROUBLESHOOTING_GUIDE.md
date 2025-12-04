# Harbor IRSA Workshop Troubleshooting Guide

## Overview

This comprehensive troubleshooting guide helps you diagnose and resolve common issues encountered during the Harbor IRSA Workshop. Issues are organized by component and include symptoms, root causes, diagnostic steps, and solutions.

## Quick Diagnostic Checklist

Before diving into specific issues, run through this quick checklist:

```bash
# 1. Verify EKS cluster is running
aws eks describe-cluster --name <cluster-name> --query 'cluster.status'

# 2. Check OIDC provider exists
aws eks describe-cluster --name <cluster-name> --query 'cluster.identity.oidc.issuer'
aws iam list-open-id-connect-providers

# 3. Verify IAM role exists
aws iam get-role --role-name HarborS3Role

# 4. Check service account annotation
kubectl get sa harbor-registry -n harbor -o yaml | grep eks.amazonaws.com/role-arn

# 5. Verify Harbor pods are running
kubectl get pods -n harbor

# 6. Check S3 bucket exists
aws s3 ls s3://<bucket-name>

# 7. Verify KMS key is enabled
aws kms describe-key --key-id alias/harbor-s3-encryption --query 'KeyMetadata.KeyState'
```

## Table of Contents

1. [EKS Cluster Issues](#eks-cluster-issues)
2. [OIDC Provider Issues](#oidc-provider-issues)
3. [IAM Role and Policy Issues](#iam-role-and-policy-issues)
4. [Service Account Issues](#service-account-issues)
5. [Harbor Deployment Issues](#harbor-deployment-issues)
6. [S3 Access Issues](#s3-access-issues)
7. [KMS Encryption Issues](#kms-encryption-issues)
8. [Terraform Issues](#terraform-issues)
9. [CloudTrail and Logging Issues](#cloudtrail-and-logging-issues)
10. [Network and Connectivity Issues](#network-and-connectivity-issues)

---

## EKS Cluster Issues

### Issue 1.1: EKS Cluster Creation Fails

**Symptoms**:
- Terraform fails with "insufficient permissions" error
- CloudFormation stack for EKS fails
- Cluster stuck in "CREATING" state

**Root Causes**:
- Insufficient IAM permissions for user/role creating cluster
- VPC/subnet configuration issues
- Service quotas exceeded


**Diagnostic Steps**:
```bash
# Check IAM permissions
aws sts get-caller-identity
aws iam get-user --user-name <your-username>

# Check VPC and subnet configuration
aws ec2 describe-vpcs
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>"

# Check service quotas
aws service-quotas get-service-quota --service-code eks --quota-code L-1194D53C
```

**Solutions**:
1. **Insufficient Permissions**: Ensure user has `eks:CreateCluster`, `iam:CreateRole`, `ec2:*` permissions
2. **VPC Issues**: Ensure VPC has DNS hostnames and DNS resolution enabled
3. **Subnet Issues**: Ensure subnets are in at least 2 availability zones
4. **Quota Issues**: Request quota increase via AWS Service Quotas console

**Prevention**:
- Use a dedicated IAM role with AdministratorAccess for workshop setup
- Pre-validate VPC configuration before cluster creation
- Check quotas before starting workshop

### Issue 1.2: Cannot Connect to EKS Cluster with kubectl

**Symptoms**:
- `kubectl` commands fail with "connection refused"
- `kubectl get nodes` returns "Unable to connect to the server"
- Authentication errors when running kubectl commands

**Root Causes**:
- kubeconfig not configured correctly
- AWS CLI credentials not set
- Cluster endpoint not accessible
- IAM permissions missing for cluster access

**Diagnostic Steps**:
```bash
# Check current kubectl context
kubectl config current-context

# Verify kubeconfig
cat ~/.kube/config

# Test AWS credentials
aws sts get-caller-identity

# Check cluster endpoint
aws eks describe-cluster --name <cluster-name> --query 'cluster.endpoint'
```

**Solutions**:
```bash
# Update kubeconfig
aws eks update-kubeconfig --name <cluster-name> --region <region>

# Verify connection
kubectl get svc

# If still failing, check IAM permissions
aws eks describe-cluster --name <cluster-name>
```

**Prevention**:
- Always run `aws eks update-kubeconfig` after cluster creation
- Ensure AWS CLI is configured with correct region
- Verify IAM user/role has `eks:DescribeCluster` permission

---

## OIDC Provider Issues

### Issue 2.1: OIDC Provider Not Found

**Symptoms**:
- Error: "OpenIDConnect provider not found"
- IAM role assumption fails
- Pods cannot access AWS services

**Root Causes**:
- OIDC provider not created in IAM
- OIDC provider URL mismatch
- Cluster created without OIDC enabled

**Diagnostic Steps**:
```bash
# Get cluster OIDC issuer URL
OIDC_URL=$(aws eks describe-cluster --name <cluster-name> --query 'cluster.identity.oidc.issuer' --output text)
echo $OIDC_URL

# List OIDC providers
aws iam list-open-id-connect-providers

# Check if provider exists for this cluster
OIDC_ID=$(echo $OIDC_URL | cut -d '/' -f 5)
aws iam get-open-id-connect-provider --open-id-connect-provider-arn arn:aws:iam::<account-id>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/$OIDC_ID
```

**Solutions**:
```bash
# Create OIDC provider
eksctl utils associate-iam-oidc-provider --cluster <cluster-name> --approve

# Or manually create with AWS CLI
OIDC_URL=$(aws eks describe-cluster --name <cluster-name> --query 'cluster.identity.oidc.issuer' --output text)
OIDC_ID=$(echo $OIDC_URL | cut -d '/' -f 5)

# Get thumbprint
THUMBPRINT=$(echo | openssl s_client -servername oidc.eks.<region>.amazonaws.com -showcerts -connect oidc.eks.<region>.amazonaws.com:443 2>&- | tac | sed -n '/-----END CERTIFICATE-----/,/-----BEGIN CERTIFICATE-----/p; /-----BEGIN CERTIFICATE-----/q' | tac | openssl x509 -fingerprint -noout | sed 's/://g' | awk -F= '{print tolower($2)}')

# Create provider
aws iam create-open-id-connect-provider \
  --url $OIDC_URL \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list $THUMBPRINT
```

**Prevention**:
- Always enable OIDC when creating EKS cluster
- Use Terraform or eksctl which handle OIDC creation automatically
- Verify OIDC provider exists before creating IAM roles

### Issue 2.2: OIDC Thumbprint Mismatch

**Symptoms**:
- Token validation fails
- "Invalid identity token" errors
- Role assumption fails intermittently

**Root Causes**:
- Incorrect thumbprint in OIDC provider configuration
- Certificate rotation on AWS side
- Manual thumbprint entry error

**Diagnostic Steps**:
```bash
# Get current thumbprint from OIDC provider
aws iam get-open-id-connect-provider --open-id-connect-provider-arn <provider-arn> --query 'ThumbprintList'

# Calculate correct thumbprint
echo | openssl s_client -servername oidc.eks.<region>.amazonaws.com -showcerts -connect oidc.eks.<region>.amazonaws.com:443 2>&- | tac | sed -n '/-----END CERTIFICATE-----/,/-----BEGIN CERTIFICATE-----/p; /-----BEGIN CERTIFICATE-----/q' | tac | openssl x509 -fingerprint -noout | sed 's/://g' | awk -F= '{print tolower($2)}'
```

**Solutions**:
```bash
# Update thumbprint
aws iam update-open-id-connect-provider-thumbprint \
  --open-id-connect-provider-arn <provider-arn> \
  --thumbprint-list <new-thumbprint>
```

**Prevention**:
- Use automated tools (eksctl, Terraform) that calculate thumbprint correctly
- Document thumbprint calculation process
- Monitor for certificate rotation announcements from AWS

---

## IAM Role and Policy Issues

### Issue 3.1: "Access Denied" When Assuming Role

**Symptoms**:
- Error: "User: arn:aws:sts::ACCOUNT:assumed-role/... is not authorized to perform: sts:AssumeRoleWithWebIdentity"
- Pods cannot access AWS services
- CloudTrail shows failed AssumeRoleWithWebIdentity attempts

**Root Causes**:
- Trust policy doesn't match service account
- OIDC provider ARN incorrect in trust policy
- Condition in trust policy too restrictive

**Diagnostic Steps**:
```bash
# Get IAM role trust policy
aws iam get-role --role-name HarborS3Role --query 'Role.AssumeRolePolicyDocument'

# Get service account details
kubectl get sa harbor-registry -n harbor -o yaml

# Get pod's service account token and decode
kubectl exec -n harbor <pod> -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token | cut -d '.' -f 2 | base64 -d | jq .

# Test role assumption manually
TOKEN=$(kubectl exec -n harbor <pod> -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token)
aws sts assume-role-with-web-identity \
  --role-arn arn:aws:iam::<account>:role/HarborS3Role \
  --role-session-name test \
  --web-identity-token $TOKEN
```

**Solutions**:
1. **Fix Trust Policy Subject**:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:harbor:harbor-registry",
        "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:aud": "sts.amazonaws.com"
      }
    }
  }]
}
```

2. **Update Trust Policy**:
```bash
# Create trust policy JSON file
cat > trust-policy.json << EOF
{... trust policy ...}
EOF

# Update role
aws iam update-assume-role-policy --role-name HarborS3Role --policy-document file://trust-policy.json
```

**Prevention**:
- Use Terraform variables to ensure consistency
- Double-check namespace and service account names
- Test role assumption before deploying application

### Issue 3.2: "Access Denied" for S3 Operations

**Symptoms**:
- Harbor can assume role but cannot access S3
- Error: "Access Denied" when uploading/downloading images
- CloudTrail shows denied S3 API calls

**Root Causes**:
- IAM permissions policy missing required S3 actions
- S3 bucket policy denying access
- KMS permissions missing
- Resource ARN mismatch

**Diagnostic Steps**:
```bash
# Check IAM role permissions
aws iam list-attached-role-policies --role-name HarborS3Role
aws iam get-policy-version --policy-arn <policy-arn> --version-id v1

# Check S3 bucket policy
aws s3api get-bucket-policy --bucket <bucket-name>

# Test S3 access from pod
kubectl exec -n harbor <pod> -- aws s3 ls s3://<bucket-name>/
kubectl exec -n harbor <pod> -- aws s3 cp /tmp/test.txt s3://<bucket-name>/test.txt

# Check CloudTrail for specific error
aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=<bucket-name> --max-results 5
```

**Solutions**:
1. **Add Missing S3 Permissions**:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ],
    "Resource": [
      "arn:aws:s3:::bucket-name",
      "arn:aws:s3:::bucket-name/*"
    ]
  }]
}
```

2. **Update IAM Policy**:
```bash
aws iam put-role-policy --role-name HarborS3Role --policy-name HarborS3Access --policy-document file://permissions-policy.json
```

**Prevention**:
- Start with comprehensive permissions and restrict later
- Test each S3 operation individually
- Use AWS IAM Policy Simulator to validate policies

### Issue 3.3: KMS "Access Denied" Errors

**Symptoms**:
- S3 operations fail with KMS-related errors
- Error: "Access Denied" when accessing encrypted objects
- Harbor cannot upload encrypted objects

**Root Causes**:
- IAM role missing KMS permissions
- KMS key policy doesn't allow Harbor role
- Condition in KMS policy too restrictive

**Diagnostic Steps**:
```bash
# Check IAM role KMS permissions
aws iam get-role-policy --role-name HarborS3Role --policy-name HarborS3Access | jq '.PolicyDocument.Statement[] | select(.Action[] | contains("kms"))'

# Check KMS key policy
aws kms get-key-policy --key-id alias/harbor-s3-encryption --policy-name default

# Test KMS access
kubectl exec -n harbor <pod> -- aws kms describe-key --key-id alias/harbor-s3-encryption
```

**Solutions**:
1. **Add KMS Permissions to IAM Role**:
```json
{
  "Effect": "Allow",
  "Action": [
    "kms:Decrypt",
    "kms:GenerateDataKey",
    "kms:DescribeKey"
  ],
  "Resource": "arn:aws:kms:REGION:ACCOUNT:key/KEY_ID",
  "Condition": {
    "StringEquals": {
      "kms:ViaService": "s3.REGION.amazonaws.com"
    }
  }
}
```

2. **Update KMS Key Policy**:
```json
{
  "Sid": "Allow Harbor Role",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::ACCOUNT:role/HarborS3Role"
  },
  "Action": [
    "kms:Decrypt",
    "kms:GenerateDataKey"
  ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "kms:ViaService": "s3.REGION.amazonaws.com"
    }
  }
}
```

**Prevention**:
- Always grant KMS permissions when using encrypted S3 buckets
- Use `kms:ViaService` condition to restrict key usage to S3
- Test encryption/decryption before deploying Harbor

---

## Service Account Issues

### Issue 4.1: Service Account Missing Role Annotation

**Symptoms**:
- Pods cannot access AWS services
- Error: "Unable to locate credentials"
- Environment variables AWS_ROLE_ARN not set in pod

**Root Causes**:
- Service account created without annotation
- Annotation has typo or incorrect format
- Service account in wrong namespace

**Diagnostic Steps**:
```bash
# Check service account
kubectl get sa harbor-registry -n harbor -o yaml

# Check if annotation exists
kubectl get sa harbor-registry -n harbor -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# Check pod environment variables
kubectl exec -n harbor <pod> -- env | grep AWS
```

**Solutions**:
```bash
# Add annotation to existing service account
kubectl annotate sa harbor-registry -n harbor eks.amazonaws.com/role-arn=arn:aws:iam::<account>:role/HarborS3Role

# Or recreate service account
kubectl delete sa harbor-registry -n harbor
kubectl create sa harbor-registry -n harbor
kubectl annotate sa harbor-registry -n harbor eks.amazonaws.com/role-arn=arn:aws:iam::<account>:role/HarborS3Role

# Restart pods to pick up changes
kubectl rollout restart deployment/harbor-registry -n harbor
```

**Prevention**:
- Use Helm values or Kubernetes manifests with annotation included
- Validate service account before deploying application
- Use Terraform to manage service accounts with annotations

### Issue 4.2: Pod Not Using Correct Service Account

**Symptoms**:
- Service account has annotation but pod still cannot access AWS
- Pod using default service account instead of custom one
- AWS_ROLE_ARN environment variable not set

**Root Causes**:
- Pod spec doesn't reference service account
- Deployment/StatefulSet not updated after service account creation
- Typo in service account name

**Diagnostic Steps**:
```bash
# Check which service account pod is using
kubectl get pod <pod> -n harbor -o jsonpath='{.spec.serviceAccountName}'

# Check pod spec
kubectl get pod <pod> -n harbor -o yaml | grep serviceAccountName

# Check deployment spec
kubectl get deployment harbor-registry -n harbor -o yaml | grep serviceAccountName
```

**Solutions**:
```bash
# Update deployment to use correct service account
kubectl patch deployment harbor-registry -n harbor -p '{"spec":{"template":{"spec":{"serviceAccountName":"harbor-registry"}}}}'

# Or edit deployment directly
kubectl edit deployment harbor-registry -n harbor
# Add: spec.template.spec.serviceAccountName: harbor-registry

# Restart pods
kubectl rollout restart deployment/harbor-registry -n harbor
```

**Prevention**:
- Always specify serviceAccountName in pod spec
- Use Helm charts that properly configure service accounts
- Validate pod spec before deployment

---

## Harbor Deployment Issues

### Issue 5.1: Harbor Pods Stuck in Pending State

**Symptoms**:
- Harbor pods show "Pending" status
- `kubectl describe pod` shows "Insufficient resources" or "FailedScheduling"
- Cluster has no available nodes or resources

**Diagnostic Steps**:
```bash
# Check pod status
kubectl get pods -n harbor

# Describe pending pod
kubectl describe pod <pod> -n harbor

# Check node resources
kubectl top nodes
kubectl describe nodes
```

**Solutions**:
1. **Insufficient Resources**: Scale up node group or add more nodes
2. **Node Selector Mismatch**: Remove or fix node selectors in pod spec
3. **Taints/Tolerations**: Add tolerations if nodes are tainted

**Prevention**:
- Ensure cluster has sufficient capacity before deploying Harbor
- Use t3.medium or larger instances for Harbor
- Monitor resource usage

### Issue 5.2: Harbor Pods CrashLoopBackOff

**Symptoms**:
- Pods repeatedly crash and restart
- Status shows "CrashLoopBackOff"
- Harbor UI not accessible

**Diagnostic Steps**:
```bash
# Check pod logs
kubectl logs <pod> -n harbor
kubectl logs <pod> -n harbor --previous

# Check pod events
kubectl describe pod <pod> -n harbor

# Check Harbor configuration
kubectl get configmap -n harbor
kubectl get secret -n harbor
```

**Solutions**:
- Check logs for specific error messages
- Verify S3 configuration in Harbor values
- Ensure database is accessible
- Check resource limits aren't too restrictive

**Prevention**:
- Test Harbor configuration before deployment
- Use recommended resource limits
- Monitor pod logs during initial deployment

---

## S3 Access Issues

### Issue 6.1: S3 Bucket Not Found

**Symptoms**:
- Error: "The specified bucket does not exist"
- Harbor cannot initialize storage backend
- S3 operations fail with 404 errors

**Diagnostic Steps**:
```bash
# Check if bucket exists
aws s3 ls s3://<bucket-name>

# Check bucket region
aws s3api get-bucket-location --bucket <bucket-name>

# Verify Harbor configuration
kubectl get configmap harbor-core -n harbor -o yaml | grep -A 10 storage
```

**Solutions**:
```bash
# Create bucket if missing
aws s3 mb s3://<bucket-name> --region <region>

# Update Harbor configuration with correct bucket name
kubectl edit configmap harbor-core -n harbor
# Update bucket name

# Restart Harbor pods
kubectl rollout restart deployment/harbor-core -n harbor
```

**Prevention**:
- Create S3 bucket before deploying Harbor
- Use consistent naming convention
- Verify bucket exists in Terraform outputs

### Issue 6.2: S3 Region Mismatch

**Symptoms**:
- Slow S3 operations
- Intermittent connection errors
- "PermanentRedirect" errors

**Diagnostic Steps**:
```bash
# Check bucket region
aws s3api get-bucket-location --bucket <bucket-name>

# Check Harbor S3 configuration
kubectl exec -n harbor <pod> -- env | grep AWS_REGION

# Check Harbor config
kubectl get configmap harbor-core -n harbor -o yaml | grep region
```

**Solutions**:
```bash
# Set correct region in Harbor configuration
# Update Helm values or configmap with correct region

# Ensure AWS_REGION environment variable is set
kubectl set env deployment/harbor-core -n harbor AWS_REGION=<correct-region>
```

**Prevention**:
- Always specify region in Harbor S3 configuration
- Use same region for EKS cluster and S3 bucket
- Set AWS_DEFAULT_REGION environment variable

---

## KMS Encryption Issues

### Issue 7.1: KMS Key Not Found

**Symptoms**:
- Error: "Key 'arn:aws:kms:...' does not exist"
- S3 encryption operations fail
- Cannot upload objects to S3

**Diagnostic Steps**:
```bash
# Check if key exists
aws kms describe-key --key-id alias/harbor-s3-encryption

# List KMS keys
aws kms list-keys
aws kms list-aliases

# Check S3 bucket encryption
aws s3api get-bucket-encryption --bucket <bucket-name>
```

**Solutions**:
```bash
# Create KMS key if missing
aws kms create-key --description "Harbor S3 encryption key"

# Create alias
aws kms create-alias --alias-name alias/harbor-s3-encryption --target-key-id <key-id>

# Update S3 bucket encryption
aws s3api put-bucket-encryption --bucket <bucket-name> --server-side-encryption-configuration '{
  "Rules": [{
    "ApplyServerSideEncryptionByDefault": {
      "SSEAlgorithm": "aws:kms",
      "KMSMasterKeyID": "alias/harbor-s3-encryption"
    }
  }]
}'
```

**Prevention**:
- Create KMS key before S3 bucket
- Use Terraform to manage KMS keys
- Verify key exists before configuring S3 encryption

### Issue 7.2: KMS Key Disabled

**Symptoms**:
- Error: "Key is disabled"
- Cannot decrypt existing objects
- S3 operations fail with KMS errors

**Diagnostic Steps**:
```bash
# Check key state
aws kms describe-key --key-id alias/harbor-s3-encryption --query 'KeyMetadata.KeyState'

# Check key policy
aws kms get-key-policy --key-id alias/harbor-s3-encryption --policy-name default
```

**Solutions**:
```bash
# Enable key
aws kms enable-key --key-id <key-id>

# Verify key is enabled
aws kms describe-key --key-id alias/harbor-s3-encryption
```

**Prevention**:
- Never manually disable KMS keys used for production
- Set up CloudWatch alarms for key state changes
- Use key policies to prevent accidental disabling

---

## Terraform Issues

### Issue 8.1: Terraform State Lock

**Symptoms**:
- Error: "Error locking state: Error acquiring the state lock"
- Cannot run terraform plan or apply
- State file locked by another process

**Diagnostic Steps**:
```bash
# Check if state is locked
terraform force-unlock <lock-id>

# Check S3 backend configuration
cat backend.tf

# Check DynamoDB lock table
aws dynamodb scan --table-name terraform-state-lock
```

**Solutions**:
```bash
# Force unlock (use with caution)
terraform force-unlock <lock-id>

# If using local state, remove lock file
rm .terraform.tfstate.lock.info
```

**Prevention**:
- Don't run multiple terraform operations simultaneously
- Use remote state with locking
- Clean up locks after failed operations

### Issue 8.2: Terraform Resource Already Exists

**Symptoms**:
- Error: "Resource already exists"
- Terraform apply fails
- Resources created outside Terraform

**Diagnostic Steps**:
```bash
# Check if resource exists in AWS
aws eks describe-cluster --name <cluster-name>
aws iam get-role --role-name HarborS3Role

# Check Terraform state
terraform state list
terraform state show <resource-name>
```

**Solutions**:
```bash
# Import existing resource
terraform import aws_eks_cluster.main <cluster-name>
terraform import aws_iam_role.harbor_s3 HarborS3Role

# Or remove from AWS and let Terraform recreate
aws eks delete-cluster --name <cluster-name>
```

**Prevention**:
- Always use Terraform for infrastructure management
- Import existing resources before managing with Terraform
- Use unique resource names

---

## CloudTrail and Logging Issues

### Issue 9.1: CloudTrail Events Not Appearing

**Symptoms**:
- Cannot find S3 access events in CloudTrail
- Logs delayed or missing
- Cannot verify IRSA identity in logs

**Diagnostic Steps**:
```bash
# Check CloudTrail is enabled
aws cloudtrail describe-trails

# Check trail status
aws cloudtrail get-trail-status --name <trail-name>

# Query recent events
aws cloudtrail lookup-events --max-results 10

# Check S3 bucket for CloudTrail logs
aws s3 ls s3://<cloudtrail-bucket>/AWSLogs/<account-id>/CloudTrail/
```

**Solutions**:
1. **Wait for Propagation**: CloudTrail events can take 5-15 minutes to appear
2. **Enable CloudTrail**: If not enabled, create a trail
3. **Check Data Events**: Ensure S3 data events are enabled if needed

**Prevention**:
- Enable CloudTrail before starting workshop
- Explain delay to participants
- Use CloudWatch Events for real-time notifications

### Issue 9.2: Cannot Find IRSA Identity in Logs

**Symptoms**:
- CloudTrail logs don't show assumed role
- Cannot trace access to specific pod
- User identity shows wrong information

**Diagnostic Steps**:
```bash
# Query for AssumeRoleWithWebIdentity events
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity

# Query for S3 events
aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=<bucket-name>

# Check event details
aws cloudtrail lookup-events --max-results 1 | jq '.Events[0].CloudTrailEvent' | jq -r . | jq .
```

**Solutions**:
- Look for `userIdentity.principalId` containing assumed role ARN
- Check `userIdentity.sessionContext.sessionIssuer.userName` for role name
- Verify events are recent (within last 90 days)

**Prevention**:
- Generate test events and verify they appear correctly
- Document expected log format for participants
- Provide example CloudTrail queries

---

## Network and Connectivity Issues

### Issue 10.1: Cannot Access Harbor UI

**Symptoms**:
- Harbor UI not accessible via LoadBalancer
- Connection timeout or refused
- DNS resolution fails

**Diagnostic Steps**:
```bash
# Check Harbor service
kubectl get svc -n harbor

# Get LoadBalancer URL
kubectl get svc harbor -n harbor -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Check if LoadBalancer is provisioned
aws elbv2 describe-load-balancers

# Test connectivity
curl -I http://<loadbalancer-url>
```

**Solutions**:
1. **LoadBalancer Not Provisioned**: Wait for AWS to provision (can take 5-10 minutes)
2. **Security Group Issues**: Check security groups allow inbound traffic on port 80/443
3. **DNS Propagation**: Wait for DNS to propagate

**Prevention**:
- Allow time for LoadBalancer provisioning
- Pre-configure security groups
- Use kubectl port-forward for immediate access

### Issue 10.2: Pods Cannot Reach S3

**Symptoms**:
- S3 operations timeout
- Network errors when accessing S3
- Intermittent connectivity issues

**Diagnostic Steps**:
```bash
# Test S3 connectivity from pod
kubectl exec -n harbor <pod> -- curl -I https://s3.amazonaws.com

# Check VPC endpoints
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=<vpc-id>"

# Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<vpc-id>"

# Check security groups
kubectl get pod <pod> -n harbor -o yaml | grep securityContext
```

**Solutions**:
1. **Create VPC Endpoint**: Create S3 VPC endpoint for better performance
2. **Check NAT Gateway**: Ensure NAT gateway exists for private subnets
3. **Security Groups**: Verify security groups allow outbound HTTPS

**Prevention**:
- Use VPC endpoints for S3 access
- Ensure proper VPC networking configuration
- Test connectivity before deploying Harbor

---

## Frequently Asked Questions (FAQ)

### Q1: How long does it take for IRSA to start working after configuration?

**A**: IRSA should work immediately after:
1. Service account annotation is added
2. Pod is restarted (to pick up new environment variables)
3. IAM role trust policy is updated

If it's not working, check each component systematically.

### Q2: Can I use the same IAM role for multiple service accounts?

**A**: Yes, but you need to update the trust policy to include all service accounts:
```json
"Condition": {
  "StringEquals": {
    "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:sub": [
      "system:serviceaccount:namespace1:sa1",
      "system:serviceaccount:namespace2:sa2"
    ]
  }
}
```

However, it's better to use separate roles for better isolation and least privilege.

### Q3: How do I rotate the JWT token manually?

**A**: You don't need to! The kubelet automatically rotates the token before expiration. If you need to force a refresh, restart the pod:
```bash
kubectl rollout restart deployment/<deployment> -n <namespace>
```

### Q4: Can I use IRSA with non-AWS SDK applications?

**A**: Yes, but the application must support the AWS credential provider chain and web identity token flow. Most modern AWS SDKs support this. For custom applications, you may need to implement the token exchange logic.

### Q5: What happens if the OIDC provider is deleted?

**A**: All IRSA authentication will fail immediately. Pods will not be able to assume IAM roles. You'll need to recreate the OIDC provider with the same configuration.

### Q6: How do I debug "Unable to locate credentials" errors?

**A**: Follow this checklist:
1. Check service account has annotation
2. Verify pod is using correct service account
3. Check AWS_ROLE_ARN and AWS_WEB_IDENTITY_TOKEN_FILE environment variables are set
4. Verify token file exists at /var/run/secrets/eks.amazonaws.com/serviceaccount/token
5. Test role assumption manually with the token
6. Check IAM role trust policy matches service account

### Q7: Can I use IRSA with Fargate?

**A**: Yes! IRSA works with both EC2 and Fargate pods. The configuration is identical.

### Q8: How do I monitor IRSA usage?

**A**: Use CloudTrail to monitor:
- AssumeRoleWithWebIdentity events (role assumptions)
- AWS API calls with assumed role identity
- Failed authentication attempts

Set up CloudWatch alarms for failed assumptions or unusual access patterns.

### Q9: What's the cost of using IRSA?

**A**: IRSA itself has no additional cost. You only pay for:
- AWS STS API calls (very low cost, usually free tier)
- CloudTrail logging (if enabled)
- Standard AWS service costs (S3, KMS, etc.)

### Q10: Can I use IRSA across AWS accounts?

**A**: Yes! Update the IAM role trust policy to allow the OIDC provider from another account, and ensure the role has appropriate permissions. This is useful for multi-account architectures.

---

## Getting Help

If you're still experiencing issues after following this guide:

1. **Check AWS Documentation**: [IRSA Technical Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
2. **Review Workshop Materials**: Re-read relevant sections of the workshop guide
3. **Check Logs**: Always check pod logs, CloudTrail, and Kubernetes events
4. **Ask for Help**: Reach out to workshop instructor or AWS support
5. **Community Resources**: EKS GitHub issues, AWS forums, Stack Overflow

## Conclusion

Most IRSA issues fall into a few categories:
- Configuration mismatches (trust policy, service account, annotations)
- Missing permissions (IAM policies, KMS key policies)
- Timing issues (CloudTrail delay, token expiration)

By systematically checking each component and following the diagnostic steps in this guide, you should be able to resolve most issues quickly. Remember: IRSA is designed to be simple and secure - if something seems overly complicated, you're probably missing a simple configuration step.
