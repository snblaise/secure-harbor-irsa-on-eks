# Workshop Validation Checkpoints

## Overview

This document provides validation checkpoints throughout the Harbor IRSA Workshop to ensure participants understand key concepts before progressing. Each checkpoint includes questions, hands-on exercises, and answer keys for self-assessment or instructor evaluation.

## How to Use This Document

- **For Participants**: Use checkpoints to verify your understanding before moving to the next phase
- **For Instructors**: Use checkpoints to assess participant progress and identify areas needing clarification
- **Timing**: Each checkpoint should take 5-10 minutes to complete

## Checkpoint 1: Security Fundamentals

**Phase**: After completing the introduction and insecure deployment demonstration

**Duration**: 10 minutes

### Knowledge Check Questions

**Question 1.1**: What are three security risks of storing AWS credentials in Kubernetes secrets?

**Question 1.2**: How does base64 encoding differ from encryption?

**Question 1.3**: What is the principle of least privilege, and why does it matter for IAM policies?

**Question 1.4**: In the insecure Harbor deployment, who can access the IAM credentials stored in the Kubernetes secret?

### Hands-On Validation Exercise

**Exercise 1.1**: Extract IAM Credentials from Kubernetes Secret

```bash
# Task: Extract the AWS_ACCESS_KEY_ID from the harbor-s3-credentials secret
kubectl get secret harbor-s3-credentials -n harbor -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d
```

**Success Criteria**: 
- ✅ You successfully extracted the access key ID
- ✅ You understand that anyone with kubectl access can do this
- ✅ You recognize this as a security vulnerability

### Answer Key

**Answer 1.1**: Three security risks of storing AWS credentials in Kubernetes secrets:
1. **Easy Extraction**: Anyone with kubectl access to the namespace can extract credentials using base64 decode
2. **No Automatic Rotation**: Credentials remain static and never rotate automatically, increasing exposure window
3. **Credential Sprawl**: Credentials can be copied, shared, or leaked to logs, making it difficult to track usage

**Answer 1.2**: Base64 encoding is NOT encryption:
- Base64 is a reversible encoding scheme that converts binary data to ASCII text
- It provides NO security or confidentiality
- Anyone can decode base64 without a key or password
- Encryption requires a secret key and is designed to protect confidentiality

**Answer 1.3**: Least privilege principle:
- Grant only the minimum permissions necessary to perform a specific task
- Reduces blast radius if credentials are compromised
- Limits lateral movement opportunities for attackers
- Makes audit and compliance easier by clearly defining access boundaries

**Answer 1.4**: In the insecure deployment, the following can access IAM credentials:
- Any user with `kubectl get secret` permissions in the harbor namespace
- Any pod running in the harbor namespace (via service account)
- Cluster administrators
- Anyone who gains access to etcd (where secrets are stored)
- Anyone who can view pod environment variables or logs

---

## Checkpoint 2: IRSA Architecture

**Phase**: After learning about IRSA concepts and OIDC provider setup

**Duration**: 10 minutes

### Knowledge Check Questions

**Question 2.1**: What is the role of the OIDC provider in IRSA?

**Question 2.2**: What information is contained in the JWT token that Kubernetes issues to a pod?

**Question 2.3**: How does AWS IAM verify that a JWT token is valid and should be trusted?

**Question 2.4**: What happens when a pod's JWT token expires?

### Hands-On Validation Exercise

**Exercise 2.1**: Inspect the OIDC Provider Configuration

```bash
# Task: Get your EKS cluster's OIDC provider URL
aws eks describe-cluster --name <your-cluster-name> --query "cluster.identity.oidc.issuer" --output text

# Task: List IAM OIDC providers in your account
aws iam list-open-id-connect-providers

# Task: Verify the OIDC provider exists for your cluster
```

**Success Criteria**:
- ✅ You can retrieve your cluster's OIDC issuer URL
- ✅ You can confirm the OIDC provider is registered in IAM
- ✅ You understand the relationship between EKS and IAM OIDC provider

### Answer Key

**Answer 2.1**: The OIDC provider's role in IRSA:
- Acts as a trusted identity provider that bridges Kubernetes and AWS IAM
- Issues JWT tokens to pods that contain service account identity information
- Provides a public endpoint where AWS can verify token signatures
- Enables AWS STS to exchange JWT tokens for temporary AWS credentials

