# Harbor IRSA Workshop - Terraform Infrastructure

This directory contains Terraform infrastructure as code for deploying the complete Harbor IRSA workshop environment on AWS EKS.

## Overview

The Terraform configuration creates:

- **EKS Cluster**: Managed Kubernetes cluster with OIDC provider enabled
- **VPC and Networking**: Complete networking setup with public/private subnets, NAT gateways, and route tables
- **IRSA Configuration**: IAM roles with trust policies for Kubernetes service accounts
- **S3 Storage**: Encrypted S3 bucket for Harbor registry storage
- **KMS Encryption**: Customer-managed key for S3 encryption
- **Harbor Deployment**: Harbor container registry deployed via Helm with IRSA integration

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS Account                          │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │              Amazon EKS Cluster                     │    │
│  │  - OIDC Provider Enabled                           │    │
│  │  - Harbor Namespace                                │    │
│  │  - Service Account with IRSA Annotation            │    │
│  └────────────────────────────────────────────────────┘    │
│                           │                                  │
│                           │ IRSA (JWT Token)                 │
│                           ▼                                  │
│  ┌────────────────────────────────────────────────────┐    │
│  │              IAM Role (HarborS3Role)               │    │
│  │  - Trust Policy: Specific SA/Namespace             │    │
│  │  - Permissions: Least Privilege S3/KMS             │    │
│  └────────────────────────────────────────────────────┘    │
│                           │                                  │
│                           ▼                                  │
│  ┌────────────────────────────────────────────────────┐    │
│  │              S3 Bucket + KMS Key                   │    │
│  │  - Versioning Enabled                              │    │
│  │  - SSE-KMS Encryption                              │    │
│  │  - Public Access Blocked                           │    │
│  └────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

## Module Structure

```
terraform/
├── main.tf                    # Root configuration orchestrating all modules
├── variables.tf               # Root variables
├── outputs.tf                 # Root outputs
├── terraform.tfvars.example   # Example configuration
└── modules/
    ├── eks-cluster/           # EKS cluster with VPC and networking
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── irsa/                  # IAM roles for service accounts
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── s3-kms/                # S3 bucket with KMS encryption
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── harbor-helm/           # Harbor Helm deployment
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## Prerequisites

Before deploying, ensure you have:

1. **Terraform** >= 1.0 installed
2. **AWS CLI** configured with appropriate credentials
3. **kubectl** installed
4. **Helm** >= 3.0 installed
5. **AWS Account** with permissions to create:
   - EKS clusters
   - VPCs and networking resources
   - IAM roles and policies
   - S3 buckets
   - KMS keys

## Quick Start

### 1. Configure Variables

Copy the example variables file and customize:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your configuration:

```hcl
aws_region = "us-east-1"
cluster_name = "harbor-irsa-workshop"
harbor_admin_password = "YourSecurePassword123!"

# Adjust other variables as needed
```

### 2. Deploy Infrastructure

Use the automated deployment script:

```bash
cd ..
./scripts/deploy-infrastructure.sh
```

Or manually:

```bash
cd terraform

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

Deployment takes approximately 15-20 minutes.

### 3. Configure kubectl

After deployment, configure kubectl to access the cluster:

```bash
aws eks update-kubeconfig --region <region> --name <cluster-name>
```

Or use the Terraform output:

```bash
$(terraform output -raw configure_kubectl)
```

### 4. Validate Deployment

Run the validation script:

```bash
cd ..
./scripts/validate-deployment.sh
```

### 5. Access Harbor

Get the Harbor URL:

