# Workshop Learning Objectives and Outcomes

## Overview

This document defines the learning objectives, expected outcomes, and success criteria for the Harbor IRSA Workshop on EKS. Participants will gain hands-on experience with AWS security best practices, Kubernetes identity management, and infrastructure as code.

## Target Audience

- **Primary**: Cloud security engineers, DevOps engineers, and platform engineers
- **Secondary**: Solutions architects and security architects
- **Prerequisites**: 
  - Basic Kubernetes knowledge (pods, services, namespaces)
  - Familiarity with AWS IAM concepts
  - Understanding of container registries
  - Basic Terraform experience (helpful but not required)

## Learning Objectives

By the end of this workshop, participants will be able to:

### 1. Security Fundamentals

**Objective**: Understand the security risks of static credentials in Kubernetes environments

**Specific Learning Goals**:
- Explain why long-lived IAM user credentials pose security risks
- Identify credential leakage vectors in Kubernetes (secrets, environment variables, logs)
- Describe the principle of least privilege and its application to cloud workloads
- Articulate the shared responsibility model for container security on AWS

**Assessment**: Participants can explain at least 3 security risks of IAM user tokens and how IRSA mitigates each

### 2. IRSA Architecture and Concepts

**Objective**: Comprehend how IAM Roles for Service Accounts (IRSA) works at a technical level

**Specific Learning Goals**:
- Explain the role of OIDC providers in federating Kubernetes and AWS IAM
- Describe how JWT tokens are issued and validated in the IRSA flow
- Understand the trust relationship between Kubernetes service accounts and IAM roles
- Identify the components involved in IRSA (EKS OIDC provider, IAM role, service account, projected token)

**Assessment**: Participants can draw or describe the IRSA authentication flow from pod to AWS service

### 3. Threat Modeling and Risk Analysis

**Objective**: Apply structured threat modeling to identify security vulnerabilities

**Specific Learning Goals**:
- Use STRIDE methodology to analyze security threats
- Differentiate between high-impact and low-impact security risks
- Evaluate the effectiveness of security controls
- Compare threat profiles between insecure and secure architectures

**Assessment**: Participants can complete a STRIDE analysis for a given deployment scenario

### 4. IAM Policy Design

**Objective**: Create least-privilege IAM policies for specific workload requirements

**Specific Learning Goals**:
- Write IAM trust policies with namespace and service account restrictions
- Design permissions policies that grant only required actions on specific resources
- Use IAM policy conditions to add additional security constraints
- Validate IAM policies using AWS IAM Policy Simulator or similar tools

**Assessment**: Participants can write a least-privilege IAM policy for a given S3 access scenario

### 5. Kubernetes Security Best Practices

**Objective**: Implement Kubernetes security controls for workload isolation

**Specific Learning Goals**:
- Configure service accounts with appropriate annotations for IRSA
- Implement namespace isolation for multi-tenant clusters
- Apply RBAC policies to restrict access to sensitive resources
- Use projected service account tokens for AWS authentication

**Assessment**: Participants can configure a Kubernetes service account for IRSA and verify the token projection

### 6. Encryption and Key Management

**Objective**: Implement encryption at rest using AWS KMS with customer-managed keys

**Specific Learning Goals**:
- Create and configure KMS customer-managed keys (CMKs)
- Write KMS key policies that restrict key usage to specific IAM roles
- Configure S3 bucket encryption with KMS CMKs
- Understand the difference between AWS-managed and customer-managed keys

**Assessment**: Participants can configure S3 bucket encryption with a KMS CMK and verify encryption is enforced

### 7. Infrastructure as Code

**Objective**: Use Terraform to provision secure, reproducible infrastructure

**Specific Learning Goals**:
- Understand Terraform module structure and organization
- Provision EKS clusters with OIDC provider enabled
- Create IAM resources (roles, policies, OIDC providers) using Terraform
- Deploy Kubernetes resources using Terraform Helm provider

**Assessment**: Participants can modify Terraform code to add a new IAM permission or S3 bucket configuration

### 8. Validation and Testing

**Objective**: Verify security controls through systematic testing

**Specific Learning Goals**:
- Test access controls by attempting unauthorized access
- Validate credential rotation by monitoring token expiration
- Review CloudTrail logs to verify identity attribution
- Use kubectl and AWS CLI to inspect security configurations

**Assessment**: Participants can run validation tests and interpret the results to confirm security controls are working

### 9. Audit and Compliance

**Objective**: Demonstrate audit capabilities for compliance requirements

**Specific Learning Goals**:
- Locate and interpret CloudTrail logs for S3 access events
- Trace AWS API calls back to specific Kubernetes pods and namespaces
- Understand the difference in audit trails between IAM users and IRSA
- Explain how IRSA supports compliance frameworks (SOC2, ISO 27001, PCI-DSS)

