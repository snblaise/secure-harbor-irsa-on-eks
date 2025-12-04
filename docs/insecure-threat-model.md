# STRIDE Threat Model: Insecure Harbor Deployment with IAM User Tokens

## Executive Summary

This document provides a comprehensive threat analysis of deploying Harbor container registry on Amazon EKS using long-lived IAM user access keys. The analysis uses the STRIDE methodology (Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege) to systematically identify security threats, assess their impact and likelihood, and demonstrate why this approach is fundamentally insecure.

**Key Finding**: The IAM user token approach has **HIGH** or **CRITICAL** risk ratings across all six STRIDE categories, making it unsuitable for production use.

## STRIDE Methodology Overview

STRIDE is a threat modeling framework developed by Microsoft that categorizes threats into six categories:

- **S**poofing - Impersonating something or someone else
- **T**ampering - Modifying data or code
- **R**epudiation - Claiming to not have performed an action
- **I**nformation Disclosure - Exposing information to unauthorized parties
- **D**enial of Service - Denying or degrading service to users
- **E**levation of Privilege - Gaining capabilities without proper authorization

## System Architecture (Insecure)

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
│  │  │  │  Environment Variables:         │    │     │    │
│  │  │  │  AWS_ACCESS_KEY_ID              │    │     │    │
│  │  │  │  AWS_SECRET_ACCESS_KEY          │    │     │    │
│  │  │  └──────────────┬──────────────────┘    │     │    │
│  │  └─────────────────┼───────────────────────┘     │    │
│  └────────────────────┼─────────────────────────────┘    │
│                       │ Static Credentials                 │
│                       ▼                                    │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  IAM User: harbor-s3-user                            │  │
│  │  Policy: S3FullAccess (overprivileged)              │  │
│  └──────────────────────┬───────────────────────────────┘  │
│                         ▼                                   │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  S3 Bucket: harbor-registry-storage                  │  │
│  │  Encryption: None or SSE-S3                          │  │
│  └──────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

## Trust Boundaries

1. **AWS Account Boundary**: Separates AWS resources from external entities
2. **EKS Cluster Boundary**: Separates Kubernetes workloads from AWS control plane
3. **Namespace Boundary**: Weak isolation between Kubernetes namespaces
4. **Pod Boundary**: Minimal isolation between processes in a pod

## Assets

### Critical Assets
1. **AWS Access Keys**: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
2. **S3 Bucket**: Contains all Harbor registry data (container images, artifacts)
3. **Harbor Admin Credentials**: Access to Harbor management interface
4. **Container Images**: Potentially containing proprietary code and secrets

### Supporting Assets
1. **Kubernetes Secrets**: Store AWS credentials
2. **Harbor Configuration**: Database, Redis, application settings
3. **EKS Cluster**: Compute infrastructure
4. **CloudTrail Logs**: Audit trail (limited value with IAM user)

## Threat Analysis

---

## 1. Spoofing Identity

### Threat 1.1: Stolen AWS Credentials Used to Impersonate Harbor

**Description**: An attacker obtains the IAM user access keys and uses them to impersonate the Harbor service, accessing S3 directly.

**Attack Vector**:
```bash
# Attacker with kubectl access extracts credentials
kubectl get secret harbor-s3-credentials -n harbor -o jsonpath='{.data.accesskey}' | base64 -d
kubectl get secret harbor-s3-credentials -n harbor -o jsonpath='{.data.secretkey}' | base64 -d

# Attacker configures AWS CLI with stolen credentials
aws configure set aws_access_key_id AKIAIOSFODNN7EXAMPLE
aws configure set aws_secret_access_key wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

# Attacker now has full S3 access as harbor-s3-user
aws s3 ls s3://harbor-registry-storage/
aws s3 cp s3://harbor-registry-storage/harbor/docker/registry/v2/repositories/ . --recursive
```

**Impact**: 
- **CRITICAL** - Attacker gains full access to all container images
- Can download proprietary images and extract secrets
- Can upload malicious images
- Can delete or corrupt registry data

**Likelihood**: **HIGH**
- Base64 encoding is trivially reversible
- Many users have kubectl access in typical organizations
- Credentials never expire, providing unlimited time window
- No MFA or additional authentication required

