# Add Application to Cluster

## Overview

Deploy a new application to one or more clusters via GitOps.

## Prerequisites

- Git access to this repository
- Application manifests ready (Deployment, Service, etc.)

## Procedure

### Step 1: Create Application Manifests

Create a directory for your application:

```bash
mkdir -p apps/my-app
```

Add your Kubernetes manifests:

```bash
# apps/my-app/namespace.yaml
cat > apps/my-app/namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
EOF

# apps/my-app/deployment.yaml
cat > apps/my-app/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: my-app
          image: registry.example.com:5000/my-app:latest
EOF
```

### Step 2: Create ArgoCD Application

Create Application YAML for target cluster:

```bash
cat > clusters/ai-pod-1/my-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  project: default
  source:
    repoURL: https://github.com/mahowlin/saif-gitops.git
    targetRevision: main
    path: apps/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

### Step 3: Commit and Push

```bash
git add apps/my-app clusters/ai-pod-1/my-app.yaml
git commit -m "feat: Add my-app to ai-pod-1"
git push
```

### Step 4: Verify Deployment

**Option A: ArgoCD UI**

1. Open ArgoCD: `https://openshift-gitops-server-openshift-gitops.apps.cluster-1.example.com`
2. Find `my-app` Application
3. Verify status is "Synced" and "Healthy"

**Option B: CLI**

```bash
# Check Application status
oc get application my-app -n openshift-gitops

# Check pods
oc get pods -n my-app
```

## Deploying to Multiple Clusters

Copy the Application YAML to other cluster folders:

```bash
cp clusters/ai-pod-1/my-app.yaml clusters/ai-pod-2/
cp clusters/ai-pod-1/my-app.yaml clusters/ai-pod-3/
git add clusters/
git commit -m "feat: Enable my-app on ai-pod-2 and ai-pod-3"
git push
```

## Troubleshooting

### Sync Fails with "path does not exist"

Verify the path in Application spec matches actual directory:

```yaml
spec:
  source:
    path: apps/my-app  # Must match actual path
```

### Image Pull Error

Ensure image is mirrored and IDMS is applied:

```bash
# Check IDMS
oc get imagedigestmirrorset

# Check if image is mirrored
curl -s https://registry.example.com:5000/v2/my-app/tags/list
```

### Application Stuck in "Progressing"

Check events and logs:

```bash
oc describe application my-app -n openshift-gitops
oc logs -n my-app -l app=my-app
```
