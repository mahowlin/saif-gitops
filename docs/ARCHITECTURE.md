# GitOps Architecture

## Overview

This repository implements the **App-of-Apps** pattern for managing Kubernetes workloads across multiple clusters via ArgoCD.

All Day 2 operations flow through Git:
- Add application → Create YAML in `clusters/<cluster>/`
- Remove application → Delete YAML file
- Update configuration → Edit manifests in `apps/`
- No pipeline runs required → ArgoCD syncs automatically

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              GitOps Flow                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐                                                        │
│  │     GitHub      │                                                        │
│  │  (This Repo)    │                                                        │
│  │                 │                                                        │
│  │ clusters/       │◄─────── Git Push                                      │
│  │   ai-pod-1/     │                                                        │
│  │   ai-pod-2/     │                                                        │
│  │ apps/           │                                                        │
│  │   tetragon/     │                                                        │
│  │   gpu-operator/ │                                                        │
│  └────────┬────────┘                                                        │
│           │                                                                 │
│           │ ArgoCD polls (every 3 min)                                     │
│           │ or hard refresh on demand                                       │
│           ▼                                                                 │
│  ┌─────────────────┐         ┌─────────────────┐                           │
│  │     ArgoCD      │         │     ArgoCD      │                           │
│  │   (ai-pod-1)    │         │   (ai-pod-2)    │  ...                      │
│  │                 │         │                 │                           │
│  │ saif-apps       │         │ saif-apps       │  (App-of-Apps)            │
│  │   ├─tetragon    │         │   ├─tetragon    │                           │
│  │   ├─gpu-operator│         │   ├─gpu-operator│                           │
│  │   └─...         │         │   └─...         │                           │
│  └────────┬────────┘         └────────┬────────┘                           │
│           │                           │                                     │
│           │ kubectl apply             │                                     │
│           ▼                           ▼                                     │
│  ┌─────────────────┐         ┌─────────────────┐                           │
│  │   OpenShift     │         │   OpenShift     │                           │
│  │   (ai-pod-1)    │         │   (ai-pod-2)    │                           │
│  └─────────────────┘         └─────────────────┘                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## App-of-Apps Pattern

### Structure

```
clusters/
├── ai-pod-1/                    # Cluster-specific applications
│   ├── tetragon.yaml            # ArgoCD Application → apps/tetragon/
│   ├── gpu-operator.yaml        # ArgoCD Application → apps/gpu-operator/
│   └── hubble-timescape.yaml    # ArgoCD Application → apps/hubble-timescape/
├── ai-pod-2/
│   └── ...
└── _base/                       # Shared configurations (Kustomize bases)
    ├── tier1-platform/          # Core platform (IDMS, catalogsources)
    ├── tier2-isovalent/         # Cilium ecosystem (Tetragon, Timescape)
    ├── tier3-nvidia/            # GPU stack (GPU Operator, NIM)
    └── tier4-observability/     # Monitoring (Splunk OTEL)

apps/
├── tetragon/                    # Application manifests
│   ├── namespace.yaml
│   ├── subscription.yaml
│   └── operator-config.yaml
├── gpu-operator/
└── ...
```

### How It Works

1. **Day 1 Bootstrap**: `openshift-post-install.yaml` creates `saif-apps` Application
2. **saif-apps** watches `clusters/<cluster>/` directory
3. Each YAML in cluster folder is an ArgoCD Application
4. Applications point to `apps/` for actual manifests
5. ArgoCD reconciles continuously

## Sync Waves and Deployment Order

