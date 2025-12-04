# Harbor IRSA Workshop - Scripts

This directory contains orchestration and utility scripts for deploying, validating, and cleaning up the Harbor IRSA workshop infrastructure.

## Available Scripts

### 1. deploy-infrastructure.sh

**Purpose**: Automated deployment of the complete workshop infrastructure

**What it does**:
- Checks prerequisites (Terraform, AWS CLI, kubectl, Helm)
- Validates AWS credentials
- Initializes Terraform
- Creates infrastructure plan
- Deploys EKS cluster, VPC, S3, KMS, IAM roles, and Harbor
- Configures kubectl
- Waits for Harbor to be ready
- Displays access information

**Usage**:
```bash
./scripts/deploy-infrastructure.sh
```

**Duration**: Approximately 15-20 minutes

**Prerequisites**:
- Terraform >= 1.0
- AWS CLI configured with credentials
- kubectl installed
- Helm >= 3.0 installed
- AWS account with appropriate permissions

**What gets created**:
- EKS cluster with 2 nodes
- VPC with public/private subnets
- NAT gateways and route tables
- S3 bucket with KMS encryption
- IAM roles and policies for IRSA
- Harbor container registry

### 2. validate-deployment.sh

**Purpose**: Validates that infrastructure is correctly deployed and configured

**What it validates**:
- ✓ EKS cluster is accessible
- ✓ Cluster nodes are ready
- ✓ OIDC provider is configured
- ✓ Harbor namespace exists
- ✓ Service account has IRSA annotation
- ✓ IAM role exists with correct policies
- ✓ S3 bucket exists with versioning and encryption
- ✓ S3 public access is blocked
- ✓ KMS key exists with rotation enabled
- ✓ Harbor pods are running
- ✓ Harbor services are created
- ✓ LoadBalancer has external IP
- ✓ No static AWS credentials in pod specs

**Usage**:
```bash
./scripts/validate-deployment.sh
```

**Duration**: 1-2 minutes

**Output**: Detailed validation report with pass/fail/warning status for each check

**Example output**:
```
========================================
Validating EKS Cluster
========================================

Testing: EKS cluster exists and is accessible
  ✓ PASS: Cluster is accessible
Testing: Cluster nodes are ready
  ✓ PASS: 2 node(s) ready
...

========================================
Validation Summary
========================================

Passed:   25
Warnings: 2
Failed:   0

✓ All validations passed!
```

### 3. cleanup-infrastructure.sh

**Purpose**: Destroys all workshop infrastructure resources

**What it does**:
- Confirms destruction with user
- Empties S3 bucket (including all versions)
- Deletes Kubernetes-created load balancers
- Runs terraform destroy
- Cleans up local Terraform state files
- Removes kubectl context

**Usage**:
```bash
./scripts/cleanup-infrastructure.sh
```

**Duration**: Approximately 10-15 minutes

**⚠️ WARNING**: This permanently deletes all resources including stored container images!

**Confirmation required**: You must type 'destroy' and then 'yes' to confirm

**What gets deleted**:
- EKS cluster and all workloads
- VPC and networking resources
- S3 bucket and all stored images
- KMS key (scheduled for deletion with 30-day window)
- IAM roles and policies
- Local Terraform state

### 4. extract-credentials.sh

**Purpose**: Demonstrates credential extraction from insecure deployment (educational)

**Location**: This script is created as part of task 6.1 (not yet implemented)

**What it demonstrates**:
- How to extract base64-encoded credentials from Kubernetes secrets
- Security risks of storing static credentials
- Why IRSA is more secure

**Usage** (when available):
```bash
./scripts/extract-credentials.sh
```

## Workflow

### Initial Deployment

```bash
# 1. Deploy infrastructure
./scripts/deploy-infrastructure.sh

# 2. Validate deployment
./scripts/validate-deployment.sh

# 3. Access Harbor
# Use the URL and credentials displayed by deploy script
```

### Daily Workshop Use

```bash
# Check infrastructure status
./scripts/validate-deployment.sh

# Get Harbor URL
kubectl get svc -n harbor harbor-portal -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Get Harbor admin password
kubectl get secret -n harbor harbor-core -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 --decode
```