**Answer 2.2**: JWT token contents:
- **Subject (sub)**: The Kubernetes service account identity (e.g., `system:serviceaccount:harbor:harbor-registry`)
- **Audience (aud)**: The intended recipient, typically `sts.amazonaws.com`
- **Issuer (iss)**: The EKS OIDC provider URL
- **Expiration (exp)**: Token expiration timestamp (typically 24 hours)
- **Issued At (iat)**: Token issuance timestamp
- **Namespace and service account name**: Embedded in the subject claim

**Answer 2.3**: AWS IAM verification process:
1. AWS STS receives the JWT token from the pod
2. STS extracts the issuer (iss) claim and looks up the registered OIDC provider
3. STS retrieves the public keys from the OIDC provider's JWKS endpoint
4. STS verifies the token signature using the public key
5. STS validates the token hasn't expired and checks the audience claim
6. If valid, STS checks if an IAM role trusts this OIDC provider and subject
7. If trust policy matches, STS issues temporary AWS credentials

**Answer 2.4**: When a JWT token expires:
- The Kubernetes kubelet automatically requests a new token from the API server
- The new token is written to the projected volume mount
- The AWS SDK detects the new token and uses it for subsequent API calls
- This happens transparently without pod restart or manual intervention
- Default token lifetime is 86400 seconds (24 hours)

---

## Checkpoint 3: IAM Policy Design

**Phase**: After creating IAM roles and policies for Harbor

**Duration**: 10 minutes

### Knowledge Check Questions

**Question 3.1**: What is the difference between a trust policy and a permissions policy?

**Question 3.2**: In the Harbor IAM role trust policy, what condition restricts which service accounts can assume the role?

**Question 3.3**: Why is it important to scope S3 permissions to a specific bucket rather than using `s3:*` on `*`?

**Question 3.4**: What IAM actions does Harbor need for S3 storage? List at least 4.

### Hands-On Validation Exercise

**Exercise 3.1**: Review and Validate IAM Policy

```bash
# Task: Get the Harbor IAM role ARN
export HARBOR_ROLE_ARN=$(aws iam get-role --role-name HarborS3Role --query 'Role.Arn' --output text)

# Task: View the trust policy
aws iam get-role --role-name HarborS3Role --query 'Role.AssumeRolePolicyDocument'

# Task: List attached policies
aws iam list-attached-role-policies --role-name HarborS3Role

# Task: View the permissions policy
aws iam get-policy-version --policy-arn <policy-arn> --version-id v1
```

**Success Criteria**:
- ✅ You can retrieve and read the trust policy
- ✅ You can identify the service account restriction in the trust policy
- ✅ You can list the S3 and KMS permissions granted
- ✅ You understand why each permission is necessary

### Answer Key

**Answer 3.1**: Trust policy vs. permissions policy:
- **Trust Policy**: Defines WHO can assume the role (which principals/identities)
  - Attached to the role itself
  - Controls authentication (who can use this role)
  - Example: Allow OIDC provider with specific service account subject
- **Permissions Policy**: Defines WHAT the role can do (which actions on which resources)
  - Attached to the role or inherited
  - Controls authorization (what actions are allowed)
  - Example: Allow s3:PutObject on specific bucket

**Answer 3.2**: Service account restriction in trust policy:
```json
"Condition": {
  "StringEquals": {
    "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:harbor:harbor-registry"
  }
}
```
This condition ensures only pods using the `harbor-registry` service account in the `harbor` namespace can assume the role.

**Answer 3.3**: Importance of scoping S3 permissions:
- **Least Privilege**: Limits access to only the bucket Harbor needs
- **Blast Radius**: If credentials are compromised, attacker can't access other buckets
- **Compliance**: Demonstrates proper access control for audit requirements
- **Mistake Prevention**: Prevents accidental deletion or modification of unrelated data
- **Multi-Tenancy**: Allows multiple workloads to use different buckets safely

**Answer 3.4**: IAM actions Harbor needs for S3:
1. **s3:PutObject**: Upload container images and artifacts
2. **s3:GetObject**: Download container images and artifacts
3. **s3:DeleteObject**: Remove old or deleted images
4. **s3:ListBucket**: List objects in the bucket for inventory
5. **s3:GetBucketLocation**: Determine bucket region for proper endpoint usage
6. **kms:Decrypt**: Decrypt objects encrypted with KMS
7. **kms:GenerateDataKey**: Generate data keys for encrypting new objects

---

