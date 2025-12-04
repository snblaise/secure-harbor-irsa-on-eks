# OIDC Provider Setup Guide for EKS IRSA

## Overview

This guide walks you through setting up an OpenID Connect (OIDC) identity provider for your Amazon EKS cluster. The OIDC provider is the foundation of IAM Roles for Service Accounts (IRSA), enabling Kubernetes service accounts to assume AWS IAM roles securely.

## Table of Contents

1. [What is OIDC and Why Do We Need It?](#what-is-oidc-and-why-do-we-need-it)
2. [Prerequisites](#prerequisites)
3. [Step 1: Verify EKS Cluster OIDC Issuer](#step-1-verify-eks-cluster-oidc-issuer)
4. [Step 2: Create IAM OIDC Identity Provider](#step-2-create-iam-oidc-identity-provider)
5. [Step 3: Verify OIDC Provider Configuration](#step-3-verify-oidc-provider-configuration)
6. [Step 4: Understand OIDC Thumbprint](#step-4-understand-oidc-thumbprint)
7. [Troubleshooting](#troubleshooting)

## What is OIDC and Why Do We Need It?

### The Challenge

Kubernetes pods need to access AWS services (like S3), but how do they authenticate securely without static credentials?

### The Solution: OIDC Federation

OpenID Connect (OIDC) is an identity layer built on OAuth 2.0 that enables federation between Kubernetes and AWS IAM:

1. **EKS creates an OIDC provider** that issues JWT (JSON Web Tokens) to service accounts
2. **AWS IAM trusts this OIDC provider** through an IAM OIDC identity provider
3. **Pods present JWT tokens** to AWS STS (Security Token Service)
4. **AWS STS validates the token** and issues temporary AWS credentials
5. **Pods use temporary credentials** to access AWS services

### Benefits

✅ **No static credentials** - Tokens are short-lived and automatically rotated  
✅ **Strong identity binding** - Tokens are bound to specific namespace and service account  
✅ **AWS-native trust** - Uses standard AWS IAM trust policies  
✅ **Automatic token projection** - Kubernetes automatically mounts tokens in pods  

## Prerequisites

Before starting, ensure you have:

- **EKS cluster** running version 1.28 or later
- **AWS CLI** v2.x installed and configured
- **kubectl** configured to access your EKS cluster
- **IAM permissions** to create OIDC providers
- **jq** installed for JSON parsing (optional but recommended)

### Required IAM Permissions

Your AWS user/role needs these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "iam:CreateOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider",
        "iam:TagOpenIDConnectProvider"
      ],
      "Resource": "*"
    }
  ]
}
```

## Step 1: Verify EKS Cluster OIDC Issuer

Every EKS cluster has an OIDC issuer URL automatically created by AWS. Let's verify it exists.

### 1.1 Set Environment Variables

```bash
# Set your cluster name and region
export CLUSTER_NAME="harbor-irsa-workshop"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Cluster: ${CLUSTER_NAME}"
echo "Region: ${AWS_REGION}"
echo "Account: ${AWS_ACCOUNT_ID}"
```

### 1.2 Get OIDC Issuer URL

```bash
# Retrieve the OIDC issuer URL from your EKS cluster
export OIDC_ISSUER=$(aws eks describe-cluster \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --query "cluster.identity.oidc.issuer" \
  --output text)

echo "OIDC Issuer: ${OIDC_ISSUER}"
```

**Expected output:**
```
OIDC Issuer: https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE
```

### 1.3 Extract OIDC Provider ID

```bash
# Extract just the ID portion (everything after /id/)
export OIDC_PROVIDER_ID=$(echo ${OIDC_ISSUER} | sed 's|https://||' | sed 's|oidc.eks.||' | sed 's|.amazonaws.com/id/||')

echo "OIDC Provider ID: ${OIDC_PROVIDER_ID}"
```

**Expected output:**
```
OIDC Provider ID: EXAMPLED539D4633E53DE1B71EXAMPLE
```

### 1.4 Verify OIDC Discovery Document

The OIDC provider exposes a discovery document at `/.well-known/openid-configuration`. Let's verify it's accessible:

```bash
# Fetch the OIDC discovery document
curl -s ${OIDC_ISSUER}/.well-known/openid-configuration | jq .

# Or without jq:
curl -s ${OIDC_ISSUER}/.well-known/openid-configuration
```

**Expected output (partial):**
```json
{
  "issuer": "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE",
  "jwks_uri": "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE/keys",
  "authorization_endpoint": "urn:kubernetes:programmatic_authorization",
  "response_types_supported": [
    "id_token"
  ],
  "subject_types_supported": [
    "public"
  ],
  "id_token_signing_alg_values_supported": [
    "RS256"
  ]
}
```

✅ **Checkpoint**: If you can retrieve this document, your EKS cluster's OIDC provider is working correctly.

## Step 2: Create IAM OIDC Identity Provider

Now we'll register the EKS OIDC provider with AWS IAM so that IAM can trust tokens issued by your cluster.

### 2.1 Check if OIDC Provider Already Exists

```bash
# List existing OIDC providers
aws iam list-open-id-connect-providers --output table

# Check if your specific provider exists
aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, '${OIDC_PROVIDER_ID}')].Arn" \
  --output text
```

If the command returns an ARN, the provider already exists. You can skip to Step 3.

### 2.2 Create OIDC Provider (Method 1: Using eksctl)

The easiest way to create the OIDC provider is using `eksctl`:

```bash
# Install eksctl if not already installed
# macOS: brew install eksctl
# Linux: See https://eksctl.io/installation/

# Create OIDC provider
eksctl utils associate-iam-oidc-provider \
  --cluster ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --approve
```

**Expected output:**
```
2024-01-15 10:30:00 [ℹ]  will create IAM Open ID Connect provider for cluster "harbor-irsa-workshop" in "us-east-1"
2024-01-15 10:30:05 [✔]  created IAM Open ID Connect provider for cluster "harbor-irsa-workshop" in "us-east-1"
```

### 2.3 Create OIDC Provider (Method 2: Using AWS CLI)

If you prefer using AWS CLI directly:

```bash
# Get the OIDC provider thumbprint
# For EKS, the thumbprint is the same across all regions
export OIDC_THUMBPRINT="9e99a48a9960b14926bb7f3b02e22da2b0ab7280"

# Create the OIDC provider
aws iam create-open-id-connect-provider \
  --url ${OIDC_ISSUER} \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list ${OIDC_THUMBPRINT} \
  --tags Key=Environment,Value=workshop Key=ManagedBy,Value=manual

# Capture the ARN
export OIDC_PROVIDER_ARN=$(aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, '${OIDC_PROVIDER_ID}')].Arn" \
  --output text)

