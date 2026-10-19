# Secure AI GitOps: agent entry point

Hold reusable Kubernetes resources and the rendered selections reconciled by Argo CD. See [README](README.md) for the human composition.

## Route the task

| Goal | Authoritative editable input | Procedure | Actual output | Relevant check | Next owner |
|---|---|---|---|---|---|
| Change cluster intent or destination selection | manifest-listed renderer outputs: edit their Datacenter inputs | [operations](agents/operations.md) | root → Application → overlay/chart → destination | build root and actual selected child | Datacenter then GitOps |
| Maintain reusable runtime components | unmarked `apps/` bases, charts, helper/workflow mechanics | [architecture](docs/ARCHITECTURE.md) | reviewed resource/chart change | selected Helm/Kustomize builds and helper tests | Argo reconciliation owner |
| Supply encrypted configuration | private runtime references and selected secret metadata | [secret contract](docs/SECRET_MANAGEMENT.md) | encrypted manifests only | `test_seal_workflow.py`; inspect exact event/effects | secret/cluster owner |

## Toolchain and execution boundary

Use Kustomize/kubectl, Helm for selected charts and Python with PyYAML. `oc` reads require the intended API context. A root build neither builds every remote chart nor registers clusters. Manual sealing can read configured Secrets even in dry-run mode; writing runs can commit and reconcile. No plaintext secret belongs in Git. Verify sync policy and actual destination before any authorized reconciliation; local checks are not a sync.

Keep exact executable sequences in the linked procedure; update its input/output/check handoff when an interface changes. Record unknown runtime facts as unknown rather than inferring them from local success.