## Checkpoint 4: Kubernetes Service Account Configuration

**Phase**: After configuring service accounts and deploying Harbor

**Duration**: 10 minutes


### Knowledge Check Questions

**Question 4.1**: What annotation must be added to a Kubernetes service account to enable IRSA?

**Question 4.2**: Where is the JWT token mounted in a pod that uses IRSA?

**Question 4.3**: How does the AWS SDK know to use the projected service account token instead of looking for static credentials?

**Question 4.4**: What happens if you forget to add the IAM role annotation to the service account?

### Hands-On Validation Exercise

**Exercise 4.1**: Verify Service Account Configuration

```bash
# Task: Check the service account has the correct annotation
kubectl get serviceaccount harbor-registry -n harbor -o yaml

# Task: Verify a Harbor pod is using the service account
kubectl get pods -n harbor -o jsonpath='{.items[0].spec.serviceAccountName}'

# Task: Check that the token is mounted in the pod
kubectl exec -n harbor <harbor-pod-name> -- ls -la /var/run/secrets/eks.amazonaws.com/serviceaccount/

# Task: Inspect the token (first few characters)
kubectl exec -n harbor <harbor-pod-name> -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token | cut -c1-50
```

**Success Criteria**:
- ✅ Service account has `eks.amazonaws.com/role-arn` annotation
- ✅ Harbor pod is using the correct service account
- ✅ Token file exists in the projected volume mount
- ✅ Token is a JWT (starts with `eyJ`)

### Answer Key

**Answer 4.1**: Required annotation:
```yaml
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/HarborS3Role
```
This annotation tells the EKS pod identity webhook to inject the IAM role information.

**Answer 4.2**: JWT token mount location:
- **Path**: `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
- **Type**: Projected volume (not a regular secret)
- **Refresh**: Automatically refreshed by kubelet before expiration
- **Permissions**: Readable only by the pod's user

**Answer 4.3**: AWS SDK credential discovery:
The AWS SDK follows a credential provider chain:
1. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
2. Web identity token file (AWS_WEB_IDENTITY_TOKEN_FILE environment variable)
3. ECS container credentials
4. EC2 instance metadata

For IRSA, the EKS pod identity webhook automatically sets:
- `AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
- `AWS_ROLE_ARN=<role-arn-from-annotation>`

The SDK detects these environment variables and uses the web identity token flow.

**Answer 4.4**: If annotation is missing:
- The pod identity webhook won't inject the AWS_ROLE_ARN environment variable
- The AWS SDK won't know which role to assume
- Harbor will fail to access S3 with error: "Unable to locate credentials"
- Pod logs will show authentication failures
- Harbor will not start properly or will fail when trying to push/pull images

---

## Checkpoint 5: Access Control Validation

**Phase**: After deploying Harbor and running initial validation tests

**Duration**: 10 minutes

### Knowledge Check Questions

**Question 5.1**: What should happen when a pod in a different namespace tries to access the S3 bucket?

**Question 5.2**: How can you verify that Harbor is using IRSA and not static credentials?

**Question 5.3**: What information in CloudTrail logs proves that IRSA is being used?

**Question 5.4**: Why is it important to test unauthorized access scenarios?

### Hands-On Validation Exercise

**Exercise 5.1**: Test Access Controls

```bash
# Task 1: Verify Harbor can access S3
kubectl exec -n harbor <harbor-pod-name> -- aws s3 ls s3://<bucket-name>/

# Task 2: Create an unauthorized pod in a different namespace
kubectl create namespace test-unauthorized
kubectl run test-pod -n test-unauthorized --image=amazon/aws-cli --command -- sleep 3600

# Task 3: Try to access S3 from unauthorized pod (should fail)
kubectl exec -n test-unauthorized test-pod -- aws s3 ls s3://<bucket-name>/

# Task 4: Check CloudTrail for the access attempt
aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=<bucket-name> --max-results 5
```

**Success Criteria**:
- ✅ Harbor pod successfully accesses S3
- ✅ Unauthorized pod receives "Access Denied" error
- ✅ CloudTrail shows the assumed role ARN with session name
- ✅ You understand why access control worked correctly

### Answer Key

**Answer 5.1**: Unauthorized namespace access:
- The pod will receive an "Access Denied" error from S3
- The IAM trust policy restricts role assumption to `harbor:harbor-registry` service account
- Even if the pod has a service account with the same name, it's in a different namespace
- The OIDC subject claim includes the namespace, so the trust policy won't match
- This demonstrates fine-grained access control at the namespace level