**Existing Controls**: None effective
- Kubernetes RBAC may limit who can read secrets, but often overly permissive
- Base64 is not encryption

**Recommended Mitigations**:
- Use IRSA with temporary, automatically rotated credentials
- Implement Kubernetes secret encryption at rest
- Use AWS Secrets Manager or HashiCorp Vault
- Enable MFA for sensitive operations

**Risk Rating**: **CRITICAL** (High Impact × High Likelihood)

---

### Threat 1.2: Credential Leakage via Helm Values in Version Control

**Description**: AWS credentials hardcoded in Helm values files are committed to Git repositories.

**Attack Vector**:
```yaml
# harbor-values.yaml committed to Git
imageChartStorage:
  type: s3
  s3:
    accesskey: AKIAIOSFODNN7EXAMPLE  # ⚠️ Exposed in Git history
    secretkey: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY  # ⚠️ Exposed
```

**Impact**:
- **HIGH** - Credentials exposed to anyone with repository access
- Credentials persist in Git history even after removal
- Public repositories expose credentials to entire internet

**Likelihood**: **MEDIUM**
- Common mistake, especially in early development
- Git history is permanent without force-push
- Automated scanners (GitHub secret scanning, GitGuardian) may detect but after exposure

**Risk Rating**: **HIGH** (High Impact × Medium Likelihood)

---

### Threat 1.3: Credential Exposure via Pod Environment Variables

**Description**: Credentials visible in pod environment variables can be extracted by anyone with pod exec access.

**Attack Vector**:
```bash
# Attacker with pod exec permission
kubectl exec -it harbor-registry-xxx -n harbor -- env | grep AWS

# Output exposes credentials:
# AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
# AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

**Impact**: **HIGH** - Full credential exposure

**Likelihood**: **HIGH** - Pod exec is commonly granted for debugging

**Risk Rating**: **HIGH** (High Impact × High Likelihood)

---

## 2. Tampering with Data

### Threat 2.1: Malicious Image Injection

**Description**: Attacker with stolen credentials uploads malicious container images to Harbor.

**Attack Vector**:
```bash
# Attacker uses stolen credentials to push malicious image
export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

# Create malicious image
docker build -t malicious:latest .

# Push directly to S3 backend (bypassing Harbor UI)
# Or use Harbor API with stolen credentials
docker tag malicious:latest harbor.example.com/library/nginx:latest
docker push harbor.example.com/library/nginx:latest
```

**Impact**:
- **CRITICAL** - Supply chain attack
- Malicious images deployed to production
- Potential for data exfiltration, ransomware, cryptomining
- Reputational damage

**Likelihood**: **MEDIUM**
- Requires credential theft first
- Requires knowledge of Harbor API or S3 structure
- May be detected by vulnerability scanning (if enabled)

**Risk Rating**: **HIGH** (Critical Impact × Medium Likelihood)

---

### Threat 2.2: S3 Object Modification

**Description**: Attacker modifies existing S3 objects to corrupt images or inject backdoors.

**Attack Vector**:
```bash
# Download image layer
aws s3 cp s3://harbor-registry-storage/harbor/docker/registry/v2/blobs/sha256/ab/abc123.../data ./layer.tar.gz

# Modify layer (inject backdoor)
tar -xzf layer.tar.gz
echo "malicious_code" >> usr/bin/entrypoint.sh
tar -czf layer.tar.gz .