echo "OIDC Provider ARN: ${OIDC_PROVIDER_ARN}"
```

**Expected output:**
```
OIDC Provider ARN: arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE
```

### 2.4 Understanding the Parameters

Let's break down what each parameter means:

- **`--url`**: The OIDC issuer URL from your EKS cluster
- **`--client-id-list`**: Set to `sts.amazonaws.com` (the AWS STS service that will validate tokens)
- **`--thumbprint-list`**: SHA-1 fingerprint of the OIDC provider's certificate (see Step 4 for details)
- **`--tags`**: Optional tags for resource management

## Step 3: Verify OIDC Provider Configuration

### 3.1 Get OIDC Provider Details

```bash
# Get detailed information about the OIDC provider
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn ${OIDC_PROVIDER_ARN}
```

**Expected output:**
```json
{
    "Url": "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE",
    "ClientIDList": [
        "sts.amazonaws.com"
    ],
    "ThumbprintList": [
        "9e99a48a9960b14926bb7f3b02e22da2b0ab7280"
    ],
    "CreateDate": "2024-01-15T10:30:05Z",
    "Tags": [
        {
            "Key": "Environment",
            "Value": "workshop"
        },
        {
            "Key": "ManagedBy",
            "Value": "manual"
        }
    ]
}
```

### 3.2 Verify Configuration Checklist

✅ **URL matches your cluster's OIDC issuer** (without `https://`)  
✅ **ClientIDList contains `sts.amazonaws.com`**  
✅ **ThumbprintList is not empty**  
✅ **CreateDate is recent**  

### 3.3 Test OIDC Provider Trust

Create a test service account to verify the OIDC provider is working:

```bash
# Create a test namespace
kubectl create namespace oidc-test

# Create a test service account
kubectl create serviceaccount test-sa -n oidc-test

# Get the service account token
kubectl create token test-sa -n oidc-test --duration=600s
```

This should return a JWT token. If it fails, there's an issue with your cluster's OIDC configuration.

## Step 4: Understand OIDC Thumbprint

### What is the Thumbprint?

The thumbprint is the SHA-1 fingerprint of the root certificate authority (CA) that signed the OIDC provider's TLS certificate. AWS uses this to verify the authenticity of the OIDC provider.

### Why is it Always the Same for EKS?

For Amazon EKS, the thumbprint is **always** `9e99a48a9960b14926bb7f3b02e22da2b0ab7280` across all regions because:

1. All EKS OIDC endpoints use the same root CA
2. AWS manages the certificates centrally
3. The root CA is Amazon's own certificate authority

### How to Retrieve Thumbprint Manually (Optional)

If you want to verify or retrieve the thumbprint yourself:

```bash
# Method 1: Using OpenSSL
echo | openssl s_client -servername oidc.eks.${AWS_REGION}.amazonaws.com \
  -connect oidc.eks.${AWS_REGION}.amazonaws.com:443 2>/dev/null \
  | openssl x509 -fingerprint -noout \
  | sed 's/://g' \
  | awk -F= '{print tolower($2)}'

# Method 2: Using a helper script
cat > get-thumbprint.sh << 'EOF'
#!/bin/bash
OIDC_URL=$1
THUMBPRINT=$(echo | openssl s_client -servername ${OIDC_URL} \
  -showcerts -connect ${OIDC_URL}:443 2>&- \
  | tail -r | sed -n '/-----END CERTIFICATE-----/,/-----BEGIN CERTIFICATE-----/p; /-----BEGIN CERTIFICATE-----/q' \
  | tail -r | openssl x509 -fingerprint -noout \
  | sed 's/://g' | awk -F= '{print tolower($2)}')
echo $THUMBPRINT
EOF

chmod +x get-thumbprint.sh
./get-thumbprint.sh oidc.eks.${AWS_REGION}.amazonaws.com
```