**Answer 5.2**: Verifying IRSA usage (no static credentials):
```bash
# Check environment variables - should NOT see AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY
kubectl exec -n harbor <pod> -- env | grep AWS

# Should see:
# AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
# AWS_ROLE_ARN=arn:aws:iam::ACCOUNT:role/HarborS3Role
# AWS_REGION=us-east-1

# Check for secrets in the namespace - should NOT have credential secrets
kubectl get secrets -n harbor

# Verify no static credentials in pod spec
kubectl get pod <pod> -n harbor -o yaml | grep -i "AWS_ACCESS_KEY_ID"
# Should return nothing
```

**Answer 5.3**: CloudTrail evidence of IRSA:
Look for these indicators in CloudTrail logs:
- **Event Name**: `AssumeRoleWithWebIdentity`
- **User Identity Type**: `WebIdentityUser`
- **Principal ID**: Contains the OIDC provider and subject (service account)
- **Session Name**: Often includes pod name or UID
- **Assumed Role ARN**: Shows the Harbor IAM role
- **Source IP**: The EKS node IP where the pod is running

Example CloudTrail entry:
```json
{
  "eventName": "AssumeRoleWithWebIdentity",
  "userIdentity": {
    "type": "WebIdentityUser",
    "principalId": "arn:aws:sts::ACCOUNT:assumed-role/HarborS3Role/eks-harbor-harbor-registry-...",
    "userName": "system:serviceaccount:harbor:harbor-registry"
  }
}
```

**Answer 5.4**: Importance of testing unauthorized access:
- **Validates Security Controls**: Confirms that access restrictions actually work
- **Identifies Misconfigurations**: Catches overly permissive policies before production
- **Demonstrates Defense in Depth**: Shows multiple layers of security (IAM + Kubernetes)
- **Compliance Evidence**: Provides proof for auditors that access controls are enforced
- **Builds Confidence**: Gives assurance that the security model is correctly implemented

---

## Checkpoint 6: Encryption and Key Management

**Phase**: After configuring S3 encryption with KMS

**Duration**: 10 minutes

### Knowledge Check Questions

**Question 6.1**: What is the difference between SSE-S3 and SSE-KMS encryption?

**Question 6.2**: Why use a customer-managed key (CMK) instead of an AWS-managed key?

**Question 6.3**: What KMS permissions does Harbor need to work with encrypted S3 objects?

**Question 6.4**: How does the S3 bucket policy enforce encryption?

### Hands-On Validation Exercise

**Exercise 6.1**: Verify Encryption Configuration

```bash
# Task 1: Check S3 bucket encryption configuration
aws s3api get-bucket-encryption --bucket <bucket-name>

# Task 2: Verify KMS key exists and is enabled
aws kms describe-key --key-id alias/harbor-s3-encryption

# Task 3: Check KMS key policy allows Harbor role
aws kms get-key-policy --key-id alias/harbor-s3-encryption --policy-name default

# Task 4: Upload a test object and verify it's encrypted
kubectl exec -n harbor <pod> -- sh -c "echo 'test' | aws s3 cp - s3://<bucket>/test.txt"
aws s3api head-object --bucket <bucket-name> --key test.txt --query 'ServerSideEncryption'
```

**Success Criteria**:
- ✅ Bucket has SSE-KMS encryption enabled
- ✅ KMS key is active and has automatic rotation enabled
- ✅ KMS key policy allows Harbor role to decrypt and generate data keys
- ✅ Uploaded objects are encrypted with the CMK

### Answer Key

**Answer 6.1**: SSE-S3 vs. SSE-KMS:

**SSE-S3 (Server-Side Encryption with S3-Managed Keys)**:
- S3 manages encryption keys automatically
- No visibility into key usage or rotation
- No ability to control key policies
- No CloudTrail logs for key usage
- Lower cost (no KMS charges)

**SSE-KMS (Server-Side Encryption with KMS-Managed Keys)**:
- Customer controls the encryption key
- Full visibility into key usage via CloudTrail
- Granular key policies control who can use the key
- Automatic key rotation available
- Additional KMS costs apply
- Better for compliance requirements