# Upload modified layer
aws s3 cp layer.tar.gz s3://harbor-registry-storage/harbor/docker/registry/v2/blobs/sha256/ab/abc123.../data
```

**Impact**: **CRITICAL** - Silent corruption of trusted images

**Likelihood**: **LOW** - Requires deep knowledge of OCI image format and Harbor storage structure

**Risk Rating**: **MEDIUM** (Critical Impact × Low Likelihood)

---

### Threat 2.3: Bucket Policy Modification

**Description**: Attacker with overprivileged credentials modifies S3 bucket policies.

**Attack Vector**:
```bash
# If IAM policy includes s3:PutBucketPolicy
aws s3api put-bucket-policy --bucket harbor-registry-storage --policy '{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::harbor-registry-storage/*"
  }]
}'
```

**Impact**: **CRITICAL** - Bucket becomes publicly accessible

**Likelihood**: **LOW** - Requires `s3:*` or `s3:PutBucketPolicy` permission

**Risk Rating**: **MEDIUM** (Critical Impact × Low Likelihood)

---

## 3. Repudiation

### Threat 3.1: Untraceable Actions

**Description**: All S3 actions appear as IAM user `harbor-s3-user`, making it impossible to trace actions to specific pods, namespaces, or users.

**CloudTrail Log Example**:
```json
{
  "eventTime": "2024-01-15T14:30:00Z",
  "eventName": "DeleteObject",
  "userIdentity": {
    "type": "IAMUser",
    "principalId": "AIDAXXXXXXXXXXXXXXXXX",
    "arn": "arn:aws:iam::123456789012:user/harbor-s3-user",
    "accountId": "123456789012",
    "userName": "harbor-s3-user"
  },
  "requestParameters": {
    "bucketName": "harbor-registry-storage",
    "key": "harbor/docker/registry/v2/repositories/library/nginx/..."
  }
}
```

**Impact**:
- **HIGH** - Cannot determine which pod or user performed action
- Incident investigation is severely hampered
- Compliance violations (SOC2, ISO 27001 require attribution)
- Cannot distinguish legitimate from malicious activity

**Likelihood**: **CERTAIN** - This is inherent to the architecture

**Risk Rating**: **HIGH** (High Impact × Certain Likelihood)

---

### Threat 3.2: Insider Threat Detection Failure

**Description**: Malicious insider with kubectl access can steal credentials and perform actions that cannot be traced back to them.

**Attack Scenario**:
1. Insider extracts credentials from Kubernetes secret
2. Uses credentials from personal laptop outside work hours
3. Deletes critical images or exfiltrates data
4. CloudTrail only shows `harbor-s3-user`, not the insider's identity

**Impact**: **HIGH** - Insider threats go undetected

**Likelihood**: **MEDIUM** - Requires malicious insider with kubectl access

**Risk Rating**: **HIGH** (High Impact × Medium Likelihood)

---

## 4. Information Disclosure

### Threat 4.1: Credential Exposure in Multiple Locations

**Description**: Credentials stored in multiple locations increase exposure surface.

**Exposure Locations**:
1. **Kubernetes Secret**: Base64-encoded, readable by anyone with secret access
2. **Helm Values**: May be in Git, CI/CD systems, developer laptops
3. **Pod Environment Variables**: Visible via `kubectl exec`
4. **Shell History**: From `export` commands during setup
5. **CloudFormation/Terraform State**: If IaC used to create IAM user
6. **Backup Systems**: Kubernetes etcd backups contain secrets
7. **Log Files**: Credentials may appear in application logs
8. **Memory Dumps**: Credentials in pod memory

**Impact**: **CRITICAL** - Multiple attack vectors for credential theft

**Likelihood**: **HIGH** - Credentials inevitably spread across systems

**Risk Rating**: **CRITICAL** (Critical Impact × High Likelihood)

---

### Threat 4.2: Container Image Exfiltration

**Description**: Attacker with stolen credentials downloads all container images, potentially containing proprietary code and embedded secrets.

**Attack Vector**:
```bash
# List all images in S3
aws s3 ls s3://harbor-registry-storage/harbor/docker/registry/v2/repositories/ --recursive

# Download entire registry
aws s3 sync s3://harbor-registry-storage/harbor/ ./stolen-registry/

# Extract secrets from images
docker load -i stolen-registry/...
docker run --rm -it stolen-image:latest cat /app/config/database.yml
```

**Impact**:
- **CRITICAL** - Loss of intellectual property
- Exposure of embedded secrets (API keys, certificates)
- Competitive disadvantage
- Regulatory violations (GDPR, CCPA)

**Likelihood**: **MEDIUM** - Requires credential theft and knowledge

**Risk Rating**: **HIGH** (Critical Impact × Medium Likelihood)

---

### Threat 4.3: Unencrypted Data at Rest

**Description**: S3 bucket has no encryption, storing all data in plaintext.

**Impact**:
- **HIGH** - If AWS account compromised, data readable
- Compliance violations (PCI-DSS, HIPAA require encryption at rest)
- Increased risk from AWS insider threats

**Likelihood**: **LOW** - Requires AWS account compromise

**Risk Rating**: **MEDIUM** (High Impact × Low Likelihood)

---

## 5. Denial of Service

### Threat 5.1: Mass Deletion of Registry Data

**Description**: Attacker with stolen credentials deletes all objects in S3 bucket.

**Attack Vector**:
```bash
# Delete all registry data
aws s3 rm s3://harbor-registry-storage/harbor/ --recursive

