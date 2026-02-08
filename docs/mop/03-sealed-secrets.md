# Sealed Secrets Management

## Overview

Manage secrets via GitOps using Sealed Secrets. Encrypted secrets are stored in Git and decrypted by the controller in-cluster.

## Prerequisites

- Sealed Secrets controller deployed (via `sealed-secrets-controller` Application)
- Public certificate available (`sealed-secrets.crt`)
- `kubeseal` CLI installed

## Procedure: Create New Secret

### Step 1: Create Plain Secret

Create a temporary secret file (DO NOT commit this):

```bash
cat > /tmp/my-secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: my-app
type: Opaque
stringData:
  api-key: "your-api-key-here"
  password: "your-password-here"
EOF
```

### Step 2: Seal the Secret

```bash
# Using helper script
./scripts/seal-secret.sh my-app my-secret /tmp/my-secret.yaml > apps/sealed-secrets/my-app/my-secret.yaml

# Or manually with kubeseal
kubeseal \
  --cert sealed-secrets.crt \
  --format yaml \
  < /tmp/my-secret.yaml \
  > apps/sealed-secrets/my-app/my-secret.yaml
```

### Step 3: Clean Up Plain Secret

```bash
rm /tmp/my-secret.yaml
```

### Step 4: Commit and Push

```bash
git add apps/sealed-secrets/my-app/my-secret.yaml
git commit -m "feat: Add sealed secret for my-app"
git push
```

### Step 5: Verify Deployment

```bash
# Check SealedSecret exists
oc get sealedsecret my-secret -n my-app

# Check Secret was created
oc get secret my-secret -n my-app

# Verify secret data (base64 encoded)
oc get secret my-secret -n my-app -o jsonpath='{.data.api-key}' | base64 -d
```

## Procedure: Update Existing Secret

### Step 1: Create Updated Plain Secret

```bash
cat > /tmp/my-secret-updated.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: my-app
type: Opaque
stringData:
  api-key: "new-api-key-here"
  password: "new-password-here"
EOF
```

### Step 2: Re-seal and Replace

```bash
kubeseal \
  --cert sealed-secrets.crt \
  --format yaml \
  < /tmp/my-secret-updated.yaml \
  > apps/sealed-secrets/my-app/my-secret.yaml

rm /tmp/my-secret-updated.yaml
```

### Step 3: Commit and Push

```bash
git add apps/sealed-secrets/my-app/my-secret.yaml
git commit -m "fix: Update my-secret credentials"
git push
```

## Directory Structure

```
apps/sealed-secrets/
├── nim-llm/
│   └── ngc-api-key.yaml        # NGC credentials
├── hubble-timescape/
│   ├── clickhouse-credentials.yaml
│   └── vector-push-credentials.yaml
├── splunk-otel/
│   └── splunk-token.yaml
├── intersight-otel/
│   └── api-credentials.yaml
└── my-app/
    └── my-secret.yaml          # Your new secret
```

## Getting the Certificate

### From Cluster

```bash
# Extract from controller
oc get secret sealed-secrets-key -n sealed-secrets -o jsonpath='{.data.tls\.crt}' | base64 -d > sealed-secrets.crt
```

### From GitHub Secrets

The shared key is stored as GitHub Secret `SEALED_SECRETS_CERT`.

## Using Helper Script

The `scripts/seal-secret.sh` simplifies secret creation:

```bash
# Syntax: ./scripts/seal-secret.sh <namespace> <name> [input-file]

# From file
./scripts/seal-secret.sh my-app my-secret /tmp/secret.yaml > apps/sealed-secrets/my-app/my-secret.yaml

# From stdin
echo "api-key=secret123" | ./scripts/seal-secret.sh my-app my-secret > apps/sealed-secrets/my-app/my-secret.yaml
```

## Multi-Cluster Secrets

The same SealedSecret works on all clusters because they share the same key pair.

```bash
# Seal once, deploy everywhere
kubeseal --cert sealed-secrets.crt < secret.yaml > sealedsecret.yaml

# ArgoCD deploys to all clusters with sealed-secrets Application
```

## Troubleshooting

### SealedSecret Not Decrypting

Check controller logs:

```bash
oc logs -n sealed-secrets deployment/sealed-secrets-controller
```

Common issues:
- Wrong namespace in SealedSecret
- Key mismatch (controller has different key)

### Secret Shows Empty Data

Verify SealedSecret annotation matches target namespace:

```yaml
metadata:
  name: my-secret
  namespace: my-app  # Must match
  annotations:
    sealedsecrets.bitnami.com/namespace-wide: "true"
```

### Controller Pod CrashLooping

Check if key secret exists:

```bash
oc get secret sealed-secrets-key -n sealed-secrets
```

If missing, re-run post-install to inject key:

```bash
gh workflow run openshift-post-install.yaml \
  -f cluster_name=ai-pod-1 \
  --repo mahowlin/saif-ai-pod
```