**Answer 6.2**: Benefits of customer-managed keys (CMK):
- **Access Control**: Define exactly who can use the key via key policy
- **Audit Trail**: CloudTrail logs every key usage for compliance
- **Key Rotation**: Control rotation schedule and policy
- **Compliance**: Meet regulatory requirements for customer-controlled encryption
- **Revocation**: Ability to disable key and immediately revoke access to encrypted data
- **Cross-Account**: Can grant access to keys across AWS accounts

**Answer 6.3**: KMS permissions Harbor needs:
```json
{
  "Action": [
    "kms:Decrypt",           // Decrypt existing objects when reading from S3
    "kms:GenerateDataKey",   // Generate data keys for encrypting new objects
    "kms:DescribeKey"        // Get key metadata and status
  ]
}
```

Additional context:
- `kms:Decrypt`: Required when Harbor reads encrypted objects from S3
- `kms:GenerateDataKey`: Required when Harbor writes new objects to S3
- S3 uses envelope encryption: generates a data key with KMS, encrypts object with data key
- The condition `kms:ViaService: s3.REGION.amazonaws.com` ensures key is only used via S3

**Answer 6.4**: S3 bucket policy enforcement:
```json
{
  "Sid": "DenyUnencryptedObjectUploads",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::bucket-name/*",
  "Condition": {
    "StringNotEquals": {
      "s3:x-amz-server-side-encryption": "aws:kms"
    }
  }
}
```

This policy:
- Denies any PutObject request that doesn't specify KMS encryption
- Applies to all principals (even if they have s3:PutObject permission)
- Ensures no unencrypted objects can be uploaded
- Provides defense in depth (even if client misconfigured)

---

## Checkpoint 7: Audit and Compliance

**Phase**: After reviewing CloudTrail logs and audit capabilities

**Duration**: 10 minutes

### Knowledge Check Questions

**Question 7.1**: How can you trace an S3 API call back to a specific Kubernetes pod?

**Question 7.2**: What is the difference in audit trails between IAM user access and IRSA access?

**Question 7.3**: How long does it take for CloudTrail events to appear after an API call?

**Question 7.4**: What compliance benefits does IRSA provide over static IAM credentials?

### Hands-On Validation Exercise

**Exercise 7.1**: Analyze Audit Logs

```bash
# Task 1: Generate an S3 access event
kubectl exec -n harbor <pod> -- aws s3 ls s3://<bucket>/

# Task 2: Wait 5-15 minutes for CloudTrail propagation

# Task 3: Query CloudTrail for recent S3 events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=<bucket-name> \
  --max-results 10 \
  --output json > cloudtrail-events.json

# Task 4: Extract the assumed role session name
cat cloudtrail-events.json | jq '.Events[0].CloudTrailEvent' | jq -r '.userIdentity.principalId'

# Task 5: Correlate with Kubernetes pod
kubectl get pods -n harbor -o wide
```

**Success Criteria**:
- ✅ You can find the S3 access event in CloudTrail
- ✅ You can identify the assumed role ARN
- ✅ You can see the session name that includes pod information
- ✅ You understand how to trace access back to specific pods

### Answer Key

**Answer 7.1**: Tracing S3 calls to Kubernetes pods:

**Step 1**: Find the CloudTrail event for the S3 API call
**Step 2**: Extract the `userIdentity.principalId` which contains:
- Format: `arn:aws:sts::ACCOUNT:assumed-role/HarborS3Role/eks-harbor-harbor-registry-<pod-uid>`
- The session name includes namespace, service account, and pod UID

**Step 3**: Extract the pod UID from the session name
**Step 4**: Find the pod in Kubernetes:
```bash
kubectl get pods -n harbor -o json | jq '.items[] | select(.metadata.uid=="<pod-uid>") | .metadata.name'
```

**Step 5**: Get additional pod details:
```bash
kubectl describe pod <pod-name> -n harbor
```

This provides complete traceability from AWS API call → IAM role → Service account → Pod → Node

**Answer 7.2**: Audit trail comparison:

**IAM User Access**:
- **Identity**: Shows IAM user name (e.g., `harbor-s3-user`)
- **Attribution**: All actions appear as the same user
- **Granularity**: Cannot distinguish between different pods/applications
- **Session**: Long-lived credentials, no session information
- **Traceability**: Cannot trace back to specific pod or namespace
- **Example**: `"userName": "harbor-s3-user"`

