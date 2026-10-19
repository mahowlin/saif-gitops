# Inspect selected GitOps configuration

## Build the root and a child separately

Run from this checkout with the selected kubectl/Kustomize toolchain. These commands write local output and contact no API; Kustomize may fetch a remote base if the selected source declares one. The example paths below are real local paths.

```bash
ROOT_OUTPUT="$(mktemp)"
CHILD_OUTPUT="$(mktemp)"
kubectl kustomize clusters/example-management > "$ROOT_OUTPUT"
kubectl kustomize apps/hcp/management/parent-network/overlays/example-management > "$CHILD_OUTPUT"
```

The root output is a list of Argo Applications, not all their child resources. Inspect each `spec.source(s)`, source ref/path/chart, destination and sync policy. Build the specific changed child or Helm chart with the actual selected values; generic defaults are not the rendered site's final values. [Architecture navigation](../docs/ARCHITECTURE.md) links the chain.

## Read-only reconciliation checks

Use the intended management kubeconfig. These queries inspect status, not Secret data, and do not sync/apply.

```bash
: "${KUBECONFIG:?Set intended private management kubeconfig}"
oc config current-context
oc -n openshift-gitops get applications -o wide
: "${APPLICATION:?Set the actual child Application name}"
oc -n openshift-gitops get application "$APPLICATION" \
  -o jsonpath='{.spec.source.repoURL}{"\n"}{.spec.source.targetRevision}{"\n"}{.spec.source.path}{"\n"}{.spec.destination.server}{"\n"}{.status.sync.status}{" "}{.status.health.status}{"\n"}'
```

For multi-source Applications inspect all `spec.sources` through private operational handling. Sync changes use the owning delivery pipeline and reviewed source; local root rendering is not a deployment.

## Add or change an application/operator

Use an existing base/chart when it implements the selected behavior. For composed site values change Datacenter; for reusable behavior change the maintained base/chart. Select the parent Application in the appropriate root, explicit repo/ref/path, destination API/namespace and sync policy. Operator Subscriptions additionally need an actual available catalog/channel and the selected InstallPlan policy; do not assume every source is `certified-operators-local` or convert Manual approval to Automatic.

Build the changed local root and source using the procedure above. Review the exact diff and private runtime references before the site's normal GitOps delivery. A branch push is not an independent proof of sync or child health.

## Seal private inputs

The authoritative workflow is [`sealed-secrets-sync.yaml`](../.github/workflows/sealed-secrets-sync.yaml). It is manual, uses the selected runtime references/public sealing certificate, and requires explicit `allow_secret_access`. Dry run still reads configured Secrets/certificate. An authorized operator can request it with the existing contract:

```bash
: "${CUSTOMER_GITOPS_REPOSITORY:?Set the actual repository}"
: "${REVIEWED_BRANCH:?Set reviewed branch}"
gh workflow run sealed-secrets-sync.yaml --repo "$CUSTOMER_GITOPS_REPOSITORY" \
  --ref "$REVIEWED_BRANCH" -f allow_secret_access=true -f scope=all -f dry_run=true
```

This command accesses Secrets through the workflow; it is not offline validation. After the site's review, a separate invocation with `dry_run=false` permits the existing commit/push. Never store plaintext Secret input in source or print decoded values. The existing helper `scripts/seal-secret.sh` accepts key=value arguments, not a YAML filename; do not copy the retired filename invocation. For private-file sealing, use the selected public certificate with kubeseal through the site's private input handling instead of putting secret values in command history.

For a private YAML input file (not the key=value helper), encrypt with the selected public sealing certificate. Keep the input in private storage and write only encrypted output to a reviewed source path:

```bash
: "${PRIVATE_SECRET_FILE:?Set private plaintext YAML path}"
: "${PUBLIC_SEALING_CERT:?Set selected public certificate path}"
: "${SEALED_OUTPUT:?Set reviewed encrypted output path}"
umask 077
kubeseal --cert "$PUBLIC_SEALING_CERT" --format yaml \
  < "$PRIVATE_SECRET_FILE" > "$SEALED_OUTPUT"
```

The encrypted object's namespace/name and selected certificate must match its intended controller; inspect object metadata without decoding payloads.

## Offline secret-contract checks

Local helper dry-run reads metadata without reading runtime values or a certificate. This differs from the opt-in GitHub workflow dry-run, whose job environment and certificate step still access configured Secrets.

```bash
python .github/scripts/seal_manifest.py --dry-run --scope _common
python -m unittest discover -s tests -p test_seal_workflow.py -v
python -m unittest discover -s tests -p test_scoped_secret_contracts.py -v
python -m unittest discover -s tests -p test_secret_manifest_join.py -v
```

The synthetic tests do not perform real encryption/decryption, registration or cluster changes. A SealedSecret's scope, namespace, name and encrypted keys must match both declared metadata and its watched path. Optional `_gpu`/`_splunk` and retained hosted-writer scopes are not widened into `_common`.

## Selected Cilium chart checks

The chart consumes explicit Cilium device lists, a separate direct-routing device and a separately selected legacy BGP policy. The restart hook's image is a required chart input; Datacenter supplies it from declared `gitops.images.oseTools`. Receipt-resolved annotation identity also comes from the selected API group. No lab registry or namespace identity is substituted from a private checkout.

```bash
SELECTED_CLUSTER_ROOT=clusters/example-management \
  python -m unittest discover -s tests -p test_cilium_selected_consumer.py -v
```

This runs local Kustomize/Helm only. The test does not restart Cilium or establish live BGP.