ArgoCD applies resources in order using sync-wave annotations. Lower (more negative) waves deploy first. Resources within the same wave deploy concurrently. ArgoCD waits for all resources in a wave to be healthy before advancing to the next wave.

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-10"
```

### Complete Wave Order

The table below lists every ArgoCD Application in deployment order. All clusters deploy Tiers 1, 2, 4, and 5. GPU clusters (ai-pod-1, ai-pod-2) additionally deploy Tier 3 and Tier 6.

| Wave | Tier | Application | What It Deploys | Key Dependencies |
|------|------|-------------|-----------------|------------------|
| **-15** | 1 | argocd-config | OCI registry pull-secret for ArgoCD | None (first to deploy) |
| **-10** | 1 | platform-idms | IDMS/ITMS manifests for disconnected image resolution | argocd-config (registry auth) |
| **-8** | 1 | sealed-secrets-controller | Sealed Secrets controller operator | platform-idms (image pull) |
| **-5** | 1 | platform-catalogsources | Red Hat + Certified operator CatalogSources | platform-idms (image pull) |
| **-5** | 1 | sealed-secrets | Common SealedSecrets (Splunk, Hubble, Intersight) | sealed-secrets-controller |
| **-5** | 3 | sealed-secrets-gpu | GPU SealedSecrets (NGC API key, webserver-credentials) | sealed-secrets-controller |
| **-3** | 3 | nfd-operator | Node Feature Discovery operator (OLM) | platform-catalogsources |
| **-2** | 2 | hubble-timescape-scc | SecurityContextConstraints for Hubble Timescape pods | None |
| **-2** | 3 | gpu-operator | NVIDIA GPU Operator (OLM: driver, device plugin, DCGM) | platform-catalogsources, nfd-operator |
| **-1** | 1 | lvms-operator | LVM Storage operator (OLM) + LVMCluster CR | platform-catalogsources |
| **-1** | 2 | tetragon-catalogsource | Tetragon Enterprise CatalogSource | platform-catalogsources |
| **-1** | 2 | clickhouse-operator | Altinity ClickHouse Operator (Helm) | platform-catalogsources |
| **-1** | 2 | tetragon | Tetragon operator (OLM) + TracingPolicies | tetragon-catalogsource |
| **-1** | 2 | cilium-config | Cilium Hubble ConfigMap | Cilium CNI (deployed at Day 1) |
| **0** | 2 | hubble-timescape | Hubble Timescape (Helm: server, ingester, UI, trimmer) | clickhouse-operator, hubble-timescape-scc, sealed-secrets |
| **0** | 3 | nfd-instance | NodeFeatureDiscovery CR (activates feature detection) | nfd-operator |
| **1** | 2 | vector-exporter | Vector DaemonSet (pushes Hubble flows to Timescape) | hubble-timescape, sealed-secrets (push-api creds) |
| **1** | 3 | gpu-cluster-policy | GPU ClusterPolicy CR (driver config, MIG, DCGM) | gpu-operator (CRD must exist) |
| **1** | 3 | nim-operator | NVIDIA NIM Operator (Helm, admission controller) | platform-catalogsources, gpu-operator |
| **1** | 4 | splunk-otel | Splunk OTel Collector (agent + cluster receiver) | sealed-secrets (Splunk token) |
| **1** | 4 | intersight-otel | Intersight metrics OTEL Collector (Helm) | sealed-secrets (Intersight API creds) |
| **2** | 3 | nim-llm | NIM LLM inference service | nim-operator, sealed-secrets-gpu (NGC + webserver creds), gpu-cluster-policy |
| **2** | 4 | splunk-reporter | Splunk Dashboard updater CronJob | splunk-otel, sealed-secrets (Splunk token) |

> **Note:** All applications have explicit sync-wave annotations. ArgoCD deploys resources within the same wave concurrently and waits for health before advancing to the next wave.

### Nested Sync Waves (Within Applications)

Several OLM-based applications use internal sync waves to order their own resources:

**Pattern: Namespace → OperatorGroup → Subscription → CR**

| Application | Wave -2 | Wave -1 | Wave 0 | Wave 1 |
|-------------|---------|---------|--------|--------|
| nfd-operator | Namespace | OperatorGroup | Subscription | RBAC (seccomp patcher) |
| gpu-operator | Namespace | OperatorGroup | Subscription | *(ClusterPolicy is separate app)* |
| lvms-operator | Namespace | OperatorGroup | Subscription | LVMCluster CR |
| tetragon | Namespace | OperatorGroup, Subscription | Operator ConfigMap | TracingPolicy |

### ArgoCD Hooks

The NFD operator uses a **PostSync hook** (`seccomp-fix-hook.yaml`) to patch the OLM-managed deployment after ArgoCD finishes syncing. This is a workaround for a K8s 1.32 seccomp annotation bug.

### Dependency Chains

The platform has three critical dependency chains that sync waves enforce:

**Chain 1: Image Resolution (must complete before anything else)**
```
argocd-config (-15) → platform-idms (-10) → all operators can pull images
```

**Chain 2: Secrets Provisioning (must complete before workloads)**
```
sealed-secrets-controller (-8) → sealed-secrets / sealed-secrets-gpu (-5) → workloads consume secrets
```

**Chain 3: GPU Workload Stack**
```
platform-catalogsources (-5) → nfd-operator (-3) → gpu-operator (-2)
    → nfd-instance (0) + gpu-cluster-policy (1) → nim-operator (1) → nim-llm (2)
```

### End-to-End Deployment Flow

From a freshly bootstrapped cluster (Day 1 complete), the full Day 2 rollout proceeds:

```
Day 1 (saif-ai-pod):
  1. OpenShift deployed (Agent-Based Installer)
  2. Cilium CNI installed (isovalent-cilium-ee Helm)
  3. Sealed Secrets shared key injected
  4. ArgoCD operator + saif-apps Application created
  5. ArgoCD begins syncing from this repository

Day 2 (this repository via ArgoCD):
  Wave -15: ArgoCD OCI registry auth
  Wave -10: IDMS/ITMS (image mirrors active)
  Wave  -8: Sealed Secrets controller starts
  Wave  -5: CatalogSources registered + all SealedSecrets decrypted into Secrets
  Wave  -3: NFD operator installing (OLM)
  Wave  -2: GPU operator installing (OLM), Hubble SCC created
  Wave  -1: LVMS, Tetragon CatalogSource, ClickHouse operator
  Wave   0: Hubble Timescape deploying, NFD instance created
             NFD PostSync hook patches seccomp bug → NFD pods start → GPU labels appear
  Wave   1: Vector, GPU ClusterPolicy, NIM operator, Splunk OTel
             GPU driver loads, device plugin registers nvidia.com/gpu
  Wave   2: NIM LLM starts (model download from NGC), Splunk reporter
  (Tetragon, Cilium config deploy at wave -1; Intersight OTEL at wave 1; demo apps at waves 0-1)