**IRSA Access**:
- **Identity**: Shows assumed role with session name
- **Attribution**: Each pod gets unique session name
- **Granularity**: Can identify exact pod, namespace, and service account
- **Session**: Temporary credentials with session metadata
- **Traceability**: Full path from API call to specific pod
- **Example**: `"principalId": "arn:aws:sts::ACCOUNT:assumed-role/HarborS3Role/eks-harbor-harbor-registry-abc123"`

**Answer 7.3**: CloudTrail event delivery time:
- **Typical Delay**: 5-15 minutes after the API call
- **Why**: CloudTrail aggregates events and delivers them in batches
- **Management Events**: Usually appear within 15 minutes
- **Data Events**: May take longer (if enabled)
- **Real-time Needs**: Use CloudWatch Events for near real-time notifications
- **Workshop Impact**: Explain delay to participants; have them work on other tasks while waiting

**Answer 7.4**: Compliance benefits of IRSA:

1. **Credential Lifecycle Management**:
   - Automatic rotation eliminates manual credential management
   - No long-lived credentials to track or rotate
   - Reduces risk of credential exposure

2. **Audit and Traceability**:
   - Complete audit trail with pod-level attribution
   - Can prove which workload accessed which resource when
   - Supports non-repudiation requirements

3. **Least Privilege**:
   - Fine-grained access control per service account
   - Easy to implement and verify least privilege
   - Reduces blast radius of compromised credentials

4. **Compliance Frameworks**:
   - **SOC 2**: Demonstrates access control and audit logging
   - **ISO 27001**: Shows credential management and access control
   - **PCI-DSS**: Supports requirement for unique IDs and audit trails
   - **HIPAA**: Demonstrates access control and audit capabilities

5. **Separation of Duties**:
   - Different teams can manage Kubernetes and AWS permissions
   - Clear boundaries between platform and application teams

---

## Checkpoint 8: Troubleshooting and Operations

**Phase**: After completing the workshop and discussing operational considerations

**Duration**: 10 minutes

### Knowledge Check Questions

**Question 8.1**: What are three common misconfigurations that prevent IRSA from working?

**Question 8.2**: How would you troubleshoot a "Unable to locate credentials" error in a pod?

**Question 8.3**: What operational benefits does IRSA provide compared to managing IAM user credentials?

**Question 8.4**: When would you NOT want to use IRSA?

### Hands-On Validation Exercise

**Exercise 8.1**: Troubleshooting Challenge

```bash
# Scenario: A pod cannot access S3. Diagnose the issue.

# Task 1: Check if service account has the annotation
kubectl get sa <service-account> -n <namespace> -o yaml | grep eks.amazonaws.com/role-arn

# Task 2: Verify pod is using the correct service account
kubectl get pod <pod> -n <namespace> -o jsonpath='{.spec.serviceAccountName}'

# Task 3: Check if token is mounted
kubectl exec -n <namespace> <pod> -- ls /var/run/secrets/eks.amazonaws.com/serviceaccount/

# Task 4: Verify environment variables are set
kubectl exec -n <namespace> <pod> -- env | grep AWS

# Task 5: Check IAM role trust policy
aws iam get-role --role-name <role-name> --query 'Role.AssumeRolePolicyDocument'

# Task 6: Test role assumption manually
aws sts assume-role-with-web-identity \
  --role-arn <role-arn> \
  --role-session-name test \
  --web-identity-token $(kubectl exec -n <namespace> <pod> -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token)
```

**Success Criteria**:
- ✅ You can systematically check each component of IRSA
- ✅ You can identify which component is misconfigured
- ✅ You know how to fix common issues
- ✅ You understand the troubleshooting workflow

### Answer Key

**Answer 8.1**: Three common IRSA misconfigurations:

1. **Missing or Incorrect Service Account Annotation**:
   - Symptom: "Unable to locate credentials"
   - Cause: Service account missing `eks.amazonaws.com/role-arn` annotation
   - Fix: Add annotation with correct IAM role ARN

2. **IAM Trust Policy Mismatch**:
   - Symptom: "Not authorized to perform sts:AssumeRoleWithWebIdentity"
   - Cause: Trust policy subject doesn't match actual service account/namespace
   - Fix: Update trust policy with correct `system:serviceaccount:namespace:sa-name`

3. **OIDC Provider Not Configured**:
   - Symptom: "OpenIDConnect provider not found"
   - Cause: IAM OIDC provider not created for the EKS cluster
   - Fix: Create OIDC provider in IAM with correct thumbprint

**Answer 8.2**: Troubleshooting "Unable to locate credentials":

