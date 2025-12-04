# Kubernetes Namespace Isolation for Harbor IRSA

## Overview

This guide demonstrates how to implement defense-in-depth security for Harbor deployments using Kubernetes namespace isolation, network policies, and RBAC (Role-Based Access Control). When combined with IRSA, these controls create multiple security layers that prevent unauthorized access and limit the blast radius of potential security incidents.

## Table of Contents

1. [Understanding Namespace Isolation](#understanding-namespace-isolation)
2. [Prerequisites](#prerequisites)
3. [Step 1: Create Isolated Namespace](#step-1-create-isolated-namespace)
4. [Step 2: Configure RBAC](#step-2-configure-rbac)
5. [Step 3: Implement Network Policies](#step-3-implement-network-policies)
6. [Step 4: Resource Quotas and Limits](#step-4-resource-quotas-and-limits)
7. [Step 5: Pod Security Standards](#step-5-pod-security-standards)
8. [Verification and Testing](#verification-and-testing)
9. [Best Practices](#best-practices)
10. [Troubleshooting](#troubleshooting)

## Understanding Namespace Isolation

### Why Namespace Isolation Matters

Kubernetes namespaces provide logical isolation between workloads, but by default they don't enforce security boundaries. Without proper configuration:

❌ **Pods in any namespace can communicate with each other**  
❌ **Users with cluster-wide permissions can access all namespaces**  
❌ **Service accounts can potentially access resources across namespaces**  
❌ **No resource limits prevent one namespace from consuming all cluster resources**  

With proper namespace isolation:

✅ **Network traffic is restricted to authorized paths only**  
✅ **RBAC limits who can view and modify resources**  
✅ **Service accounts are scoped to their namespace**  
✅ **Resource quotas prevent resource exhaustion**  
✅ **Pod security standards enforce security baselines**  

### Defense in Depth Layers

When combined with IRSA, namespace isolation provides multiple security layers:

```
┌─────────────────────────────────────────────────────────────┐
│                    Security Layer 1                          │
│              Namespace Logical Isolation                     │
│  - Separate namespace for Harbor workloads                   │
│  - Prevents accidental resource conflicts                    │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                    Security Layer 2                          │
│                   RBAC Authorization                         │
│  - Limits who can view/modify Harbor resources               │
│  - Service accounts scoped to namespace                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                    Security Layer 3                          │
│                  Network Policies                            │
│  - Restricts network traffic to/from Harbor pods             │
│  - Denies unauthorized ingress/egress                        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                    Security Layer 4                          │
│                  IRSA IAM Controls                           │
│  - AWS permissions bound to specific service account         │
│  - Trust policy restricts to namespace + service account     │
└─────────────────────────────────────────────────────────────┘

```

### How This Protects Harbor

With all layers in place:

1. **Attacker gains access to a pod in another namespace**
   - ❌ Cannot communicate with Harbor pods (network policy blocks)
   - ❌ Cannot view Harbor secrets or configs (RBAC blocks)
   - ❌ Cannot assume Harbor's IAM role (IRSA trust policy blocks)

2. **Attacker compromises a Harbor pod**
   - ✅ Damage limited to Harbor namespace (namespace isolation)
   - ✅ Cannot access other namespaces (RBAC blocks)
   - ✅ Can only access authorized S3 bucket (IAM policy limits)
   - ✅ Network access limited to required services (network policy)

3. **Attacker gains cluster-admin access**
   - ⚠️ Can access Harbor namespace (defense in depth failed)
   - ✅ Still cannot use Harbor's AWS credentials directly (IRSA bound to pod)
   - ✅ CloudTrail logs show all actions (audit trail)

## Prerequisites

Before starting, ensure you have:

- **EKS cluster** with OIDC provider configured
- **kubectl** configured to access your cluster
- **Cluster admin permissions** to create namespaces and RBAC resources
- **CNI plugin** that supports network policies (AWS VPC CNI, Calico, Cilium)
- **Harbor not yet deployed** (or prepared to redeploy)

### Verify Network Policy Support

```bash
# Check if your CNI supports network policies
kubectl get pods -n kube-system | grep -E 'aws-node|calico|cilium'

# For AWS VPC CNI, verify network policy support is enabled
kubectl describe daemonset aws-node -n kube-system | grep ENABLE_NETWORK_POLICY
```

If network policies are not supported, you'll need to install a compatible CNI plugin.

### Environment Variables

```bash
export CLUSTER_NAME="harbor-irsa-workshop"
export AWS_REGION="us-east-1"
export HARBOR_NAMESPACE="harbor"
export HARBOR_SERVICE_ACCOUNT="harbor-registry"
```

## Step 1: Create Isolated Namespace

### 1.1 Create Namespace with Labels

Create a namespace with appropriate labels for organization and policy enforcement:

```bash
cat > harbor-namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: harbor
  labels:
    name: harbor
    environment: production
    app: container-registry
    security-tier: high
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
EOF

kubectl apply -f harbor-namespace.yaml
```

### 1.2 Understanding Namespace Labels

Let's break down each label:

- **`name: harbor`**: Identifies the namespace for network policies
- **`environment: production`**: Indicates this is a production workload
- **`app: container-registry`**: Describes the application type
- **`security-tier: high`**: Marks this as a high-security namespace
- **`pod-security.kubernetes.io/enforce: restricted`**: Enforces restricted pod security standard
- **`pod-security.kubernetes.io/audit: restricted`**: Audits violations of restricted standard
- **`pod-security.kubernetes.io/warn: restricted`**: Warns about violations

### 1.3 Verify Namespace Creation

```bash
# Verify namespace exists
kubectl get namespace harbor

# View namespace labels
kubectl get namespace harbor --show-labels

# View namespace details
kubectl describe namespace harbor
```

**Expected output:**
```
NAME     STATUS   AGE
harbor   Active   10s
```

## Step 2: Configure RBAC

RBAC controls who can access resources in the Harbor namespace. We'll create roles that follow the principle of least privilege.

### 2.1 Create Harbor Admin Role

This role allows full management of Harbor resources within the namespace:

```bash
cat > harbor-admin-role.yaml << 'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: harbor-admin
  namespace: harbor
rules:
  # Full access to Harbor deployments and pods
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "replicasets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  
  # Full access to pods for debugging
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec"]
    verbs: ["get", "list", "watch", "create", "delete"]
  
  # Full access to services and networking
  - apiGroups: [""]
    resources: ["services", "endpoints"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  
  # Full access to configuration
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  
  # Full access to service accounts (for IRSA)
  - apiGroups: [""]
    resources: ["serviceaccounts"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  
  # Access to persistent volumes
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF

kubectl apply -f harbor-admin-role.yaml
```


### 2.2 Create Harbor Read-Only Role

This role allows viewing Harbor resources without modification:

```bash
cat > harbor-readonly-role.yaml << 'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: harbor-readonly
  namespace: harbor
rules:
  # Read-only access to workloads
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "replicasets"]
    verbs: ["get", "list", "watch"]
  
  # Read-only access to pods (no exec)
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
  
  # Read-only access to services
  - apiGroups: [""]
    resources: ["services", "endpoints"]
    verbs: ["get", "list", "watch"]
  
  # Read-only access to configuration (excluding secrets)
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
  
  # Read-only access to networking
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["get", "list", "watch"]
EOF

kubectl apply -f harbor-readonly-role.yaml
```

### 2.3 Create RoleBindings

Bind roles to users or groups:

```bash
# Example: Bind harbor-admin role to a specific user
cat > harbor-admin-rolebinding.yaml << 'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: harbor-admin-binding
  namespace: harbor
subjects:
  # Replace with your actual IAM user or role
  - kind: User
    name: "arn:aws:iam::123456789012:user/harbor-admin"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: harbor-admin
  apiGroup: rbac.authorization.k8s.io
EOF

# Apply the binding (update the user ARN first!)
# kubectl apply -f harbor-admin-rolebinding.yaml
```

### 2.4 Restrict Service Account Permissions

Ensure Harbor's service account has minimal permissions:

```bash
cat > harbor-serviceaccount-role.yaml << 'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: harbor-serviceaccount-role
  namespace: harbor
rules:
  # Harbor only needs to read its own configmaps
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
  
  # Harbor may need to read secrets for internal configuration
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: harbor-serviceaccount-binding
  namespace: harbor
subjects:
  - kind: ServiceAccount
    name: harbor-registry
    namespace: harbor
roleRef:
  kind: Role
  name: harbor-serviceaccount-role
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f harbor-serviceaccount-role.yaml
```

### 2.5 Verify RBAC Configuration

```bash
# List roles in harbor namespace
kubectl get roles -n harbor

# List role bindings
kubectl get rolebindings -n harbor

# View role details
kubectl describe role harbor-admin -n harbor

# Test permissions (as a user with the role)
kubectl auth can-i get pods -n harbor --as=system:serviceaccount:harbor:harbor-registry
kubectl auth can-i delete pods -n harbor --as=system:serviceaccount:harbor:harbor-registry
```

## Step 3: Implement Network Policies

Network policies control traffic flow to and from Harbor pods. By default, we'll deny all traffic and explicitly allow only required connections.

### 3.1 Default Deny All Traffic

Start with a default deny policy:

```bash
cat > harbor-default-deny.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: harbor
spec:
  podSelector: {}  # Applies to all pods in namespace
  policyTypes:
    - Ingress
    - Egress
EOF

kubectl apply -f harbor-default-deny.yaml
```

**Important**: This will block all traffic until we add allow rules!

### 3.2 Allow Ingress to Harbor UI/API

Allow external traffic to Harbor's web interface:

```bash
cat > harbor-allow-ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: harbor-allow-ingress
  namespace: harbor
spec:
  podSelector:
    matchLabels:
      app: harbor
      component: core
  policyTypes:
    - Ingress
  ingress:
    # Allow traffic from ingress controller
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: ingress-nginx
      ports:
        - protocol: TCP
          port: 8080
    
    # Allow traffic from within the cluster (for docker pull/push)
    - from:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 8080
EOF

kubectl apply -f harbor-allow-ingress.yaml
```

### 3.3 Allow Egress to AWS Services

Allow Harbor to communicate with AWS S3 and KMS:

```bash
cat > harbor-allow-aws-egress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: harbor-allow-aws-egress
  namespace: harbor
spec:
  podSelector:
    matchLabels:
      app: harbor
  policyTypes:
    - Egress
  egress:
    # Allow DNS resolution
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
        - podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
    
    # Allow HTTPS to AWS services (S3, KMS, STS)
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 443
    
    # Allow HTTP for AWS metadata service (IMDS)
    - to:
        - ipBlock:
            cidr: 169.254.169.254/32
      ports:
        - protocol: TCP
          port: 80
EOF

kubectl apply -f harbor-allow-aws-egress.yaml
```


### 3.4 Allow Internal Harbor Communication

Harbor components need to communicate with each other:

```bash
cat > harbor-allow-internal.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: harbor-allow-internal
  namespace: harbor
spec:
  podSelector:
    matchLabels:
      app: harbor
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow traffic from other Harbor components
    - from:
        - podSelector:
            matchLabels:
              app: harbor
  egress:
    # Allow traffic to other Harbor components
    - to:
        - podSelector:
            matchLabels:
              app: harbor
EOF

kubectl apply -f harbor-allow-internal.yaml
```

### 3.5 Allow Database Access (if using external DB)

If Harbor uses an external database:

```bash
cat > harbor-allow-database.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: harbor-allow-database
  namespace: harbor
spec:
  podSelector:
    matchLabels:
      app: harbor
  policyTypes:
    - Egress
  egress:
    # Allow PostgreSQL access (adjust CIDR for your RDS instance)
    - to:
        - ipBlock:
            cidr: 10.0.0.0/16  # Replace with your VPC CIDR
      ports:
        - protocol: TCP
          port: 5432
EOF

# Only apply if using external database
# kubectl apply -f harbor-allow-database.yaml
```

### 3.6 Verify Network Policies

```bash
# List network policies
kubectl get networkpolicies -n harbor

# Describe a specific policy
kubectl describe networkpolicy harbor-allow-ingress -n harbor

# View all policies in detail
kubectl get networkpolicies -n harbor -o yaml
```

### 3.7 Test Network Policies

Test that policies are working correctly:

```bash
# Create a test pod in a different namespace
kubectl run test-pod --image=nicolaka/netshoot -n default -- sleep 3600

# Try to access Harbor from the test pod (should fail if policies are correct)
kubectl exec -it test-pod -n default -- curl -v http://harbor-core.harbor.svc.cluster.local:8080

# Expected: Connection timeout or refused (blocked by network policy)

# Create a test pod in the harbor namespace
kubectl run test-pod-harbor --image=nicolaka/netshoot -n harbor -- sleep 3600

# Try to access Harbor from within the namespace (should succeed)
kubectl exec -it test-pod-harbor -n harbor -- curl -v http://harbor-core.harbor.svc.cluster.local:8080

# Expected: HTTP response (allowed by network policy)

# Cleanup
kubectl delete pod test-pod -n default
kubectl delete pod test-pod-harbor -n harbor
```

## Step 4: Resource Quotas and Limits

Resource quotas prevent one namespace from consuming all cluster resources.

### 4.1 Create Resource Quota

```bash
cat > harbor-resource-quota.yaml << 'EOF'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: harbor-quota
  namespace: harbor
spec:
  hard:
    # Limit total CPU and memory
    requests.cpu: "8"
    requests.memory: 16Gi
    limits.cpu: "16"
    limits.memory: 32Gi
    
    # Limit number of resources
    pods: "20"
    services: "10"
    persistentvolumeclaims: "5"
    
    # Limit storage
    requests.storage: 100Gi
EOF

kubectl apply -f harbor-resource-quota.yaml
```

### 4.2 Create Limit Range

Limit ranges set default and maximum resource limits for pods:

```bash
cat > harbor-limit-range.yaml << 'EOF'
apiVersion: v1
kind: LimitRange
metadata:
  name: harbor-limits
  namespace: harbor
spec:
  limits:
    # Container limits
    - type: Container
      default:
        cpu: 500m
        memory: 512Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      max:
        cpu: 2
        memory: 4Gi
      min:
        cpu: 50m
        memory: 64Mi
    
    # Pod limits
    - type: Pod
      max:
        cpu: 4
        memory: 8Gi
    
    # PVC limits
    - type: PersistentVolumeClaim
      max:
        storage: 50Gi
      min:
        storage: 1Gi
EOF

kubectl apply -f harbor-limit-range.yaml
```

### 4.3 Verify Resource Quotas

```bash
# View resource quota
kubectl get resourcequota -n harbor

# View quota details
kubectl describe resourcequota harbor-quota -n harbor

# View limit range
kubectl get limitrange -n harbor

# View limit range details
kubectl describe limitrange harbor-limits -n harbor
```

## Step 5: Pod Security Standards

Pod Security Standards enforce security best practices at the pod level.

### 5.1 Understanding Pod Security Standards

Kubernetes defines three pod security standards:

1. **Privileged**: Unrestricted (not recommended)
2. **Baseline**: Minimally restrictive (prevents known privilege escalations)
3. **Restricted**: Heavily restricted (follows hardening best practices)

We'll use the **restricted** standard for Harbor.

### 5.2 Namespace Labels (Already Applied)

We already applied pod security labels when creating the namespace:

```yaml
pod-security.kubernetes.io/enforce: restricted
pod-security.kubernetes.io/audit: restricted
pod-security.kubernetes.io/warn: restricted
```

### 5.3 Verify Pod Security Standards

```bash
# View namespace labels
kubectl get namespace harbor -o yaml | grep pod-security

# Try to create a privileged pod (should fail)
kubectl run privileged-test --image=nginx --privileged=true -n harbor

# Expected error: pods "privileged-test" is forbidden: violates PodSecurity "restricted:latest"
```

### 5.4 Harbor Pod Security Context

Ensure Harbor pods comply with restricted standard:

```yaml
# Example security context for Harbor pods
securityContext:
  runAsNonRoot: true
  runAsUser: 10000
  fsGroup: 10000
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop:
      - ALL
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
```

This should be included in your Harbor Helm values or deployment manifests.

## Verification and Testing

### 6.1 Comprehensive Verification Checklist

Run through this checklist to verify all isolation controls:

```bash
# 1. Verify namespace exists with correct labels
kubectl get namespace harbor --show-labels

# 2. Verify RBAC roles exist
kubectl get roles -n harbor

# 3. Verify network policies exist
kubectl get networkpolicies -n harbor

# 4. Verify resource quotas exist
kubectl get resourcequota -n harbor

# 5. Verify limit ranges exist
kubectl get limitrange -n harbor

# 6. Verify pod security standards are enforced
kubectl get namespace harbor -o yaml | grep pod-security

# 7. Test RBAC permissions
kubectl auth can-i get pods -n harbor --as=system:serviceaccount:harbor:harbor-registry
kubectl auth can-i delete pods -n harbor --as=system:serviceaccount:harbor:harbor-registry

# 8. Test network policies (see section 3.7)

# 9. Verify Harbor pods are running
kubectl get pods -n harbor

# 10. Check Harbor pod security contexts
kubectl get pods -n harbor -o jsonpath='{.items[*].spec.securityContext}' | jq .
```


### 6.2 Security Validation Script

Create a comprehensive validation script:

```bash
cat > validate-namespace-isolation.sh << 'EOF'
#!/bin/bash

set -e

NAMESPACE="harbor"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Harbor Namespace Isolation Validation"
echo "=========================================="
echo ""

# Function to check and report
check_resource() {
    local resource=$1
    local name=$2
    local namespace=$3
    
    if kubectl get $resource $name -n $namespace &> /dev/null; then
        echo -e "${GREEN}✓${NC} $resource '$name' exists in namespace '$namespace'"
        return 0
    else
        echo -e "${RED}✗${NC} $resource '$name' NOT found in namespace '$namespace'"
        return 1
    fi
}

# Check namespace
echo "1. Checking Namespace..."
check_resource namespace $NAMESPACE ""

# Check namespace labels
echo ""
echo "2. Checking Namespace Labels..."
LABELS=$(kubectl get namespace $NAMESPACE -o jsonpath='{.metadata.labels}')
if echo "$LABELS" | grep -q "pod-security.kubernetes.io/enforce"; then
    echo -e "${GREEN}✓${NC} Pod Security Standards labels are set"
else
    echo -e "${RED}✗${NC} Pod Security Standards labels are missing"
fi

# Check RBAC
echo ""
echo "3. Checking RBAC Configuration..."
ROLE_COUNT=$(kubectl get roles -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
if [ "$ROLE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Found $ROLE_COUNT role(s) in namespace"
    kubectl get roles -n $NAMESPACE
else
    echo -e "${YELLOW}⚠${NC} No roles found in namespace"
fi

# Check network policies
echo ""
echo "4. Checking Network Policies..."
NP_COUNT=$(kubectl get networkpolicies -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
if [ "$NP_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Found $NP_COUNT network policy(ies)"
    kubectl get networkpolicies -n $NAMESPACE
else
    echo -e "${RED}✗${NC} No network policies found - namespace is not isolated!"
fi

# Check resource quotas
echo ""
echo "5. Checking Resource Quotas..."
if kubectl get resourcequota -n $NAMESPACE &> /dev/null; then
    echo -e "${GREEN}✓${NC} Resource quota exists"
    kubectl describe resourcequota -n $NAMESPACE | grep -A 10 "Resource"
else
    echo -e "${YELLOW}⚠${NC} No resource quota found"
fi

# Check limit ranges
echo ""
echo "6. Checking Limit Ranges..."
if kubectl get limitrange -n $NAMESPACE &> /dev/null; then
    echo -e "${GREEN}✓${NC} Limit range exists"
else
    echo -e "${YELLOW}⚠${NC} No limit range found"
fi

# Test RBAC permissions
echo ""
echo "7. Testing RBAC Permissions..."
SA="system:serviceaccount:$NAMESPACE:harbor-registry"

if kubectl auth can-i get pods -n $NAMESPACE --as=$SA &> /dev/null; then
    echo -e "${GREEN}✓${NC} Service account can get pods (expected)"
else
    echo -e "${YELLOW}⚠${NC} Service account cannot get pods"
fi

if kubectl auth can-i delete pods -n $NAMESPACE --as=$SA &> /dev/null; then
    echo -e "${YELLOW}⚠${NC} Service account can delete pods (may be overprivileged)"
else
    echo -e "${GREEN}✓${NC} Service account cannot delete pods (expected)"
fi

# Check for pods
echo ""
echo "8. Checking Harbor Pods..."
POD_COUNT=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
if [ "$POD_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Found $POD_COUNT pod(s) in namespace"
    kubectl get pods -n $NAMESPACE
else
    echo -e "${YELLOW}⚠${NC} No pods found in namespace"
fi

# Summary
echo ""
echo "=========================================="
echo "Validation Complete"
echo "=========================================="
echo ""
echo "Review the results above. All critical checks should show ✓"
echo "Yellow warnings (⚠) indicate optional configurations"
echo "Red errors (✗) indicate missing security controls"
EOF

chmod +x validate-namespace-isolation.sh
./validate-namespace-isolation.sh
```

## Best Practices

### Defense in Depth

Always implement multiple security layers:

✅ **Namespace isolation** - Logical separation  
✅ **RBAC** - Access control  
✅ **Network policies** - Traffic control  
✅ **Resource quotas** - Resource limits  
✅ **Pod security standards** - Pod-level security  
✅ **IRSA** - AWS credential management  

### Principle of Least Privilege

- **Service accounts**: Grant only necessary Kubernetes permissions
- **RBAC roles**: Create specific roles for different user types
- **Network policies**: Start with deny-all, explicitly allow required traffic
- **IAM policies**: Scope to specific resources (covered in IRSA setup)

### Regular Auditing

```bash
# Audit RBAC permissions
kubectl auth can-i --list -n harbor

# Audit network policies
kubectl get networkpolicies -n harbor -o yaml

# Audit resource usage
kubectl top pods -n harbor
kubectl describe resourcequota -n harbor

# Audit pod security
kubectl get pods -n harbor -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.securityContext}{"\n"}{end}'
```

### Monitoring and Alerting

Set up monitoring for:

- **Network policy violations**: Monitor denied connections
- **RBAC denials**: Track unauthorized access attempts
- **Resource quota exhaustion**: Alert when quotas are near limits
- **Pod security violations**: Monitor for non-compliant pods

### Documentation

Document your isolation strategy:

- **Network policy diagram**: Show allowed traffic flows
- **RBAC matrix**: Document who has what permissions
- **Runbooks**: Procedures for common operations
- **Incident response**: Steps for security incidents

## Troubleshooting

### Issue 1: Pods Cannot Communicate

**Symptom:**
```
Harbor pods cannot reach each other or external services
```

**Diagnosis:**
```bash
# Check network policies
kubectl get networkpolicies -n harbor

# Describe the policy
kubectl describe networkpolicy harbor-allow-internal -n harbor

# Test connectivity from a pod
kubectl exec -it <harbor-pod> -n harbor -- curl -v http://harbor-core:8080
```

**Solution:**
Ensure you have network policies that allow:
1. Internal Harbor communication
2. DNS resolution
3. Egress to AWS services

### Issue 2: RBAC Permission Denied

**Symptom:**
```
Error from server (Forbidden): pods is forbidden: User "..." cannot list resource "pods" in API group "" in the namespace "harbor"
```

**Diagnosis:**
```bash
# Check what permissions the user has
kubectl auth can-i --list -n harbor --as=<user>

# Check role bindings
kubectl get rolebindings -n harbor
```

**Solution:**
Create appropriate role binding for the user:
```bash
kubectl create rolebinding <name> \
  --role=harbor-readonly \
  --user=<user> \
  -n harbor
```

### Issue 3: Resource Quota Exceeded

**Symptom:**
```
Error from server (Forbidden): pods "harbor-core-xxx" is forbidden: exceeded quota: harbor-quota
```

**Diagnosis:**
```bash
# Check quota usage
kubectl describe resourcequota harbor-quota -n harbor
```

**Solution:**
Either increase the quota or reduce resource requests:
```bash
# Edit quota
kubectl edit resourcequota harbor-quota -n harbor

# Or reduce pod resource requests in Harbor deployment
```

### Issue 4: Pod Security Standard Violation

**Symptom:**
```
Error: pods "harbor-core-xxx" is forbidden: violates PodSecurity "restricted:latest"
```

**Diagnosis:**
```bash
# Check namespace pod security labels
kubectl get namespace harbor -o yaml | grep pod-security

# Check pod security context
kubectl get pod <pod-name> -n harbor -o yaml | grep -A 20 securityContext
```

**Solution:**
Update pod security context to comply with restricted standard:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10000
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop:
      - ALL
  allowPrivilegeEscalation: false
```

### Issue 5: Network Policy Not Working

**Symptom:**
```
Network policies exist but traffic is not being blocked
```

**Diagnosis:**
```bash
# Check if CNI supports network policies
kubectl get pods -n kube-system | grep -E 'aws-node|calico|cilium'

# For AWS VPC CNI
kubectl set env daemonset aws-node -n kube-system --list | grep ENABLE_NETWORK_POLICY
```

**Solution:**
Enable network policy support in your CNI:
```bash
# For AWS VPC CNI (requires EKS 1.25+)
kubectl set env daemonset aws-node -n kube-system ENABLE_NETWORK_POLICY=true
```

## Advanced Configurations

### Multi-Tenant Isolation

For multiple Harbor instances or tenants:

```bash
# Create separate namespaces
kubectl create namespace harbor-team-a
kubectl create namespace harbor-team-b

# Apply isolation to each
for ns in harbor-team-a harbor-team-b; do
  kubectl apply -f harbor-default-deny.yaml -n $ns
  kubectl apply -f harbor-resource-quota.yaml -n $ns
done
```

### Cross-Namespace Communication

If Harbor needs to communicate with services in other namespaces:

```bash
cat > harbor-allow-cross-namespace.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: harbor-allow-monitoring
  namespace: harbor
spec:
  podSelector:
    matchLabels:
      app: harbor
  policyTypes:
    - Ingress
  ingress:
    # Allow Prometheus to scrape metrics
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
        - podSelector:
            matchLabels:
              app: prometheus
      ports:
        - protocol: TCP
          port: 9090
EOF

kubectl apply -f harbor-allow-cross-namespace.yaml
```

### Egress to Specific External IPs

Restrict egress to specific external services:

```bash
cat > harbor-allow-specific-egress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: harbor-allow-specific-egress
  namespace: harbor
spec:
  podSelector:
    matchLabels:
      app: harbor
  policyTypes:
    - Egress
  egress:
    # Allow only specific external IPs (e.g., S3 VPC endpoint)
    - to:
        - ipBlock:
            cidr: 10.0.100.0/24
      ports:
        - protocol: TCP
          port: 443
EOF

kubectl apply -f harbor-allow-specific-egress.yaml
```

## Summary

You've successfully implemented comprehensive namespace isolation for Harbor! Here's what you accomplished:

✅ Created isolated namespace with security labels  
✅ Configured RBAC with least-privilege roles  
✅ Implemented network policies for traffic control  
✅ Set resource quotas and limits  
✅ Enforced pod security standards  
✅ Validated all security controls  

### Security Layers Achieved

1. **Namespace Isolation**: Harbor workloads are logically separated
2. **RBAC**: Access control limits who can manage Harbor resources
3. **Network Policies**: Traffic is restricted to authorized paths only
4. **Resource Limits**: Prevents resource exhaustion
5. **Pod Security**: Enforces security best practices at pod level
6. **IRSA** (from previous guides): AWS credentials bound to specific service account

### Combined with IRSA

When combined with IRSA, you now have:

- **Kubernetes-level isolation**: Namespace, RBAC, network policies
- **AWS-level isolation**: IAM role bound to specific service account
- **Defense in depth**: Multiple security layers
- **Least privilege**: Minimal permissions at every level
- **Audit trail**: CloudTrail + Kubernetes audit logs

## Next Steps

1. **[Deploy Harbor with IRSA](./harbor-irsa-deployment.md)** - Deploy Harbor using all security controls
2. **[Validate Security Controls](../validation-tests/)** - Test that isolation is working
3. **[Monitor and Audit](./monitoring-guide.md)** - Set up ongoing monitoring

---

**Previous**: [IAM Guardrails Documentation](./iam-guardrails.md)  
**Next**: [Harbor IRSA Deployment](./harbor-irsa-deployment.md)
