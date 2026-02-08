# Application CR Inventory

## Classification

### Tier 1: Core Platform (ALL clusters, identical)
These apps are deployed to every cluster with **zero differences**.

| Application | Source | Notes |
|-------------|--------|-------|
| argocd-config | apps/argocd-config | ArgoCD settings |
| platform-idms | apps/platform-idms | Image registry mirrors |
| platform-catalogsources | apps/platform-catalogsources | Operator catalogs |
| lvms-operator | apps/lvms-operator | Storage |
| sealed-secrets-controller | apps/sealed-secrets-controller | Secrets management |
| tetragon | apps/tetragon | Runtime security |
| tetragon-catalogsource | apps/tetragon-catalogsource | Tetragon catalog |
| cilium | charts/cilium-config | CNI config |

### Tier 2: Observability Stack (ai-pod-1,2,3 - hostname differs)
These apps differ **only in ingress hostname**.

| Application | Source | Cluster-Specific Field |
|-------------|--------|------------------------|
| hubble-timescape | charts/hubble-timescape | `ui.ingress.host` |
| hubble-timescape-scc | apps/hubble-timescape-scc | None (identical) |
| clickhouse-operator | charts/altinity-clickhouse-operator | None (after fixes) |
| vector-exporter | charts/vector | None (identical) |

### Tier 3: NVIDIA Stack (ai-pod-1,2 only)
GPU/AI workloads - only on clusters with GPUs.

| Application | Source | Notes |
|-------------|--------|-------|
| gpu-operator | apps/gpu-operator | Operator subscription |
| gpu-cluster-policy | apps/gpu-cluster-policy | ClusterPolicy CR |
| nfd-operator | apps/nfd-operator | Node Feature Discovery |
| nfd-instance | apps/nfd-instance | NFD CR |
| nim-operator | apps/nim-llm | NIM operator |
| nim-llm | apps/nim-llm | LLM model |

### Tier 4: Monitoring/Integration (ai-pod-1,2 only)
External integrations.

| Application | Source | Cluster-Specific Field |
|-------------|--------|------------------------|
| splunk-otel | charts/splunk-otel-collector | `clusterName` in values |
| splunk-reporter | apps/splunk-reporter | None |
| intersight-otel | apps/intersight-otel | None |
| sealed-secrets | apps/sealed-secrets | None |

### Tier 5: Demo Apps (all clusters)

| Application | Source | Notes |
|-------------|--------|-------|
| mnist-ml-lab | apps/mnist-ml-lab | MNIST demo app (SAIF DNS policy flow) |

---

## Cluster Coverage Matrix

| Application | pod-1 | pod-2 | pod-3 | pod-4 |
|-------------|-------|-------|-------|-------|
| **Tier 1 - Core** |
| argocd-config | ✓ | ✓ | ✓ | ✓ |
| platform-idms | ✓ | ✓ | ✓ | ✓ |
| platform-catalogsources | ✓ | ✓ | ✓ | ✓ |
| lvms-operator | ✓ | ✓ | ✓ | ✓ |
| sealed-secrets-controller | ✓ | ✓ | ✓ | ✓ |
| tetragon | ✓ | ✓ | ✓ | ✓ |
| tetragon-catalogsource | ✓ | ✓ | ✓ | ✓ |
| cilium | ✓ | ✓ | ✓ | ✓ |
| **Tier 2 - Observability** |
| hubble-timescape | ✓ | ✓ | ✓ | |
| hubble-timescape-scc | ✓ | ✓ | ✓ | |
| clickhouse-operator | ✓ | ✓ | ✓ | |
| vector-exporter | ✓ | ✓ | ✓ | |
| **Tier 3 - NVIDIA** |
| gpu-operator | ✓ | ✓ | | |
| gpu-cluster-policy | ✓ | ✓ | | |
| nfd-operator | ✓ | ✓ | | |
| nfd-instance | ✓ | ✓ | | |
| nim-operator | ✓ | ✓ | | |
| nim-llm | ✓ | ✓ | | |
| **Tier 4 - Monitoring** |
| splunk-otel | ✓ | ✓ | | |
| splunk-reporter | ✓ | ✓ | | |
| intersight-otel | ✓ | ✓ | | |
| sealed-secrets | ✓ | ✓ | | |
| **Tier 5 - Demo** |
| mnist-ml-lab | ✓ | ✓ | ✓ | ✓ |

---

## Implemented Kustomize Structure

**Status:** Implemented 2026-02-01

```
clusters/
├── _base/
│   ├── tier1-core/                    # 8 apps - ALL clusters
│   │   ├── kustomization.yaml
│   │   ├── argocd-config.yaml
│   │   ├── platform-idms.yaml
│   │   ├── platform-catalogsources.yaml
│   │   ├── lvms-operator.yaml
│   │   ├── sealed-secrets-controller.yaml
│   │   ├── tetragon.yaml
│   │   ├── tetragon-catalogsource.yaml
│   │   └── cilium.yaml
│   │
│   ├── tier2-observability/           # 3 apps - ai-pod-1,2,3
│   │   ├── kustomization.yaml         # EXCLUDES hubble-timescape (cluster-specific)
│   │   ├── hubble-timescape-scc.yaml
│   │   ├── clickhouse-operator.yaml
│   │   └── vector-exporter.yaml
│   │
│   ├── tier3-nvidia/                  # 6 apps - ai-pod-1,2 only
│   │   ├── kustomization.yaml
│   │   ├── gpu-operator.yaml
│   │   ├── gpu-cluster-policy.yaml
│   │   ├── nfd-operator.yaml
│   │   ├── nfd-instance.yaml
│   │   ├── nim-operator.yaml
│   │   └── nim-llm.yaml
│   │
│   └── tier4-monitoring/              # 3 apps - ai-pod-1,2 only
│       ├── kustomization.yaml         # EXCLUDES splunk-otel (cluster-specific)
│       ├── splunk-reporter.yaml
│       ├── intersight-otel.yaml
│       └── sealed-secrets.yaml
│
├── ai-pod-1/                          # 24 total apps
│   ├── kustomization.yaml             # References: tier1, tier2, tier3, tier4
│   ├── hubble-timescape.yaml          # LOCAL - cluster-specific hostname
│   ├── splunk-otel.yaml               # LOCAL - cluster-specific clusterName
│
├── ai-pod-2/                          # 22 total apps
│   ├── kustomization.yaml             # References: tier1, tier2, tier3, tier4
│   ├── hubble-timescape.yaml          # LOCAL - cluster-specific hostname
│   └── splunk-otel.yaml               # LOCAL - cluster-specific clusterName
│
├── ai-pod-3/                          # 12 total apps
│   ├── kustomization.yaml             # References: tier1, tier2
│   └── hubble-timescape.yaml          # LOCAL - cluster-specific hostname
│
└── ai-pod-4/                          # 8 total apps
    └── kustomization.yaml             # References: tier1 only
```

### Key Design Decisions

1. **Cluster-specific apps stay local**: `hubble-timescape.yaml` and `splunk-otel.yaml` contain
   Helm values with cluster-specific data (hostname, clusterName). Kustomize cannot patch inside
   string fields (`spec.source.helm.values` is a string), so these remain in cluster folders.

2. **Identical apps in base**: All other apps are truly identical across clusters and live in
   `_base/` tier directories.

3. **Reduction achieved**: ~20 duplicate files eliminated by moving to base structure.
