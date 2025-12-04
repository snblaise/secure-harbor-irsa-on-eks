# Architecture Diagrams: Harbor on EKS - Insecure vs Secure

This document provides detailed architecture diagrams comparing the insecure IAM user token approach with the secure IRSA (IAM Roles for Service Accounts) approach for deploying Harbor container registry on Amazon EKS with S3 backend storage.

## Table of Contents

1. [Insecure Architecture (IAM User Tokens)](#insecure-architecture-iam-user-tokens)
2. [Secure Architecture (IRSA)](#secure-architecture-irsa)
3. [Component Descriptions](#component-descriptions)
4. [Security Comparison](#security-comparison)
5. [Data Flow Analysis](#data-flow-analysis)

---

## Insecure Architecture (IAM User Tokens)

### High-Level Architecture Diagram

```mermaid
graph TB
    subgraph "AWS Account"
        subgraph "Amazon EKS Cluster"
            subgraph "harbor namespace"
                K8sSecret["🔓 Kubernetes Secret<br/>(Base64 Encoded)<br/>━━━━━━━━━━━━━━<br/>AWS_ACCESS_KEY_ID<br/>AWS_SECRET_ACCESS_KEY"]
                HarborPod["🐳 Harbor Registry Pod<br/>━━━━━━━━━━━━━━<br/>Environment Variables:<br/>• AWS_ACCESS_KEY_ID<br/>• AWS_SECRET_ACCESS_KEY<br/>(from secret)"]
            end
        end
        
        IAMUser["👤 IAM User<br/>━━━━━━━━━━━━━━<br/>Name: harbor-s3-user<br/>Policy: S3FullAccess<br/>(Overprivileged)"]
        
        S3Bucket["🪣 S3 Bucket<br/>━━━━━━━━━━━━━━<br/>Name: harbor-registry-storage<br/>Encryption: None or SSE-S3<br/>Policy: Permissive"]
    end
    
    K8sSecret -->|"Mounted as<br/>Environment Variables"| HarborPod
    HarborPod -->|"Static Credentials<br/>(Never Rotated)"| IAMUser
    IAMUser -->|"S3 API Calls<br/>(All actions as IAM user)"| S3Bucket
    
    style K8sSecret fill:#ff6b6b,stroke:#c92a2a,stroke-width:3px,color:#fff
    style HarborPod fill:#ff8787,stroke:#c92a2a,stroke-width:2px,color:#fff
    style IAMUser fill:#ffa94d,stroke:#e67700,stroke-width:2px,color:#fff
    style S3Bucket fill:#ffd43b,stroke:#fab005,stroke-width:2px,color:#000
```

### Detailed Component Flow

```mermaid
sequenceDiagram
    participant Admin as 👨‍💻 Administrator
    participant K8s as Kubernetes API
    participant Secret as Kubernetes Secret
    participant Pod as Harbor Pod
    participant IAM as IAM User
    participant S3 as S3 Bucket
    
    Admin->>IAM: 1. Create IAM User<br/>(harbor-s3-user)
    Admin->>IAM: 2. Generate Access Keys<br/>(AKIAIOSFODNN7EXAMPLE)
    Admin->>K8s: 3. Create Secret with<br/>base64(credentials)
    K8s->>Secret: 4. Store credentials<br/>(base64 is NOT encryption!)
    Admin->>K8s: 5. Deploy Harbor Pod<br/>with secret reference
    K8s->>Pod: 6. Mount secret as<br/>environment variables
    Pod->>S3: 7. S3 API calls using<br/>static credentials
    S3-->>Pod: 8. Response
    
    Note over Secret,Pod: ⚠️ Anyone with kubectl access<br/>can extract credentials!
    Note over Pod,S3: ⚠️ Credentials never rotate<br/>Valid indefinitely!
    Note over IAM,S3: ⚠️ All actions appear as<br/>single IAM user!
```

### Security Risks Visualization

```mermaid
mindmap
  root((Insecure<br/>Architecture<br/>Risks))
    Credential Theft
      Base64 is not encryption
      kubectl get secret reveals all
      Credentials in pod env vars
      Easy to extract and misuse
    No Rotation
      Static credentials
      Valid indefinitely
      Manual rotation required
      Rarely done in practice
    Overprivileged
      S3FullAccess common
      Broad permissions
      Violates least privilege
      Lateral movement risk
    Poor Audit Trail
      All actions as IAM user
      Cannot trace to specific pod
      No namespace attribution
      Compliance challenges
    Credential Sprawl
      Copied to multiple places
      Shared across teams
      Version control exposure
      Hard to revoke
```

---

## Secure Architecture (IRSA)

### High-Level Architecture Diagram

```mermaid
graph TB
    subgraph "AWS Account"
        subgraph "Amazon EKS Cluster"
            subgraph "harbor namespace"
                ServiceAccount["🎫 Kubernetes Service Account<br/>━━━━━━━━━━━━━━<br/>Name: harbor-registry<br/>Annotation:<br/>eks.amazonaws.com/role-arn:<br/>arn:aws:iam::ACCOUNT:role/HarborS3Role"]
                HarborPod["🐳 Harbor Registry Pod<br/>━━━━━━━━━━━━━━<br/>serviceAccountName: harbor-registry<br/>Projected Volume:<br/>/var/run/secrets/eks.amazonaws.com/<br/>serviceaccount/token<br/>(JWT, auto-rotated)"]
            end
            OIDCProvider["🔐 OIDC Provider<br/>━━━━━━━━━━━━━━<br/>Issues JWT tokens bound to:<br/>• Namespace: harbor<br/>• ServiceAccount: harbor-registry<br/>• Expiry: 86400s"]
        end
        
        IAMOIDCProvider["🌐 IAM OIDC Provider<br/>━━━━━━━━━━━━━━<br/>URL: oidc.eks.region.amazonaws.com<br/>/id/CLUSTER_ID<br/>Validates JWT tokens"]
        
        IAMRole["🛡️ IAM Role: HarborS3Role<br/>━━━━━━━━━━━━━━<br/>Trust Policy: Specific SA only<br/>Permissions: Least privilege<br/>• s3:PutObject<br/>• s3:GetObject<br/>• s3:DeleteObject<br/>• s3:ListBucket<br/>• kms:Decrypt<br/>• kms:GenerateDataKey"]
        
        S3Bucket["🪣 S3 Bucket<br/>━━━━━━━━━━━━━━<br/>Name: harbor-registry-storage<br/>Encryption: SSE-KMS (CMK)<br/>Versioning: Enabled<br/>Public Access: Blocked"]
        
        KMSKey["🔑 KMS Customer Managed Key<br/>━━━━━━━━━━━━━━<br/>Alias: alias/harbor-s3-encryption<br/>Key Policy: Restricts to HarborS3Role<br/>Rotation: Enabled"]
    end
    
    ServiceAccount -->|"Bound to"| HarborPod
    HarborPod -->|"JWT Token<br/>(Temporary)"| OIDCProvider
    OIDCProvider -->|"Token Validation"| IAMOIDCProvider
    IAMOIDCProvider -->|"AssumeRoleWithWebIdentity"| IAMRole
    IAMRole -->|"Temporary Credentials<br/>(Auto-rotated)"| S3Bucket
    S3Bucket -->|"Encryption/Decryption"| KMSKey
    IAMRole -.->|"KMS Permissions"| KMSKey
    
    style ServiceAccount fill:#51cf66,stroke:#2f9e44,stroke-width:2px,color:#000
    style HarborPod fill:#69db7c,stroke:#2f9e44,stroke-width:2px,color:#000
    style OIDCProvider fill:#4dabf7,stroke:#1971c2,stroke-width:2px,color:#fff
    style IAMOIDCProvider fill:#339af0,stroke:#1971c2,stroke-width:2px,color:#fff
    style IAMRole fill:#748ffc,stroke:#5f3dc4,stroke-width:2px,color:#fff
    style S3Bucket fill:#ffd43b,stroke:#fab005,stroke-width:2px,color:#000
    style KMSKey fill:#ffa94d,stroke:#e67700,stroke-width:2px,color:#000
```

### Detailed IRSA Authentication Flow

```mermaid
sequenceDiagram
    participant Admin as 👨‍💻 Administrator
    participant K8s as Kubernetes API
    participant SA as Service Account
    participant Pod as Harbor Pod
    participant OIDC as EKS OIDC Provider
    participant IAM as IAM OIDC Provider
    participant Role as IAM Role
    participant STS as AWS STS
    participant S3 as S3 Bucket
    participant KMS as KMS Key
    
    Admin->>K8s: 1. Create Service Account<br/>with role-arn annotation
    Admin->>IAM: 2. Create IAM OIDC Provider<br/>(EKS cluster issuer)
    Admin->>Role: 3. Create IAM Role with<br/>trust policy (specific SA)
    Admin->>K8s: 4. Deploy Harbor Pod<br/>with serviceAccountName
    
    K8s->>Pod: 5. Inject projected SA token<br/>(JWT, 24h expiry)
    Pod->>OIDC: 6. Request JWT token
    OIDC-->>Pod: 7. Issue JWT (bound to<br/>namespace + SA)
    
    Pod->>IAM: 8. Present JWT token
    IAM->>IAM: 9. Validate JWT signature<br/>and claims
    IAM->>Role: 10. Check trust policy<br/>(namespace + SA match)
    Role->>STS: 11. AssumeRoleWithWebIdentity
    STS-->>Pod: 12. Temporary credentials<br/>(AccessKeyId, SecretAccessKey,<br/>SessionToken, Expiration)
    
    Pod->>S3: 13. S3 API call with<br/>temporary credentials
    S3->>KMS: 14. Request encryption key
    KMS->>Role: 15. Verify IAM role has<br/>kms:GenerateDataKey
    KMS-->>S3: 16. Data encryption key
    S3-->>Pod: 17. Response
    
    Note over Pod,STS: ✅ Credentials auto-rotate<br/>before expiration
    Note over Role,S3: ✅ Least privilege IAM policy
    Note over S3,KMS: ✅ Encryption at rest with CMK
```

### Security Benefits Visualization

```mermaid
mindmap
  root((Secure<br/>IRSA<br/>Architecture))
    No Static Credentials
      JWT tokens only
      Projected volume
      Never stored persistently
      AWS SDK auto-discovers
    Automatic Rotation
      24-hour token expiry
      Auto-refresh before expiration
      No manual intervention
      Continuous security
    Least Privilege
      Specific S3 bucket only
      Limited actions
      KMS key restrictions
      Namespace + SA binding
    Excellent Audit Trail
      CloudTrail shows pod identity
      Namespace attribution
      Service account tracking
      Compliance ready
    Defense in Depth
      OIDC authentication
      IAM authorization
      KMS encryption
      S3 bucket policies
      Network policies
```

---

## Component Descriptions

### Insecure Architecture Components

#### 1. Kubernetes Secret (Base64 Encoded)
- **Purpose**: Stores IAM user access keys
- **Security Issue**: Base64 encoding is NOT encryption - easily decoded
- **Risk**: Anyone with `kubectl get secret` access can extract credentials
- **Example**:
  ```yaml
  apiVersion: v1
  kind: Secret
  metadata:
    name: harbor-s3-credentials
    namespace: harbor
  type: Opaque
  data:
    AWS_ACCESS_KEY_ID: <base64-encoded-access-key-id>
    AWS_SECRET_ACCESS_KEY: <base64-encoded-secret-access-key>
  ```

#### 2. Harbor Pod (with Static Credentials)
- **Purpose**: Runs Harbor container registry
- **Configuration**: Credentials mounted as environment variables from secret
- **Security Issue**: Credentials visible in pod spec and environment
- **Risk**: Credentials can be extracted via `kubectl exec` or pod inspection

#### 3. IAM User
- **Purpose**: Provides AWS credentials for S3 access
- **Typical Policy**: Often overprivileged (S3FullAccess or similar)
- **Security Issue**: Long-lived credentials, no automatic rotation
- **Risk**: If compromised, valid indefinitely until manually rotated

#### 4. S3 Bucket (Unencrypted or Default SSE)
- **Purpose**: Backend storage for Harbor container images
- **Security Issue**: Often lacks encryption or uses default SSE-S3
- **Risk**: Data at rest not protected with customer-managed keys

### Secure Architecture Components

#### 1. Kubernetes Service Account
- **Purpose**: Provides Kubernetes identity for Harbor pods
- **Key Feature**: Annotated with IAM role ARN
- **Security Benefit**: Binds AWS permissions to Kubernetes identity
- **Example**:
  ```yaml
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: harbor-registry
    namespace: harbor
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/HarborS3Role
  ```

#### 2. Harbor Pod (with IRSA)
- **Purpose**: Runs Harbor container registry
- **Configuration**: References service account, no static credentials
- **Key Feature**: Projected service account token auto-mounted
- **Security Benefit**: AWS SDK automatically discovers and uses temporary credentials

#### 3. EKS OIDC Provider
- **Purpose**: Issues JWT tokens for service accounts
- **Key Feature**: Tokens bound to specific namespace and service account
- **Token Expiry**: 86400 seconds (24 hours), auto-rotated
- **Security Benefit**: Short-lived, scoped credentials

#### 4. IAM OIDC Provider
- **Purpose**: Enables federation between Kubernetes and AWS IAM
- **URL Format**: `https://oidc.eks.{region}.amazonaws.com/id/{CLUSTER_ID}`
- **Key Feature**: Validates JWT tokens from EKS
- **Security Benefit**: Trusted identity provider for AssumeRoleWithWebIdentity

#### 5. IAM Role (HarborS3Role)
- **Purpose**: Provides temporary AWS credentials to Harbor pods
- **Trust Policy**: Restricts assumption to specific service account in specific namespace
- **Permissions Policy**: Least-privilege S3 and KMS access
- **Security Benefit**: Fine-grained access control with automatic credential rotation

#### 6. S3 Bucket (with SSE-KMS)
- **Purpose**: Backend storage for Harbor container images
- **Encryption**: SSE-KMS with customer-managed key
- **Additional Security**: Versioning enabled, public access blocked
- **Bucket Policy**: Enforces encryption and TLS-only access

#### 7. KMS Customer Managed Key (CMK)
- **Purpose**: Encryption key for S3 bucket
- **Key Policy**: Restricts usage to HarborS3Role and S3 service
- **Key Features**: Automatic rotation enabled, audit logging
- **Security Benefit**: Customer control over encryption keys

---

## Security Comparison

### Side-by-Side Comparison Table

| Security Dimension | Insecure (IAM User Tokens) | Secure (IRSA) |
|-------------------|---------------------------|---------------|
| **Credential Storage** | Static keys in Kubernetes secrets (base64) | No stored credentials, JWT tokens only |
| **Credential Lifetime** | Indefinite (until manually rotated) | 24 hours (auto-rotated) |
| **Rotation Mechanism** | Manual (rarely done) | Automatic (transparent) |
| **Privilege Level** | Often overprivileged (S3FullAccess) | Least privilege (specific bucket + actions) |
| **Access Control Granularity** | Any pod can use credentials | Bound to specific namespace + service account |
| **Credential Theft Risk** | High (base64 easily decoded) | Low (short-lived, scoped tokens) |
| **Audit Trail Quality** | Poor (all actions as IAM user) | Excellent (pod-level identity in CloudTrail) |
| **Compliance** | Difficult (static credentials) | Easy (automatic rotation, audit trail) |
| **Encryption at Rest** | Often none or default SSE-S3 | SSE-KMS with customer-managed key |
| **Operational Complexity** | Low (but insecure) | Medium (but secure) |
| **Blast Radius** | High (credentials work anywhere) | Low (scoped to specific workload) |
| **Revocation** | Manual (delete/rotate keys) | Automatic (token expiry) |

### STRIDE Threat Model Comparison

#### Insecure Approach Threats

```mermaid
graph LR
    subgraph "STRIDE Threats - Insecure Approach"
        S[Spoofing<br/>━━━━━━━━<br/>Risk: HIGH<br/>Stolen credentials<br/>work anywhere]
        T[Tampering<br/>━━━━━━━━<br/>Risk: HIGH<br/>Overprivileged<br/>access]
        R[Repudiation<br/>━━━━━━━━<br/>Risk: MEDIUM<br/>Poor audit<br/>trail]
        I[Information<br/>Disclosure<br/>━━━━━━━━<br/>Risk: HIGH<br/>Easy credential<br/>extraction]
        D[Denial of<br/>Service<br/>━━━━━━━━<br/>Risk: MEDIUM<br/>S3FullAccess<br/>allows deletion]
        E[Elevation of<br/>Privilege<br/>━━━━━━━━<br/>Risk: HIGH<br/>Lateral<br/>movement]
    end
    
    style S fill:#ff6b6b,stroke:#c92a2a,stroke-width:2px,color:#fff
    style T fill:#ff6b6b,stroke:#c92a2a,stroke-width:2px,color:#fff
    style R fill:#ffa94d,stroke:#e67700,stroke-width:2px,color:#fff
    style I fill:#ff6b6b,stroke:#c92a2a,stroke-width:2px,color:#fff
    style D fill:#ffa94d,stroke:#e67700,stroke-width:2px,color:#fff
    style E fill:#ff6b6b,stroke:#c92a2a,stroke-width:2px,color:#fff
```

#### Secure Approach Mitigations

```mermaid
graph LR
    subgraph "STRIDE Mitigations - Secure IRSA Approach"
        S[Spoofing<br/>━━━━━━━━<br/>Risk: LOW<br/>JWT tokens<br/>expire in 24h]
        T[Tampering<br/>━━━━━━━━<br/>Risk: LOW<br/>Least privilege<br/>policies]
        R[Repudiation<br/>━━━━━━━━<br/>Risk: VERY LOW<br/>Full CloudTrail<br/>attribution]
        I[Information<br/>Disclosure<br/>━━━━━━━━<br/>Risk: LOW<br/>Short-lived<br/>tokens]
        D[Denial of<br/>Service<br/>━━━━━━━━<br/>Risk: VERY LOW<br/>Restricted<br/>permissions]
        E[Elevation of<br/>Privilege<br/>━━━━━━━━<br/>Risk: VERY LOW<br/>Scoped to S3<br/>+ KMS only]
    end
    
    style S fill:#51cf66,stroke:#2f9e44,stroke-width:2px,color:#000
    style T fill:#51cf66,stroke:#2f9e44,stroke-width:2px,color:#000
    style R fill:#51cf66,stroke:#2f9e44,stroke-width:2px,color:#000
    style I fill:#51cf66,stroke:#2f9e44,stroke-width:2px,color:#000
    style D fill:#51cf66,stroke:#2f9e44,stroke-width:2px,color:#000
    style E fill:#51cf66,stroke:#2f9e44,stroke-width:2px,color:#000
```

---

## Data Flow Analysis

### Insecure Data Flow

```mermaid
flowchart TD
    Start([Administrator Creates<br/>IAM User]) --> CreateKeys[Generate Access Keys<br/>AKIAIOSFODNN7EXAMPLE]
    CreateKeys --> Base64[Base64 Encode Credentials<br/>echo -n 'AKIAIO...' | base64]
    Base64 --> CreateSecret[Create Kubernetes Secret<br/>kubectl create secret generic]
    CreateSecret --> DeployPod[Deploy Harbor Pod<br/>with secret reference]
    DeployPod --> MountEnv[Mount Secret as<br/>Environment Variables]
    MountEnv --> S3Call[Harbor Makes S3 API Call<br/>using static credentials]
    S3Call --> IAMAuth[IAM Authenticates<br/>as IAM User]
    IAMAuth --> S3Access[S3 Grants Access<br/>based on IAM user policy]
    S3Access --> StoreData[Store Container Images<br/>in S3 bucket]
    
    Extract[Attacker Extracts Credentials<br/>kubectl get secret -o yaml] -.->|"Base64 decode"| Stolen[Stolen Credentials<br/>Valid Indefinitely]
    Stolen -.->|"Use anywhere"| Misuse[Unauthorized S3 Access<br/>from anywhere]
    
    style Start fill:#e3f2fd,stroke:#1976d2,stroke-width:2px
    style Extract fill:#ff6b6b,stroke:#c92a2a,stroke-width:3px,color:#fff
    style Stolen fill:#ff8787,stroke:#c92a2a,stroke-width:2px,color:#fff
    style Misuse fill:#ffa94d,stroke:#e67700,stroke-width:2px,color:#fff
```

### Secure Data Flow (IRSA)

```mermaid
flowchart TD
    Start([Administrator Creates<br/>Service Account]) --> Annotate[Annotate with IAM Role ARN<br/>eks.amazonaws.com/role-arn]
    Annotate --> CreateRole[Create IAM Role<br/>with Trust Policy]
    CreateRole --> TrustPolicy[Trust Policy Restricts to<br/>Specific Namespace + SA]
    TrustPolicy --> DeployPod[Deploy Harbor Pod<br/>with serviceAccountName]
    DeployPod --> ProjectToken[Kubernetes Projects<br/>JWT Token into Pod]
    ProjectToken --> AWSSDKDiscover[AWS SDK Discovers Token<br/>at /var/run/secrets/...]
    AWSSDKDiscover --> AssumeRole[SDK Calls AssumeRoleWithWebIdentity<br/>with JWT token]
    AssumeRole --> ValidateJWT[IAM OIDC Provider<br/>Validates JWT]
    ValidateJWT --> CheckTrust[Check Trust Policy<br/>Namespace + SA Match]
    CheckTrust --> IssueCreds[STS Issues Temporary Credentials<br/>Valid for 1 hour]
    IssueCreds --> S3Call[Harbor Makes S3 API Call<br/>with temporary credentials]
    S3Call --> S3Access[S3 Grants Access<br/>based on IAM role policy]
    S3Access --> KMSDecrypt[KMS Decrypts Data<br/>using CMK]
    KMSDecrypt --> StoreData[Store Encrypted Images<br/>in S3 bucket]
    
    AutoRotate[Token Auto-Rotates<br/>before 24h expiry] -.->|"Seamless"| ProjectToken
    
    style Start fill:#e3f2fd,stroke:#1976d2,stroke-width:2px
    style ValidateJWT fill:#51cf66,stroke:#2f9e44,stroke-width:2px
    style CheckTrust fill:#51cf66,stroke:#2f9e44,stroke-width:2px
    style IssueCreds fill:#69db7c,stroke:#2f9e44,stroke-width:2px
    style AutoRotate fill:#4dabf7,stroke:#1971c2,stroke-width:2px,color:#fff
    style KMSDecrypt fill:#ffa94d,stroke:#e67700,stroke-width:2px
```

---

## Architecture Decision Records

### ADR-001: Why IRSA Over IAM User Tokens

**Status**: Accepted

**Context**: Harbor requires S3 access for backend storage. Two approaches exist:
1. IAM user tokens (static credentials)
2. IRSA (temporary, auto-rotated credentials)

**Decision**: Use IRSA for all production deployments

**Consequences**:
- ✅ Eliminates static credential storage
- ✅ Automatic credential rotation
- ✅ Least privilege access control
- ✅ Better audit trail
- ⚠️ Slightly more complex initial setup
- ⚠️ Requires EKS 1.14+ with OIDC enabled

### ADR-002: Why KMS CMK Over Default SSE-S3

**Status**: Accepted

**Context**: S3 bucket encryption options:
1. No encryption
2. SSE-S3 (AWS-managed keys)
3. SSE-KMS with CMK (customer-managed keys)

**Decision**: Use SSE-KMS with customer-managed keys

**Consequences**:
- ✅ Customer control over encryption keys
- ✅ Key rotation policies
- ✅ Detailed audit logging
- ✅ Compliance requirements met
- ⚠️ Additional cost (~$1/month per key)
- ⚠️ Requires KMS permissions in IAM policy

### ADR-003: Why Namespace Isolation

**Status**: Accepted

**Context**: Service account scope options:
1. Cluster-wide service account
2. Namespace-specific service account

**Decision**: Use namespace-specific service accounts with trust policy restrictions

**Consequences**:
- ✅ Blast radius limited to single namespace
- ✅ Multi-tenancy support
- ✅ Easier access control management
- ✅ Better security posture
- ⚠️ Requires separate IAM role per namespace (if needed)

---

## Conclusion

The architecture diagrams clearly demonstrate the security advantages of IRSA over traditional IAM user tokens:

1. **No Static Credentials**: IRSA eliminates the need to store long-lived credentials
2. **Automatic Rotation**: Credentials refresh automatically without manual intervention
3. **Least Privilege**: Fine-grained IAM policies scoped to specific workloads
4. **Strong Isolation**: Access bound to specific namespace and service account
5. **Excellent Audit Trail**: CloudTrail shows pod-level identity for compliance
6. **Defense in Depth**: Multiple security layers (OIDC, IAM, KMS, S3 policies)

The insecure approach should **never be used in production** and is included in this workshop solely for educational purposes to demonstrate the security risks and help practitioners understand what to avoid.

---

**Next Steps**: 
- Review [Insecure Deployment Documentation](02-insecure-deployment.md)
- Proceed to [IRSA Implementation Guide](04-irsa-fundamentals.md)
- Complete [Validation Tests](../validation-tests/README.md)
