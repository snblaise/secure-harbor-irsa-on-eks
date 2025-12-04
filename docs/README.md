# Harbor IRSA Workshop Documentation

This directory contains comprehensive documentation for the Harbor IRSA (IAM Roles for Service Accounts) workshop on Amazon EKS.

## Documentation Structure

### Architecture Documentation

- **[architecture-diagrams.md](./architecture-diagrams.md)** - Visual architecture diagrams showing both insecure and secure approaches
- **[architecture-ascii.md](./architecture-ascii.md)** - ASCII-based architecture diagrams for text-based viewing
- **[architecture-comparison.md](./architecture-comparison.md)** - Side-by-side comparison of insecure vs secure architectures

### Insecure Deployment Path (Educational - What NOT to Do)

- **[insecure-deployment-guide.md](./insecure-deployment-guide.md)** - Complete step-by-step guide for deploying Harbor with IAM user tokens (insecure approach)
  - Creating IAM users with access keys
  - Storing credentials in Kubernetes secrets
  - Deploying Harbor with static credentials
  - Understanding the security risks

- **[insecure-threat-model.md](./insecure-threat-model.md)** - Comprehensive STRIDE threat analysis
  - 17 distinct threats across all six STRIDE categories
  - Impact and likelihood assessments
  - Attack scenarios and vectors
  - Risk ratings and mitigation strategies

- **[credential-extraction-demo.md](./credential-extraction-demo.md)** - Demonstration of credential theft
  - Multiple extraction methods
  - Automated extraction scripts
  - Attack scenarios
  - Security implications
  - Detection challenges

### Secure Deployment Path (Production-Ready)

- **[oidc-provider-setup.md](./oidc-provider-setup.md)** - OIDC provider setup guide
  - Understanding OIDC and why it's needed
  - Verifying EKS cluster OIDC issuer
  - Creating IAM OIDC identity provider
  - OIDC thumbprint retrieval and validation
  - Troubleshooting OIDC configuration

- **[iam-role-policy-setup.md](./iam-role-policy-setup.md)** - IAM role and policy configuration
  - Creating least-privilege IAM permissions policy
  - Creating restrictive trust policy with namespace/SA binding
  - Understanding IRSA security model
  - Configuring IAM role for Harbor

- **[s3-kms-setup.md](./s3-kms-setup.md)** - S3 and KMS backend storage setup
  - Creating KMS customer managed key
  - Configuring KMS key policy
  - Creating S3 bucket with encryption
  - Bucket policy enforcement
  - Versioning and lifecycle policies

- **[harbor-irsa-deployment.md](./harbor-irsa-deployment.md)** - Harbor deployment with IRSA
  - Creating Kubernetes service account with IAM annotation
  - Configuring Harbor Helm values for IRSA
  - Deploying Harbor without static credentials
  - Validating IRSA configuration
  - Testing S3 access from Harbor pods

### Best Practices and Hardening

- **[security-best-practices.md](./security-best-practices.md)** *(Coming soon)* - Security hardening guidelines
  - KMS key policy hardening
  - S3 bucket policy hardening
  - IAM guardrails
  - Namespace isolation
  - Defense in depth

### Validation and Testing

- **[validation-guide.md](./validation-guide.md)** *(Coming soon)* - Testing and validation procedures
  - Access control tests
  - Credential rotation verification
  - Audit log analysis
  - Compliance validation

## Quick Start

### For Workshop Participants

1. **Understand the Problem**: Start with [insecure-deployment-guide.md](./insecure-deployment-guide.md) to see what NOT to do
2. **Analyze Threats**: Review [insecure-threat-model.md](./insecure-threat-model.md) to understand the risks
3. **See the Vulnerability**: Run the credential extraction demo from [credential-extraction-demo.md](./credential-extraction-demo.md)
4. **Learn the Solution**: Follow the secure deployment guides:
   - [OIDC Provider Setup](./oidc-provider-setup.md)
   - [IAM Role Configuration](./iam-role-policy-setup.md)
   - [S3 and KMS Setup](./s3-kms-setup.md)
   - [Harbor IRSA Deployment](./harbor-irsa-deployment.md)