**Expected output:**
```
9e99a48a9960b14926bb7f3b02e22da2b0ab7280
```

### When Would the Thumbprint Change?

The thumbprint would only change if:
- AWS rotates the root CA (rare, with advance notice)
- You're using a custom OIDC provider (not EKS-managed)

For EKS, you can safely use the standard thumbprint.

## Troubleshooting

### Issue 1: OIDC Issuer Not Found

**Symptom:**
```
An error occurred (ResourceNotFoundException) when calling the DescribeCluster operation: No cluster found for name: harbor-irsa-workshop
```

**Solution:**
- Verify cluster name: `aws eks list-clusters --region ${AWS_REGION}`
- Check you're in the correct region
- Ensure your AWS credentials have EKS permissions

### Issue 2: OIDC Provider Already Exists

**Symptom:**
```
An error occurred (EntityAlreadyExists) when calling the CreateOpenIDConnectProvider operation: Provider with url https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE already exists.
```

**Solution:**
This is not an error! The provider already exists. Verify it:
```bash
aws iam get-open-id-connect-provider --open-id-connect-provider-arn ${OIDC_PROVIDER_ARN}
```

### Issue 3: Cannot Access OIDC Discovery Document

**Symptom:**
```
curl: (6) Could not resolve host: oidc.eks.us-east-1.amazonaws.com
```

**Solution:**
- Check your internet connectivity
- Verify the OIDC issuer URL is correct
- Ensure no firewall is blocking HTTPS traffic

### Issue 4: Insufficient IAM Permissions

**Symptom:**
```
An error occurred (AccessDenied) when calling the CreateOpenIDConnectProvider operation: User: arn:aws:iam::123456789012:user/myuser is not authorized to perform: iam:CreateOpenIDConnectProvider
```

**Solution:**
Add the required IAM permissions (see Prerequisites section) to your user/role.

### Issue 5: Wrong Thumbprint

**Symptom:**
IAM role assumption fails later with:
```
An error occurred (InvalidIdentityToken) when calling the AssumeRoleWithWebIdentity operation: Couldn't retrieve verification key from your identity provider
```

**Solution:**
Update the OIDC provider with the correct thumbprint:
```bash
aws iam update-open-id-connect-provider-thumbprint \
  --open-id-connect-provider-arn ${OIDC_PROVIDER_ARN} \
  --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab7280
```

## Verification Checklist

Before proceeding to IAM role configuration, verify:

- [ ] EKS cluster OIDC issuer URL retrieved successfully
- [ ] OIDC discovery document accessible via curl
- [ ] IAM OIDC identity provider created in AWS
- [ ] OIDC provider ARN captured in environment variable
- [ ] OIDC provider details show correct URL and client ID
- [ ] Test service account token can be created

## Next Steps

Now that your OIDC provider is configured, you can proceed to:

1. **[Create IAM Role and Policy Documents](./iam-role-policy-setup.md)** - Configure IAM roles that trust your OIDC provider
2. **[Deploy Harbor with IRSA](./harbor-irsa-deployment.md)** - Deploy Harbor using the IRSA configuration
3. **[Validate IRSA Setup](../validation-tests/02-irsa-validation.sh)** - Test that everything works correctly

## Additional Resources

### AWS Documentation
- [IAM OIDC Identity Providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [EKS OIDC Provider](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html)
- [Service Account Token Volume Projection](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#service-account-token-volume-projection)

### Useful Commands Reference

```bash
# List all OIDC providers
aws iam list-open-id-connect-providers

# Get specific OIDC provider details
aws iam get-open-id-connect-provider --open-id-connect-provider-arn <ARN>

# Delete OIDC provider (cleanup)
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn <ARN>

# Update OIDC provider thumbprint
aws iam update-open-id-connect-provider-thumbprint \
  --open-id-connect-provider-arn <ARN> \
  --thumbprint-list <THUMBPRINT>

# Tag OIDC provider
aws iam tag-open-id-connect-provider \
  --open-id-connect-provider-arn <ARN> \
  --tags Key=Name,Value=eks-oidc-provider
```

## Summary

You've successfully configured the OIDC identity provider for your EKS cluster! This is the foundation that enables IRSA to work. Here's what you accomplished:

✅ Verified your EKS cluster's OIDC issuer URL  
✅ Created an IAM OIDC identity provider  
✅ Configured the provider to trust `sts.amazonaws.com`  
✅ Verified the provider configuration  
✅ Understood how OIDC thumbprints work  

The OIDC provider now acts as a trust bridge between Kubernetes and AWS IAM, enabling service accounts to assume IAM roles securely without static credentials.

---

**Next**: [IAM Role and Policy Configuration](./iam-role-policy-setup.md)
