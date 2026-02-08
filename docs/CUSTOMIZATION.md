# Customization Guide

How to adapt saif-gitops for your environment.

## Overview

This repository is designed for the SAIF environment but can be customized for:
- Different registries (air-gap, enterprise)
- Different Splunk endpoints
- Different cluster configurations
- Different operator versions

## Registry Configuration

### Changing Image Registry

All images are pulled from the internal registry. To change:

1. **Update IDMS** in `apps/platform-idms/`

```yaml
# apps/platform-idms/idms-*.yaml
spec:
  imageDigestMirrors:
    - mirrors:
        - your-registry.example.com:5000/openshift4
      source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

2. **Update Helm values** in cluster overlays

```yaml
# clusters/_base/tier3-nvidia/gpu-operator.yaml
spec:
  source:
    helm:
      values: |
        operator:
          repository: your-registry.example.com:5000/nvidia
```

### Air-Gap Requirements

For fully disconnected environments:

1. Mirror images using `saif-sys-admin/sync-images.yaml`
2. Update IDMS manifests
3. Ensure CatalogSources point to mirrored operator indexes

## Splunk Configuration

### Changing Splunk Endpoint

Edit the Splunk OTEL configuration:

```yaml
# clusters/_base/tier4-observability/splunk-otel-values.yaml
splunkObservability:
  realm: us1                    # Change to your realm
  accessToken: "${SPLUNK_ACCESS_TOKEN}"

clusterReceiver:
  config:
    exporters:
      signalfx:
        api_url: https://api.us1.signalfx.com  # Change endpoint
        ingest_url: https://ingest.us1.signalfx.com
```

### Using Different Observability Backend

Replace Splunk OTEL with your preferred collector:

1. Remove `splunk-otel.yaml` from cluster folders
2. Create new Application pointing to your collector config
3. Ensure metrics endpoints are scraped:
   - Cilium: `:9962`
   - Hubble: `:9965`
   - Tetragon: `:2112`
   - DCGM: `:9400`

## Cluster Configuration

### Adding a New Cluster

1. **Create cluster folder:**

```bash
mkdir clusters/my-cluster
```

2. **Add base applications:**

```bash
# Copy from existing cluster
cp clusters/ai-pod-1/platform-idms.yaml clusters/my-cluster/
cp clusters/ai-pod-1/tetragon.yaml clusters/my-cluster/
# Add others as needed
```

3. **Bootstrap ArgoCD** (in saif-ai-pod):

```bash
gh workflow run openshift-post-install.yaml \
  -f cluster_name=my-cluster \
  -f apply_argocd=true
```

4. **Inject secrets:**

```bash
gh workflow run gitops-sync.yaml \
  -f cluster=my-cluster \
  -f inject_secrets=true
```

### GPU vs Non-GPU Clusters

For clusters without GPU:

```bash
# Don't include these in cluster folder:
# - gpu-operator.yaml
# - nim-operator.yaml
# - nim-llm.yaml (model deployment)
```

### Cluster-Specific Values

Use Kustomize patches for per-cluster configuration:

```yaml
# clusters/my-cluster/hubble-timescape.yaml
spec:
  source:
    path: apps/hubble-timescape
    kustomize:
      patches:
        - target:
            kind: Service
            name: hubble-timescape-ui
          patch: |
            - op: replace
              path: /spec/loadBalancerIP
              value: "10.0.1.100"  # Your IP
```

## Operator Versions

### Upgrading Operators

1. **Check compatibility** with your OpenShift version
2. **Update subscription channel:**

```yaml
# apps/gpu-operator/subscription.yaml
spec:
  channel: v24.6    # Change from v25.10
```

3. **Commit and push** - ArgoCD syncs automatically

### Pinning Specific Versions

Use `startingCSV` for exact version control:

```yaml
spec:
  channel: v25.10
  startingCSV: gpu-operator-certified.v25.10.0
  installPlanApproval: Manual  # Prevent auto-upgrades
```

## Secrets Management

### Using External Secrets

Replace Sealed Secrets with External Secrets Operator:

1. Remove `sealed-secrets-controller` Application
2. Add External Secrets Operator subscription
3. Create `ExternalSecret` resources pointing to your vault

### Using Vault

```yaml
# apps/external-secrets/vault-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets"
```

## Network Configuration

### LoadBalancer IPs

Cilium L2 announcements require explicit IPs:

```yaml
# Per-service annotation
metadata:
  annotations:
    io.cilium/lb-ipam-ips: "10.0.1.80"
```

Or use IP pools:

```yaml
# apps/cilium-config/ip-pool.yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: default-pool
spec:
  cidrs:
    - cidr: 10.0.1.80/29  # Adjust for your network
```

### Ingress Configuration

For clusters with Ingress instead of LoadBalancer:

```yaml
# Replace LoadBalancer services with Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hubble-timescape-ui
spec:
  rules:
    - host: hubble.apps.my-cluster.example.com
      http:
        paths:
          - path: /
            backend:
              service:
                name: hubble-timescape-ui
                port:
                  number: 80
```

## Tetragon Configuration

### Custom Tracing Policies

Add your own TracingPolicies:

```yaml
# apps/tetragon/custom-policies/my-policy.yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: my-custom-policy
spec:
  kprobes:
    - call: "security_file_open"
      # Your policy configuration
```

### Adjusting Export Settings

```yaml
# apps/tetragon/operator-config.yaml
spec:
  tracingPolicy:
    exportFilename: /var/run/cilium/hubble/tetragon.log
    connectionLogFilename: /var/run/cilium/hubble/tetragon-connections.log
```

## Hubble Timescape

### Storage Configuration

Adjust ClickHouse storage for your environment:

```yaml
# charts/hubble-timescape/values.yaml
clickhouse:
  persistence:
    size: 100Gi  # Adjust based on retention needs
  resources:
    requests:
      memory: 4Gi
      cpu: 2
```

### Retention Settings

```yaml
hubbleServer:
  retention:
    flowsMaxAge: 7d      # Adjust retention period
    connectionMaxAge: 7d
```

## Development Workflow

### Testing Changes

1. **Fork the repo** for testing
2. **Update ArgoCD** to point to your fork:

```bash
oc -n openshift-gitops patch application saif-apps \
  --type merge \
  --patch '{"spec":{"source":{"repoURL":"https://github.com/YOUR_ORG/saif-gitops.git"}}}'
```

3. **Test changes** on development cluster
4. **Merge to main** when validated

### Local Validation

```bash
# Validate YAML syntax
find apps/ -name "*.yaml" -exec yamllint {} \;

# Validate Kubernetes manifests
kubectl apply --dry-run=client -f apps/my-app/
```

## Related Documentation

- [Architecture](ARCHITECTURE.md) - GitOps patterns
- [saif-ai-pod CUSTOMIZATION.md](https://github.com/mahowlin/saif-ai-pod/blob/main/docs/CUSTOMIZATION.md) - Infrastructure customization
