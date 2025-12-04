# Secure Harbor Registry on EKS with IRSA

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![AWS](https://img.shields.io/badge/AWS-EKS-orange.svg)](https://aws.amazon.com/eks/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28+-blue.svg)](https://kubernetes.io/)
[![Terraform](https://img.shields.io/badge/Terraform-1.5+-purple.svg)](https://www.terraform.io/)
[![Harbor](https://img.shields.io/badge/Harbor-2.x-blue.svg)](https://goharbor.io/)
[![Workshop](https://img.shields.io/badge/Type-Workshop-green.svg)](https://github.com/yourusername/secure-harbor-irsa-on-eks)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

A comprehensive, hands-on workshop demonstrating the security, scalability, and maintainability advantages of **IAM Roles for Service Accounts (IRSA)** over long-lived IAM user tokens when deploying Harbor container registry on Amazon EKS with S3 backend storage encrypted using AWS KMS.

## 📑 Table of Contents

- [What You'll Learn](#-what-youll-learn)
- [The Security Problem](#-the-security-problem)
- [The IRSA Solution](#-the-irsa-solution)
- [Quick Comparison](#-quick-comparison)
- [Architecture Overview](#️-architecture-overview)
- [Quick Start](#-quick-start)
- [Workshop Structure](#-workshop-structure)
- [Learning Objectives](#-learning-objectives)
- [Repository Structure](#️-repository-structure)
- [Getting Started](#-getting-started)
- [Validation Checkpoints](#-validation-checkpoints)
- [Troubleshooting](#-troubleshooting)
- [Additional Resources](#-additional-resources)
- [Contributing](#-contributing)
- [License](#-license)
- [Acknowledgments](#-acknowledgments)
- [Contact](#-contact)
- [Next Steps](#-next-steps)

## 📦 What's Included

This comprehensive workshop provides everything you need:

- 📚 **Complete Documentation** - Step-by-step guides, architecture diagrams, and best practices
- 🏗️ **Production-Ready Infrastructure** - Terraform modules for automated deployment
- ✅ **Validation Test Suite** - Automated tests proving security properties
- 🔒 **Security Hardening Guides** - KMS, S3, IAM, and namespace isolation
- 📊 **Comparison Analysis** - Detailed comparison of insecure vs secure approaches
- 🎓 **Learning Materials** - Lab guide, checkpoints, and troubleshooting
- 📝 **Professional Deliverables** - Medium article and LinkedIn post templates
- 🧪 **Hands-On Examples** - Both insecure and secure deployment patterns

## 🎯 What You'll Learn

This workshop provides a complete end-to-end learning experience that will teach you:

- **Security Fundamentals**: Understand the critical security risks of static IAM credentials in Kubernetes
- **IRSA Implementation**: Master IAM Roles for Service Accounts for secure AWS access from Kubernetes
- **Threat Modeling**: Learn to identify and mitigate credential-based security threats using STRIDE analysis
- **Infrastructure as Code**: Deploy production-ready infrastructure using Terraform
- **Security Best Practices**: Implement defense-in-depth with KMS encryption, least-privilege IAM policies, and comprehensive audit logging
- **Validation Testing**: Prove security properties through automated validation tests

## 🔒 The Security Problem

Many teams deploy Harbor on EKS using **IAM user tokens** (access keys) stored as Kubernetes secrets. This approach creates serious security vulnerabilities:

❌ **Static credentials** stored in base64-encoded secrets (not encryption!)  
❌ **No automatic rotation** - credentials remain valid indefinitely  
❌ **Overprivileged access** - often granted broad S3 permissions  
❌ **Easy credential theft** - anyone with kubectl access can extract secrets  
❌ **Poor audit trail** - all actions appear as a single IAM user  
❌ **Credential sprawl** - same credentials copied to multiple locations  

## ✅ The IRSA Solution

**IAM Roles for Service Accounts (IRSA)** eliminates these risks by providing:

✅ **No static credentials** - temporary tokens issued automatically  
✅ **Automatic rotation** - credentials refresh every 24 hours  
✅ **Least privilege** - fine-grained IAM policies per service account  
✅ **Strong isolation** - access bound to specific namespace and service account  
✅ **Excellent audit trail** - CloudTrail shows pod-level identity  
✅ **Encryption at rest** - S3 backend encrypted with KMS customer-managed keys  

## 📊 Quick Comparison

| Dimension | IAM User Tokens | IRSA |
|-----------|----------------|------|
| **Credential Storage** | Static keys in Kubernetes secrets | No stored credentials |
| **Rotation** | Manual (rarely done) | Automatic (every 24h) |
| **Privilege Level** | Often overprivileged (S3FullAccess) | Least privilege (specific bucket/actions) |
| **Access Control** | Any pod can use credentials | Bound to specific namespace + service account |
| **Audit Trail** | All actions as IAM user | Pod-level identity in CloudTrail |
| **Credential Theft Risk** | High (base64 easily decoded) | Low (short-lived, scoped tokens) |
| **Operational Complexity** | Low (but insecure) | Medium (but secure) |

## 🏗️ Architecture Overview

### Insecure Architecture (What NOT to Do)

```
┌─────────────────────────────────────────────────────────┐
│                    Amazon EKS Cluster                    │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │  Kubernetes Secret (Base64)                    │    │
│  │  - AWS_ACCESS_KEY_ID                           │    │
│  │  - AWS_SECRET_ACCESS_KEY                       │    │
│  └──────────────┬─────────────────────────────────┘    │
│                 │                                        │
│                 ▼                                        │
│  ┌────────────────────────────────────────────────┐    │
│  │  Harbor Pod (with static credentials)          │    │
│  └──────────────┬─────────────────────────────────┘    │
└─────────────────┼──────────────────────────────────────┘
                  │
                  │ Static IAM User Credentials
                  ▼
┌─────────────────────────────────────────────────────────┐
│  IAM User → S3 Bucket (unencrypted or default SSE)     │
└─────────────────────────────────────────────────────────┘

RISKS: Credential theft, no rotation, overprivileged, poor audit
```

### Secure Architecture (IRSA Best Practice)

```
┌──────────────────────────────────────────────────────────┐
│                    Amazon EKS Cluster                     │
│                                                           │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Service Account: harbor-registry               │    │
│  │  Annotation: eks.amazonaws.com/role-arn         │    │
│  └──────────────┬──────────────────────────────────┘    │
│                 │                                         │
│                 ▼                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Harbor Pod (no static credentials)             │    │
│  │  - Projected service account token              │    │
│  │  - AWS SDK auto-discovers credentials           │    │
│  └──────────────┬──────────────────────────────────┘    │
└─────────────────┼───────────────────────────────────────┘
                  │
                  │ JWT Token (temporary, auto-rotated)
                  ▼
┌──────────────────────────────────────────────────────────┐
│  OIDC Provider → IAM Role (least privilege)              │
│  ↓                                                        │
│  S3 Bucket (SSE-KMS) ← KMS CMK                          │
└──────────────────────────────────────────────────────────┘

BENEFITS: No static creds, auto-rotation, least privilege, audit trail
```

## 🚀 Quick Start

### Prerequisites

Before starting this workshop, ensure you have:

**Required Tools:**
- **AWS Account** with administrative access (or sufficient IAM permissions)
- **AWS CLI** v2.x installed and configured ([Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
- **kubectl** v1.28+ installed ([Installation Guide](https://kubernetes.io/docs/tasks/tools/))
- **Terraform** v1.5+ installed ([Installation Guide](https://developer.hashicorp.com/terraform/downloads))
- **Helm** v3.x installed ([Installation Guide](https://helm.sh/docs/intro/install/))
- **Git** for cloning the repository

**Required Knowledge:**
- Basic understanding of Kubernetes concepts (pods, services, namespaces)
- Familiarity with AWS IAM (roles, policies, permissions)
- Basic command-line proficiency (bash/shell)
- Understanding of container registries (Docker Hub, ECR, etc.)

**Optional but Helpful:**
- Experience with Terraform or Infrastructure as Code
- Knowledge of AWS security services (CloudTrail, KMS)
- Understanding of OIDC and JWT tokens

### Estimated Time

- **Complete Workshop**: 3-4 hours
- **Core IRSA Implementation**: 1-2 hours
- **Validation and Testing**: 30-60 minutes

### Estimated Cost

Running this workshop will incur AWS charges:

- **EKS Cluster**: ~$0.10/hour
- **EC2 Worker Nodes**: ~$0.08/hour (2 × t3.medium)
- **S3 Storage**: ~$0.023/GB
- **KMS Key**: ~$1/month (prorated)

**Total estimated cost**: ~$1.50-2.00 for a 4-hour workshop session

💡 **Cost Tip**: Delete all resources immediately after completing the workshop to minimize charges.

## 📚 Workshop Structure

This workshop is organized into clear learning paths:

### 1. Understanding the Problem
- [Architecture Diagrams](docs/architecture-diagrams.md) - Visual overview of insecure vs secure architectures
- [Architecture Comparison](docs/architecture-comparison.md) - Detailed comparison table
- [Insecure Deployment Guide](docs/insecure-deployment-guide.md) - What NOT to do
- [STRIDE Threat Model](docs/insecure-threat-model.md) - Security risk analysis
- [Credential Extraction Demo](docs/credential-extraction-demo.md) - How credentials can be stolen

### 2. Implementing the Solution
- [OIDC Provider Setup](docs/oidc-provider-setup.md) - Enable OIDC on EKS
- [IAM Role and Policy Setup](docs/iam-role-policy-setup.md) - Configure IRSA roles
- [S3 and KMS Setup](docs/s3-kms-setup.md) - Configure encrypted storage
- [Harbor IRSA Deployment](docs/harbor-irsa-deployment.md) - Deploy Harbor with IRSA

### 3. Infrastructure as Code
- [Terraform Overview](terraform/README.md) - Complete infrastructure automation
- [Deployment Scripts](scripts/deploy-infrastructure.sh) - Automated provisioning
- [Cleanup Scripts](scripts/cleanup-infrastructure.sh) - Resource deletion

### 4. Validation and Testing
- [IRSA Access Validation](validation-tests/test-irsa-access-validation.sh) - Verify IRSA works
- [Access Denial Testing](validation-tests/test-access-denial.sh) - Verify unauthorized access blocked
- [Credential Extraction Test](validation-tests/test-credential-extraction-insecure.sh) - Demonstrate insecure risks
- [Log Verification](validation-tests/test-log-verification.sh) - Verify audit trails
- [No Static Credentials Test](validation-tests/test-no-static-credentials.sh) - Verify no hardcoded credentials

### 5. Security Hardening
- [KMS Key Policy Hardening](docs/kms-key-policy-hardening.md) - Secure encryption keys
- [S3 Bucket Policy Hardening](docs/s3-bucket-policy-hardening.md) - Secure storage
- [IAM Guardrails](docs/iam-guardrails.md) - Additional IAM controls
- [Namespace Isolation](docs/namespace-isolation-guide.md) - Kubernetes security

## 🎓 Learning Objectives

By completing this workshop, you will be able to:

1. **Explain** the security risks of static IAM credentials in Kubernetes environments
2. **Implement** IRSA for secure AWS service access from EKS pods
3. **Configure** least-privilege IAM policies for specific workload requirements
4. **Deploy** Harbor container registry with S3 backend using IRSA
5. **Validate** security controls through automated testing
6. **Analyze** CloudTrail logs for audit and compliance purposes
7. **Apply** defense-in-depth security principles with KMS encryption
8. **Troubleshoot** common IRSA configuration issues

## 🛠️ Repository Structure

```
secure-harbor-irsa-on-eks/
├── README.md                                      # This file
├── LICENSE                                        # MIT License
├── .gitignore                                     # Git ignore rules
│
├── docs/                                          # Workshop documentation
│   ├── README.md                                  # Documentation index
│   ├── WORKSHOP_LAB_GUIDE.md                      # Complete lab guide
│   ├── LEARNING_OBJECTIVES.md                     # Learning outcomes
│   ├── VALIDATION_CHECKPOINTS.md                  # Progress checkpoints
│   ├── TROUBLESHOOTING_GUIDE.md                   # Common issues and fixes
│   ├── MEDIUM_ARTICLE.md                          # Medium publication
│   ├── LINKEDIN_POST.md                           # LinkedIn announcement
│   │
│   ├── architecture-diagrams.md                   # Visual architectures
│   ├── architecture-comparison.md                 # Detailed comparison
│   ├── insecure-deployment-guide.md               # Insecure pattern
│   ├── insecure-threat-model.md                   # STRIDE analysis
│   ├── credential-extraction-demo.md              # Credential theft demo
│   │
│   ├── oidc-provider-setup.md                     # OIDC configuration
│   ├── iam-role-policy-setup.md                   # IAM setup
│   ├── s3-kms-setup.md                            # Storage setup
│   ├── harbor-irsa-deployment.md                  # Harbor deployment
│   │
│   ├── kms-key-policy-hardening.md                # KMS best practices
│   ├── s3-bucket-policy-hardening.md              # S3 best practices
│   ├── iam-guardrails.md                          # IAM controls
│   ├── namespace-isolation-guide.md               # K8s isolation
│   │
│   ├── cloudtrail-log-analysis.md                 # Audit log analysis
│   ├── permission-tracking-guide.md               # Permission auditing
│   └── incident-investigation-guide.md            # Investigation procedures
│
├── terraform/                                     # Infrastructure as Code
│   ├── main.tf                                    # Root module
│   ├── variables.tf                               # Input variables
│   ├── outputs.tf                                 # Output values
│   ├── terraform.tfvars.example                   # Example configuration
│   ├── README.md                                  # Terraform documentation
│   └── modules/                                   # Reusable modules
│       ├── eks/                                   # EKS cluster module
│       ├── irsa/                                  # IRSA configuration
│       ├── storage/                               # S3 and KMS
│       └── harbor/                                # Harbor deployment
│
├── examples/                                      # Example configurations
│   └── secure/                                    # Secure IRSA examples
│       ├── harbor-values-irsa.yaml                # Helm values
│       ├── service-account.yaml                   # K8s service account
│       ├── iam-role-trust-policy.json             # IAM trust policy
│       └── iam-role-permissions-policy.json       # IAM permissions
│
├── validation-tests/                              # Validation test suite
│   ├── README.md                                  # Test documentation
│   ├── test-irsa-access-validation.sh             # IRSA access test
│   ├── test-access-denial.sh                      # Access control test
│   ├── test-credential-extraction-insecure.sh     # Insecure demo
│   ├── test-log-verification.sh                   # Audit log test
│   ├── test-no-static-credentials.sh              # Credential check
│   ├── test-credential-rotation.sh                # Rotation test
│   ├── test-error-scenarios.sh                    # Error handling
│   └── test-infrastructure-best-practices.sh      # Infrastructure validation
│
└── scripts/                                       # Deployment automation
    ├── deploy-infrastructure.sh                   # Full deployment
    ├── cleanup-infrastructure.sh                  # Resource cleanup
    ├── validate-deployment.sh                     # Deployment validation
    └── extract-credentials.sh                     # Credential extraction demo
```

## 🚦 Getting Started

### Step 1: Clone the Repository

```bash
git clone https://github.com/yourusername/secure-harbor-irsa-on-eks.git
cd secure-harbor-irsa-on-eks
```

### Step 2: Validate Prerequisites

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

Ensure all tools are installed and AWS credentials are configured.

### Step 3: Configure AWS Credentials

```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, and default region
```

### Step 4: Set Environment Variables

```bash
export AWS_REGION=us-east-1
export CLUSTER_NAME=harbor-irsa-workshop
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

### Step 5: Choose Your Path

**Option A: Automated Deployment (Recommended for Quick Start)**

```bash
# Navigate to terraform directory
cd terraform

# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit variables with your AWS account details
# vim terraform.tfvars

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy infrastructure
terraform apply

# Validate deployment
cd ../scripts
./validate-deployment.sh
```

**Option B: Manual Step-by-Step (Recommended for Learning)**

Follow the comprehensive workshop lab guide:
1. Start with [Workshop Lab Guide](docs/WORKSHOP_LAB_GUIDE.md)
2. Review [Learning Objectives](docs/LEARNING_OBJECTIVES.md)
3. Progress through each module systematically
4. Complete [Validation Checkpoints](docs/VALIDATION_CHECKPOINTS.md)
5. Reference [Troubleshooting Guide](docs/TROUBLESHOOTING_GUIDE.md) as needed

## 🧪 Validation Checkpoints

Throughout the workshop, you'll validate your progress:

### Checkpoint 1: Insecure Deployment
- [ ] Harbor deployed with IAM user credentials
- [ ] Credentials extracted from Kubernetes secret
- [ ] STRIDE threat model completed

### Checkpoint 2: IRSA Configuration
- [ ] OIDC provider created and configured
- [ ] IAM role with trust policy created
- [ ] Service account annotated correctly

### Checkpoint 3: Secure Deployment
- [ ] Harbor deployed with IRSA
- [ ] S3 access working without static credentials
- [ ] KMS encryption enabled

### Checkpoint 4: Security Validation
- [ ] Unauthorized access denied
- [ ] CloudTrail logs show pod identity
- [ ] All validation tests passing

## ❓ Frequently Asked Questions

### General Questions

**Q: Can I use this workshop with existing EKS clusters?**  
A: Yes! The Terraform modules can be adapted to work with existing clusters. You'll need to ensure OIDC is enabled on your cluster.

**Q: Does this work with other container registries besides Harbor?**  
A: Absolutely! The IRSA principles apply to any application needing AWS access. The same patterns work for Docker Registry, Artifactory, Nexus, etc.

**Q: What AWS regions are supported?**  
A: All regions that support EKS. Simply set your desired region in the Terraform variables.

**Q: Can I use this in production?**  
A: Yes! The infrastructure code follows AWS best practices. However, review and adjust for your specific security and compliance requirements.

### Cost Questions

**Q: How much will this workshop cost?**  
A: Approximately $1.50-2.00 for a 4-hour session. Delete resources immediately after to minimize costs.

**Q: Can I use AWS Free Tier?**  
A: Partially. EKS control plane ($0.10/hour) is not free tier eligible, but some EC2 and S3 usage may qualify.

**Q: How do I minimize costs?**  
A: Use spot instances for worker nodes, delete resources after completion, and consider sharing a cluster across multiple participants.

### Technical Questions

**Q: Why not just use IAM roles for EC2 instances?**  
A: EC2 instance roles apply to all pods on a node. IRSA provides pod-level granularity, enabling least privilege per workload.

**Q: How often do IRSA tokens rotate?**  
A: Tokens expire after 24 hours and are automatically rotated by the Kubernetes service account token projection feature.

**Q: Can I use IRSA with other AWS services?**  
A: Yes! IRSA works with any AWS service. Common use cases include S3, DynamoDB, SQS, SNS, Secrets Manager, and more.

**Q: What happens if the OIDC provider is unavailable?**  
A: Existing tokens continue to work until expiration. New pod starts would fail to get tokens. This is extremely rare with EKS-managed OIDC.

## 🔍 Troubleshooting

### Common Issues

**Issue**: Harbor pod cannot access S3
```bash
# Check service account annotation
kubectl get sa harbor-registry -n harbor -o yaml

# Verify IAM role trust policy
aws iam get-role --role-name HarborS3Role

# Check pod logs
kubectl logs -n harbor -l app=harbor-registry
```

**Issue**: OIDC provider not found
```bash
# Verify OIDC provider exists
aws iam list-open-id-connect-providers

# Check EKS cluster OIDC issuer
aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer"
```

**Issue**: KMS decryption failures
```bash
# Verify KMS key policy
aws kms get-key-policy --key-id <KEY_ID> --policy-name default

# Check IAM role has KMS permissions
aws iam get-role-policy --role-name HarborS3Role --policy-name HarborS3Access
```

For more troubleshooting guidance, see [Troubleshooting Guide](docs/TROUBLESHOOTING_GUIDE.md).

## 📖 Additional Resources

### AWS Documentation
- [IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) - Official AWS documentation
- [Amazon EKS Security Best Practices](https://docs.aws.amazon.com/eks/latest/userguide/best-practices-security.html) - Comprehensive security guide
- [AWS KMS Best Practices](https://docs.aws.amazon.com/kms/latest/developerguide/best-practices.html) - Encryption key management
- [Amazon EKS Workshop](https://www.eksworkshop.com/) - Additional EKS learning resources
- [AWS Security Blog](https://aws.amazon.com/blogs/security/) - Latest security updates and practices

### Harbor Documentation
- [Harbor Installation Guide](https://goharbor.io/docs/latest/install-config/) - Official installation documentation
- [Harbor S3 Storage Configuration](https://goharbor.io/docs/latest/install-config/configure-yml-file/#storage) - S3 backend setup
- [Harbor Security](https://goharbor.io/docs/latest/administration/security/) - Harbor security features

### Kubernetes Security
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/security-checklist/) - Official K8s security checklist
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) - Pod security policies
- [Service Account Token Projection](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#service-account-token-volume-projection) - Technical details

### Security Resources
- [STRIDE Threat Modeling](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats) - Threat modeling framework
- [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html) - Security guidelines
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes) - Security benchmarks

### Related Projects
- [AWS EKS Blueprints](https://github.com/aws-ia/terraform-aws-eks-blueprints) - EKS infrastructure patterns
- [External Secrets Operator](https://external-secrets.io/) - Kubernetes secrets management with AWS Secrets Manager
- [Kyverno](https://kyverno.io/) - Kubernetes policy management
- [Falco](https://falco.org/) - Runtime security monitoring

## 🤝 Contributing

Contributions are welcome! This workshop is designed to help the community learn about secure Kubernetes deployments on AWS.

### How to Contribute

1. **Fork the repository** - Click the "Fork" button at the top right
2. **Clone your fork** - `git clone https://github.com/YOUR_USERNAME/secure-harbor-irsa-on-eks.git`
3. **Create a feature branch** - `git checkout -b feature/amazing-feature`
4. **Make your changes** - Add documentation, fix bugs, improve examples
5. **Test your changes** - Ensure all validation tests still pass
6. **Commit your changes** - `git commit -m 'Add amazing feature'`
7. **Push to your fork** - `git push origin feature/amazing-feature`
8. **Open a Pull Request** - Submit your changes for review

### Contribution Guidelines

- **Documentation**: Ensure all new features are documented
- **Code Quality**: Follow existing code style and conventions
- **Testing**: Add validation tests for new features
- **Security**: Never commit AWS credentials or sensitive data
- **Clarity**: Write clear commit messages and PR descriptions

### Areas for Contribution

- Additional validation tests
- Support for other Kubernetes distributions (GKE, AKS)
- Alternative storage backends (Azure Blob, GCS)
- Enhanced monitoring and observability examples
- Translations to other languages
- Bug fixes and documentation improvements

### Reporting Issues

Found a bug or have a suggestion? Please [open an issue](https://github.com/yourusername/secure-harbor-irsa-on-eks/issues) with:

- Clear description of the problem or suggestion
- Steps to reproduce (for bugs)
- Expected vs actual behavior
- Environment details (AWS region, EKS version, etc.)

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⭐ Show Your Support

If you find this workshop helpful, please consider:

- ⭐ **Star this repository** - It helps others discover this resource
- 🐛 **Report issues** - Help improve the workshop for everyone
- 💡 **Suggest improvements** - Share your ideas and feedback
- 🔀 **Submit pull requests** - Contribute your enhancements
- 📢 **Share with your network** - Help spread secure Kubernetes practices
- ✍️ **Write about your experience** - Blog posts and articles welcome

## 🙏 Acknowledgments

This workshop builds upon the excellent work of:

- **AWS EKS Team** - For implementing and documenting IRSA
- **Harbor Project Maintainers** - For creating a robust container registry
- **Kubernetes Community** - For service account token projection and security features
- **Security Researchers** - Who identified and documented credential-based attack vectors
- **Cloud Security Community** - For sharing best practices and lessons learned

Special thanks to all contributors who have helped improve this workshop through issues, pull requests, and feedback.

## 📊 Project Status

This workshop is actively maintained and regularly updated with:

- ✅ Complete documentation and lab guides
- ✅ Production-ready Terraform infrastructure code
- ✅ Comprehensive validation test suite
- ✅ Security best practices and hardening guides
- ✅ Professional deliverables (Medium article, LinkedIn post)
- 🔄 Regular updates for latest AWS/Kubernetes versions
- 🔄 Community contributions and improvements

**Current Version**: 1.0.0  
**Last Updated**: December 2025  
**Tested With**: EKS 1.28+, Terraform 1.5+, Harbor 2.x

## 📧 Contact

For questions, feedback, or support:

- **GitHub Issues**: [Create an issue](https://github.com/yourusername/secure-harbor-irsa-on-eks/issues) - Best for bug reports and feature requests
- **GitHub Discussions**: [Start a discussion](https://github.com/yourusername/secure-harbor-irsa-on-eks/discussions) - Best for questions and community help
- **LinkedIn**: Connect for professional networking and workshop feedback
- **Medium**: Read the [detailed article](docs/MEDIUM_ARTICLE.md) about this workshop

### Workshop Support

If you're running this workshop for your team or organization:

- 📖 All materials are open source and free to use
- 🎓 Suitable for training sessions and lunch-and-learns
- 🏢 Can be customized for your specific AWS environment
- 💬 Community support available via GitHub Discussions

## 🎯 Next Steps

Ready to get started? Here's what to do next:

1. **Read the Security Context**: Understand why this matters - [Architecture Comparison](docs/architecture-comparison.md) and [STRIDE Threat Model](docs/insecure-threat-model.md)
2. **Set Up Your Environment**: Install prerequisites and configure AWS
3. **Follow the Workshop**: Work through each module systematically
4. **Validate Your Learning**: Complete all validation tests
5. **Share Your Success**: Write about your experience and share with the community

---

**⚠️ Important Security Note**: This workshop includes examples of insecure configurations for educational purposes. Never use the insecure patterns in production environments. Always follow the secure IRSA approach demonstrated in this workshop.

**💡 Pro Tip**: Complete the insecure deployment path first to fully appreciate the security improvements that IRSA provides. Understanding what not to do is just as important as knowing the right approach.

---

Made with ❤️ for the cloud security community. Happy learning! 🚀
