# Supply encrypted configuration

SealedSecret resources can be committed after encryption with the selected public sealing certificate. Their private sealing key and original plaintext remain outside Git. The existing manual workflow reads configured runtime Secrets; dry run is not secret-free and a writing run may commit/push encrypted output. Check controller/object status without decoding Secret values into reports.

[Architecture navigation](../ARCHITECTURE.md) identifies the real source/destination chain. [AGENTS execution](../../agents/operations.md) owns exact builds, status checks and secret-workflow invocation; do not duplicate those commands here.