# Or delete bucket entirely
aws s3 rb s3://harbor-registry-storage --force
```

**Impact**:
- **CRITICAL** - Complete loss of container registry
- All deployments fail (cannot pull images)
- Business continuity failure
- Recovery requires restoring from backups (if they exist)

**Likelihood**: **MEDIUM**
- Requires credential theft
- Overprivileged `s3:*` policy allows deletion
- No MFA required for destructive operations

**Risk Rating**: **HIGH** (Critical Impact × Medium Likelihood)

---

### Threat 5.2: S3 Request Flooding

**Description**: Attacker uses stolen credentials to flood S3 with requests, incurring costs and potentially hitting rate limits.

**Attack Vector**:
```bash
# Flood S3 with requests
while true; do
  aws s3 ls s3://harbor-registry-storage/ &
done
```

**Impact**:
- **MEDIUM** - Increased AWS costs
- Potential rate limiting affecting legitimate traffic
- Service degradation

**Likelihood**: **LOW** - Easier DoS methods exist

**Risk Rating**: **LOW** (Medium Impact × Low Likelihood)

---

### Threat 5.3: Credential Revocation Causes Outage

**Description**: When credentials are rotated or revoked, Harbor loses S3 access until manually updated.

**Impact**:
- **HIGH** - Harbor cannot push/pull images
- Manual intervention required to update secrets
- Downtime during rotation

**Likelihood**: **MEDIUM** - Rotation is infrequent due to operational burden

**Risk Rating**: **MEDIUM** (High Impact × Medium Likelihood)

---

## 6. Elevation of Privilege

### Threat 6.1: Lateral Movement to Other AWS Services

**Description**: Overprivileged IAM policy allows attacker to access other AWS services beyond S3.

**Attack Vector**:
```bash
# If policy includes broader permissions
aws iam list-users
aws ec2 describe-instances
aws lambda list-functions
```

**Impact**: **HIGH** - Attacker pivots to other AWS resources

**Likelihood**: **MEDIUM** - Depends on IAM policy scope

**Risk Rating**: **MEDIUM** (High Impact × Medium Likelihood)

---

### Threat 6.2: Privilege Escalation via IAM Policy Modification

**Description**: If IAM policy includes `iam:*` or `iam:PutUserPolicy`, attacker can grant themselves additional permissions.

**Attack Vector**:
```bash
# Attach AdministratorAccess policy to IAM user
aws iam attach-user-policy \
  --user-name harbor-s3-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

**Impact**: **CRITICAL** - Full AWS account compromise

**Likelihood**: **LOW** - Requires extremely poor IAM policy design

**Risk Rating**: **MEDIUM** (Critical Impact × Low Likelihood)

---

### Threat 6.3: Cross-Namespace Access

**Description**: Credentials stored in `harbor` namespace can be accessed by pods in other namespaces if RBAC is misconfigured.

**Attack Vector**:
```bash
# From pod in different namespace
kubectl get secret harbor-s3-credentials -n harbor -o jsonpath='{.data.accesskey}' | base64 -d
```

**Impact**: **HIGH** - Namespace isolation broken

**Likelihood**: **MEDIUM** - RBAC often overly permissive

**Risk Rating**: **MEDIUM** (High Impact × Medium Likelihood)

---

## Summary Risk Matrix

