# CloudTrail Log Analysis Guide

## Overview

This guide demonstrates how to analyze AWS CloudTrail logs to understand the identity attribution and audit trail differences between IAM user token access and IRSA (IAM Roles for Service Accounts) access. CloudTrail provides comprehensive logging of all AWS API calls, enabling security teams to track who accessed what resources, when, and from where.

## Table of Contents

1. [CloudTrail Basics](#cloudtrail-basics)
2. [IRSA Access Log Examples](#irsa-access-log-examples)
3. [IAM User Access Log Examples](#iam-user-access-log-examples)
4. [Comparison and Analysis](#comparison-and-analysis)
5. [Querying CloudTrail Logs](#querying-cloudtrail-logs)
6. [Identity Attribution](#identity-attribution)
7. [Security Insights](#security-insights)

## CloudTrail Basics

### What CloudTrail Logs

CloudTrail records AWS API calls made in your account, including:
- **Who**: The identity that made the request (IAM user, role, service)
- **What**: The API action performed (e.g., s3:PutObject, kms:Decrypt)
- **When**: Timestamp of the request
- **Where**: Source IP address and user agent
- **Result**: Success or failure of the request

### CloudTrail Event Structure

Every CloudTrail event contains key fields:
- `eventTime`: When the API call occurred
- `eventName`: The API action (e.g., PutObject, GetObject)
- `userIdentity`: Details about who made the request
- `sourceIPAddress`: IP address of the requester
- `requestParameters`: Parameters passed to the API
- `responseElements`: Response from the API
- `errorCode`: Error code if the request failed


## IRSA Access Log Examples

### Example 1: S3 PutObject via IRSA

When Harbor uses IRSA to upload an image layer to S3, CloudTrail records the following:

```json
{
  "eventVersion": "1.08",
  "userIdentity": {
    "type": "AssumedRole",
    "principalId": "AROAEXAMPLEID:botocore-session-1234567890",
    "arn": "arn:aws:sts::123456789012:assumed-role/HarborS3Role/botocore-session-1234567890",
    "accountId": "123456789012",
    "accessKeyId": "ASIAEXAMPLEACCESSKEY",
    "sessionContext": {
      "sessionIssuer": {
        "type": "Role",
        "principalId": "AROAEXAMPLEID",
        "arn": "arn:aws:iam::123456789012:role/HarborS3Role",
        "accountId": "123456789012",
        "userName": "HarborS3Role"
      },
      "webIdFederationData": {
        "federatedProvider": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE",
        "attributes": {
          "aud": "sts.amazonaws.com",
          "sub": "system:serviceaccount:harbor:harbor-registry"
        }
      },
      "attributes": {
        "creationDate": "2024-12-03T10:15:30Z",
        "mfaAuthenticated": "false"
      }
    }
  },
  "eventTime": "2024-12-03T10:16:45Z",
  "eventSource": "s3.amazonaws.com",
  "eventName": "PutObject",
  "awsRegion": "us-east-1",
  "sourceIPAddress": "10.0.1.45",
  "userAgent": "aws-sdk-go/1.44.0 (go1.19; linux; amd64)",
  "requestParameters": {
    "bucketName": "harbor-registry-storage-123456789012-us-east-1",
    "key": "docker/registry/v2/blobs/sha256/ab/abc123.../data",
    "x-amz-server-side-encryption": "aws:kms",
    "x-amz-server-side-encryption-aws-kms-key-id": "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  },
  "responseElements": null,
  "requestID": "EXAMPLE123456789",
  "eventID": "EXAMPLE-1234-5678-9012-EXAMPLE",
  "readOnly": false,
  "resources": [
    {
      "type": "AWS::S3::Object",
      "ARN": "arn:aws:s3:::harbor-registry-storage-123456789012-us-east-1/docker/registry/v2/blobs/sha256/ab/abc123.../data"
    },
    {
      "accountId": "123456789012",
      "type": "AWS::S3::Bucket",
      "ARN": "arn:aws:s3:::harbor-registry-storage-123456789012-us-east-1"
    }
  ],
  "eventType": "AwsApiCall",
  "managementEvent": false,
  "recipientAccountId": "123456789012",
  "sharedEventID": "EXAMPLE-SHARED-ID"
}
```

### Key IRSA Identifiers

**Critical fields that identify IRSA access:**

1. **userIdentity.type**: `AssumedRole` - Indicates temporary credentials from role assumption
2. **userIdentity.arn**: Shows the assumed role session ARN
3. **sessionContext.webIdFederationData**: Contains OIDC provider information
4. **sessionContext.webIdFederationData.attributes.sub**: Shows the Kubernetes service account
   - Format: `system:serviceaccount:<namespace>:<service-account-name>`
   - Example: `system:serviceaccount:harbor:harbor-registry`


### Example 2: KMS Decrypt via IRSA

When Harbor decrypts an S3 object encrypted with KMS:

```json
{
  "eventVersion": "1.08",
  "userIdentity": {
    "type": "AssumedRole",
    "principalId": "AROAEXAMPLEID:botocore-session-1234567890",
    "arn": "arn:aws:sts::123456789012:assumed-role/HarborS3Role/botocore-session-1234567890",
    "accountId": "123456789012",
    "accessKeyId": "ASIAEXAMPLEACCESSKEY",
    "sessionContext": {
      "sessionIssuer": {
        "type": "Role",
        "principalId": "AROAEXAMPLEID",
        "arn": "arn:aws:iam::123456789012:role/HarborS3Role",
        "accountId": "123456789012",
        "userName": "HarborS3Role"
      },
      "webIdFederationData": {
        "federatedProvider": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE",
        "attributes": {
          "aud": "sts.amazonaws.com",
          "sub": "system:serviceaccount:harbor:harbor-registry"
        }
      }
    }
  },
  "eventTime": "2024-12-03T10:16:46Z",
  "eventSource": "kms.amazonaws.com",
  "eventName": "Decrypt",
  "awsRegion": "us-east-1",
  "sourceIPAddress": "10.0.1.45",
  "userAgent": "aws-sdk-go/1.44.0 (go1.19; linux; amd64)",
  "requestParameters": {
    "encryptionContext": {
      "aws:s3:arn": "arn:aws:s3:::harbor-registry-storage-123456789012-us-east-1/docker/registry/v2/blobs/sha256/ab/abc123.../data"
    },
    "encryptionAlgorithm": "SYMMETRIC_DEFAULT"
  },
  "responseElements": null,
  "requestID": "EXAMPLE-KMS-REQUEST-ID",
  "eventID": "EXAMPLE-KMS-EVENT-ID",
  "readOnly": true,
  "resources": [
    {
      "accountId": "123456789012",
      "type": "AWS::KMS::Key",
      "ARN": "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    }
  ],
  "eventType": "AwsApiCall",
  "managementEvent": false,
  "recipientAccountId": "123456789012"
}
```


## IAM User Access Log Examples

### Example 3: S3 PutObject via IAM User

When Harbor uses static IAM user credentials to upload to S3:

```json
{
  "eventVersion": "1.08",
  "userIdentity": {
    "type": "IAMUser",
    "principalId": "AIDAEXAMPLEUSERID",
    "arn": "arn:aws:iam::123456789012:user/harbor-s3-user",
    "accountId": "123456789012",
    "accessKeyId": "AKIAEXAMPLEACCESSKEY",
    "userName": "harbor-s3-user"
  },
  "eventTime": "2024-12-03T10:16:45Z",
  "eventSource": "s3.amazonaws.com",
  "eventName": "PutObject",
  "awsRegion": "us-east-1",
  "sourceIPAddress": "10.0.1.45",
  "userAgent": "aws-sdk-go/1.44.0 (go1.19; linux; amd64)",
  "requestParameters": {
    "bucketName": "harbor-registry-storage-123456789012-us-east-1",
    "key": "docker/registry/v2/blobs/sha256/ab/abc123.../data"
  },
  "responseElements": null,
  "requestID": "EXAMPLE123456789",
  "eventID": "EXAMPLE-1234-5678-9012-EXAMPLE",
  "readOnly": false,
  "resources": [
    {
      "type": "AWS::S3::Object",
      "ARN": "arn:aws:s3:::harbor-registry-storage-123456789012-us-east-1/docker/registry/v2/blobs/sha256/ab/abc123.../data"
    },
    {
      "accountId": "123456789012",
      "type": "AWS::S3::Bucket",
      "ARN": "arn:aws:s3:::harbor-registry-storage-123456789012-us-east-1"
    }
  ],
  "eventType": "AwsApiCall",
  "managementEvent": false,
  "recipientAccountId": "123456789012"
}
```

### Key IAM User Identifiers

**Critical fields that identify IAM user access:**

1. **userIdentity.type**: `IAMUser` - Indicates long-lived IAM user credentials
2. **userIdentity.userName**: Shows the IAM user name (e.g., `harbor-s3-user`)
3. **userIdentity.accessKeyId**: Shows the access key ID (starts with `AKIA`)
4. **No sessionContext**: IAM users don't have session context or federation data


## Comparison and Analysis

### Side-by-Side Comparison

| Aspect | IRSA Access | IAM User Access |
|--------|-------------|-----------------|
| **Identity Type** | `AssumedRole` | `IAMUser` |
| **Principal ARN** | `arn:aws:sts::ACCOUNT:assumed-role/HarborS3Role/session` | `arn:aws:iam::ACCOUNT:user/harbor-s3-user` |
| **Access Key Type** | Temporary (ASIA...) | Long-lived (AKIA...) |
| **Session Context** | Present with federation data | Absent |
| **Service Account Info** | `system:serviceaccount:harbor:harbor-registry` | Not available |
| **OIDC Provider** | Visible in `webIdFederationData` | Not applicable |
| **Credential Rotation** | Automatic (visible in logs) | Manual (not visible) |
| **Granularity** | Pod-level attribution | User-level only |

### Identity Attribution Differences

#### IRSA: Fine-Grained Attribution

With IRSA, you can trace access to:
1. **AWS Account**: From `accountId`
2. **IAM Role**: From `sessionIssuer.arn`
3. **EKS Cluster**: From OIDC provider URL
4. **Kubernetes Namespace**: From `sub` attribute (e.g., `harbor`)
5. **Service Account**: From `sub` attribute (e.g., `harbor-registry`)
6. **Specific Pod**: By correlating with Kubernetes audit logs using timestamp and IP

**Example attribution chain:**
```
AWS Account 123456789012
  → IAM Role: HarborS3Role
    → EKS Cluster: EXAMPLED539D4633E53DE1B71EXAMPLE
      → Namespace: harbor
        → Service Account: harbor-registry
          → Pod: harbor-registry-core-7d8f9c5b6d-x7k2m (via K8s logs)
```

#### IAM User: Coarse-Grained Attribution

With IAM user credentials, you can only trace access to:
1. **AWS Account**: From `accountId`
2. **IAM User**: From `userName`
3. **Access Key**: From `accessKeyId`

**Example attribution chain:**
```
AWS Account 123456789012
  → IAM User: harbor-s3-user
    → Access Key: AKIAEXAMPLEACCESSKEY
      → ??? (Could be any pod, any namespace, or even outside the cluster)
```

**Problem**: You cannot determine:
- Which pod used the credentials
- Which namespace the pod was in
- Whether the credentials were used from inside or outside the cluster
- If the credentials were stolen and used elsewhere


## Querying CloudTrail Logs

### Using AWS CLI

#### Query IRSA Access Events

```bash
# Find all S3 access via IRSA role
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::S3::Bucket \
  --start-time "2024-12-03T00:00:00Z" \
  --end-time "2024-12-03T23:59:59Z" \
  --query 'Events[?contains(CloudTrailEvent, `HarborS3Role`)].{Time:EventTime,Name:EventName,User:Username}' \
  --output table

# Find events from specific service account
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::S3::Bucket \
  --start-time "2024-12-03T00:00:00Z" \
  --query 'Events[?contains(CloudTrailEvent, `system:serviceaccount:harbor:harbor-registry`)].{Time:EventTime,Name:EventName,Resource:Resources[0].ResourceName}' \
  --output table
```

#### Query IAM User Access Events

```bash
# Find all S3 access via IAM user
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=harbor-s3-user \
  --start-time "2024-12-03T00:00:00Z" \
  --end-time "2024-12-03T23:59:59Z" \
  --query 'Events[].{Time:EventTime,Name:EventName,Resource:Resources[0].ResourceName}' \
  --output table
```

### Using CloudWatch Logs Insights

If CloudTrail is configured to send logs to CloudWatch Logs:

#### Query for IRSA Events

```sql
fields @timestamp, eventName, userIdentity.arn, userIdentity.sessionContext.webIdFederationData.attributes.sub as serviceAccount
| filter eventSource = "s3.amazonaws.com"
| filter userIdentity.type = "AssumedRole"
| filter userIdentity.sessionContext.sessionIssuer.userName = "HarborS3Role"
| sort @timestamp desc
| limit 100
```

#### Query for IAM User Events

```sql
fields @timestamp, eventName, userIdentity.userName, userIdentity.accessKeyId
| filter eventSource = "s3.amazonaws.com"
| filter userIdentity.type = "IAMUser"
| filter userIdentity.userName = "harbor-s3-user"
| sort @timestamp desc
| limit 100
```

#### Compare Access Patterns

```sql
fields @timestamp, 
       userIdentity.type as identityType,
       userIdentity.userName as user,
       userIdentity.sessionContext.webIdFederationData.attributes.sub as serviceAccount,
       eventName,
       sourceIPAddress
| filter eventSource = "s3.amazonaws.com"
| filter requestParameters.bucketName like /harbor-registry-storage/
| sort @timestamp desc
| limit 100
```


### Using Amazon Athena

For large-scale analysis, use Athena to query CloudTrail logs stored in S3:

#### Create Athena Table

```sql
CREATE EXTERNAL TABLE IF NOT EXISTS cloudtrail_logs (
  eventversion STRING,
  useridentity STRUCT<
    type:STRING,
    principalid:STRING,
    arn:STRING,
    accountid:STRING,
    accesskeyid:STRING,
    username:STRING,
    sessioncontext:STRUCT<
      sessionissuer:STRUCT<
        type:STRING,
        principalid:STRING,
        arn:STRING,
        accountid:STRING,
        username:STRING
      >,
      webidfederationdata:STRUCT<
        federatedprovider:STRING,
        attributes:MAP<STRING,STRING>
      >
    >
  >,
  eventtime STRING,
  eventsource STRING,
  eventname STRING,
  awsregion STRING,
  sourceipaddress STRING,
  useragent STRING,
  requestparameters STRING,
  responseelements STRING,
  resources ARRAY<STRUCT<
    arn:STRING,
    accountid:STRING,
    type:STRING
  >>
)
PARTITIONED BY (region STRING, year STRING, month STRING, day STRING)
ROW FORMAT SERDE 'com.amazon.emr.hive.serde.CloudTrailSerde'
STORED AS INPUTFORMAT 'com.amazon.emr.cloudtrail.CloudTrailInputFormat'
OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION 's3://your-cloudtrail-bucket/AWSLogs/123456789012/CloudTrail/';
```

#### Query IRSA Access with Service Account Details

```sql
SELECT 
  eventtime,
  eventname,
  useridentity.sessioncontext.sessionissuer.username as role_name,
  useridentity.sessioncontext.webidfederationdata.attributes['sub'] as service_account,
  sourceipaddress,
  resources[1].arn as resource
FROM cloudtrail_logs
WHERE eventsource = 's3.amazonaws.com'
  AND useridentity.type = 'AssumedRole'
  AND useridentity.sessioncontext.sessionissuer.username = 'HarborS3Role'
  AND year = '2024'
  AND month = '12'
  AND day = '03'
ORDER BY eventtime DESC
LIMIT 100;
```

#### Compare IRSA vs IAM User Access Counts

```sql
SELECT 
  useridentity.type as identity_type,
  CASE 
    WHEN useridentity.type = 'AssumedRole' THEN useridentity.sessioncontext.sessionissuer.username
    WHEN useridentity.type = 'IAMUser' THEN useridentity.username
  END as identity_name,
  eventname,
  COUNT(*) as event_count
FROM cloudtrail_logs
WHERE eventsource = 's3.amazonaws.com'
  AND year = '2024'
  AND month = '12'
  AND day = '03'
GROUP BY useridentity.type, 
         CASE 
           WHEN useridentity.type = 'AssumedRole' THEN useridentity.sessioncontext.sessionissuer.username
           WHEN useridentity.type = 'IAMUser' THEN useridentity.username
         END,
         eventname
ORDER BY event_count DESC;
```


## Identity Attribution

### Tracing IRSA Access to Specific Pods

To trace an IRSA CloudTrail event back to a specific Kubernetes pod:

#### Step 1: Extract Key Information from CloudTrail

From the CloudTrail event, note:
- **Timestamp**: `2024-12-03T10:16:45Z`
- **Source IP**: `10.0.1.45`
- **Service Account**: `system:serviceaccount:harbor:harbor-registry`

#### Step 2: Query Kubernetes Audit Logs

```bash
# Find pods using the service account around the same time
kubectl get pods -n harbor \
  --field-selector status.phase=Running \
  -o json | jq -r '.items[] | select(.spec.serviceAccountName=="harbor-registry") | "\(.metadata.name) \(.status.podIP)"'

# Output:
# harbor-registry-core-7d8f9c5b6d-x7k2m 10.0.1.45
# harbor-registry-jobservice-6c9d8f7b5d-p4n8k 10.0.1.46
```

#### Step 3: Correlate by IP Address

The pod with IP `10.0.1.45` matches the CloudTrail `sourceIPAddress`, confirming:
- **Pod Name**: `harbor-registry-core-7d8f9c5b6d-x7k2m`
- **Namespace**: `harbor`
- **Service Account**: `harbor-registry`

#### Step 4: Get Pod Details

```bash
kubectl describe pod harbor-registry-core-7d8f9c5b6d-x7k2m -n harbor

# Check pod logs for additional context
kubectl logs harbor-registry-core-7d8f9c5b6d-x7k2m -n harbor --since=5m
```

### Tracing IAM User Access (Limited)

With IAM user credentials, attribution is limited:

#### Step 1: Extract Information from CloudTrail

From the CloudTrail event, note:
- **Timestamp**: `2024-12-03T10:16:45Z`
- **Source IP**: `10.0.1.45`
- **IAM User**: `harbor-s3-user`
- **Access Key**: `AKIAEXAMPLEACCESSKEY`

#### Step 2: Attempt to Find Source (Limited Success)

```bash
# Search all pods for environment variables containing the access key
# WARNING: This only works if credentials are in env vars, not if mounted as secrets
kubectl get pods --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.containers[].env[]?.value | contains("AKIAEXAMPLE")) | .metadata.name'
```

**Problem**: 
- Credentials might be in Kubernetes secrets (base64 encoded)
- Credentials might have been extracted and used outside the cluster
- Multiple pods might have the same credentials
- No definitive way to identify which pod made the request


## Security Insights

### Detecting Anomalous Access Patterns

#### IRSA: Easy to Detect Anomalies

With IRSA, you can easily detect:

1. **Unexpected Service Account Usage**
```sql
-- Athena query to find service accounts accessing S3
SELECT DISTINCT
  useridentity.sessioncontext.webidfederationdata.attributes['sub'] as service_account,
  COUNT(*) as access_count
FROM cloudtrail_logs
WHERE eventsource = 's3.amazonaws.com'
  AND useridentity.type = 'AssumedRole'
GROUP BY useridentity.sessioncontext.webidfederationdata.attributes['sub']
HAVING COUNT(*) > 1000;  -- Flag high-volume access
```

2. **Access from Unexpected Namespaces**
```bash
# Alert if service accounts from non-harbor namespaces access Harbor's S3 bucket
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::S3::Bucket \
  --query 'Events[?contains(CloudTrailEvent, `harbor-registry-storage`) && !contains(CloudTrailEvent, `system:serviceaccount:harbor:`)].CloudTrailEvent' \
  --output text
```

3. **Unusual Access Times**
```sql
-- Find S3 access outside business hours
SELECT 
  eventtime,
  useridentity.sessioncontext.webidfederationdata.attributes['sub'] as service_account,
  eventname,
  sourceipaddress
FROM cloudtrail_logs
WHERE eventsource = 's3.amazonaws.com'
  AND useridentity.type = 'AssumedRole'
  AND (CAST(date_format(from_iso8601_timestamp(eventtime), '%H') AS INTEGER) < 6 
       OR CAST(date_format(from_iso8601_timestamp(eventtime), '%H') AS INTEGER) > 22)
ORDER BY eventtime DESC;
```

#### IAM User: Difficult to Detect Anomalies

With IAM user credentials:

1. **Cannot Distinguish Legitimate vs Stolen Credentials**
   - All access appears as the same IAM user
   - No way to know if credentials were extracted and used elsewhere

2. **Cannot Detect Lateral Movement**
   - Credentials might be used from multiple pods
   - No visibility into which pod is making requests

3. **Limited Context for Investigation**
   - Only have IP address and user agent
   - Cannot correlate with Kubernetes resources


### Compliance and Audit Benefits

#### IRSA Advantages for Compliance

1. **SOC 2 Type II Compliance**
   - **Control**: Access to sensitive data is logged with user attribution
   - **Evidence**: CloudTrail logs show service account identity
   - **Benefit**: Can prove which application component accessed data

2. **ISO 27001 Compliance**
   - **Control**: Logical access controls with least privilege
   - **Evidence**: IAM policies scoped to specific service accounts
   - **Benefit**: Can demonstrate fine-grained access control

3. **PCI DSS Compliance**
   - **Requirement 10**: Track and monitor all access to network resources
   - **Evidence**: CloudTrail logs with pod-level attribution
   - **Benefit**: Can trace access to specific workloads

4. **HIPAA Compliance**
   - **Control**: Audit controls to record access to ePHI
   - **Evidence**: Complete audit trail with identity attribution
   - **Benefit**: Can identify which service accessed protected data

#### IAM User Limitations for Compliance

1. **Insufficient Attribution**
   - Cannot prove which application component accessed data
   - Auditors may flag as insufficient access logging

2. **Shared Credentials Risk**
   - Same credentials used across multiple pods
   - Violates principle of unique user identification

3. **Manual Rotation Burden**
   - Must document credential rotation procedures
   - Risk of credentials not being rotated per policy

### Real-World Investigation Scenarios

#### Scenario 1: Unauthorized S3 Access Detected

**IRSA Investigation:**
```bash
# 1. Find the CloudTrail event
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteObject \
  --query 'Events[?contains(CloudTrailEvent, `harbor-registry-storage`)].CloudTrailEvent' \
  --output text | jq .

# 2. Extract service account from event
# Output shows: system:serviceaccount:default:suspicious-sa

# 3. Identify the pod
kubectl get pods -n default --field-selector spec.serviceAccountName=suspicious-sa

# 4. Investigate pod
kubectl describe pod <pod-name> -n default
kubectl logs <pod-name> -n default

# 5. Check IAM role trust policy
aws iam get-role --role-name HarborS3Role --query 'Role.AssumeRolePolicyDocument'

# Result: Trust policy allows default namespace (misconfiguration found!)
```

**IAM User Investigation:**
```bash
# 1. Find the CloudTrail event
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=harbor-s3-user \
  --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteObject

# 2. Extract source IP
# Output shows: 10.0.1.45

# 3. Try to find the pod (limited success)
kubectl get pods --all-namespaces -o wide | grep 10.0.1.45

# Result: Multiple pods might have this IP over time, credentials could be 
# used from outside cluster, investigation inconclusive
```


#### Scenario 2: Compliance Audit Request

**Auditor Request**: "Show me all access to customer data in S3 for the past 90 days, with attribution to specific application components."

**IRSA Response:**
```sql
-- Athena query providing complete attribution
SELECT 
  eventtime,
  eventname,
  useridentity.sessioncontext.sessionissuer.username as iam_role,
  useridentity.sessioncontext.webidfederationdata.attributes['sub'] as service_account,
  SPLIT(useridentity.sessioncontext.webidfederationdata.attributes['sub'], ':')[3] as namespace,
  SPLIT(useridentity.sessioncontext.webidfederationdata.attributes['sub'], ':')[4] as sa_name,
  sourceipaddress,
  resources[1].arn as s3_object
FROM cloudtrail_logs
WHERE eventsource = 's3.amazonaws.com'
  AND resources[1].arn LIKE '%harbor-registry-storage%'
  AND eventtime >= CURRENT_TIMESTAMP - INTERVAL '90' DAY
ORDER BY eventtime DESC;
```

**Result**: Complete audit trail with:
- Timestamp of each access
- IAM role used
- Kubernetes namespace and service account
- Source IP (can correlate to pod)
- Specific S3 object accessed

**IAM User Response:**
```sql
-- Limited attribution available
SELECT 
  eventtime,
  eventname,
  useridentity.username as iam_user,
  useridentity.accesskeyid as access_key,
  sourceipaddress,
  resources[1].arn as s3_object
FROM cloudtrail_logs
WHERE eventsource = 's3.amazonaws.com'
  AND useridentity.username = 'harbor-s3-user'
  AND eventtime >= CURRENT_TIMESTAMP - INTERVAL '90' DAY
ORDER BY eventtime DESC;
```

**Result**: Limited audit trail with:
- Timestamp of each access
- IAM user name (same for all access)
- Access key ID (same for all access)
- Source IP (could be any pod)
- Specific S3 object accessed

**Auditor Concern**: Cannot determine which application component accessed data, only that "some pod with these credentials" did.

## Best Practices

### For IRSA Deployments

1. **Enable CloudTrail Data Events**
   ```bash
   # Ensure S3 data events are logged
   aws cloudtrail put-event-selectors \
     --trail-name my-trail \
     --event-selectors '[{
       "ReadWriteType": "All",
       "IncludeManagementEvents": true,
       "DataResources": [{
         "Type": "AWS::S3::Object",
         "Values": ["arn:aws:s3:::harbor-registry-storage-*/"]
       }]
     }]'
   ```

2. **Set Up CloudWatch Alarms**
   ```bash
   # Alert on unexpected service account access
   aws logs put-metric-filter \
     --log-group-name CloudTrail/logs \
     --filter-name UnexpectedServiceAccountAccess \
     --filter-pattern '{ $.userIdentity.sessionContext.webIdFederationData.attributes.sub != "system:serviceaccount:harbor:harbor-registry" && $.eventSource = "s3.amazonaws.com" }' \
     --metric-transformations \
       metricName=UnexpectedS3Access,metricNamespace=Security,metricValue=1
   ```

3. **Regular Audit Reviews**
   - Weekly review of service accounts accessing S3
   - Monthly review of access patterns and volumes
   - Quarterly review of IAM role trust policies

4. **Integrate with SIEM**
   - Forward CloudTrail logs to SIEM (Splunk, Datadog, etc.)
   - Create dashboards showing service account activity
   - Set up automated anomaly detection

### For IAM User Deployments (Legacy)

1. **Implement Additional Logging**
   - Log all credential usage at application level
   - Include pod name and namespace in application logs
   - Correlate application logs with CloudTrail

2. **Strict Access Key Rotation**
   - Rotate access keys every 90 days minimum
   - Document rotation in change management system
   - Alert on keys older than rotation policy

3. **Monitor for Credential Exposure**
   - Scan GitHub and public repositories for leaked keys
   - Use AWS Access Analyzer to detect unusual access patterns
   - Implement AWS GuardDuty for threat detection

## Summary

CloudTrail log analysis reveals significant differences between IRSA and IAM user access patterns:

| Capability | IRSA | IAM User |
|------------|------|----------|
| **Pod-level attribution** | ✅ Yes | ❌ No |
| **Namespace visibility** | ✅ Yes | ❌ No |
| **Service account tracking** | ✅ Yes | ❌ No |
| **Credential rotation visibility** | ✅ Automatic | ⚠️ Manual only |
| **Anomaly detection** | ✅ Easy | ⚠️ Difficult |
| **Compliance evidence** | ✅ Strong | ⚠️ Weak |
| **Incident investigation** | ✅ Detailed | ⚠️ Limited |
| **Audit trail quality** | ✅ Excellent | ⚠️ Insufficient |

**Key Takeaway**: IRSA provides superior audit trails with fine-grained identity attribution, making it essential for compliance, security investigations, and operational visibility in Kubernetes environments.

## Additional Resources

- [AWS CloudTrail User Guide](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/)
- [CloudTrail Log Event Reference](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-event-reference.html)
- [IRSA Technical Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [CloudWatch Logs Insights Query Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [Amazon Athena for CloudTrail](https://docs.aws.amazon.com/athena/latest/ug/cloudtrail-logs.html)