**Assessment**: Participants can find a CloudTrail log entry and identify which pod made the API call

### 10. Operational Excellence

**Objective**: Understand operational benefits and trade-offs of IRSA

**Specific Learning Goals**:
- Explain how automatic credential rotation reduces operational burden
- Identify scenarios where IRSA is appropriate vs. other authentication methods
- Troubleshoot common IRSA configuration issues
- Plan for production deployment considerations (HA, monitoring, cost)

**Assessment**: Participants can troubleshoot a misconfigured IRSA setup using logs and AWS/kubectl commands

## Expected Outcomes

### Knowledge Outcomes

After completing this workshop, participants will have gained:

1. **Security Awareness**: Deep understanding of credential management risks in cloud-native environments
2. **Technical Knowledge**: Comprehensive knowledge of IRSA architecture and implementation
3. **Best Practices**: Familiarity with AWS and Kubernetes security best practices
4. **Threat Modeling Skills**: Ability to analyze and compare security postures of different architectures

### Skills Outcomes

Participants will have developed the following practical skills:

1. **IAM Policy Authoring**: Write least-privilege IAM policies with appropriate trust relationships
2. **Kubernetes Configuration**: Configure service accounts and RBAC for secure workload identity
3. **Infrastructure Provisioning**: Use Terraform to deploy secure, production-ready infrastructure
4. **Security Validation**: Test and verify security controls through hands-on validation
5. **Troubleshooting**: Diagnose and resolve common IRSA configuration issues
6. **Audit Analysis**: Review and interpret CloudTrail logs for security investigations

### Behavioral Outcomes

Participants will demonstrate:

1. **Security-First Mindset**: Proactively consider security implications in design decisions
2. **Least Privilege Thinking**: Default to minimal permissions and expand only as needed
3. **Defense in Depth**: Apply multiple layers of security controls
4. **Continuous Validation**: Regularly test and verify security controls are functioning

## Success Criteria

### Individual Success Criteria

A participant has successfully completed the workshop when they can:

1. ✅ **Deploy Harbor with IRSA**: Successfully deploy Harbor container registry using IRSA for S3 access
2. ✅ **Verify Security Controls**: Confirm that unauthorized service accounts cannot access S3
3. ✅ **Demonstrate Credential Rotation**: Show that credentials automatically rotate without manual intervention
4. ✅ **Analyze Audit Logs**: Locate CloudTrail logs showing IRSA identity attribution
5. ✅ **Explain Security Benefits**: Articulate at least 5 security advantages of IRSA over IAM user tokens
6. ✅ **Troubleshoot Issues**: Diagnose and fix at least one common IRSA misconfiguration
7. ✅ **Apply to New Scenarios**: Describe how to apply IRSA to a different workload (e.g., application accessing DynamoDB)

### Workshop Delivery Success Criteria

The workshop is successful when:

1. ✅ **Completion Rate**: At least 80% of participants complete all hands-on exercises
2. ✅ **Comprehension**: At least 90% of participants can explain IRSA concepts in their own words
3. ✅ **Practical Application**: At least 75% of participants successfully deploy Harbor with IRSA
4. ✅ **Validation Tests**: 100% of validation tests pass for each participant's deployment
5. ✅ **Satisfaction**: Post-workshop survey shows at least 4.0/5.0 average satisfaction rating
6. ✅ **Knowledge Retention**: Follow-up assessment after 2 weeks shows at least 70% retention of key concepts

### Technical Success Criteria

The workshop infrastructure is successful when:

1. ✅ **Reproducibility**: All participants can provision identical infrastructure using provided Terraform code
2. ✅ **Reliability**: Infrastructure provisioning succeeds on first attempt for at least 90% of participants
3. ✅ **Security**: All deployed resources pass security validation tests
4. ✅ **Cost Efficiency**: Per-participant cost remains under $2.00 for 8-hour workshop
5. ✅ **Cleanup**: All resources can be destroyed cleanly without orphaned resources

## Learning Path

### Recommended Workshop Flow

**Phase 1: Foundation (30 minutes)**
- Introduction to Harbor and container registries
- Overview of AWS IAM and Kubernetes service accounts
- Security challenges in cloud-native environments

**Phase 2: The Problem (45 minutes)**
- Deploy Harbor using insecure IAM user tokens
- Demonstrate credential extraction from Kubernetes secrets
- Perform STRIDE threat modeling exercise
- Discuss real-world security incidents

**Phase 3: The Solution (60 minutes)**
- Introduction to IRSA architecture and concepts
- OIDC provider setup and configuration
- IAM role and policy design
- Service account configuration

**Phase 4: Hands-On Implementation (90 minutes)**
- Provision infrastructure using Terraform
- Deploy Harbor with IRSA configuration
- Configure S3 and KMS encryption
- Verify deployment and connectivity

