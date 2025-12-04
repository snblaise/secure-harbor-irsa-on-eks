# Stop Storing AWS Credentials in Kubernetes: A Security Engineer's Guide to IRSA with Harbor

## The $2 Million Mistake Most Teams Are Making

Picture this: It's 2 AM, and your security team just discovered that AWS credentials for your container registry have been exposed on GitHub. Again. The credentials have been live for 6 months, granting full S3 access to anyone who found them. Your Harbor registry, storing thousands of production container images, has been completely vulnerable.

This isn't a hypothetical scenario. It happens every day to teams running Harbor on Amazon EKS with static IAM credentials stored as Kubernetes secrets. The worst part? Most teams don't even realize they're sitting on a security time bomb.

**The good news?** There's a better way, and it's not even that hard to implement.

## The Problem: Static Credentials Are a Security Nightmare

If you're running Harbor (or any application) on Amazon EKS and storing AWS credentials as Kubernetes secrets, you're playing with fire. Here's why:

### 1. Base64 Is Not Encryption

Kubernetes secrets are base64-encoded, not encrypted. Anyone with `kubectl` access can extract your AWS credentials in seconds:

```bash
kubectl get secret harbor-s3-credentials -n harbor -o json | \
  jq -r '.data.AWS_ACCESS_KEY_ID' | base64 -d
```

That's it. Your AWS access key is now in plain text. No hacking required.

### 2. Credentials Never Rotate

When was the last time you rotated your IAM user credentials? If you're like most teams, the answer is "never" or "when we had a security incident."

Static credentials remain valid indefinitely. Once compromised, they can be used for months or years without detection.

### 3. Overprivileged Access

To make things "easier," teams often grant broad S3 permissions:

```json
{
  "Effect": "Allow",
  "Action": "s3:*",
  "Resource": "*"
}
```

Now your Harbor registry has access to every S3 bucket in your account. When those credentials leak, so does access to everything.

### 4. Zero Audit Trail

All actions appear as a single IAM user in CloudTrail. You can't tell which pod, container, or even which cluster performed an action. Good luck with your incident investigation.

## The Solution: IAM Roles for Service Accounts (IRSA)

**IRSA** (IAM Roles for Service Accounts) is AWS's answer to the static credential problem. It provides temporary, automatically-rotated credentials to Kubernetes pods without storing anything.

Here's how it works:

1. **EKS OIDC Provider** acts as an identity provider for Kubernetes
2. **Service Account** gets annotated with an IAM role ARN
3. **JWT Token** is projected into the pod automatically
4. **AWS SDK** uses the token to assume the IAM role
5. **Temporary Credentials** are issued and automatically rotated

No static credentials. No secrets. No manual rotation. Just secure, temporary access.

## The Transformation: Before and After

### Before: The Insecure Approach ❌

```
┌─────────────────────────────────────┐
│     Kubernetes Secret (Base64)      │
│  AWS_ACCESS_KEY_ID: AKIA...         │
│  AWS_SECRET_ACCESS_KEY: wJal...     │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Harbor Pod (static credentials)    │
│  Environment: AWS_ACCESS_KEY_ID     │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  IAM User → S3 (overprivileged)     │
└─────────────────────────────────────┘

RISKS:
❌ Credential theft (base64 easily decoded)
❌ No automatic rotation
❌ Overprivileged access (S3FullAccess)
❌ Poor audit trail (all actions as IAM user)
```

### After: The IRSA Approach ✅

```
┌─────────────────────────────────────┐
│  Service Account: harbor-registry   │
│  Annotation: eks.amazonaws.com/...  │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Harbor Pod (no static credentials) │
│  Projected Token: /var/run/secrets/ │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  OIDC → IAM Role (least privilege)  │
│  S3 Bucket (SSE-KMS encrypted)      │
└─────────────────────────────────────┘

BENEFITS:
✅ No static credentials stored anywhere
✅ Automatic rotation (every 24 hours)
✅ Least privilege (specific bucket/actions)
✅ Excellent audit trail (pod-level identity)
```

## Real-World Impact: The Numbers Don't Lie