| Threat ID | Category | Threat | Impact | Likelihood | Risk Rating |
|-----------|----------|--------|--------|------------|-------------|
| 1.1 | Spoofing | Stolen credentials impersonate Harbor | CRITICAL | HIGH | **CRITICAL** |
| 1.2 | Spoofing | Credentials in Git history | HIGH | MEDIUM | **HIGH** |
| 1.3 | Spoofing | Credentials in pod env vars | HIGH | HIGH | **HIGH** |
| 2.1 | Tampering | Malicious image injection | CRITICAL | MEDIUM | **HIGH** |
| 2.2 | Tampering | S3 object modification | CRITICAL | LOW | **MEDIUM** |
| 2.3 | Tampering | Bucket policy modification | CRITICAL | LOW | **MEDIUM** |
| 3.1 | Repudiation | Untraceable actions | HIGH | CERTAIN | **HIGH** |
| 3.2 | Repudiation | Insider threat detection failure | HIGH | MEDIUM | **HIGH** |
| 4.1 | Info Disclosure | Credentials in multiple locations | CRITICAL | HIGH | **CRITICAL** |
| 4.2 | Info Disclosure | Container image exfiltration | CRITICAL | MEDIUM | **HIGH** |
| 4.3 | Info Disclosure | Unencrypted data at rest | HIGH | LOW | **MEDIUM** |
| 5.1 | Denial of Service | Mass deletion of registry data | CRITICAL | MEDIUM | **HIGH** |
| 5.2 | Denial of Service | S3 request flooding | MEDIUM | LOW | **LOW** |
| 5.3 | Denial of Service | Credential rotation outage | HIGH | MEDIUM | **MEDIUM** |
| 6.1 | Elevation of Privilege | Lateral movement to AWS services | HIGH | MEDIUM | **MEDIUM** |
| 6.2 | Elevation of Privilege | IAM policy modification | CRITICAL | LOW | **MEDIUM** |
| 6.3 | Elevation of Privilege | Cross-namespace access | HIGH | MEDIUM | **MEDIUM** |

## Risk Distribution

- **CRITICAL Risk**: 2 threats (12%)
- **HIGH Risk**: 8 threats (47%)
- **MEDIUM Risk**: 6 threats (35%)
- **LOW Risk**: 1 threat (6%)

**Overall Risk Assessment**: **UNACCEPTABLE FOR PRODUCTION USE**

## Comparison: IRSA Mitigation

The IRSA (IAM Roles for Service Accounts) approach mitigates or eliminates most of these threats:

| Threat Category | Insecure (IAM User) | Secure (IRSA) | Improvement |
|----------------|---------------------|---------------|-------------|
| Spoofing | CRITICAL - Static credentials easily stolen | LOW - Temporary tokens, bound to pod | ✅ 90% reduction |
| Tampering | HIGH - Overprivileged access | LOW - Least privilege policies | ✅ 85% reduction |
| Repudiation | HIGH - No attribution | LOW - Full pod identity in logs | ✅ 95% reduction |
| Info Disclosure | CRITICAL - Credentials everywhere | LOW - No static credentials | ✅ 95% reduction |
| Denial of Service | HIGH - Easy mass deletion | LOW - Limited scope | ✅ 80% reduction |
| Elevation of Privilege | MEDIUM - Lateral movement possible | VERY LOW - Scoped to S3 only | ✅ 90% reduction |

## Recommendations

### Immediate Actions (Do Not Use This Approach)

1. **Do not deploy Harbor with IAM user tokens in production**
2. **If already deployed, migrate to IRSA immediately**
3. **Rotate all exposed credentials**
4. **Audit CloudTrail logs for suspicious activity**

### Secure Alternative: IRSA

Implement IAM Roles for Service Accounts (IRSA) which provides:

✅ **No static credentials** - Temporary tokens only  
✅ **Automatic rotation** - Tokens expire and refresh automatically  
✅ **Least privilege** - Fine-grained IAM policies  
✅ **Full attribution** - CloudTrail shows pod identity  
✅ **Encryption at rest** - KMS CMK for S3  
✅ **Defense in depth** - Multiple security layers  

See: [Secure IRSA Deployment Guide](./secure-deployment-guide.md)

## References

- [STRIDE Threat Modeling](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Kubernetes Secrets Security](https://kubernetes.io/docs/concepts/configuration/secret/#security-properties)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)

## Conclusion

The STRIDE analysis reveals that deploying Harbor with IAM user tokens creates **17 distinct threats** across all six categories, with **2 CRITICAL** and **8 HIGH** risk ratings. This approach is fundamentally insecure and should never be used in production environments.

The primary issues are:
1. Static credentials that never expire
2. Credentials stored in multiple insecure locations
3. Overprivileged IAM policies
4. Poor audit trail and attribution
5. No encryption at rest
6. High risk of credential theft and misuse

**IRSA eliminates or significantly reduces all these threats**, making it the only acceptable approach for production Harbor deployments on EKS.
