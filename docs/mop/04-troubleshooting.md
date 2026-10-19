# Diagnose reconciliation

First distinguish source/ref/path errors, rendering failures, destination registration/access, missing runtime CA/Secrets and workload/controller readiness. OutOfSync means desired/live divergence; Degraded means the Application or workload reports a health problem. A force sync does not repair missing images, catalogs, private dependencies or an invalid source. Fix the owning input and let the selected delivery process reconcile it.

[Architecture navigation](../ARCHITECTURE.md) identifies the real source/destination chain. [AGENTS execution](../../agents/operations.md) owns exact builds, status checks and secret-workflow invocation; do not duplicate those commands here.