Let's compare the two approaches across key security dimensions:

| Dimension | IAM User Tokens | IRSA |
|-----------|----------------|------|
| **Credential Storage** | Static keys in secrets | No stored credentials |
| **Rotation** | Manual (rarely done) | Automatic (every 24h) |
| **Privilege Level** | Often S3FullAccess | Least privilege |
| **Access Control** | Any pod can use | Bound to specific SA |
| **Audit Trail** | All actions as IAM user | Pod-level identity |
| **Credential Theft Risk** | High | Low |
| **Time to Compromise** | Seconds | N/A |

The difference is stark. IRSA isn't just "a bit better"—it's a complete security transformation.

## How to Implement IRSA: The 5-Step Process

Ready to secure your Harbor deployment? Here's the high-level process:

### Step 1: Enable OIDC on Your EKS Cluster

```bash
eksctl utils associate-iam-oidc-provider \
  --cluster harbor-cluster \
  --region us-east-1 \
  --approve
```

This creates an OIDC identity provider that AWS IAM can trust.

### Step 2: Create an IAM Role with Least-Privilege Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::harbor-registry-storage",
        "arn:aws:s3:::harbor-registry-storage/*"
      ]
    }
  ]
}
```

Notice: Only the specific actions Harbor needs, only on the specific bucket. No wildcards.

### Step 3: Configure the Trust Policy

This is the magic that binds the IAM role to a specific Kubernetes service account:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks..."
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks...:sub": "system:serviceaccount:harbor:harbor-registry"
        }
      }
    }
  ]
}
```

This trust policy ensures only the `harbor-registry` service account in the `harbor` namespace can assume this role. No other pod can use it.

### Step 4: Annotate Your Kubernetes Service Account

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: harbor-registry
  namespace: harbor
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/HarborS3Role
```

This annotation tells EKS to inject the IRSA token into pods using this service account.

### Step 5: Deploy Harbor Without Credentials

```yaml
imageChartStorage:
  type: s3
  s3:
    region: us-east-1
    bucket: harbor-registry-storage
    encrypt: true
    secure: true
    v4auth: true
    # No accesskey or secretkey!

serviceAccount:
  name: harbor-registry

registry:
  serviceAccountName: harbor-registry
```

Notice what's missing? No `accesskey` or `secretkey`. The AWS SDK automatically discovers credentials from the projected service account token.

## Defense in Depth: Don't Stop at IRSA

IRSA is powerful, but it's just one layer. Here's how to build a truly secure Harbor deployment:

### 1. Encrypt S3 with KMS Customer-Managed Keys

```bash
aws kms create-key --description "Harbor S3 encryption"
aws s3api put-bucket-encryption \
  --bucket harbor-registry-storage \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "your-key-id"
      }
    }]
  }'