**Step 1**: Check service account annotation
```bash
kubectl get sa <sa-name> -n <namespace> -o yaml
# Look for: eks.amazonaws.com/role-arn annotation
```

**Step 2**: Verify pod is using the service account
```bash
kubectl get pod <pod> -n <namespace> -o jsonpath='{.spec.serviceAccountName}'
```

**Step 3**: Check environment variables in pod
```bash
kubectl exec <pod> -n <namespace> -- env | grep AWS
# Should see: AWS_ROLE_ARN and AWS_WEB_IDENTITY_TOKEN_FILE
```

**Step 4**: Verify token file exists
```bash
kubectl exec <pod> -n <namespace> -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token
# Should return a JWT token
```

**Step 5**: Check pod logs for specific errors
```bash
kubectl logs <pod> -n <namespace>
```

**Step 6**: Verify IAM role exists and trust policy is correct
```bash
aws iam get-role --role-name <role-name>
```

**Answer 8.3**: Operational benefits of IRSA:

1. **No Credential Rotation Burden**:
   - Credentials rotate automatically every 24 hours
   - No manual rotation procedures or scripts needed
   - No risk of forgetting to rotate credentials

2. **Simplified Credential Distribution**:
   - No need to securely distribute credentials to pods
   - No secrets to manage in Kubernetes
   - No risk of credentials in version control

3. **Easier Onboarding**:
   - New workloads just need service account annotation
   - No credential generation or distribution process
   - Faster time to production

4. **Reduced Incident Response**:
   - If credentials compromised, they expire quickly
   - Can revoke access by updating IAM policy or deleting role
   - Clear audit trail for forensics

5. **Lower Operational Complexity**:
   - Fewer moving parts (no secrets, no rotation jobs)
   - Less documentation and runbooks needed
   - Fewer potential failure points

**Answer 8.4**: When NOT to use IRSA:

1. **Non-EKS Kubernetes**: IRSA is EKS-specific; use alternatives like:
   - Workload Identity (GKE)
   - Pod Identity (AKS)
   - SPIFFE/SPIRE (self-managed)

2. **Cross-Account Access with Complex Requirements**:
   - If you need to assume multiple roles in different accounts
   - Consider using a custom credential provider or AWS STS directly

3. **Legacy Applications**:
   - Applications that don't support AWS SDK credential chain
   - Applications that require credentials in specific formats
   - May need to use static credentials or credential proxy

4. **Very Short-Lived Workloads**:
   - Jobs that complete in seconds may not benefit
   - Overhead of token exchange might not be worth it
   - Static credentials might be simpler (if properly secured)

5. **Development/Testing Environments**:
   - Local development outside Kubernetes
   - CI/CD pipelines that don't run in EKS
   - Use IAM users or roles with appropriate restrictions

---

## Summary Checkpoint: Final Assessment

**Phase**: End of workshop

**Duration**: 15 minutes

### Comprehensive Knowledge Check

**Question F.1**: Explain the complete flow of how a Harbor pod accesses S3 using IRSA, from pod startup to S3 API call.

**Question F.2**: Compare and contrast the security posture of IAM user tokens vs. IRSA across 5 dimensions.

**Question F.3**: You need to give a new application access to DynamoDB using IRSA. What steps would you take?

### Final Hands-On Exercise

**Exercise F.1**: Deploy a New Workload with IRSA

```bash
# Challenge: Deploy a simple application that lists S3 buckets using IRSA

# Step 1: Create IAM role and policy
# Step 2: Create Kubernetes service account with annotation
# Step 3: Deploy pod using the service account
# Step 4: Verify the pod can list S3 buckets
# Step 5: Verify unauthorized pods cannot list buckets
```

**Success Criteria**:
- ✅ You can implement IRSA for a new workload from scratch
- ✅ You can verify access controls are working
- ✅ You can troubleshoot any issues that arise
- ✅ You understand the security benefits and operational considerations

### Answer Key

**Answer F.1**: Complete IRSA flow:

1. **Pod Startup**:
   - Pod spec references service account with `eks.amazonaws.com/role-arn` annotation
   - Kubernetes API server creates the pod
   - EKS pod identity webhook intercepts pod creation

2. **Token Injection**:
   - Webhook adds projected volume mount for service account token
   - Webhook sets environment variables: AWS_ROLE_ARN, AWS_WEB_IDENTITY_TOKEN_FILE
   - Kubelet requests JWT token from API server
   - Token is written to `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`

