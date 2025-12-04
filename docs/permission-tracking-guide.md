# Permission Tracking Guide

## Overview

This guide provides comprehensive procedures for tracking and auditing IAM permissions, service account bindings, and access controls in the Harbor IRSA deployment. Effective permission tracking is essential for maintaining security posture, ensuring compliance, and investigating access-related incidents.

## Table of Contents

1. [IAM Policy Tracking](#iam-policy-tracking)
2. [Service Account Binding Verification](#service-account-binding-verification)
3. [Trust Policy Auditing](#trust-policy-auditing)
4. [Permission Boundary Tracking](#permission-boundary-tracking)
5. [Audit Procedures](#audit-procedures)
6. [Automated Monitoring](#automated-monitoring)
7. [Compliance Reporting](#compliance-reporting)

## IAM Policy Tracking

### Querying IAM Role Permissions

#### Get Complete Role Information

```bash
# Get the HarborS3Role details
aws iam get-role \
  --role-name HarborS3Role \
  --output json | jq .

# Output includes:
# - Role ARN
# - Trust policy (AssumeRolePolicyDocument)
# - Creation date
# - Last used information
```

#### List All Attached Policies

```bash
# List managed policies attached to the role
aws iam list-attached-role-policies \
  --role-name HarborS3Role \
  --output table

# Example output:
# ---------------------------------------------------------------
# |                  ListAttachedRolePolicies                   |
# +-------------------------------------------------------------+
# ||                      AttachedPolicies                     ||
# |+---------------------------+-------------------------------+|
# ||  PolicyArn                | PolicyName                    ||
# |+---------------------------+-------------------------------+|
# ||  arn:aws:iam::123456...:  | HarborS3AccessPolicy          ||
# ||  policy/HarborS3Access... |                               ||
# |+---------------------------+-------------------------------+|
```


#### Get Policy Document Details

```bash
# Get the policy version
POLICY_ARN=$(aws iam list-attached-role-policies \
  --role-name HarborS3Role \
  --query 'AttachedPolicies[0].PolicyArn' \
  --output text)

# Get the default policy version
POLICY_VERSION=$(aws iam get-policy \
  --policy-arn "$POLICY_ARN" \
  --query 'Policy.DefaultVersionId' \
  --output text)

# Get the policy document
aws iam get-policy-version \
  --policy-arn "$POLICY_ARN" \
  --version-id "$POLICY_VERSION" \
  --query 'PolicyVersion.Document' \
  --output json | jq .
```

#### List Inline Policies

```bash
# List inline policies (policies embedded directly in the role)
aws iam list-role-policies \
  --role-name HarborS3Role \
  --output table

# Get inline policy document
aws iam get-role-policy \
  --role-name HarborS3Role \
  --policy-name <PolicyName> \
  --output json | jq .
```

### Analyzing Permission Scope

#### Extract S3 Permissions

```bash
# Get all S3 actions allowed by the role
aws iam get-policy-version \
  --policy-arn "$POLICY_ARN" \
  --version-id "$POLICY_VERSION" \
  --query 'PolicyVersion.Document.Statement[?Effect==`Allow`].Action[]' \
  --output json | jq -r '.[] | select(startswith("s3:"))'

# Expected output for Harbor:
# s3:PutObject
# s3:GetObject
# s3:DeleteObject
# s3:ListBucket
# s3:GetBucketLocation
```

#### Extract KMS Permissions

```bash
# Get all KMS actions allowed by the role
aws iam get-policy-version \
  --policy-arn "$POLICY_ARN" \
  --version-id "$POLICY_VERSION" \
  --query 'PolicyVersion.Document.Statement[?Effect==`Allow`].Action[]' \
  --output json | jq -r '.[] | select(startswith("kms:"))'

# Expected output for Harbor:
# kms:Decrypt
# kms:GenerateDataKey
# kms:DescribeKey
```

#### Check Resource Restrictions

```bash
# Verify that permissions are scoped to specific resources
aws iam get-policy-version \
  --policy-arn "$POLICY_ARN" \
  --version-id "$POLICY_VERSION" \
  --query 'PolicyVersion.Document.Statement[].Resource' \
  --output json | jq .

# Expected: Specific bucket ARN, not "*"
# Good: "arn:aws:s3:::harbor-registry-storage-123456789012-us-east-1/*"
# Bad: "arn:aws:s3:::*/*"
```


### Tracking Permission Changes

#### Get Policy Version History

```bash
# List all versions of a policy
aws iam list-policy-versions \
  --policy-arn "$POLICY_ARN" \
  --output table

# Compare two policy versions
aws iam get-policy-version \
  --policy-arn "$POLICY_ARN" \
  --version-id v1 \
  --output json > policy-v1.json

aws iam get-policy-version \
  --policy-arn "$POLICY_ARN" \
  --version-id v2 \
  --output json > policy-v2.json

# Use diff to compare
diff -u policy-v1.json policy-v2.json
```

#### Monitor Policy Modifications via CloudTrail

```bash
# Find all policy modification events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=HarborS3Role \
  --start-time "2024-11-01T00:00:00Z" \
  --query 'Events[?contains(EventName, `Policy`)].{Time:EventTime,Event:EventName,User:Username}' \
  --output table

# Common events to monitor:
# - PutRolePolicy (inline policy changes)
# - AttachRolePolicy (managed policy attachments)
# - DetachRolePolicy (managed policy removals)
# - CreatePolicyVersion (policy updates)
```

## Service Account Binding Verification

### Kubernetes Service Account Inspection

#### Get Service Account Details

```bash
# Get the Harbor service account
kubectl get serviceaccount harbor-registry -n harbor -o yaml

# Expected output includes:
# metadata:
#   annotations:
#     eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/HarborS3Role
#   name: harbor-registry
#   namespace: harbor
```

#### Verify Role Annotation

```bash
# Extract just the role ARN annotation
kubectl get serviceaccount harbor-registry -n harbor \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# Verify it matches the expected role
EXPECTED_ROLE="arn:aws:iam::123456789012:role/HarborS3Role"
ACTUAL_ROLE=$(kubectl get serviceaccount harbor-registry -n harbor \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')

if [ "$EXPECTED_ROLE" = "$ACTUAL_ROLE" ]; then
  echo "✅ Service account annotation is correct"
else
  echo "❌ Service account annotation mismatch!"
  echo "Expected: $EXPECTED_ROLE"
  echo "Actual: $ACTUAL_ROLE"
fi
```

#### List All Pods Using the Service Account

```bash
# Find all pods using the harbor-registry service account
kubectl get pods -n harbor \
  --field-selector spec.serviceAccountName=harbor-registry \
  -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,IP:.status.podIP

# Verify each pod has the projected service account token
kubectl get pods -n harbor \
  --field-selector spec.serviceAccountName=harbor-registry \
  -o json | jq -r '.items[].spec.volumes[] | select(.name=="kube-api-access-*" or .projected.sources[].serviceAccountToken) | "Found projected token volume"'
```


### Cross-Reference IAM and Kubernetes

#### Verify Complete Binding Chain

```bash
#!/bin/bash
# Script to verify the complete IRSA binding chain

NAMESPACE="harbor"
SERVICE_ACCOUNT="harbor-registry"
ROLE_NAME="HarborS3Role"

echo "=== IRSA Binding Verification ==="
echo ""

# 1. Check Kubernetes service account
echo "1. Checking Kubernetes Service Account..."
SA_ROLE_ARN=$(kubectl get serviceaccount $SERVICE_ACCOUNT -n $NAMESPACE \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null)

if [ -z "$SA_ROLE_ARN" ]; then
  echo "❌ Service account not found or missing role annotation"
  exit 1
else
  echo "✅ Service account exists with role: $SA_ROLE_ARN"
fi

# 2. Check IAM role exists
echo ""
echo "2. Checking IAM Role..."
ROLE_EXISTS=$(aws iam get-role --role-name $ROLE_NAME 2>/dev/null)
if [ $? -eq 0 ]; then
  echo "✅ IAM role exists"
else
  echo "❌ IAM role not found"
  exit 1
fi

# 3. Check trust policy allows the service account
echo ""
echo "3. Checking Trust Policy..."
TRUST_POLICY=$(aws iam get-role --role-name $ROLE_NAME \
  --query 'Role.AssumeRolePolicyDocument' --output json)

if echo "$TRUST_POLICY" | grep -q "system:serviceaccount:$NAMESPACE:$SERVICE_ACCOUNT"; then
  echo "✅ Trust policy allows service account"
else
  echo "❌ Trust policy does not allow service account"
  echo "Trust policy:"
  echo "$TRUST_POLICY" | jq .
  exit 1
fi

# 4. Check permissions policy
echo ""
echo "4. Checking Permissions Policy..."
POLICY_ARN=$(aws iam list-attached-role-policies --role-name $ROLE_NAME \
  --query 'AttachedPolicies[0].PolicyArn' --output text)

if [ -n "$POLICY_ARN" ]; then
  echo "✅ Permissions policy attached: $POLICY_ARN"
else
  echo "⚠️  No managed policies attached (checking inline policies...)"
  INLINE_POLICIES=$(aws iam list-role-policies --role-name $ROLE_NAME \
    --query 'PolicyNames' --output text)
  if [ -n "$INLINE_POLICIES" ]; then
    echo "✅ Inline policies found: $INLINE_POLICIES"
  else
    echo "❌ No policies attached to role"
    exit 1
  fi
fi

# 5. Check pods using the service account
echo ""
echo "5. Checking Pods..."
POD_COUNT=$(kubectl get pods -n $NAMESPACE \
  --field-selector spec.serviceAccountName=$SERVICE_ACCOUNT \
  --no-headers 2>/dev/null | wc -l)

if [ "$POD_COUNT" -gt 0 ]; then
  echo "✅ Found $POD_COUNT pod(s) using service account"
  kubectl get pods -n $NAMESPACE \
    --field-selector spec.serviceAccountName=$SERVICE_ACCOUNT \
    -o custom-columns=NAME:.metadata.name,STATUS:.status.phase
else
  echo "⚠️  No pods currently using service account"
fi

echo ""
echo "=== Verification Complete ==="
```


## Trust Policy Auditing

### Understanding Trust Policies

Trust policies (AssumeRolePolicyDocument) control who can assume an IAM role. For IRSA, the trust policy must:
1. Allow the OIDC provider as a federated principal
2. Restrict assumption to specific service accounts via conditions

### Retrieving Trust Policy

```bash
# Get the trust policy for HarborS3Role
aws iam get-role \
  --role-name HarborS3Role \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json | jq .
```

### Expected Trust Policy Structure

```json
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
```

### Auditing Trust Policy Components

#### Verify OIDC Provider

```bash
# Extract OIDC provider from trust policy
OIDC_PROVIDER=$(aws iam get-role --role-name HarborS3Role \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.Federated' \
  --output text)

echo "OIDC Provider: $OIDC_PROVIDER"

# Verify OIDC provider exists
OIDC_PROVIDER_ARN=$(echo $OIDC_PROVIDER | sed 's/.*oidc-provider\///')
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "$OIDC_PROVIDER" \
  --output json | jq .
```

#### Verify Service Account Restriction

```bash
# Extract the service account condition
aws iam get-role --role-name HarborS3Role \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals' \
  --output json | jq .

# Check for the 'sub' condition (service account)
SUB_CONDITION=$(aws iam get-role --role-name HarborS3Role \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals' \
  --output json | jq -r 'to_entries[] | select(.key | endswith(":sub")) | .value')

echo "Allowed service account: $SUB_CONDITION"

# Verify it matches expected format: system:serviceaccount:namespace:sa-name
if [[ "$SUB_CONDITION" =~ ^system:serviceaccount:[a-z0-9-]+:[a-z0-9-]+$ ]]; then
  echo "✅ Service account condition is properly formatted"
else
  echo "❌ Service account condition is malformed or missing"
fi
```

#### Check for Overly Permissive Conditions

```bash
# Audit script to detect overly permissive trust policies
#!/bin/bash

ROLE_NAME="HarborS3Role"

echo "=== Trust Policy Security Audit ==="
echo ""

# Get trust policy
TRUST_POLICY=$(aws iam get-role --role-name $ROLE_NAME \
  --query 'Role.AssumeRolePolicyDocument' --output json)

# Check 1: Verify StringEquals (not StringLike with wildcards)
if echo "$TRUST_POLICY" | jq -e '.Statement[].Condition.StringLike' > /dev/null 2>&1; then
  echo "⚠️  WARNING: Trust policy uses StringLike (may allow wildcards)"
  echo "$TRUST_POLICY" | jq '.Statement[].Condition.StringLike'
else
  echo "✅ Trust policy uses StringEquals (no wildcards)"
fi

# Check 2: Verify specific service account (not wildcard)
SUB_VALUE=$(echo "$TRUST_POLICY" | jq -r '.Statement[].Condition.StringEquals | to_entries[] | select(.key | endswith(":sub")) | .value')
if [[ "$SUB_VALUE" == *"*"* ]]; then
  echo "❌ CRITICAL: Service account condition contains wildcard: $SUB_VALUE"
else
  echo "✅ Service account is specific: $SUB_VALUE"
fi

# Check 3: Verify namespace is not 'default' or '*'
NAMESPACE=$(echo "$SUB_VALUE" | cut -d: -f3)
if [ "$NAMESPACE" = "default" ]; then
  echo "⚠️  WARNING: Service account is in 'default' namespace"
elif [ "$NAMESPACE" = "*" ]; then
  echo "❌ CRITICAL: Service account allows all namespaces"
else
  echo "✅ Service account is in specific namespace: $NAMESPACE"
fi

# Check 4: Verify audience condition exists
AUD_VALUE=$(echo "$TRUST_POLICY" | jq -r '.Statement[].Condition.StringEquals | to_entries[] | select(.key | endswith(":aud")) | .value')
if [ "$AUD_VALUE" = "sts.amazonaws.com" ]; then
  echo "✅ Audience condition is correct"
elif [ -z "$AUD_VALUE" ]; then
  echo "⚠️  WARNING: No audience condition (less secure)"
else
  echo "⚠️  WARNING: Unexpected audience value: $AUD_VALUE"
fi

echo ""
echo "=== Audit Complete ==="
```


## Permission Boundary Tracking

### Understanding Permission Boundaries

Permission boundaries are advanced IAM features that set the maximum permissions an IAM role can have, even if the role's policies grant broader permissions.

### Check for Permission Boundaries

```bash
# Check if the role has a permission boundary
aws iam get-role \
  --role-name HarborS3Role \
  --query 'Role.PermissionsBoundary' \
  --output json

# If output is null, no permission boundary is set
# If output shows a policy ARN, a boundary is in effect
```

### Analyzing Permission Boundaries

```bash
# If a permission boundary exists, get its details
BOUNDARY_ARN=$(aws iam get-role --role-name HarborS3Role \
  --query 'Role.PermissionsBoundary.PermissionsBoundaryArn' \
  --output text)

if [ "$BOUNDARY_ARN" != "None" ] && [ -n "$BOUNDARY_ARN" ]; then
  echo "Permission boundary found: $BOUNDARY_ARN"
  
  # Get the boundary policy version
  BOUNDARY_VERSION=$(aws iam get-policy --policy-arn "$BOUNDARY_ARN" \
    --query 'Policy.DefaultVersionId' --output text)
  
  # Get the boundary policy document
  aws iam get-policy-version \
    --policy-arn "$BOUNDARY_ARN" \
    --version-id "$BOUNDARY_VERSION" \
    --query 'PolicyVersion.Document' \
    --output json | jq .
else
  echo "No permission boundary set"
fi
```

### Effective Permissions Calculation

```bash
# Script to calculate effective permissions (intersection of policies and boundaries)
#!/bin/bash

ROLE_NAME="HarborS3Role"

echo "=== Effective Permissions Analysis ==="
echo ""

# Get role policies
echo "1. Role Policies:"
POLICY_ARN=$(aws iam list-attached-role-policies --role-name $ROLE_NAME \
  --query 'AttachedPolicies[0].PolicyArn' --output text)

if [ -n "$POLICY_ARN" ] && [ "$POLICY_ARN" != "None" ]; then
  POLICY_VERSION=$(aws iam get-policy --policy-arn "$POLICY_ARN" \
    --query 'Policy.DefaultVersionId' --output text)
  
  echo "  Policy: $POLICY_ARN"
  aws iam get-policy-version \
    --policy-arn "$POLICY_ARN" \
    --version-id "$POLICY_VERSION" \
    --query 'PolicyVersion.Document.Statement[].Action[]' \
    --output json | jq -r '.[]' | sort -u
fi

# Get permission boundary
echo ""
echo "2. Permission Boundary:"
BOUNDARY_ARN=$(aws iam get-role --role-name $ROLE_NAME \
  --query 'Role.PermissionsBoundary.PermissionsBoundaryArn' \
  --output text)

if [ -n "$BOUNDARY_ARN" ] && [ "$BOUNDARY_ARN" != "None" ]; then
  BOUNDARY_VERSION=$(aws iam get-policy --policy-arn "$BOUNDARY_ARN" \
    --query 'Policy.DefaultVersionId' --output text)
  
  echo "  Boundary: $BOUNDARY_ARN"
  aws iam get-policy-version \
    --policy-arn "$BOUNDARY_ARN" \
    --version-id "$BOUNDARY_VERSION" \
    --query 'PolicyVersion.Document.Statement[].Action[]' \
    --output json | jq -r '.[]' | sort -u
else
  echo "  No boundary set"
fi

echo ""
echo "Note: Effective permissions = Role Policies ∩ Permission Boundary"
echo "      (intersection of both sets)"
```


## Audit Procedures

### Daily Audit Tasks

#### 1. Verify Service Account Bindings

```bash
# Daily check that service accounts have correct role annotations
kubectl get serviceaccounts --all-namespaces \
  -o json | jq -r '.items[] | select(.metadata.annotations."eks.amazonaws.com/role-arn" != null) | "\(.metadata.namespace)/\(.metadata.name) -> \(.metadata.annotations."eks.amazonaws.com/role-arn")"'
```

#### 2. Check for Unauthorized Role Assumptions

```bash
# Check CloudTrail for AssumeRoleWithWebIdentity events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --start-time "$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --query 'Events[].{Time:EventTime,Role:Resources[0].ResourceName,ServiceAccount:CloudTrailEvent}' \
  --output json | jq -r '.[] | "\(.Time) - \(.Role)"'
```

### Weekly Audit Tasks

#### 1. Review IAM Policy Changes

```bash
# Find all IAM policy modifications in the past week
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::IAM::Policy \
  --start-time "$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --query 'Events[?contains(EventName, `Policy`)].{Time:EventTime,Event:EventName,User:Username,Resource:Resources[0].ResourceName}' \
  --output table
```

#### 2. Audit Trust Policy Configurations

```bash
# Script to audit all IRSA roles
#!/bin/bash

echo "=== Weekly IRSA Trust Policy Audit ==="
echo ""

# Find all roles with OIDC trust policies
ROLES=$(aws iam list-roles --query 'Roles[?contains(AssumeRolePolicyDocument.Statement[0].Principal.Federated, `oidc-provider`)].RoleName' --output text)

for ROLE in $ROLES; do
  echo "Role: $ROLE"
  
  # Get service account from trust policy
  SA=$(aws iam get-role --role-name $ROLE \
    --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals' \
    --output json | jq -r 'to_entries[] | select(.key | endswith(":sub")) | .value')
  
  echo "  Service Account: $SA"
  
  # Check if service account exists in Kubernetes
  NAMESPACE=$(echo $SA | cut -d: -f3)
  SA_NAME=$(echo $SA | cut -d: -f4)
  
  if kubectl get serviceaccount $SA_NAME -n $NAMESPACE &>/dev/null; then
    echo "  ✅ Service account exists in Kubernetes"
  else
    echo "  ❌ Service account NOT found in Kubernetes (orphaned role?)"
  fi
  
  echo ""
done
```

#### 3. Review Permission Scope

```bash
# Check for overly broad permissions
#!/bin/bash

echo "=== Permission Scope Audit ==="
echo ""

ROLE_NAME="HarborS3Role"
POLICY_ARN=$(aws iam list-attached-role-policies --role-name $ROLE_NAME \
  --query 'AttachedPolicies[0].PolicyArn' --output text)

POLICY_VERSION=$(aws iam get-policy --policy-arn "$POLICY_ARN" \
  --query 'Policy.DefaultVersionId' --output text)

POLICY_DOC=$(aws iam get-policy-version \
  --policy-arn "$POLICY_ARN" \
  --version-id "$POLICY_VERSION" \
  --query 'PolicyVersion.Document' --output json)

# Check for wildcard resources
WILDCARD_COUNT=$(echo "$POLICY_DOC" | jq '[.Statement[].Resource] | flatten | map(select(. == "*")) | length')

if [ "$WILDCARD_COUNT" -gt 0 ]; then
  echo "❌ CRITICAL: Policy contains $WILDCARD_COUNT wildcard resource(s)"
  echo "$POLICY_DOC" | jq '.Statement[] | select(.Resource == "*")'
else
  echo "✅ No wildcard resources found"
fi

# Check for overly broad actions
WILDCARD_ACTIONS=$(echo "$POLICY_DOC" | jq -r '.Statement[].Action[] | select(endswith(":*"))')

if [ -n "$WILDCARD_ACTIONS" ]; then
  echo "⚠️  WARNING: Policy contains wildcard actions:"
  echo "$WILDCARD_ACTIONS"
else
  echo "✅ No wildcard actions found"
fi
```


### Monthly Audit Tasks

#### 1. Comprehensive Permission Review

```bash
# Generate comprehensive permission report
#!/bin/bash

OUTPUT_FILE="irsa-permission-audit-$(date +%Y-%m-%d).txt"

echo "=== IRSA Permission Audit Report ===" > $OUTPUT_FILE
echo "Generated: $(date)" >> $OUTPUT_FILE
echo "" >> $OUTPUT_FILE

# List all IRSA roles
echo "=== IRSA Roles ===" >> $OUTPUT_FILE
aws iam list-roles \
  --query 'Roles[?contains(AssumeRolePolicyDocument.Statement[0].Principal.Federated, `oidc-provider`)].{RoleName:RoleName,Created:CreateDate}' \
  --output table >> $OUTPUT_FILE

echo "" >> $OUTPUT_FILE

# For each role, document permissions
ROLES=$(aws iam list-roles --query 'Roles[?contains(AssumeRolePolicyDocument.Statement[0].Principal.Federated, `oidc-provider`)].RoleName' --output text)

for ROLE in $ROLES; do
  echo "=== Role: $ROLE ===" >> $OUTPUT_FILE
  
  # Trust policy
  echo "Trust Policy:" >> $OUTPUT_FILE
  aws iam get-role --role-name $ROLE \
    --query 'Role.AssumeRolePolicyDocument' \
    --output json | jq . >> $OUTPUT_FILE
  
  echo "" >> $OUTPUT_FILE
  
  # Attached policies
  echo "Attached Policies:" >> $OUTPUT_FILE
  aws iam list-attached-role-policies --role-name $ROLE \
    --output table >> $OUTPUT_FILE
  
  echo "" >> $OUTPUT_FILE
  
  # Last used
  echo "Last Used:" >> $OUTPUT_FILE
  aws iam get-role --role-name $ROLE \
    --query 'Role.RoleLastUsed' \
    --output json | jq . >> $OUTPUT_FILE
  
  echo "" >> $OUTPUT_FILE
  echo "---" >> $OUTPUT_FILE
  echo "" >> $OUTPUT_FILE
done

echo "Audit report saved to: $OUTPUT_FILE"
```

#### 2. Access Pattern Analysis

```bash
# Analyze access patterns over the past month
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --start-time "$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --max-results 1000 \
  --query 'Events[].CloudTrailEvent' \
  --output text | jq -s 'group_by(.userIdentity.sessionContext.sessionIssuer.userName) | map({role: .[0].userIdentity.sessionContext.sessionIssuer.userName, count: length}) | sort_by(.count) | reverse'
```

#### 3. Compliance Checklist

```bash
# Monthly compliance checklist for IRSA
#!/bin/bash

echo "=== IRSA Compliance Checklist ==="
echo ""

ROLE_NAME="HarborS3Role"
PASS=0
FAIL=0
WARN=0

# Check 1: Role exists
if aws iam get-role --role-name $ROLE_NAME &>/dev/null; then
  echo "✅ Role exists"
  ((PASS++))
else
  echo "❌ Role not found"
  ((FAIL++))
  exit 1
fi

# Check 2: Trust policy uses StringEquals (not StringLike)
TRUST_POLICY=$(aws iam get-role --role-name $ROLE_NAME \
  --query 'Role.AssumeRolePolicyDocument' --output json)

if echo "$TRUST_POLICY" | jq -e '.Statement[].Condition.StringEquals' > /dev/null 2>&1; then
  echo "✅ Trust policy uses StringEquals"
  ((PASS++))
else
  echo "❌ Trust policy does not use StringEquals"
  ((FAIL++))
fi

# Check 3: Service account is specific (no wildcards)
SUB_VALUE=$(echo "$TRUST_POLICY" | jq -r '.Statement[].Condition.StringEquals | to_entries[] | select(.key | endswith(":sub")) | .value')
if [[ "$SUB_VALUE" != *"*"* ]]; then
  echo "✅ Service account is specific (no wildcards)"
  ((PASS++))
else
  echo "❌ Service account contains wildcards"
  ((FAIL++))
fi

# Check 4: Permissions are scoped to specific resources
POLICY_ARN=$(aws iam list-attached-role-policies --role-name $ROLE_NAME \
  --query 'AttachedPolicies[0].PolicyArn' --output text)

if [ -n "$POLICY_ARN" ] && [ "$POLICY_ARN" != "None" ]; then
  POLICY_VERSION=$(aws iam get-policy --policy-arn "$POLICY_ARN" \
    --query 'Policy.DefaultVersionId' --output text)
  
  WILDCARD_RESOURCES=$(aws iam get-policy-version \
    --policy-arn "$POLICY_ARN" \
    --version-id "$POLICY_VERSION" \
    --query 'PolicyVersion.Document.Statement[].Resource' \
    --output json | jq -r '.[] | select(. == "*")')
  
  if [ -z "$WILDCARD_RESOURCES" ]; then
    echo "✅ Permissions scoped to specific resources"
    ((PASS++))
  else
    echo "❌ Permissions use wildcard resources"
    ((FAIL++))
  fi
fi

# Check 5: Role has been used recently
LAST_USED=$(aws iam get-role --role-name $ROLE_NAME \
  --query 'Role.RoleLastUsed.LastUsedDate' --output text)

if [ "$LAST_USED" != "None" ] && [ -n "$LAST_USED" ]; then
  DAYS_SINCE_USE=$(( ($(date +%s) - $(date -d "$LAST_USED" +%s)) / 86400 ))
  if [ $DAYS_SINCE_USE -lt 7 ]; then
    echo "✅ Role used within last 7 days"
    ((PASS++))
  else
    echo "⚠️  Role last used $DAYS_SINCE_USE days ago"
    ((WARN++))
  fi
else
  echo "⚠️  Role has never been used"
  ((WARN++))
fi

# Check 6: Service account exists in Kubernetes
NAMESPACE=$(echo $SUB_VALUE | cut -d: -f3)
SA_NAME=$(echo $SUB_VALUE | cut -d: -f4)

if kubectl get serviceaccount $SA_NAME -n $NAMESPACE &>/dev/null; then
  echo "✅ Service account exists in Kubernetes"
  ((PASS++))
else
  echo "❌ Service account not found in Kubernetes"
  ((FAIL++))
fi

# Summary
echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Warnings: $WARN"

if [ $FAIL -eq 0 ]; then
  echo "✅ Compliance check PASSED"
  exit 0
else
  echo "❌ Compliance check FAILED"
  exit 1
fi
```


## Automated Monitoring

### CloudWatch Alarms

#### Alert on Policy Changes

```bash
# Create CloudWatch alarm for IAM policy changes
aws cloudwatch put-metric-alarm \
  --alarm-name "HarborS3Role-PolicyChanges" \
  --alarm-description "Alert when HarborS3Role policies are modified" \
  --metric-name PolicyChanges \
  --namespace IAM \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:security-alerts

# Create metric filter for CloudTrail logs
aws logs put-metric-filter \
  --log-group-name CloudTrail/logs \
  --filter-name HarborRolePolicyChanges \
  --filter-pattern '{ ($.eventName = PutRolePolicy || $.eventName = AttachRolePolicy || $.eventName = DetachRolePolicy || $.eventName = CreatePolicyVersion) && $.requestParameters.roleName = "HarborS3Role" }' \
  --metric-transformations \
    metricName=PolicyChanges,metricNamespace=IAM,metricValue=1
```

#### Alert on Unauthorized Role Assumptions

```bash
# Create alarm for role assumptions from unexpected service accounts
aws logs put-metric-filter \
  --log-group-name CloudTrail/logs \
  --filter-name UnauthorizedHarborRoleAssumption \
  --filter-pattern '{ $.eventName = "AssumeRoleWithWebIdentity" && $.requestParameters.roleArn = "*HarborS3Role*" && $.userIdentity.sessionContext.webIdFederationData.attributes.sub != "system:serviceaccount:harbor:harbor-registry" }' \
  --metric-transformations \
    metricName=UnauthorizedRoleAssumption,metricNamespace=Security,metricValue=1

aws cloudwatch put-metric-alarm \
  --alarm-name "HarborS3Role-UnauthorizedAssumption" \
  --alarm-description "Alert when HarborS3Role is assumed by unexpected service account" \
  --metric-name UnauthorizedRoleAssumption \
  --namespace Security \
  --statistic Sum \
  --period 60 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:security-alerts
```

### AWS Config Rules

#### Monitor IAM Role Configuration

```bash
# Create AWS Config rule to monitor IAM role trust policies
aws configservice put-config-rule \
  --config-rule '{
    "ConfigRuleName": "harbor-irsa-trust-policy-check",
    "Description": "Ensures HarborS3Role trust policy is properly configured",
    "Source": {
      "Owner": "AWS",
      "SourceIdentifier": "IAM_ROLE_MANAGED_POLICY_CHECK"
    },
    "Scope": {
      "ComplianceResourceTypes": ["AWS::IAM::Role"],
      "ComplianceResourceId": "HarborS3Role"
    }
  }'
```

### Lambda-Based Monitoring

```python
# Lambda function to monitor and report on IRSA configurations
import boto3
import json
from datetime import datetime

iam = boto3.client('iam')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Monitors IRSA role configurations and sends alerts for issues
    """
    
    role_name = 'HarborS3Role'
    issues = []
    
    try:
        # Get role details
        role = iam.get_role(RoleName=role_name)
        trust_policy = role['Role']['AssumeRolePolicyDocument']
        
        # Check 1: Verify trust policy uses StringEquals
        if 'StringLike' in str(trust_policy):
            issues.append("Trust policy uses StringLike (should use StringEquals)")
        
        # Check 2: Verify service account is specific
        for statement in trust_policy.get('Statement', []):
            conditions = statement.get('Condition', {})
            string_equals = conditions.get('StringEquals', {})
            
            for key, value in string_equals.items():
                if ':sub' in key and '*' in value:
                    issues.append(f"Service account contains wildcard: {value}")
        
        # Check 3: Verify role has been used recently
        last_used = role['Role'].get('RoleLastUsed', {}).get('LastUsedDate')
        if last_used:
            days_since_use = (datetime.now(last_used.tzinfo) - last_used).days
            if days_since_use > 7:
                issues.append(f"Role not used in {days_since_use} days")
        
        # Check 4: Verify attached policies
        attached_policies = iam.list_attached_role_policies(RoleName=role_name)
        if not attached_policies['AttachedPolicies']:
            issues.append("No policies attached to role")
        
        # Send alert if issues found
        if issues:
            message = f"IRSA Configuration Issues for {role_name}:\n\n"
            message += "\n".join(f"- {issue}" for issue in issues)
            
            sns.publish(
                TopicArn='arn:aws:sns:us-east-1:123456789012:security-alerts',
                Subject=f'IRSA Alert: {role_name}',
                Message=message
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'status': 'issues_found',
                    'issues': issues
                })
            }
        else:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'status': 'healthy',
                    'message': 'No issues found'
                })
            }
            
    except Exception as e:
        error_message = f"Error monitoring IRSA role: {str(e)}"
        sns.publish(
            TopicArn='arn:aws:sns:us-east-1:123456789012:security-alerts',
            Subject=f'IRSA Monitoring Error',
            Message=error_message
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'status': 'error',
                'error': str(e)
            })
        }
```


## Compliance Reporting

### Generating Compliance Reports

#### IAM Access Analyzer Report

```bash
# Create IAM Access Analyzer
aws accessanalyzer create-analyzer \
  --analyzer-name harbor-irsa-analyzer \
  --type ACCOUNT

# List findings for the Harbor role
aws accessanalyzer list-findings \
  --analyzer-arn arn:aws:access-analyzer:us-east-1:123456789012:analyzer/harbor-irsa-analyzer \
  --filter '{"resource": {"contains": ["HarborS3Role"]}}' \
  --output table
```

#### Generate Permission Report

```bash
#!/bin/bash
# Generate comprehensive permission report for compliance

REPORT_DATE=$(date +%Y-%m-%d)
REPORT_FILE="harbor-irsa-compliance-report-${REPORT_DATE}.html"

cat > $REPORT_FILE << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Harbor IRSA Compliance Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #232F3E; }
        h2 { color: #FF9900; border-bottom: 2px solid #FF9900; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th { background-color: #232F3E; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .pass { color: green; font-weight: bold; }
        .fail { color: red; font-weight: bold; }
        .warn { color: orange; font-weight: bold; }
    </style>
</head>
<body>
    <h1>Harbor IRSA Compliance Report</h1>
    <p><strong>Generated:</strong> $(date)</p>
    <p><strong>Role:</strong> HarborS3Role</p>
    
    <h2>Executive Summary</h2>
EOF

# Add role information
ROLE_ARN=$(aws iam get-role --role-name HarborS3Role --query 'Role.Arn' --output text)
ROLE_CREATED=$(aws iam get-role --role-name HarborS3Role --query 'Role.CreateDate' --output text)

cat >> $REPORT_FILE << EOF
    <table>
        <tr><th>Property</th><th>Value</th></tr>
        <tr><td>Role ARN</td><td>$ROLE_ARN</td></tr>
        <tr><td>Created</td><td>$ROLE_CREATED</td></tr>
    </table>
    
    <h2>Trust Policy Configuration</h2>
EOF

# Add trust policy
TRUST_POLICY=$(aws iam get-role --role-name HarborS3Role \
  --query 'Role.AssumeRolePolicyDocument' --output json | jq -r tostring)

cat >> $REPORT_FILE << EOF
    <pre>$TRUST_POLICY</pre>
    
    <h2>Permissions Policy</h2>
EOF

# Add permissions policy
POLICY_ARN=$(aws iam list-attached-role-policies --role-name HarborS3Role \
  --query 'AttachedPolicies[0].PolicyArn' --output text)

if [ -n "$POLICY_ARN" ] && [ "$POLICY_ARN" != "None" ]; then
  POLICY_VERSION=$(aws iam get-policy --policy-arn "$POLICY_ARN" \
    --query 'Policy.DefaultVersionId' --output text)
  
  POLICY_DOC=$(aws iam get-policy-version \
    --policy-arn "$POLICY_ARN" \
    --version-id "$POLICY_VERSION" \
    --query 'PolicyVersion.Document' --output json | jq -r tostring)
  
  cat >> $REPORT_FILE << EOF
    <pre>$POLICY_DOC</pre>
EOF
fi

# Add compliance checks
cat >> $REPORT_FILE << 'EOF'
    <h2>Compliance Checks</h2>
    <table>
        <tr>
            <th>Check</th>
            <th>Status</th>
            <th>Details</th>
        </tr>
EOF

# Run compliance checks and add to report
# (This would include the checks from the monthly audit script)

cat >> $REPORT_FILE << 'EOF'
    </table>
    
    <h2>Recent Access Activity</h2>
EOF

# Add recent access activity
RECENT_ACCESS=$(aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --start-time "$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --max-results 10 \
  --query 'Events[].{Time:EventTime,IP:CloudTrailEvent}' \
  --output json)

cat >> $REPORT_FILE << EOF
    <pre>$RECENT_ACCESS</pre>
    
    <h2>Recommendations</h2>
    <ul>
        <li>Continue monitoring role usage patterns</li>
        <li>Review and update policies quarterly</li>
        <li>Ensure CloudTrail logging is enabled</li>
        <li>Implement automated compliance checks</li>
    </ul>
    
</body>
</html>
EOF

echo "Compliance report generated: $REPORT_FILE"
```

### Audit Trail Export

```bash
# Export audit trail for compliance archival
#!/bin/bash

EXPORT_DATE=$(date +%Y-%m-%d)
EXPORT_DIR="harbor-irsa-audit-${EXPORT_DATE}"

mkdir -p $EXPORT_DIR

# Export IAM role configuration
aws iam get-role --role-name HarborS3Role \
  --output json > $EXPORT_DIR/role-configuration.json

# Export trust policy
aws iam get-role --role-name HarborS3Role \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json > $EXPORT_DIR/trust-policy.json

# Export permissions policies
POLICY_ARN=$(aws iam list-attached-role-policies --role-name HarborS3Role \
  --query 'AttachedPolicies[0].PolicyArn' --output text)

if [ -n "$POLICY_ARN" ] && [ "$POLICY_ARN" != "None" ]; then
  POLICY_VERSION=$(aws iam get-policy --policy-arn "$POLICY_ARN" \
    --query 'Policy.DefaultVersionId' --output text)
  
  aws iam get-policy-version \
    --policy-arn "$POLICY_ARN" \
    --version-id "$POLICY_VERSION" \
    --output json > $EXPORT_DIR/permissions-policy.json
fi

# Export CloudTrail events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=HarborS3Role \
  --start-time "$(date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --max-results 1000 \
  --output json > $EXPORT_DIR/cloudtrail-events.json

# Export Kubernetes service account configuration
kubectl get serviceaccount harbor-registry -n harbor \
  -o yaml > $EXPORT_DIR/service-account.yaml

# Create archive
tar -czf ${EXPORT_DIR}.tar.gz $EXPORT_DIR
rm -rf $EXPORT_DIR

echo "Audit trail exported to: ${EXPORT_DIR}.tar.gz"
```

## Summary

This permission tracking guide provides comprehensive procedures for:

1. **IAM Policy Tracking**: Query and analyze IAM role permissions, policies, and changes
2. **Service Account Binding**: Verify Kubernetes service account annotations and bindings
3. **Trust Policy Auditing**: Ensure trust policies are properly configured and secure
4. **Permission Boundaries**: Track and analyze permission boundaries when applicable
5. **Audit Procedures**: Daily, weekly, and monthly audit tasks for ongoing compliance
6. **Automated Monitoring**: CloudWatch alarms, Config rules, and Lambda functions
7. **Compliance Reporting**: Generate reports and export audit trails for compliance

### Key Takeaways

- **Regular Auditing**: Implement daily, weekly, and monthly audit procedures
- **Automated Monitoring**: Use CloudWatch and Lambda for continuous monitoring
- **Compliance Documentation**: Generate regular reports for audit and compliance
- **Trust Policy Security**: Ensure trust policies use StringEquals and specific service accounts
- **Permission Scope**: Verify permissions are scoped to specific resources, not wildcards
- **Cross-Reference**: Always verify both IAM and Kubernetes configurations match

### Best Practices

1. Automate permission tracking with scheduled Lambda functions
2. Set up CloudWatch alarms for policy changes and unauthorized access
3. Conduct monthly comprehensive audits
4. Export audit trails quarterly for compliance archival
5. Document all permission changes in change management system
6. Review and update trust policies when service accounts change
7. Use IAM Access Analyzer to identify external access risks

## Additional Resources

- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [IAM Access Analyzer](https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html)
- [AWS Config Rules](https://docs.aws.amazon.com/config/latest/developerguide/managed-rules-by-aws-config.html)
- [CloudWatch Logs Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AnalyzingLogData.html)
- [IRSA Technical Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