**Phase 5: Validation and Testing (60 minutes)**
- Run access control validation tests
- Demonstrate credential rotation
- Review CloudTrail audit logs
- Test unauthorized access scenarios

**Phase 6: Best Practices and Hardening (45 minutes)**
- KMS key policy hardening
- S3 bucket policy enforcement
- IAM guardrails and permission boundaries
- Namespace isolation strategies

**Phase 7: Wrap-Up and Next Steps (30 minutes)**
- Review learning objectives
- Discuss production considerations
- Troubleshooting common issues
- Q&A and additional resources

**Total Duration**: 6 hours (with breaks)

## Assessment Methods

### Formative Assessment (During Workshop)

1. **Checkpoint Questions**: Short questions at the end of each phase to verify understanding
2. **Hands-On Validation**: Participants run validation scripts that confirm correct configuration
3. **Peer Discussion**: Small group discussions to explain concepts to each other
4. **Instructor Observation**: Instructor monitors progress and provides assistance

### Summative Assessment (End of Workshop)

1. **Practical Demonstration**: Participant deploys Harbor with IRSA from scratch
2. **Troubleshooting Exercise**: Participant fixes a deliberately misconfigured IRSA setup
3. **Concept Explanation**: Participant explains IRSA flow to another participant or instructor
4. **Written Reflection**: Short written summary of key learnings and how they'll apply them

### Post-Workshop Assessment (Optional)

1. **Follow-Up Survey**: 2-week follow-up asking participants what they've implemented
2. **Knowledge Quiz**: Online quiz testing retention of key concepts
3. **Project Showcase**: Participants share how they've applied IRSA in their own environments

## Resources for Continued Learning

### AWS Documentation
- [IAM Roles for Service Accounts (IRSA) Technical Overview](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [EKS Best Practices Guide - Security](https://aws.github.io/aws-eks-best-practices/security/docs/)
- [AWS Security Blog - IRSA Articles](https://aws.amazon.com/blogs/security/)

### Kubernetes Security
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

### Harbor Documentation
- [Harbor Installation and Configuration](https://goharbor.io/docs/)
- [Harbor Security Considerations](https://goharbor.io/docs/latest/install-config/configure-system-settings-cli/)

### Security Frameworks
- [STRIDE Threat Modeling](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats)
- [MITRE ATT&CK Framework](https://attack.mitre.org/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

### Infrastructure as Code
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)

## Instructor Notes

### Prerequisites Verification

Before starting the workshop, verify participants have:
- AWS account with appropriate permissions (AdministratorAccess or equivalent)
- AWS CLI installed and configured
- kubectl installed (version 1.28+)
- Terraform installed (version 1.5+)
- Basic understanding of Kubernetes concepts
- Familiarity with command-line tools

### Common Participant Challenges

1. **IAM Policy Syntax**: Participants often struggle with JSON syntax and policy structure
   - **Mitigation**: Provide templates and use policy validator tools

2. **OIDC Thumbprint**: Retrieving and configuring OIDC thumbprint can be confusing
   - **Mitigation**: Provide clear step-by-step commands and explain the purpose

3. **Terraform State Management**: Participants may encounter state lock issues
   - **Mitigation**: Use unique S3 backend buckets per participant or local state for workshop

4. **CloudTrail Delay**: Logs may take 15 minutes to appear, causing confusion
   - **Mitigation**: Explain delay upfront and have participants work on other tasks while waiting

5. **Cost Concerns**: Participants worry about AWS costs
   - **Mitigation**: Provide clear cost estimates and emphasize cleanup procedures

### Differentiation Strategies

**For Advanced Participants**:
- Challenge exercises: Implement IRSA for additional AWS services (DynamoDB, SQS)
- Advanced hardening: Implement permission boundaries and SCPs
- Multi-cluster scenarios: Configure IRSA across multiple EKS clusters

**For Beginners**:
- Provide pre-filled Terraform templates with clear comments
- Offer additional explanation of IAM and Kubernetes concepts
- Pair with more experienced participants for peer learning

### Time Management Tips

- Use timers for hands-on exercises to keep workshop on track
- Have backup activities if participants finish early
- Prepare troubleshooting shortcuts for common issues to save time
- Consider splitting into 2-day workshop if covering all content in depth

## Conclusion

This workshop provides a comprehensive, hands-on learning experience that transforms participants from understanding the problem of static credentials to implementing production-ready IRSA solutions. The combination of theoretical knowledge, practical skills, and real-world validation ensures participants leave with both confidence and competence in securing Kubernetes workloads on AWS.

Success is measured not just by completing the exercises, but by participants' ability to apply these concepts to their own environments and make security-conscious decisions in their daily work.