### Cleanup After Workshop

```bash
# Destroy all resources
./scripts/cleanup-infrastructure.sh
```

## Troubleshooting

### Script Fails with "Command not found"

**Issue**: Missing required tools

**Solution**:
```bash
# Install Terraform
brew install terraform  # macOS
# or download from https://www.terraform.io/downloads

# Install AWS CLI
brew install awscli  # macOS
# or follow https://aws.amazon.com/cli/

# Install kubectl
brew install kubectl  # macOS
# or follow https://kubernetes.io/docs/tasks/tools/

# Install Helm
brew install helm  # macOS
# or follow https://helm.sh/docs/intro/install/
```

### Script Fails with "AWS credentials not configured"

**Issue**: AWS CLI not configured

**Solution**:
```bash
# Configure AWS credentials
aws configure

# Or set environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

### Deployment Fails with "Insufficient permissions"

**Issue**: IAM user/role lacks required permissions

**Solution**: Ensure your AWS credentials have permissions for:
- EKS (create clusters, node groups)
- VPC (create VPCs, subnets, route tables, NAT gateways)
- IAM (create roles, policies, OIDC providers)
- S3 (create buckets, configure encryption)
- KMS (create keys, manage key policies)
- EC2 (create security groups, network interfaces)

### Validation Shows Warnings

**Issue**: Some resources not fully initialized

**Solution**: 
- Wait a few minutes for resources to fully initialize
- LoadBalancers can take 5-10 minutes to get external IPs
- Harbor pods may take 3-5 minutes to be fully ready
- Run validation script again after waiting

### Cleanup Fails to Delete Resources

**Issue**: Resources have dependencies or are in use

**Solution**:
```bash
# Manually delete load balancers first
aws elbv2 describe-load-balancers --query 'LoadBalancers[*].LoadBalancerArn' --output text | \
  xargs -I {} aws elbv2 delete-load-balancer --load-balancer-arn {}

# Wait 30 seconds
sleep 30

# Try cleanup again
./scripts/cleanup-infrastructure.sh
```

## Script Customization

### Changing Deployment Region

Edit `terraform/terraform.tfvars`:
```hcl
aws_region = "us-west-2"  # Change to your preferred region
availability_zones = ["us-west-2a", "us-west-2b"]
```

### Using SPOT Instances for Cost Savings

Edit `terraform/terraform.tfvars`:
```hcl
node_capacity_type = "SPOT"  # 60-70% cost savings
```

### Adjusting Node Count

Edit `terraform/terraform.tfvars`:
```hcl
node_desired_size = 3  # Increase for more capacity
node_min_size = 2
node_max_size = 5
```

## Environment Variables

Scripts respect these environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_REGION` | AWS region for deployment | From AWS CLI config |
| `AWS_PROFILE` | AWS CLI profile to use | default |
| `KUBECONFIG` | kubectl config file location | ~/.kube/config |

## Exit Codes

All scripts use standard exit codes:

- `0`: Success
- `1`: General error
- `2`: Missing prerequisites

## Logging

Scripts output colored logs:
- 🔵 Blue: Informational messages
- 🟢 Green: Success messages
- 🟡 Yellow: Warnings
- 🔴 Red: Errors

## Safety Features

### deploy-infrastructure.sh
- Checks prerequisites before starting
- Shows Terraform plan before applying
- Requires explicit confirmation
- Validates AWS credentials

### cleanup-infrastructure.sh
- Requires typing 'destroy' to confirm
- Requires second 'yes' confirmation
- Shows what will be deleted
- Empties S3 bucket before deletion

### validate-deployment.sh
- Read-only operations
- No destructive actions
- Safe to run anytime

## Additional Resources

- [Terraform Documentation](../terraform/README.md)
- [Workshop Documentation](../docs/README.md)
- [Validation Tests](../validation-tests/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)

## Support

For issues or questions:
1. Check script output for specific error messages
2. Review the troubleshooting section above
3. Check AWS CloudFormation console for EKS stack events
4. Review Terraform logs in `terraform/` directory
5. Open an issue in the GitHub repository
