# Incident Investigation Guide

## Overview

This guide provides step-by-step procedures for investigating security incidents involving Harbor IRSA deployments. It covers how to trace access back to specific pods, identify unauthorized activity, and conduct thorough incident investigations using CloudTrail logs, Kubernetes audit logs, and IAM access patterns.

## Table of Contents

1. [Investigation Framework](#investigation-framework)
2. [Tracing Access to Specific Pods](#tracing-access-to-specific-pods)
3. [Namespace and Pod Identification](#namespace-and-pod-identification)
4. [Investigation Workflows](#investigation-workflows)
5. [Common Incident Scenarios](#common-incident-scenarios)
6. [Forensic Data Collection](#forensic-data-collection)
7. [Incident Response Procedures](#incident-response-procedures)

## Investigation Framework

### Initial Response Checklist

When a security incident is detected:

1. **Preserve Evidence**: Ensure CloudTrail and Kubernetes logs are preserved
2. **Assess Scope**: Determine what resources were accessed
3. **Identify Timeline**: Establish when the incident occurred
4. **Trace Identity**: Identify which pod/service account was involved
5. **Contain Threat**: Take immediate action if ongoing
6. **Document Findings**: Record all investigation steps and findings

### Investigation Tools

- **AWS CloudTrail**: API call logs with identity information
- **Kubernetes Audit Logs**: Pod and service account activity
- **kubectl**: Query Kubernetes resources
- **AWS CLI**: Query IAM and CloudTrail
- **jq**: Parse JSON logs
- **CloudWatch Logs Insights**: Query and analyze logs


## Tracing Access to Specific Pods

### Step 1: Identify the CloudTrail Event

When investigating suspicious S3 access, start with CloudTrail:

```bash
# Find S3 access events for Harbor bucket
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::S3::Bucket \
  --start-time "2024-12-03T10:00:00Z" \
  --end-time "2024-12-03T11:00:00Z" \
  --query 'Events[?contains(CloudTrailEvent, `harbor-registry-storage`)].CloudTrailEvent' \
  --output text | jq .
```

### Step 2: Extract Key Information

From the CloudTrail event, extract:

```bash
# Parse CloudTrail event to extract key details
EVENT_JSON='<cloudtrail-event-json>'

# Extract timestamp
TIMESTAMP=$(echo $EVENT_JSON | jq -r '.eventTime')
echo "Event Time: $TIMESTAMP"

# Extract source IP
SOURCE_IP=$(echo $EVENT_JSON | jq -r '.sourceIPAddress')
echo "Source IP: $SOURCE_IP"

# Extract service account (for IRSA)
SERVICE_ACCOUNT=$(echo $EVENT_JSON | jq -r '.userIdentity.sessionContext.webIdFederationData.attributes.sub')
echo "Service Account: $SERVICE_ACCOUNT"

# Extract IAM role
IAM_ROLE=$(echo $EVENT_JSON | jq -r '.userIdentity.sessionContext.sessionIssuer.userName')
echo "IAM Role: $IAM_ROLE"

# Extract event name (action performed)
EVENT_NAME=$(echo $EVENT_JSON | jq -r '.eventName')
echo "Action: $EVENT_NAME"

# Extract resource accessed
RESOURCE=$(echo $EVENT_JSON | jq -r '.resources[].ARN')
echo "Resource: $RESOURCE"
```

### Step 3: Correlate with Kubernetes

Use the extracted information to find the specific pod:

```bash
# Extract namespace and service account name from the 'sub' attribute
# Format: system:serviceaccount:namespace:service-account-name
NAMESPACE=$(echo $SERVICE_ACCOUNT | cut -d: -f3)
SA_NAME=$(echo $SERVICE_ACCOUNT | cut -d: -f4)

echo "Namespace: $NAMESPACE"
echo "Service Account: $SA_NAME"

# Find pods using this service account
kubectl get pods -n $NAMESPACE \
  --field-selector spec.serviceAccountName=$SA_NAME \
  -o wide

# Find the specific pod by IP address
kubectl get pods -n $NAMESPACE \
  --field-selector spec.serviceAccountName=$SA_NAME \
  -o json | jq -r ".items[] | select(.status.podIP==\"$SOURCE_IP\") | .metadata.name"
```

### Step 4: Get Pod Details

Once you've identified the pod:

```bash
POD_NAME="<identified-pod-name>"

# Get full pod details
kubectl describe pod $POD_NAME -n $NAMESPACE

# Get pod logs
kubectl logs $POD_NAME -n $NAMESPACE --since-time="$TIMESTAMP"

# Get pod events
kubectl get events -n $NAMESPACE \
  --field-selector involvedObject.name=$POD_NAME \
  --sort-by='.lastTimestamp'

# Get pod YAML configuration
kubectl get pod $POD_NAME -n $NAMESPACE -o yaml
```


## Namespace and Pod Identification

### Identifying All Pods with IRSA Access

```bash
# List all service accounts with IRSA annotations
kubectl get serviceaccounts --all-namespaces \
  -o json | jq -r '.items[] | select(.metadata.annotations."eks.amazonaws.com/role-arn" != null) | "\(.metadata.namespace)/\(.metadata.name) -> \(.metadata.annotations."eks.amazonaws.com/role-arn")"'

# For each service account, list pods
kubectl get serviceaccounts --all-namespaces \
  -o json | jq -r '.items[] | select(.metadata.annotations."eks.amazonaws.com/role-arn" != null) | "\(.metadata.namespace) \(.metadata.name)"' | \
while read NAMESPACE SA_NAME; do
  echo "=== $NAMESPACE/$SA_NAME ==="
  kubectl get pods -n $NAMESPACE \
    --field-selector spec.serviceAccountName=$SA_NAME \
    -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,IP:.status.podIP,NODE:.spec.nodeName
  echo ""
done
```

### Mapping Pods to IAM Roles

```bash
#!/bin/bash
# Script to create a complete mapping of pods to IAM roles

echo "=== Pod to IAM Role Mapping ==="
echo ""

# Get all namespaces
NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')

for NS in $NAMESPACES; do
  # Get all pods in namespace
  PODS=$(kubectl get pods -n $NS -o json)
  
  # For each pod, get service account and role
  echo "$PODS" | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name) \(.spec.serviceAccountName)"' | \
  while read NAMESPACE POD_NAME SA_NAME; do
    # Get role ARN from service account
    ROLE_ARN=$(kubectl get serviceaccount $SA_NAME -n $NAMESPACE \
      -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null)
    
    if [ -n "$ROLE_ARN" ]; then
      POD_IP=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.podIP}')
      echo "$NAMESPACE | $POD_NAME | $POD_IP | $SA_NAME | $ROLE_ARN"
    fi
  done
done
```

### Identifying Pods by Time Window

When investigating an incident at a specific time:

```bash
#!/bin/bash
# Find pods that were running during a specific time window

INCIDENT_TIME="2024-12-03T10:16:45Z"
NAMESPACE="harbor"

echo "=== Pods Running at $INCIDENT_TIME ==="
echo ""

# Get pod events around the incident time
kubectl get events -n $NAMESPACE \
  --sort-by='.lastTimestamp' \
  -o json | jq -r --arg time "$INCIDENT_TIME" '.items[] | select(.lastTimestamp <= $time) | "\(.involvedObject.name) \(.reason) \(.lastTimestamp)"'

# Note: For historical pod information, you may need to query
# Kubernetes audit logs or use a monitoring solution like Prometheus
```

### Cross-Referencing with Node Information

```bash
# Get node information for pods
kubectl get pods -n harbor -o wide

# Get node details
NODE_NAME="<node-name>"
kubectl describe node $NODE_NAME

# Check if node has any security issues
kubectl get node $NODE_NAME -o json | jq '.status.conditions'
```


## Investigation Workflows

### Workflow 1: Unauthorized S3 Access Investigation

**Scenario**: Alert triggered for unexpected S3 DeleteObject operation

#### Step-by-Step Investigation

```bash
#!/bin/bash
# Investigation script for unauthorized S3 access

echo "=== Unauthorized S3 Access Investigation ==="
echo ""

# Step 1: Find the CloudTrail event
echo "Step 1: Retrieving CloudTrail event..."
INCIDENT_TIME="2024-12-03T10:16:45Z"

EVENT=$(aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteObject \
  --start-time "$(date -u -d "$INCIDENT_TIME - 5 minutes" +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u -d "$INCIDENT_TIME + 5 minutes" +%Y-%m-%dT%H:%M:%SZ)" \
  --query 'Events[?contains(CloudTrailEvent, `harbor-registry-storage`)].CloudTrailEvent' \
  --output text | jq .)

echo "$EVENT" | jq .

# Step 2: Extract identity information
echo ""
echo "Step 2: Extracting identity information..."

USER_TYPE=$(echo "$EVENT" | jq -r '.userIdentity.type')
echo "Identity Type: $USER_TYPE"

if [ "$USER_TYPE" = "AssumedRole" ]; then
  # IRSA access
  ROLE_NAME=$(echo "$EVENT" | jq -r '.userIdentity.sessionContext.sessionIssuer.userName')
  SERVICE_ACCOUNT=$(echo "$EVENT" | jq -r '.userIdentity.sessionContext.webIdFederationData.attributes.sub')
  SOURCE_IP=$(echo "$EVENT" | jq -r '.sourceIPAddress')
  
  echo "IAM Role: $ROLE_NAME"
  echo "Service Account: $SERVICE_ACCOUNT"
  echo "Source IP: $SOURCE_IP"
  
  # Step 3: Verify if this service account should have access
  echo ""
  echo "Step 3: Verifying authorization..."
  
  NAMESPACE=$(echo $SERVICE_ACCOUNT | cut -d: -f3)
  SA_NAME=$(echo $SERVICE_ACCOUNT | cut -d: -f4)
  
  # Check if this is the expected service account
  if [ "$SERVICE_ACCOUNT" = "system:serviceaccount:harbor:harbor-registry" ]; then
    echo "✅ Service account is authorized"
    echo "⚠️  However, DeleteObject may be unexpected. Investigating further..."
  else
    echo "❌ UNAUTHORIZED: Service account should not have access!"
    echo "Expected: system:serviceaccount:harbor:harbor-registry"
    echo "Actual: $SERVICE_ACCOUNT"
  fi
  
  # Step 4: Find the pod
  echo ""
  echo "Step 4: Identifying the pod..."
  
  POD_NAME=$(kubectl get pods -n $NAMESPACE \
    --field-selector spec.serviceAccountName=$SA_NAME \
    -o json | jq -r ".items[] | select(.status.podIP==\"$SOURCE_IP\") | .metadata.name")
  
  if [ -n "$POD_NAME" ]; then
    echo "Pod identified: $POD_NAME"
    
    # Step 5: Investigate pod
    echo ""
    echo "Step 5: Investigating pod..."
    
    echo "Pod details:"
    kubectl describe pod $POD_NAME -n $NAMESPACE
    
    echo ""
    echo "Pod logs around incident time:"
    kubectl logs $POD_NAME -n $NAMESPACE --since-time="$INCIDENT_TIME" --timestamps
    
    echo ""
    echo "Pod configuration:"
    kubectl get pod $POD_NAME -n $NAMESPACE -o yaml
  else
    echo "⚠️  Pod not found (may have been deleted)"
    echo "Checking recent pod deletions..."
    kubectl get events -n $NAMESPACE \
      --field-selector reason=Killing \
      --sort-by='.lastTimestamp' | tail -10
  fi
  
  # Step 6: Check IAM role trust policy
  echo ""
  echo "Step 6: Auditing IAM role trust policy..."
  
  aws iam get-role --role-name $ROLE_NAME \
    --query 'Role.AssumeRolePolicyDocument' \
    --output json | jq .
  
  # Step 7: Review recent access patterns
  echo ""
  echo "Step 7: Reviewing recent access patterns..."
  
  aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::S3::Bucket \
    --start-time "$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)" \
    --query 'Events[?contains(CloudTrailEvent, `harbor-registry-storage`)].{Time:EventTime,Event:EventName,User:Username}' \
    --output table
  
else
  # IAM user access (should not happen with IRSA)
  echo "❌ CRITICAL: Access via IAM user detected!"
  echo "This should not happen in IRSA deployment"
  
  USER_NAME=$(echo "$EVENT" | jq -r '.userIdentity.userName')
  ACCESS_KEY=$(echo "$EVENT" | jq -r '.userIdentity.accessKeyId')
  
  echo "IAM User: $USER_NAME"
  echo "Access Key: $ACCESS_KEY"
  echo ""
  echo "IMMEDIATE ACTIONS REQUIRED:"
  echo "1. Disable the access key"
  echo "2. Investigate how IAM user credentials were created"
  echo "3. Search for the credentials in Kubernetes secrets"
fi

echo ""
echo "=== Investigation Complete ==="
```


### Workflow 2: Suspicious Role Assumption Investigation

**Scenario**: Alert triggered for role assumption from unexpected service account

```bash
#!/bin/bash
# Investigation script for suspicious role assumption

echo "=== Suspicious Role Assumption Investigation ==="
echo ""

ROLE_NAME="HarborS3Role"

# Step 1: Find recent role assumptions
echo "Step 1: Finding recent role assumptions..."

ASSUMPTIONS=$(aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --query 'Events[?contains(CloudTrailEvent, `HarborS3Role`)].CloudTrailEvent' \
  --output text)

echo "$ASSUMPTIONS" | jq -s '.'

# Step 2: Analyze each assumption
echo ""
echo "Step 2: Analyzing role assumptions..."

echo "$ASSUMPTIONS" | jq -c '.' | while read -r EVENT; do
  SERVICE_ACCOUNT=$(echo "$EVENT" | jq -r '.requestParameters.roleSessionName // .userIdentity.sessionContext.webIdFederationData.attributes.sub')
  TIMESTAMP=$(echo "$EVENT" | jq -r '.eventTime')
  SOURCE_IP=$(echo "$EVENT" | jq -r '.sourceIPAddress')
  
  echo ""
  echo "Assumption at $TIMESTAMP:"
  echo "  Service Account: $SERVICE_ACCOUNT"
  echo "  Source IP: $SOURCE_IP"
  
  # Check if this is expected
  if [ "$SERVICE_ACCOUNT" = "system:serviceaccount:harbor:harbor-registry" ]; then
    echo "  Status: ✅ Expected"
  else
    echo "  Status: ❌ UNEXPECTED!"
    
    # Investigate further
    NAMESPACE=$(echo $SERVICE_ACCOUNT | cut -d: -f3)
    SA_NAME=$(echo $SERVICE_ACCOUNT | cut -d: -f4)
    
    echo ""
    echo "  Investigating unauthorized service account..."
    
    # Check if service account exists
    if kubectl get serviceaccount $SA_NAME -n $NAMESPACE &>/dev/null; then
      echo "  Service account exists in Kubernetes"
      
      # Get service account details
      kubectl get serviceaccount $SA_NAME -n $NAMESPACE -o yaml
      
      # Find pods using this service account
      echo ""
      echo "  Pods using this service account:"
      kubectl get pods -n $NAMESPACE \
        --field-selector spec.serviceAccountName=$SA_NAME \
        -o wide
    else
      echo "  ⚠️  Service account does NOT exist in Kubernetes"
      echo "  This may indicate a misconfiguration or attack"
    fi
    
    # Check trust policy
    echo ""
    echo "  Checking if trust policy allows this service account..."
    
    TRUST_POLICY=$(aws iam get-role --role-name $ROLE_NAME \
      --query 'Role.AssumeRolePolicyDocument' --output json)
    
    if echo "$TRUST_POLICY" | grep -q "$SERVICE_ACCOUNT"; then
      echo "  ❌ Trust policy ALLOWS this service account"
      echo "  ACTION REQUIRED: Update trust policy to remove this service account"
    else
      echo "  ⚠️  Trust policy does NOT explicitly allow this service account"
      echo "  Checking for wildcards or overly permissive conditions..."
      
      echo "$TRUST_POLICY" | jq '.Statement[].Condition'
    fi
  fi
done

echo ""
echo "=== Investigation Complete ==="
```

### Workflow 3: Data Exfiltration Investigation

**Scenario**: Large volume of S3 GetObject requests detected

```bash
#!/bin/bash
# Investigation script for potential data exfiltration

echo "=== Data Exfiltration Investigation ==="
echo ""

# Step 1: Identify high-volume access
echo "Step 1: Analyzing S3 access volume..."

START_TIME="$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)"

# Get all S3 GetObject events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetObject \
  --start-time "$START_TIME" \
  --max-results 1000 \
  --query 'Events[?contains(CloudTrailEvent, `harbor-registry-storage`)].CloudTrailEvent' \
  --output text | jq -s 'group_by(.userIdentity.sessionContext.webIdFederationData.attributes.sub) | map({serviceAccount: .[0].userIdentity.sessionContext.webIdFederationData.attributes.sub, count: length, totalBytes: map(.responseElements.bytesTransferred // 0 | tonumber) | add}) | sort_by(.count) | reverse'

# Step 2: Identify anomalous patterns
echo ""
echo "Step 2: Identifying anomalous access patterns..."

# Get access by hour
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetObject \
  --start-time "$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --max-results 1000 \
  --query 'Events[?contains(CloudTrailEvent, `harbor-registry-storage`)].CloudTrailEvent' \
  --output text | jq -s 'group_by(.eventTime[0:13]) | map({hour: .[0].eventTime[0:13], count: length}) | sort_by(.hour)'

# Step 3: Identify accessed objects
echo ""
echo "Step 3: Identifying accessed objects..."

aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetObject \
  --start-time "$START_TIME" \
  --max-results 100 \
  --query 'Events[?contains(CloudTrailEvent, `harbor-registry-storage`)].CloudTrailEvent' \
  --output text | jq -r '.resources[].ARN' | sort | uniq -c | sort -rn | head -20

# Step 4: Trace to specific pod
echo ""
echo "Step 4: Tracing to specific pod..."

# Get the most recent high-volume access event
RECENT_EVENT=$(aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetObject \
  --start-time "$START_TIME" \
  --max-results 1 \
  --query 'Events[?contains(CloudTrailEvent, `harbor-registry-storage`)].CloudTrailEvent' \
  --output text | jq .)

SERVICE_ACCOUNT=$(echo "$RECENT_EVENT" | jq -r '.userIdentity.sessionContext.webIdFederationData.attributes.sub')
SOURCE_IP=$(echo "$RECENT_EVENT" | jq -r '.sourceIPAddress')

echo "Service Account: $SERVICE_ACCOUNT"
echo "Source IP: $SOURCE_IP"

NAMESPACE=$(echo $SERVICE_ACCOUNT | cut -d: -f3)
SA_NAME=$(echo $SERVICE_ACCOUNT | cut -d: -f4)

POD_NAME=$(kubectl get pods -n $NAMESPACE \
  --field-selector spec.serviceAccountName=$SA_NAME \
  -o json | jq -r ".items[] | select(.status.podIP==\"$SOURCE_IP\") | .metadata.name")

echo "Pod: $POD_NAME"

# Step 5: Investigate pod behavior
if [ -n "$POD_NAME" ]; then
  echo ""
  echo "Step 5: Investigating pod behavior..."
  
  echo "Pod resource usage:"
  kubectl top pod $POD_NAME -n $NAMESPACE
  
  echo ""
  echo "Pod network connections:"
  kubectl exec $POD_NAME -n $NAMESPACE -- netstat -an 2>/dev/null || echo "Unable to check network connections"
  
  echo ""
  echo "Recent pod logs:"
  kubectl logs $POD_NAME -n $NAMESPACE --tail=100
fi

echo ""
echo "=== Investigation Complete ==="
echo ""
echo "RECOMMENDATIONS:"
echo "1. Review if the access volume is expected for Harbor operations"
echo "2. Check if the pod is compromised or running unauthorized workloads"
echo "3. Consider implementing rate limiting on S3 access"
echo "4. Review network policies to ensure pod isolation"
```


## Common Incident Scenarios

### Scenario 1: Unauthorized Namespace Access

**Symptoms**: Role assumption from unexpected namespace

**Investigation Steps**:

1. Identify the service account from CloudTrail
2. Check trust policy for wildcards or overly permissive conditions
3. Verify if the namespace should have access
4. Review how the service account got the role annotation

**Resolution**:
```bash
# Update trust policy to be more restrictive
# Remove the unauthorized service account annotation
kubectl annotate serviceaccount <sa-name> -n <namespace> eks.amazonaws.com/role-arn-
```

### Scenario 2: Compromised Pod

**Symptoms**: Unusual API calls from a known pod

**Investigation Steps**:

1. Identify the pod from CloudTrail and Kubernetes
2. Review pod logs for suspicious activity
3. Check pod configuration for unauthorized changes
4. Examine container image for vulnerabilities
5. Review network connections from the pod

**Resolution**:
```bash
# Immediately delete the compromised pod
kubectl delete pod <pod-name> -n <namespace>

# Review and update the deployment
kubectl get deployment <deployment-name> -n <namespace> -o yaml

# Scan the container image
# Update to a patched image if vulnerabilities found

# Review and tighten network policies
kubectl get networkpolicy -n <namespace>
```

### Scenario 3: Credential Leakage (IAM User)

**Symptoms**: IAM user credentials detected in IRSA environment

**Investigation Steps**:

1. Identify the IAM user and access key from CloudTrail
2. Search Kubernetes secrets for the credentials
3. Determine how the credentials were created
4. Identify all resources that may have the credentials

**Resolution**:
```bash
# Immediately disable the access key
aws iam update-access-key \
  --access-key-id <access-key-id> \
  --status Inactive \
  --user-name <user-name>

# Search for the credentials in Kubernetes
kubectl get secrets --all-namespaces -o json | \
  jq -r '.items[] | select(.data | to_entries[] | .value | @base64d | contains("<access-key-id>")) | "\(.metadata.namespace)/\(.metadata.name)"'

# Delete any secrets containing the credentials
kubectl delete secret <secret-name> -n <namespace>

# Delete the IAM user if not needed
aws iam delete-access-key --access-key-id <access-key-id> --user-name <user-name>
aws iam delete-user --user-name <user-name>

# Rotate any other credentials that may have been exposed
```

### Scenario 4: Trust Policy Misconfiguration

**Symptoms**: Multiple unexpected service accounts can assume the role

**Investigation Steps**:

1. Review the trust policy for wildcards
2. Identify all service accounts that have assumed the role
3. Determine if the misconfiguration was intentional or accidental
4. Check CloudTrail for who modified the trust policy

**Resolution**:
```bash
# Get current trust policy
aws iam get-role --role-name HarborS3Role \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json > current-trust-policy.json

# Create corrected trust policy
cat > corrected-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE:sub": "system:serviceaccount:harbor:harbor-registry",
          "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Update trust policy
aws iam update-assume-role-policy \
  --role-name HarborS3Role \
  --policy-document file://corrected-trust-policy.json

# Verify the update
aws iam get-role --role-name HarborS3Role \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json
```

### Scenario 5: Excessive Permissions

**Symptoms**: Role has broader permissions than needed

**Investigation Steps**:

1. Review the permissions policy
2. Identify which permissions are actually being used
3. Check CloudTrail for all API calls made by the role
4. Determine minimum required permissions

**Resolution**:
```bash
# Analyze actual API calls over the past 30 days
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=HarborS3Role \
  --start-time "$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --max-results 1000 \
  --query 'Events[].CloudTrailEvent' \
  --output text | jq -r '.eventName' | sort | uniq

# Create least-privilege policy based on actual usage
cat > least-privilege-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "HarborS3Access",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::harbor-registry-storage-123456789012-us-east-1",
        "arn:aws:s3:::harbor-registry-storage-123456789012-us-east-1/*"
      ]
    },
    {
      "Sid": "HarborKMSAccess",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "s3.us-east-1.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Update the policy
POLICY_ARN=$(aws iam list-attached-role-policies --role-name HarborS3Role \
  --query 'AttachedPolicies[0].PolicyArn' --output text)

aws iam create-policy-version \
  --policy-arn $POLICY_ARN \
  --policy-document file://least-privilege-policy.json \
  --set-as-default
```


## Forensic Data Collection

### Comprehensive Evidence Collection Script

```bash
#!/bin/bash
# Forensic data collection script for IRSA incident investigation

INCIDENT_ID="INC-$(date +%Y%m%d-%H%M%S)"
EVIDENCE_DIR="incident-evidence-${INCIDENT_ID}"
INCIDENT_TIME="${1:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

echo "=== Forensic Data Collection ==="
echo "Incident ID: $INCIDENT_ID"
echo "Incident Time: $INCIDENT_TIME"
echo ""

mkdir -p $EVIDENCE_DIR

# 1. Collect CloudTrail logs
echo "Collecting CloudTrail logs..."
aws cloudtrail lookup-events \
  --start-time "$(date -u -d "$INCIDENT_TIME - 1 hour" +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u -d "$INCIDENT_TIME + 1 hour" +%Y-%m-%dT%H:%M:%SZ)" \
  --max-results 1000 \
  --output json > $EVIDENCE_DIR/cloudtrail-events.json

# 2. Collect IAM role configuration
echo "Collecting IAM role configuration..."
aws iam get-role --role-name HarborS3Role \
  --output json > $EVIDENCE_DIR/iam-role-config.json

aws iam list-attached-role-policies --role-name HarborS3Role \
  --output json > $EVIDENCE_DIR/iam-attached-policies.json

POLICY_ARN=$(aws iam list-attached-role-policies --role-name HarborS3Role \
  --query 'AttachedPolicies[0].PolicyArn' --output text)

if [ -n "$POLICY_ARN" ] && [ "$POLICY_ARN" != "None" ]; then
  POLICY_VERSION=$(aws iam get-policy --policy-arn "$POLICY_ARN" \
    --query 'Policy.DefaultVersionId' --output text)
  
  aws iam get-policy-version \
    --policy-arn "$POLICY_ARN" \
    --version-id "$POLICY_VERSION" \
    --output json > $EVIDENCE_DIR/iam-policy-document.json
fi

# 3. Collect Kubernetes resources
echo "Collecting Kubernetes resources..."
kubectl get all -n harbor -o yaml > $EVIDENCE_DIR/k8s-harbor-namespace.yaml
kubectl get serviceaccounts -n harbor -o yaml > $EVIDENCE_DIR/k8s-service-accounts.yaml
kubectl get secrets -n harbor -o yaml > $EVIDENCE_DIR/k8s-secrets.yaml
kubectl get networkpolicies -n harbor -o yaml > $EVIDENCE_DIR/k8s-network-policies.yaml
kubectl get events -n harbor --sort-by='.lastTimestamp' > $EVIDENCE_DIR/k8s-events.txt

# 4. Collect pod logs
echo "Collecting pod logs..."
kubectl get pods -n harbor -o json | jq -r '.items[].metadata.name' | while read POD; do
  echo "Collecting logs for $POD..."
  kubectl logs $POD -n harbor --all-containers --timestamps > $EVIDENCE_DIR/pod-logs-${POD}.txt 2>&1
  kubectl logs $POD -n harbor --all-containers --timestamps --previous > $EVIDENCE_DIR/pod-logs-${POD}-previous.txt 2>&1 || true
done

# 5. Collect pod descriptions
echo "Collecting pod descriptions..."
kubectl get pods -n harbor -o json | jq -r '.items[].metadata.name' | while read POD; do
  kubectl describe pod $POD -n harbor > $EVIDENCE_DIR/pod-describe-${POD}.txt
done

# 6. Collect node information
echo "Collecting node information..."
kubectl get nodes -o yaml > $EVIDENCE_DIR/k8s-nodes.yaml
kubectl top nodes > $EVIDENCE_DIR/k8s-nodes-resources.txt 2>&1 || true

# 7. Collect S3 bucket configuration
echo "Collecting S3 bucket configuration..."
BUCKET_NAME="harbor-registry-storage-123456789012-us-east-1"
aws s3api get-bucket-policy --bucket $BUCKET_NAME > $EVIDENCE_DIR/s3-bucket-policy.json 2>&1 || true
aws s3api get-bucket-encryption --bucket $BUCKET_NAME > $EVIDENCE_DIR/s3-bucket-encryption.json 2>&1 || true
aws s3api get-bucket-versioning --bucket $BUCKET_NAME > $EVIDENCE_DIR/s3-bucket-versioning.json 2>&1 || true
aws s3api get-bucket-logging --bucket $BUCKET_NAME > $EVIDENCE_DIR/s3-bucket-logging.json 2>&1 || true

# 8. Collect KMS key configuration
echo "Collecting KMS key configuration..."
KMS_KEY_ID="12345678-1234-1234-1234-123456789012"
aws kms describe-key --key-id $KMS_KEY_ID > $EVIDENCE_DIR/kms-key-config.json 2>&1 || true
aws kms get-key-policy --key-id $KMS_KEY_ID --policy-name default > $EVIDENCE_DIR/kms-key-policy.json 2>&1 || true

# 9. Create investigation summary
cat > $EVIDENCE_DIR/investigation-summary.txt << EOF
Incident Investigation Summary
==============================

Incident ID: $INCIDENT_ID
Incident Time: $INCIDENT_TIME
Collection Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Evidence Collected:
- CloudTrail events (1 hour before/after incident)
- IAM role and policy configurations
- Kubernetes resources (harbor namespace)
- Pod logs and descriptions
- Node information
- S3 bucket configuration
- KMS key configuration

Next Steps:
1. Review CloudTrail events for suspicious activity
2. Analyze pod logs for anomalies
3. Verify IAM role trust policy
4. Check for unauthorized service accounts
5. Review network policies and pod isolation

Investigator: $(whoami)
Hostname: $(hostname)
EOF

# 10. Create archive
echo ""
echo "Creating evidence archive..."
tar -czf ${EVIDENCE_DIR}.tar.gz $EVIDENCE_DIR
rm -rf $EVIDENCE_DIR

echo ""
echo "=== Evidence Collection Complete ==="
echo "Evidence archive: ${EVIDENCE_DIR}.tar.gz"
echo ""
echo "IMPORTANT: Preserve this evidence for forensic analysis"
echo "Store in a secure location with restricted access"
```

### Chain of Custody Documentation

```bash
# Create chain of custody document
cat > chain-of-custody-${INCIDENT_ID}.txt << EOF
CHAIN OF CUSTODY DOCUMENT
=========================

Incident ID: $INCIDENT_ID
Evidence File: ${EVIDENCE_DIR}.tar.gz

Collection Information:
- Date/Time: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
- Collected By: $(whoami)
- System: $(hostname)
- Method: Automated forensic collection script

Evidence Hash:
- SHA256: $(sha256sum ${EVIDENCE_DIR}.tar.gz | awk '{print $1}')
- MD5: $(md5sum ${EVIDENCE_DIR}.tar.gz | awk '{print $1}')

Transfer Log:
-------------
Date/Time | From | To | Purpose | Signature
$(date -u +"%Y-%m-%d %H:%M:%S") | $(whoami) | [Recipient] | Initial Collection | [Signature]

Notes:
------
[Add any relevant notes about the evidence collection]

EOF

echo "Chain of custody document created: chain-of-custody-${INCIDENT_ID}.txt"
```


## Incident Response Procedures

### Immediate Response Actions

When a security incident is detected:

1. **Contain the Threat**
   - If a pod is compromised, delete it immediately
   - If credentials are leaked, disable them immediately
   - If trust policy is misconfigured, update it immediately

2. **Preserve Evidence**
   - Run the forensic data collection script
   - Do not modify resources until evidence is collected
   - Document all actions taken

3. **Assess Impact**
   - Determine what data was accessed
   - Identify affected resources
   - Estimate scope of compromise

4. **Notify Stakeholders**
   - Alert security team
   - Notify management if required
   - Contact AWS support if needed

### Containment Procedures

#### Immediate Pod Isolation

```bash
# Isolate a compromised pod using network policy
cat > isolate-pod-policy.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: isolate-compromised-pod
  namespace: harbor
spec:
  podSelector:
    matchLabels:
      app: harbor-registry
  policyTypes:
  - Ingress
  - Egress
  # Deny all traffic
EOF

kubectl apply -f isolate-pod-policy.yaml
```

#### Revoke IAM Role Access

```bash
# Temporarily deny all access by updating the trust policy
cat > deny-all-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "sts:AssumeRoleWithWebIdentity"
    }
  ]
}
EOF

aws iam update-assume-role-policy \
  --role-name HarborS3Role \
  --policy-document file://deny-all-trust-policy.json
```


### Recovery Procedures

#### Restore Normal Operations

```bash
# 1. Verify the threat is contained
# 2. Update configurations to prevent recurrence
# 3. Restore trust policy with corrected configuration

cat > corrected-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE:sub": "system:serviceaccount:harbor:harbor-registry",
          "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

aws iam update-assume-role-policy \
  --role-name HarborS3Role \
  --policy-document file://corrected-trust-policy.json

# 4. Redeploy Harbor pods
kubectl rollout restart deployment -n harbor

# 5. Verify normal operations
kubectl get pods -n harbor
kubectl logs -n harbor -l app=harbor-registry --tail=50
```

### Post-Incident Activities

#### Incident Report Template

```markdown
# Incident Report: [INCIDENT_ID]

## Executive Summary
[Brief description of the incident]

## Incident Details
- **Incident ID**: [ID]
- **Detection Time**: [Timestamp]
- **Resolution Time**: [Timestamp]
- **Duration**: [Duration]
- **Severity**: [Critical/High/Medium/Low]

## Timeline
| Time | Event | Action Taken |
|------|-------|--------------|
| [Time] | [Event description] | [Action] |

## Root Cause
[Detailed analysis of what caused the incident]

## Impact Assessment
- **Data Accessed**: [Description]
- **Systems Affected**: [List]
- **Business Impact**: [Description]

## Response Actions
1. [Action 1]
2. [Action 2]
3. [Action 3]

## Lessons Learned
- [Lesson 1]
- [Lesson 2]

## Recommendations
1. [Recommendation 1]
2. [Recommendation 2]

## Follow-up Actions
- [ ] [Action item 1]
- [ ] [Action item 2]
```

#### Lessons Learned Session

Conduct a post-incident review to:
1. Analyze what went well
2. Identify areas for improvement
3. Update incident response procedures
4. Implement preventive measures
5. Update monitoring and alerting

## Summary

This incident investigation guide provides:

1. **Investigation Framework**: Structured approach to incident response
2. **Tracing Procedures**: Step-by-step methods to trace access to specific pods
3. **Identification Techniques**: Methods to identify namespaces and pods involved
4. **Investigation Workflows**: Complete workflows for common incident scenarios
5. **Common Scenarios**: Detailed procedures for typical IRSA-related incidents
6. **Forensic Collection**: Comprehensive evidence collection scripts
7. **Response Procedures**: Immediate containment and recovery procedures

### Key Capabilities with IRSA

IRSA significantly improves incident investigation capabilities:

| Capability | IRSA | IAM User |
|------------|------|----------|
| **Pod identification** | ✅ Direct from CloudTrail | ❌ Requires correlation |
| **Namespace tracking** | ✅ In service account | ❌ Not available |
| **Timeline reconstruction** | ✅ Complete audit trail | ⚠️ Limited visibility |
| **Scope assessment** | ✅ Pod-level granularity | ⚠️ User-level only |
| **Containment** | ✅ Precise targeting | ⚠️ Broad impact |
| **Root cause analysis** | ✅ Clear attribution | ⚠️ Ambiguous |

### Best Practices

1. **Preparation**: Have investigation scripts ready before incidents occur
2. **Automation**: Automate evidence collection to preserve data quickly
3. **Documentation**: Document all investigation steps and findings
4. **Preservation**: Preserve evidence with proper chain of custody
5. **Communication**: Keep stakeholders informed throughout investigation
6. **Learning**: Conduct post-incident reviews to improve processes

## Additional Resources

- [AWS Security Incident Response Guide](https://docs.aws.amazon.com/whitepapers/latest/aws-security-incident-response-guide/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/security-best-practices/)
- [CloudTrail Log Event Reference](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-event-reference.html)
- [IRSA Technical Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [NIST Incident Response Guide](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-61r2.pdf)
