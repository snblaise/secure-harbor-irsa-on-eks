# Quick Deployment and Testing Guide

This guide provides step-by-step instructions to deploy and test the Harbor IRSA workshop.

## 📋 Prerequisites Checklist

Before you begin, ensure you have:

### Required Tools
- [ ] **AWS Account** with administrative access
- [ ] **AWS CLI** v2.x installed and configured
- [ ] **kubectl** v1.28+ installed
- [ ] **Terraform** v1.5+ installed
- [ ] **Helm** v3.x installed
- [ ] **Git** installed

### Verify Installation

```bash
# Check all tools are installed
aws --version          # Should show v2.x
kubectl version --client  # Should show v1.28+
terraform version      # Should show v1.5+
helm version          # Should show v3.x
git --version         # Any recent version

# Verify AWS credentials
aws sts get-caller-identity
```

### Set Up Environment

```bash
# Configure AWS credentials if not already done
aws configure
# Enter your AWS Access Key ID
# Enter your Secret Access Key
# Enter default region (e.g., us-east-1)
# Enter output format (json)

# Set environment variables
export AWS_REGION=us-east-1
export CLUSTER_NAME=harbor-irsa-workshop
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "AWS Account: $AWS_ACCOUNT_ID"
echo "AWS Region: $AWS_REGION"
```

## 🚀 Deployment Options

You have two deployment options:

### Option A: Automated Deployment (Fastest - 20 minutes)

**Best for:** Quick start, testing, demos

```bash
# 1. Clone the repository
git clone https://github.com/snblaise/secure-harbor-irsa-on-eks.git
cd secure-harbor-irsa-on-eks

# 2. Navigate to terraform directory
cd terraform

# 3. Copy and edit configuration
cp terraform.tfvars.example terraform.tfvars

# Edit the file (at minimum, change the harbor_admin_password)
nano terraform.tfvars  # or vim, code, etc.

# 4. Run the automated deployment script
cd ../scripts
chmod +x deploy-infrastructure.sh
./deploy-infrastructure.sh
```

The script will:
- ✅ Check all prerequisites
- ✅ Initialize Terraform
- ✅ Create EKS cluster with OIDC enabled
- ✅ Set up IAM roles with IRSA
- ✅ Create S3 bucket with KMS encryption
- ✅ Deploy Harbor with IRSA configuration
- ✅ Configure kubectl
- ✅ Display access information

**Time:** ~20 minutes

### Option B: Manual Step-by-Step (Best for Learning - 3-4 hours)

**Best for:** Understanding each component, learning IRSA concepts

```bash
# 1. Clone the repository
git clone https://github.com/snblaise/secure-harbor-irsa-on-eks.git
cd secure-harbor-irsa-on-eks

# 2. Follow the comprehensive workshop guide
# Start with the workshop lab guide
cat docs/WORKSHOP_LAB_GUIDE.md

# 3. Progress through each module:
# - Module 1: Understanding the insecure approach
# - Module 2: Setting up OIDC provider
# - Module 3: Configuring IAM roles
# - Module 4: Setting up S3 and KMS
# - Module 5: Deploying Harbor with IRSA
# - Module 6: Validation and testing
```

## 🧪 Testing and Validation

After deployment, run the validation tests to verify everything works correctly.

### Quick Validation

```bash
# Navigate to validation tests directory
cd validation-tests

# Make all test scripts executable
chmod +x *.sh

# Run the quick validation script
./validate-deployment.sh
```

### Comprehensive Test Suite

Run each test individually to understand what's being validated:

#### 1. Verify No Static Credentials

```bash
./test-no-static-credentials.sh
```

**What it tests:**
- ✅ No AWS credentials in Kubernetes secrets
- ✅ No AWS credentials in pod environment variables
- ✅ No hardcoded credentials in Helm values

**Expected result:** All checks should pass with no credentials found

#### 2. Verify IRSA Access Works

```bash
./test-irsa-access-validation.sh
```

**What it tests:**
- ✅ Service account has correct annotation
- ✅ Pod can access S3 using IRSA
- ✅ Temporary credentials are being used
- ✅ JWT token is projected into pod

**Expected result:** Harbor can successfully read/write to S3

#### 3. Verify Access Control