```

### Why Sync Waves Matter

Without sync waves, resources deploy concurrently and hit dependency failures:

```
Without sync waves:
  GPU Operator Subscription created
  ClusterPolicy created → FAILS (CRD doesn't exist yet)
  NIM Service created → FAILS (NIM Operator not installed)
  SealedSecret created → FAILS (controller not running)

With sync waves:
  Wave -8: Sealed Secrets controller starts
  Wave -5: SealedSecrets decrypted into Secrets (NGC key, Splunk token, etc.)
  Wave -2: GPU Operator Subscription → installs CRDs
  Wave  1: ClusterPolicy created (CRD exists) → GPU driver loads
  Wave  1: NIM Operator installed
  Wave  2: NIM Service created → downloads model → serves inference
```

## Per-Cluster Configuration

### Enabling Apps Per Cluster

Each cluster folder controls what's deployed:

```bash
# ai-pod-1 has GPU
clusters/ai-pod-1/
├── gpu-operator.yaml      ✓
├── nim-operator.yaml      ✓
├── tetragon.yaml          ✓
└── hubble-timescape.yaml  ✓

# ai-pod-3 has no GPU
clusters/ai-pod-3/
├── tetragon.yaml          ✓
├── hubble-timescape.yaml  ✓
└── (no gpu-operator.yaml) ✗ Not deployed
```

### Cluster-Specific Values

Use Kustomize overlays for cluster-specific configuration:

```yaml
# clusters/ai-pod-1/hubble-timescape.yaml
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
              value: "10.0.1.80"
```

## Secrets Management

### Option 1: Sealed Secrets (Preferred)

Encrypted secrets stored in Git:

```
apps/sealed-secrets/
├── nim-llm/
│   └── ngc-api-key.yaml      # SealedSecret (encrypted)
├── hubble-timescape/
│   └── clickhouse-creds.yaml
└── splunk-otel/
    └── access-token.yaml
```

**Flow:**
1. Seal secret: `kubeseal --cert sealed-secrets.crt < secret.yaml > sealedsecret.yaml`
2. Commit to Git
3. ArgoCD syncs SealedSecret
4. Controller decrypts to Secret

### Option 2: Workflow Injection

For secrets not in Git:

```bash
gh workflow run gitops-sync.yaml -f cluster=ai-pod-1 -f inject_secrets=true
```

**Flow:**
1. Workflow reads from GitHub Secrets
2. Creates Kubernetes Secrets via `oc create secret`
3. Applications consume secrets

## Component Categories

### Tier 1: Platform (Required)

Core platform components that ALL clusters need:

| Component | Purpose |
|-----------|---------|
| platform-idms | Image mirrors for air-gap |
| sealed-secrets-controller | GitOps secret management |
| catalogsources | Operator catalogs |

### Tier 2: Isovalent (SAIF Security)

Cilium ecosystem for security and observability:

| Component | Purpose |
|-----------|---------|
| tetragon | Runtime security, process monitoring |
| hubble-timescape | Flow storage, historical analysis |
| vector | Log forwarding to Timescape |

### Tier 3: NVIDIA (AI Workloads)

GPU and inference stack:

| Component | Purpose |
|-----------|---------|
| nfd-operator | Node Feature Discovery |
| gpu-operator | NVIDIA driver, device plugin |
| nim-operator | Model inference serving |

### Tier 4: Observability

Metrics and monitoring:

| Component | Purpose |
|-----------|---------|
| splunk-otel | Metrics to Splunk Cloud |
| dcgm-exporter | GPU metrics (via GPU Operator) |

## Integration with Other Repos

### From saif-sys-admin

IDMS manifests flow from image mirroring:

```
saif-sys-admin
  └── sync-images.yaml
       └── generates mirror/idms/*.yaml
            └── ./scripts/sync-idms-from-sys-admin.sh
                 └── copies to apps/platform-idms/
                      └── ArgoCD syncs to clusters
```

### From saif-ai-pod

ArgoCD is bootstrapped during Day 1:

```
saif-ai-pod
  └── openshift-post-install.yaml
       └── creates ArgoCD operator
       └── creates saif-apps Application
            └── points to clusters/<cluster>/ in this repo
```

## Related Documentation

- [Observability Architecture](OBSERVABILITY_ARCHITECTURE.md) - Data flow details
- [Customization](CUSTOMIZATION.md) - Adapting for your environment
- [saif-platform Architecture](https://github.com/mahowlin/saif-platform/blob/main/docs/ARCHITECTURE.md) - Platform overview