5. **Validate Security**: Use the validation guide to verify your implementation (coming soon)

### For Security Practitioners

1. **Threat Analysis**: Review [insecure-threat-model.md](./insecure-threat-model.md) for comprehensive STRIDE analysis
2. **Architecture Comparison**: See [architecture-comparison.md](./architecture-comparison.md) for side-by-side comparison
3. **Security Validation**: Use validation tests to prove security properties (coming soon)

### For DevOps Engineers

1. **Deployment Guide**: Follow step-by-step instructions in deployment guides
2. **Infrastructure as Code**: Use Terraform modules in `../terraform/` directory (coming soon)
3. **Automation Scripts**: Use scripts in `../scripts/` directory for deployment automation (coming soon)

## Key Takeaways

### Why IAM User Tokens are Insecure

❌ **Static credentials** that never expire  
❌ **Easily extracted** from Kubernetes secrets (base64 is not encryption)  
❌ **Overprivileged** IAM policies granting broad access  
❌ **Poor audit trail** - all actions appear as IAM user  
❌ **No automatic rotation** - manual process is error-prone  
❌ **Credential sprawl** - copied to multiple locations  

### Why IRSA is Secure

✅ **No static credentials** - temporary tokens only  
✅ **Automatic rotation** - tokens expire and refresh automatically  
✅ **Least privilege** - fine-grained IAM policies  
✅ **Full attribution** - CloudTrail shows pod identity  
✅ **Encryption at rest** - KMS CMK for S3  
✅ **Defense in depth** - multiple security layers  

## Security Risk Summary

Based on the STRIDE threat analysis:

- **CRITICAL Risk**: 2 threats (12%)
- **HIGH Risk**: 8 threats (47%)
- **MEDIUM Risk**: 6 threats (35%)
- **LOW Risk**: 1 threat (6%)

**Overall Assessment**: The IAM user token approach is **UNACCEPTABLE FOR PRODUCTION USE**.

## Workshop Learning Objectives

By completing this workshop, you will:

1. ✅ Understand the security risks of long-lived IAM credentials
2. ✅ Learn how to perform threat modeling using STRIDE methodology
3. ✅ Understand how IRSA works and why it's secure
4. ✅ Deploy Harbor on EKS with IRSA
5. ✅ Configure S3 backend storage with KMS encryption
6. ✅ Validate security properties through testing
7. ✅ Implement security best practices and hardening

## Prerequisites

- AWS account with administrative access
- EKS cluster (or ability to create one)
- kubectl configured for your cluster
- Helm 3.x installed
- AWS CLI configured
- Basic understanding of Kubernetes and AWS IAM

## Additional Resources

### AWS Documentation

- [IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Amazon EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [AWS KMS Best Practices](https://docs.aws.amazon.com/kms/latest/developerguide/best-practices.html)
- [S3 Security Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)

### Kubernetes Documentation

- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Service Accounts](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)

### Harbor Documentation

- [Harbor Installation Guide](https://goharbor.io/docs/latest/install-config/)
- [Harbor S3 Storage Configuration](https://goharbor.io/docs/latest/install-config/configure-yml-file/#storage)

### Security Resources

- [STRIDE Threat Modeling](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)

## Contributing

This workshop is part of a larger educational initiative. Contributions are welcome! Please see the main repository README for contribution guidelines.

## License

See the LICENSE file in the root directory.

## Support

For questions or issues:
1. Check the troubleshooting guide (coming soon)
2. Review the FAQ section (coming soon)
3. Open an issue in the GitHub repository

## Acknowledgments

This workshop demonstrates security best practices for deploying Harbor container registry on Amazon EKS using IAM Roles for Service Accounts (IRSA). It is designed for educational purposes to help security practitioners, DevOps engineers, and cloud architects understand the importance of proper credential management in Kubernetes environments.

---

**⚠️ Important Security Notice**

The insecure deployment path documented in this workshop is provided for **educational purposes only** to demonstrate security vulnerabilities. **Never use IAM user tokens with static credentials in production environments.** Always use IRSA or similar secure credential management solutions.