```bash
./test-access-denial.sh
```

**What it tests:**
- ✅ Unauthorized service accounts cannot access S3
- ✅ Pods without IRSA annotation are denied
- ✅ Access is scoped to specific namespace

**Expected result:** Unauthorized access attempts are denied

#### 4. Verify Audit Trail

```bash
./test-log-verification.sh
```

**What it tests:**
- ✅ CloudTrail logs show AssumedRole (not IAM user)
- ✅ Logs include service account identity
- ✅ Pod-level attribution is visible

**Expected result:** CloudTrail logs show detailed pod identity

#### 5. Verify Credential Rotation

```bash
./test-credential-rotation.sh
```

**What it tests:**
- ✅ JWT tokens have expiration time
- ✅ Tokens are set to auto-rotate
- ✅ No manual rotation required

**Expected result:** Tokens expire in ~24 hours and auto-rotate

#### 6. Verify Infrastructure Best Practices

```bash
./test-infrastructure-best-practices.sh
```

**What it tests:**
- ✅ S3 bucket has encryption enabled (SSE-KMS)
- ✅ S3 bucket has versioning enabled
- ✅ S3 bucket blocks public access
- ✅ KMS key has proper key policy
- ✅ IAM role has least-privilege permissions

**Expected result:** All security best practices are implemented

### Run All Tests

```bash
# Run all validation tests at once
for test in test-*.sh; do
    echo "Running $test..."
    ./"$test"
    echo "---"
done
```

## 🔍 Verify Deployment Manually

### Check EKS Cluster

```bash
# Get cluster info
kubectl cluster-info

# List nodes
kubectl get nodes

# Check OIDC provider
aws eks describe-cluster --name $CLUSTER_NAME \
  --query "cluster.identity.oidc.issuer" --output text
```

### Check Harbor Deployment

```bash
# Check Harbor namespace
kubectl get ns harbor

# Check Harbor pods
kubectl get pods -n harbor

# Check Harbor services
kubectl get svc -n harbor

# Check service account
kubectl get sa harbor-registry -n harbor -o yaml
```

### Check IRSA Configuration

```bash
# Verify service account annotation
kubectl get sa harbor-registry -n harbor \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# Check IAM role exists
aws iam get-role --role-name HarborS3Role

# Check IAM role trust policy
aws iam get-role --role-name HarborS3Role \
  --query 'Role.AssumeRolePolicyDocument' --output json
```

### Check S3 and KMS

```bash
# List S3 buckets (find Harbor bucket)
aws s3 ls | grep harbor

# Check bucket encryption
aws s3api get-bucket-encryption --bucket <harbor-bucket-name>

# List KMS keys
aws kms list-aliases | grep harbor
```

### Access Harbor UI

```bash
# Get Harbor URL
kubectl get svc -n harbor harbor-portal \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Get admin password
kubectl get secret -n harbor harbor-core \
  -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 --decode && echo
```

Open the URL in your browser and log in with:
- **Username:** admin
- **Password:** (from command above)

### Test Container Push/Pull

```bash
# Get Harbor URL
HARBOR_URL=$(kubectl get svc -n harbor harbor-portal \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Get admin password
HARBOR_PASSWORD=$(kubectl get secret -n harbor harbor-core \
  -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 --decode)

# Login to Harbor
docker login $HARBOR_URL -u admin -p $HARBOR_PASSWORD

# Pull a test image
docker pull nginx:alpine

# Tag for Harbor
docker tag nginx:alpine $HARBOR_URL/library/nginx:test

# Push to Harbor
docker push $HARBOR_URL/library/nginx:test

# Verify in S3
aws s3 ls s3://<harbor-bucket-name>/harbor/ --recursive
```

## 📊 View CloudTrail Logs

```bash
# View recent S3 API calls from Harbor
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::S3::Object \
  --max-results 10 \
  --query 'Events[].{Time:EventTime,User:Username,Event:EventName,Identity:UserIdentity.type}' \
  --output table

# Look for AssumedRole entries (IRSA) vs IAMUser entries (static credentials)
```

## 🧹 Cleanup

When you're done with the workshop, clean up all resources to avoid charges:

```bash
# Option 1: Use the cleanup script
cd scripts
chmod +x cleanup-infrastructure.sh
./cleanup-infrastructure.sh

# Option 2: Manual cleanup with Terraform
cd terraform
terraform destroy

# Verify all resources are deleted
aws eks list-clusters
aws s3 ls | grep harbor
aws kms list-aliases | grep harbor
```

## 💰 Cost Estimate

Running this workshop will cost approximately:

| Resource | Cost | Duration | Total |
|----------|------|----------|-------|
| EKS Cluster | $0.10/hour | 4 hours | $0.40 |
| EC2 Nodes (2x t3.medium) | $0.08/hour | 4 hours | $0.32 |
| S3 Storage | $0.023/GB | ~5GB | $0.12 |
| KMS Key | $1/month | 1 day | $0.03 |
| Data Transfer | Variable | - | ~$0.10 |
| **Total** | | | **~$1.00-2.00** |

💡 **Tip:** Delete all resources immediately after completing the workshop to minimize costs.

## ❓ Troubleshooting

### Common Issues

#### Issue: "AWS credentials not configured"

```bash
# Solution: Configure AWS CLI
aws configure

# Or set environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

#### Issue: "Terraform init fails"

```bash
# Solution: Check Terraform version
terraform version  # Should be 1.5+

# Reinstall Terraform if needed
# https://developer.hashicorp.com/terraform/downloads
```

#### Issue: "Harbor pods not starting"

```bash
# Check pod status
kubectl get pods -n harbor

# Check pod logs
kubectl logs -n harbor <pod-name>

# Check events
kubectl get events -n harbor --sort-by='.lastTimestamp'
```

#### Issue: "Cannot access S3 from Harbor"

```bash
# Verify service account annotation
kubectl get sa harbor-registry -n harbor -o yaml

# Check IAM role trust policy
aws iam get-role --role-name HarborS3Role

# Check pod has projected token
kubectl exec -n harbor <harbor-pod> -- \
  ls -la /var/run/secrets/eks.amazonaws.com/serviceaccount/
```

#### Issue: "LoadBalancer URL not available"

```bash
# Wait a few minutes for LoadBalancer to provision
kubectl get svc -n harbor harbor-portal -w

# Check LoadBalancer events
kubectl describe svc -n harbor harbor-portal
```

### Get Help

If you encounter issues:

1. Check the [Troubleshooting Guide](docs/TROUBLESHOOTING_GUIDE.md)
2. Review [Validation Checkpoints](docs/VALIDATION_CHECKPOINTS.md)
3. Open an issue on [GitHub](https://github.com/snblaise/secure-harbor-irsa-on-eks/issues)
4. Check AWS CloudWatch logs for EKS cluster
5. Review Terraform state: `terraform show`

## 📚 Next Steps

After successful deployment and testing:

1. **Explore the Documentation**
   - Read the [Architecture Comparison](docs/architecture-comparison.md)
   - Study the [STRIDE Threat Model](docs/insecure-threat-model.md)
   - Review [Security Hardening Guides](docs/)

2. **Experiment**
   - Try deploying other applications with IRSA
   - Modify IAM policies to test least privilege
   - Explore CloudTrail logs for audit trails

3. **Share Your Experience**
   - Write about your learnings
   - Share on LinkedIn or Medium
   - Contribute improvements to the workshop

4. **Apply to Production**
   - Adapt the Terraform modules for your environment
   - Implement IRSA for existing workloads
   - Train your team on IRSA best practices

## 🎯 Success Criteria

You've successfully completed the workshop when:

- ✅ Harbor is running on EKS
- ✅ Harbor can read/write to S3 using IRSA (no static credentials)
- ✅ S3 bucket is encrypted with KMS customer-managed key
- ✅ Unauthorized access is denied
- ✅ CloudTrail logs show pod-level identity
- ✅ All validation tests pass
- ✅ You understand the security benefits of IRSA over static credentials

## 📞 Support

- **GitHub Issues:** [Report bugs or request features](https://github.com/snblaise/secure-harbor-irsa-on-eks/issues)
- **GitHub Discussions:** [Ask questions](https://github.com/snblaise/secure-harbor-irsa-on-eks/discussions)
- **Medium:** [@shublaisengwa](https://medium.com/@shublaisengwa)

---

**Happy Learning! 🚀**
