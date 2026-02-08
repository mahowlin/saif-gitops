# Add OLM Operator

## Overview

Install a new certified operator from OperatorHub via GitOps.

## Prerequisites

- Operator available in CatalogSource (mirrored for air-gap)
- Images mirrored via `saif-sys-admin/sync-images.yaml`

## Procedure

### Step 1: Verify Operator Availability

```bash
# Check available operators
oc get packagemanifests | grep <operator-name>

# Check available channels
oc get packagemanifest <operator-name> -o jsonpath='{.status.channels[*].name}'
```

### Step 2: Create Operator Manifests

```bash
mkdir -p apps/my-operator
```

**Namespace:**
```bash
cat > apps/my-operator/namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: my-operator
EOF
```

**OperatorGroup:**
```bash
cat > apps/my-operator/operatorgroup.yaml << 'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: my-operator
  namespace: my-operator
spec:
  targetNamespaces:
    - my-operator
EOF
```

**Subscription:**
```bash
cat > apps/my-operator/subscription.yaml << 'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: my-operator
  namespace: my-operator
spec:
  channel: stable
  name: my-operator
  source: certified-operators-local  # Use mirrored catalog
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
```

### Step 3: Create ArgoCD Application

```bash
cat > clusters/ai-pod-1/my-operator.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-operator
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # Deploy with other operators
spec:
  project: default
  source:
    repoURL: https://github.com/mahowlin/saif-gitops.git
    targetRevision: main
    path: apps/my-operator
  destination:
    server: https://kubernetes.default.svc
    namespace: my-operator
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

### Step 4: Add Operator Configuration (if needed)

Many operators require a CR after installation:

```bash
cat > apps/my-operator/config.yaml << 'EOF'
apiVersion: myoperator.io/v1
kind: MyOperatorConfig
metadata:
  name: my-config
  namespace: my-operator
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # After subscription
spec:
  # Operator-specific configuration
EOF
```

### Step 5: Commit and Push

```bash
git add apps/my-operator clusters/ai-pod-1/my-operator.yaml
git commit -m "feat: Add my-operator to ai-pod-1"
git push
```

### Step 6: Verify Installation

```bash
# Check CSV status
oc get csv -n my-operator

# Expected: my-operator.v1.0.0 Succeeded

# Check operator pod
oc get pods -n my-operator
```

## Sync Wave Guidelines

| Wave | Use For |
|------|---------|
| -1 | CatalogSources |
| 0 | Operator Subscriptions |
| 1 | Operator CRs (ClusterPolicy, etc.) |
| 2+ | Applications using operator |

## Common Operators

### GPU Operator

```yaml
spec:
  channel: v25.10
  name: gpu-operator-certified
  source: certified-operators-local
```

### NIM Operator

```yaml
spec:
  channel: v3.0
  name: k8s-nim-operator
  source: certified-operators-local
```

## Troubleshooting

### Subscription Stuck in "UpgradePending"

Check InstallPlan:

```bash
oc get installplan -n my-operator
oc describe installplan <name> -n my-operator
```

Usually caused by missing images. Verify mirroring.

### CSV Failed

Check operator logs:

```bash
oc logs -n my-operator deployment/<operator-name>
```

### CatalogSource Not Available

Verify CatalogSource exists and is healthy:

```bash
oc get catalogsource -n openshift-marketplace
oc describe catalogsource certified-operators-local -n openshift-marketplace
```