3. **Application Startup**:
   - Harbor application starts and initializes AWS SDK
   - SDK reads AWS_ROLE_ARN and AWS_WEB_IDENTITY_TOKEN_FILE environment variables
   - SDK enters web identity token credential provider mode

4. **First S3 API Call**:
   - Application calls S3 API (e.g., PutObject)
   - SDK reads JWT token from file
   - SDK calls AWS STS AssumeRoleWithWebIdentity with token and role ARN

5. **Token Validation**:
   - STS validates JWT signature using OIDC provider's public keys
   - STS checks token expiration and audience
   - STS verifies IAM role trust policy matches token subject

6. **Credential Issuance**:
   - STS issues temporary credentials (access key, secret key, session token)
   - Credentials valid for 1 hour (default)
   - SDK caches credentials in memory

7. **S3 Access**:
   - SDK signs S3 request with temporary credentials
   - S3 validates credentials and checks IAM permissions policy
   - S3 processes request and returns response

8. **Credential Refresh**:
   - SDK automatically refreshes credentials before expiration
   - Process repeats from step 4
   - JWT token itself refreshes every 24 hours (kubelet handles this)

**Answer F.2**: Security comparison table:

| Dimension | IAM User Tokens | IRSA | Winner |
|-----------|----------------|------|--------|
| **Credential Lifetime** | Permanent until manually rotated | 24-hour JWT, 1-hour AWS credentials | IRSA |
| **Rotation** | Manual, error-prone, often forgotten | Automatic, transparent | IRSA |
| **Least Privilege** | Often overprivileged, hard to scope | Easy to scope per service account | IRSA |
| **Audit Trail** | All actions appear as same user | Pod-level attribution | IRSA |
| **Credential Storage** | Kubernetes secrets (base64) | Projected token (auto-refreshed) | IRSA |
| **Blast Radius** | High - credentials work anywhere | Low - bound to specific namespace/SA | IRSA |
| **Extraction Risk** | Easy to extract and reuse | Token expires quickly, limited scope | IRSA |
| **Operational Burden** | High - manual rotation, distribution | Low - fully automated | IRSA |
| **Compliance** | Difficult to prove controls | Clear audit trail and controls | IRSA |
| **Setup Complexity** | Simple - create user, add to secret | Moderate - OIDC, IAM, annotations | IAM User |

**Overall Winner**: IRSA provides significantly better security with lower operational burden, despite slightly higher initial setup complexity.

**Answer F.3**: Steps to give new application IRSA access to DynamoDB:

**Step 1**: Create IAM permissions policy
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ],
    "Resource": "arn:aws:dynamodb:REGION:ACCOUNT:table/my-table"
  }]
}
```

**Step 2**: Create IAM role with trust policy
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:my-namespace:my-app-sa"
      }
    }
  }]
}
```

**Step 3**: Create Kubernetes service account
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  namespace: my-namespace
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/MyAppDynamoDBRole
```

**Step 4**: Deploy application using the service account
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-namespace
spec:
  template:
    spec:
      serviceAccountName: my-app-sa
      containers:
      - name: app
        image: my-app:latest
```

**Step 5**: Verify access
```bash
kubectl exec -n my-namespace <pod> -- aws dynamodb list-tables
```

**Step 6**: Test unauthorized access
```bash
# Create pod without service account - should fail
kubectl run test -n my-namespace --image=amazon/aws-cli -- aws dynamodb list-tables
```

---

## Checkpoint Usage Guidelines

### For Self-Paced Learning

- Complete each checkpoint before moving to the next phase
- If you can't answer a question, review the relevant documentation section
- Use the hands-on exercises to verify your understanding
- Don't skip checkpoints - they build on each other

### For Instructor-Led Workshops

- Use checkpoints as natural break points in the workshop
- Allow 5-10 minutes for participants to complete each checkpoint
- Review answers as a group to reinforce learning
- Use checkpoint results to identify topics needing more explanation

### For Assessment

- Checkpoints can be used for formative assessment during the workshop
- Final checkpoint serves as summative assessment
- Participants should be able to answer 80% of questions correctly
- Hands-on exercises should all complete successfully

## Conclusion

These validation checkpoints ensure participants build a solid foundation of knowledge throughout the workshop. By verifying understanding at each phase, we prevent knowledge gaps from accumulating and ensure participants can successfully apply IRSA concepts in their own environments.
