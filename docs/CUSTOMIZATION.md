# Select and customize an application

For composed use, edit secure-ai-datacenter canonical cluster/default/release inputs, run its existing renderers, inspect the generated artifact manifest and copy only the manifest-owned files to their matching GitOps paths. Check byte equality before private enrichment. Generated files are not a second defaults source.

For independent use, choose an existing chart or application base, supply explicit values and a reviewed Argo Application with your repository/ref, cluster API and namespace. Build that source with `helm template` or `kubectl kustomize`. The complete selected management root is `clusters/example-management`; `clusters/example-sno` is only a storage fragment, not a standalone bootstrap root; optional platform features need their actual controllers, images, storage and credentials.

Runner labels/image and optional private kubeconfig repository/ref are explicit workflow variables. Private secret/CA overlays and API registration are pipeline prerequisites, not checked-in sample credentials. Never change the API server in a stored kubeconfig to an inferred site endpoint.

Before sync, inspect the Application source/destination and all nested sources. Runtime health and convergence are separately observed after the owning delivery pipeline. The local preparation has not performed that sync.

## Retained optional download and telemetry inputs

These adapters remain optional and require site inputs before activation.

- **NIM model download:** populate `apps/nim-llm/model-download-config.yaml` with
  the HTTPS model directory URL, exact filename list and trusted SHA256 sums
  (`<64 hex digits>  <filename>`, one entry per file). Obtain sums from the model
  producer; do not generate the expected sums from an unverified download. Keep
  `model-dir` aligned with the NIMService model path. The existing
  `webserver-credentials` runtime Secret supplies `username` and `password`.
  An empty/incomplete manifest fails before downloading. Retries validate every
  existing file, download into a private sibling directory and publish only after
  all hashes match. Interrupted downloads leave the prior directory intact.
  A downloader lock is removed on ordinary process exit; abrupt host loss can
  leave a stale lock, which the operator must reconcile before retrying.
- **Splunk dashboard updater:** populate `apps/splunk-reporter/settings.yaml` with
  the intended realm and chart IDs. The CronJob imports those nonsecret values;
  its existing `splunk-credentials` Secret supplies `api-token`. Missing mappings
  fail before writes. Failed or redirected updates return failure; a failure can
  occur after earlier chart writes, so the operation is not a transaction.
- **Intersight chart:** set `clusterName`, `bladeSerial`,
  `image.intersightOtel.repository` and `splunk.realm/apiUrl/ingestUrl` in the
  selected Application's Helm inputs. Endpoints must use HTTPS. Cluster
  attribution uses the exact declared name without appending a domain. Existing
  Intersight/Splunk runtime Secret references remain unchanged.

Local fixture tests exercise serialization, partial-download recovery and input
joins. They do not qualify an actual model source, account, image or live API.