```

### 2. Enforce Encryption with Bucket Policies

```json
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::harbor-registry-storage/*",
  "Condition": {
    "StringNotEquals": {
      "s3:x-amz-server-side-encryption": "aws:kms"
    }
  }
}
```

This policy denies any unencrypted uploads. No exceptions.

### 3. Implement Namespace Isolation

Use Kubernetes network policies to isolate the Harbor namespace:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: harbor-isolation
  namespace: harbor
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: harbor
```

### 4. Enable Comprehensive Audit Logging

CloudTrail now shows pod-level identity:

```json
{
  "userIdentity": {
    "type": "AssumedRole",
    "principalId": "AROAEXAMPLE:eks-harbor-registry-...",
    "arn": "arn:aws:sts::ACCOUNT:assumed-role/HarborS3Role/eks-harbor-registry-...",
    "sessionContext": {
      "sessionIssuer": {
        "type": "Role",
        "arn": "arn:aws:iam::ACCOUNT:role/HarborS3Role"
      },
      "webIdFederationData": {
        "federatedProvider": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks...",
        "attributes": {
          "sub": "system:serviceaccount:harbor:harbor-registry"
        }
      }
    }
  }
}
```

You can now trace every S3 action back to the specific pod that performed it.

## Validation: Prove Your Security

Don't just implement IRSA—validate it works. Here are the key tests:

### Test 1: Verify No Static Credentials

```bash
kubectl get pods -n harbor -o json | \
  jq -r '.items[].spec.containers[].env[]? | select(.name | contains("AWS"))' 

# Should return nothing
```

### Test 2: Verify Access Control

Create an unauthorized service account and try to access S3:

```bash
kubectl create sa unauthorized-sa -n harbor
kubectl run test --image=amazon/aws-cli \
  --serviceaccount=unauthorized-sa \
  --namespace=harbor \
  -- aws s3 ls s3://harbor-registry-storage/

# Should fail with AccessDenied
```

### Test 3: Verify Automatic Rotation

Check token expiration:

```bash
kubectl exec -n harbor harbor-pod -- \
  cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token | \
  cut -d'.' -f2 | base64 -d | jq -r '.exp'

# Token expires in ~24 hours and auto-rotates
```

## The Business Case: Why Your CISO Will Love This

Security improvements are great, but what about the business impact?

### Reduced Risk

- **Credential exposure incidents**: Down to near-zero
- **Blast radius of compromised credentials**: Dramatically reduced
- **Time to detect credential misuse**: From days/weeks to minutes

### Compliance Benefits

- **SOC 2**: Automatic credential rotation satisfies control requirements
- **ISO 27001**: Least privilege and audit logging check multiple boxes
- **PCI DSS**: Encryption and access controls align with requirements

### Operational Efficiency

- **No manual credential rotation**: Saves hours per quarter
- **Faster incident investigation**: Pod-level audit trail speeds up forensics
- **Reduced security toil**: Fewer credential-related tickets

## Common Pitfalls and How to Avoid Them

I've helped dozens of teams implement IRSA. Here are the mistakes I see most often:

### Pitfall 1: Forgetting the Service Account Annotation

**Symptom**: Pod logs show "Unable to locate credentials"

**Fix**: Verify the annotation exists:

```bash
kubectl get sa harbor-registry -n harbor -o yaml | grep eks.amazonaws.com
```

### Pitfall 2: Trust Policy Doesn't Match Service Account

**Symptom**: AssumeRoleWithWebIdentity fails

**Fix**: The trust policy condition must exactly match:
- Namespace: `harbor`
- Service account: `harbor-registry`

### Pitfall 3: Missing KMS Permissions

**Symptom**: S3 operations fail with KMS access denied

**Fix**: Add KMS permissions to the IAM role:

```json
{
  "Effect": "Allow",
  "Action": [
    "kms:Decrypt",
    "kms:GenerateDataKey"
  ],
  "Resource": "arn:aws:kms:region:account:key/key-id"
}
```

### Pitfall 4: Not Waiting for OIDC Provider Propagation

**Symptom**: Role assumption fails immediately after setup

**Fix**: Wait 5-10 minutes after creating the OIDC provider before testing.

## Infrastructure as Code: Make It Reproducible

Don't implement IRSA manually. Use Terraform to make it reproducible:

```hcl
module "irsa_harbor" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "HarborS3Role"

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["harbor:harbor-registry"]
    }
  }

  role_policy_arns = {
    policy = aws_iam_policy.harbor_s3_access.arn
  }
}
```

This ensures every environment gets the same secure configuration.

## The Migration Path: From Static Credentials to IRSA

Already running Harbor with static credentials? Here's how to migrate safely:

### Phase 1: Preparation (1 hour)

1. Enable OIDC on your EKS cluster
2. Create the IAM role with IRSA trust policy
3. Create the Kubernetes service account with annotation

### Phase 2: Parallel Run (1 week)

1. Deploy a test Harbor instance with IRSA
2. Validate S3 access works correctly
3. Run both instances in parallel
4. Monitor CloudTrail logs for both

### Phase 3: Cutover (1 hour)

1. Update production Harbor to use IRSA service account
2. Remove static credentials from Helm values
3. Restart Harbor pods
4. Verify S3 access works

### Phase 4: Cleanup (30 minutes)

1. Delete the IAM user
2. Delete the Kubernetes secret
3. Revoke the old access keys
4. Update documentation

Total migration time: ~2 hours of active work, 1 week of validation.

## Real-World Success Story

I recently helped a fintech company migrate their Harbor deployment from static credentials to IRSA. Here's what happened:

**Before:**
- 3 credential exposure incidents in 6 months
- 2 hours per quarter rotating credentials manually
- No way to trace S3 actions to specific pods
- Failed SOC 2 audit finding on credential management

**After:**
- Zero credential exposure incidents in 12 months
- Zero time spent on credential rotation
- Complete audit trail for compliance
- SOC 2 audit finding closed

**Their CISO's quote:** "This should have been our default from day one. The security improvement is night and day."

## Key Takeaways

If you remember nothing else from this article, remember these five points:

1. **Static credentials in Kubernetes secrets are not secure**. Base64 encoding is not encryption.

2. **IRSA provides temporary, automatically-rotated credentials** without storing anything. It's the AWS-native solution to the credential problem.

3. **Least privilege is non-negotiable**. Grant only the specific S3 actions Harbor needs, only on the specific bucket.

4. **Defense in depth matters**. Combine IRSA with KMS encryption, bucket policies, and network isolation.

5. **Validation is critical**. Don't assume it works—test that unauthorized access is denied and credentials rotate automatically.

## Your Next Steps

Ready to secure your Harbor deployment? Here's what to do next:

1. **Audit your current setup**: Do you have static credentials in Kubernetes secrets? If yes, you have work to do.

2. **Try the workshop**: I've created a complete hands-on workshop that walks you through implementing IRSA with Harbor. It includes:
   - Step-by-step instructions
   - Complete Terraform code
   - Validation tests
   - Troubleshooting guide

   👉 **[Get the workshop on GitHub](https://github.com/snblaise/secure-harbor-irsa-on-eks)**

3. **Start small**: Implement IRSA in a dev environment first. Validate it works. Then roll it out to production.

4. **Share your success**: Once you've implemented IRSA, share your experience with your team and the community. Security is a team sport.

## Conclusion: Security Doesn't Have to Be Hard

For years, teams have accepted static credentials as a necessary evil. "It's just how Kubernetes works," they said.

But it doesn't have to be that way. IRSA proves that security and convenience can coexist. You can have:

- ✅ No static credentials
- ✅ Automatic rotation
- ✅ Least privilege access
- ✅ Complete audit trail
- ✅ Easy implementation

The technology exists. The tools are mature. The documentation is comprehensive. The only question is: when will you make the switch?

Your future self—and your security team—will thank you.

---

## About This Workshop

This article is based on a comprehensive hands-on workshop I created for cloud security engineers. The workshop includes:

- Complete architecture diagrams
- Step-by-step implementation guide
- Terraform infrastructure as code
- Automated validation tests
- Security hardening best practices
- Troubleshooting guide

**Workshop Repository**: [secure-harbor-irsa-on-eks](https://github.com/snblaise/secure-harbor-irsa-on-eks)

**Estimated Time**: 3-4 hours  
**Level**: Intermediate to Advanced  
**Cost**: ~$2 for a complete workshop session

---

## Tags

`#AWS` `#Kubernetes` `#EKS` `#Security` `#CloudSecurity` `#DevSecOps` `#Harbor` `#ContainerSecurity` `#IRSA` `#IAM` `#BestPractices` `#CloudNative` `#InfrastructureAsCode` `#Terraform` `#S3` `#KMS` `#Encryption`

---

## Connect With Me

Found this helpful? Let's connect:

- **Medium**: [@shublaisengwa](https://medium.com/@shublaisengwa)
- **GitHub**: [snblaise](https://github.com/snblaise)
- **LinkedIn**: Connect with me on LinkedIn

Have questions about implementing IRSA? Drop a comment below or reach out directly. I'm always happy to help teams improve their cloud security posture.

---

**⚠️ Security Note**: This article includes examples of insecure configurations for educational purposes. Never use static IAM credentials in production Kubernetes environments. Always use IRSA or similar secure credential management solutions.

**💡 Pro Tip**: Bookmark this article and share it with your team. The best security improvements happen when everyone understands why they matter.

---

*Last updated: December 2025*
