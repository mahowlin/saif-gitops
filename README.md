# SAIF GitOps Applications

Day 2 workload management for the SAIF Platform via ArgoCD using the App-of-Apps pattern.

## Overview

This repository is the **source of truth** for everything deployed on OpenShift clusters after the Day 1 bootstrap. ArgoCD syncs directly from this repository to manage all operators, configurations, and workloads.

## Architecture

### Tier Structure

Applications are organized into tiers with sync wave ordering to handle dependencies:

| Tier | Purpose | Examples |
|------|---------|---------|
| **tier1-core** | Platform prerequisites | IDMS, Sealed Secrets, LVMS, CatalogSources |
| **tier2-isovalent** | Cilium / eBPF stack | Cilium config, Tetragon, Hubble Timescape |
| **tier3-nvidia** | GPU / AI inference | GPU Operator, NFD, NIM Operator, NIM LLM |
| **tier4-observability** | Monitoring / export | Splunk OTEL, Intersight OTEL |
| **tier5-demo** | Demo applications | MNIST ML Lab, Open WebUI |

### App-of-Apps Pattern

```
clusters/ai-pod-1/kustomization.yaml     <-- Per-cluster overlay
  └── clusters/_base/tier*/               <-- Base tier definitions
        └── apps/<app-name>/              <-- Shared application manifests
```

Each cluster folder uses Kustomize to select which tiers and applications to deploy.

## Quick Start

### Add an Application to a Cluster

1. Create manifests in `apps/my-app/`
2. Create an ArgoCD Application in `clusters/_base/tier5-demo/my-app.yaml`
3. Reference it in the tier's `kustomization.yaml`
4. Commit and push -- ArgoCD syncs automatically

### Trigger Manual Sync

```bash
gh workflow run gitops-sync.yaml -f cluster=ai-pod-1
```

## Clusters

| Cluster | GPU | Stack |
|---------|-----|-------|
| ai-pod-1 | NVIDIA L40S | Full stack (GPU + AI inference) |
| ai-pod-2 | NVIDIA L40S | Full stack (GPU + AI inference) |
| ai-pod-3 | None | Base stack (no NIM/GPU workloads) |
| ai-pod-4 | None | Base stack (no NIM/GPU workloads) |

## Directory Structure

```
saif-gitops/
├── apps/                       # Shared application manifests
│   ├── gpu-operator/           # NVIDIA GPU Operator
│   ├── nim-llm/                # LLM model via NIM
│   ├── tetragon/               # Tetragon security policies
│   ├── splunk-otel/            # Splunk OpenTelemetry
│   └── ...
├── clusters/                   # Per-cluster configurations
│   ├── _base/                  # Base tier definitions
│   │   ├── tier1-core/
│   │   ├── tier2-isovalent/
│   │   ├── tier3-nvidia/
│   │   ├── tier4-observability/
│   │   └── tier5-demo/
│   ├── ai-pod-1/               # Cluster overlays
│   ├── ai-pod-2/
│   ├── ai-pod-3/
│   └── ai-pod-4/
├── charts/                     # Helm charts (custom + vendored)
├── scripts/                    # Helper scripts
└── .github/workflows/          # CI/CD workflows
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - GitOps patterns and sync waves
- [Observability Architecture](docs/OBSERVABILITY_ARCHITECTURE.md) - Data flow diagrams
- [Customization](docs/CUSTOMIZATION.md) - Adapting for your environment
- [MOPs](docs/mop/) - Operational procedures

## Related Repositories

| Repository | Relationship |
|------------|-------------|
| [saif-platform](https://github.com/mahowlin/saif-platform) | Platform orchestration |
| [saif-ai-pod](https://github.com/mahowlin/saif-ai-pod) | Day 0/1 - bootstraps ArgoCD pointing here |
| [saif-sys-admin](https://github.com/mahowlin/saif-sys-admin) | Produces IDMS manifests consumed by this repo |
| [saif-splunk-dashboard](https://github.com/mahowlin/saif-splunk-dashboard) | Dashboard specifications for Splunk Observability |

## License

This project is licensed under the Cisco Sample Code License, Version 1.1. See [LICENSE](LICENSE) for details.