```bash
kubectl get svc -n harbor harbor-portal -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Get the admin password:

```bash
kubectl get secret -n harbor harbor-core -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 --decode
```

## Configuration Options

### EKS Cluster

| Variable | Description | Default |
|----------|-------------|---------|
| `cluster_name` | Name of the EKS cluster | `harbor-irsa-workshop` |
| `kubernetes_version` | Kubernetes version | `1.28` |
| `node_instance_types` | EC2 instance types for nodes | `["t3.medium"]` |
| `node_desired_size` | Desired number of nodes | `2` |
| `node_capacity_type` | ON_DEMAND or SPOT | `ON_DEMAND` |

### S3 and KMS

| Variable | Description | Default |
|----------|-------------|---------|
| `s3_bucket_prefix` | Prefix for S3 bucket name | `harbor-registry-storage` |
| `kms_deletion_window` | KMS key deletion window (days) | `30` |
| `enable_lifecycle_rules` | Enable S3 lifecycle rules | `true` |

### Harbor

| Variable | Description | Default |
|----------|-------------|---------|
| `harbor_namespace` | Kubernetes namespace | `harbor` |
| `harbor_admin_password` | Admin password | `Harbor12345` |
| `harbor_enable_trivy` | Enable vulnerability scanning | `true` |
| `harbor_expose_type` | Service type | `loadBalancer` |

## Outputs

After deployment, Terraform provides useful outputs:

```bash
# View all outputs
terraform output

# Specific outputs
terraform output cluster_name
terraform output harbor_iam_role_arn
terraform output s3_bucket_name
terraform output kms_key_arn
```

## Security Best Practices

This infrastructure implements several security best practices:

### ✅ IRSA Configuration
- No static credentials stored in Kubernetes
- Automatic credential rotation (24-hour tokens)
- Fine-grained access control (specific namespace + service account)

### ✅ S3 Security
- Versioning enabled for data protection
- SSE-KMS encryption with customer-managed key
- Bucket policy enforces encryption and TLS
- Public access completely blocked

### ✅ KMS Security
- Customer-managed key with key rotation enabled
- Key policy restricts usage to Harbor IAM role
- ViaService condition ensures key only used by S3

### ✅ Network Security
- Private subnets for EKS nodes
- NAT gateways for outbound internet access
- Security groups with least privilege rules

### ✅ IAM Security
- Least privilege IAM policies
- Trust policy restricts to specific service account
- No wildcard permissions

## Troubleshooting

### EKS Cluster Creation Fails

**Issue**: Insufficient permissions or quota limits

**Solution**:
- Verify IAM permissions for EKS, VPC, IAM
- Check AWS service quotas (VPCs, EIPs, etc.)
- Review CloudFormation events in AWS Console

### Harbor Pods Not Starting

**Issue**: Pods stuck in Pending or CrashLoopBackOff

**Solution**:
```bash
# Check pod status
kubectl get pods -n harbor

# View pod logs
kubectl logs -n harbor <pod-name>

# Check events
kubectl get events -n harbor --sort-by='.lastTimestamp'
```

### S3 Access Denied

**Issue**: Harbor cannot write to S3 bucket

**Solution**:
```bash
# Verify service account annotation
kubectl get sa -n harbor harbor-registry -o yaml

# Check IAM role trust policy
aws iam get-role --role-name <role-name>

# Verify IAM policy
aws iam list-attached-role-policies --role-name <role-name>
```

### LoadBalancer Not Getting External IP

**Issue**: LoadBalancer service stuck in pending

**Solution**:
- Wait 5-10 minutes for AWS to provision the load balancer
- Check AWS Load Balancer console for errors
- Verify subnet tags for EKS load balancer controller

## Cleanup

To destroy all resources:

```bash
# Using the cleanup script (recommended)
cd ..
./scripts/cleanup-infrastructure.sh

# Or manually
cd terraform
terraform destroy
```

**Warning**: This will permanently delete all resources including the S3 bucket and stored images.

## Cost Estimation

Approximate costs for running this workshop (per day):

| Resource | Cost |
|----------|------|
| EKS Cluster | $0.10/hour × 24 = $2.40 |
| EC2 Nodes (2 × t3.medium) | $0.0416/hour × 2 × 24 = $2.00 |
| NAT Gateways (2) | $0.045/hour × 2 × 24 = $2.16 |
| S3 Storage | ~$0.023/GB × 5GB = $0.12 |
| KMS Key | $1/month (prorated) = $0.03 |
| Data Transfer | ~$0.10 |
| **Total** | **~$6.81/day** |

**Cost Optimization Tips**:
- Use SPOT instances for nodes (60-70% savings)
- Delete resources immediately after workshop
- Use single NAT gateway for non-production
- Enable S3 lifecycle policies

## Additional Resources

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Harbor Documentation](https://goharbor.io/docs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Terraform and kubectl logs
3. Consult the workshop documentation in `../docs/`
4. Open an issue in the GitHub repository
