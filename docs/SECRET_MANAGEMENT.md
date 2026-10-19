# Supply secrets privately

Keep kubeconfigs, registry credentials, sealing keys and CA files in your approved private delivery process. Public example manifests do not contain those values. A SealedSecret is encrypted configuration; its private sealing key must remain private.

## Seal Secrets workflow

`sealed-secrets-sync.yaml` has only `workflow_dispatch`; publishing or pushing a
branch cannot run it. Customer-managed use retains `RUNNER_LABELS` (JSON runner
labels), `RUNNER_CONTAINER_IMAGE`, the existing Secret references and public
sealing certificate contract. Configure those privately through the owning
process. No repository settings or Secrets are supplied by this source tree.

After an authorized operator reviews `apps/sealed-secrets/secrets-manifest.yaml`,
invoke **Seal Secrets** manually on the selected branch with
`allow_secret_access=true`, an explicit `scope`, and `dry_run=true` first. Without
the explicit access opt-in the job is skipped. Dry run still reads the selected
configured Secrets and certificate, but does not write generated source. After
review, a separate authorized manual invocation with `dry_run=false` permits the
existing commit/push step. Do not assume a workflow dry run is secret-free. [The agent procedure](../agents/operations.md#seal-private-inputs) owns the exact invocation.

The metadata file contains scope, namespace, object name, encrypted key names and GitHub Secret references, never their values. The helper emits only the selected scoped encrypted outputs; the workflow stages those exact paths and removes its per-run certificate even on failure. Retained hosted-writer scopes remain separate declared owners.

The focused local workflow validation is listed in [AGENTS](../AGENTS.md#validation); it reads YAML and parses shell syntax without workflow dispatch or Secret access.
