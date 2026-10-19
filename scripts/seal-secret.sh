#!/bin/bash
# Copyright (c) 2026 Cisco and/or its affiliates.
# Licensed under the Cisco Sample Code License, Version 1.1
# See LICENSE in the project root.
# Seal a secret using the shared cluster key
#
# Usage:
#   ./seal-secret.sh <namespace> <secret-name> <key>=<value> [<key>=<value> ...]
#
# Example:
#   ./seal-secret.sh nim-llm ngc-api-key NGC_API_KEY=nvapi-xxx
#   ./seal-secret.sh hubble-timescape clickhouse-creds CLICKHOUSE_PASSWORD=mypassword

set -euo pipefail

CERT_FILE="${SEALED_SECRETS_CERT:-sealed-secrets.crt}"

if [ ! -f "$CERT_FILE" ]; then
  echo "Error: Certificate file not found: $CERT_FILE"
  echo "Set SEALED_SECRETS_CERT or run generate-sealed-secrets-key.sh first"
  exit 1
fi

if [ $# -lt 3 ]; then
  echo "Usage: $0 <namespace> <secret-name> <key>=<value> [<key>=<value> ...]"
  echo ""
  echo "Example:"
  echo "  $0 nim-llm ngc-api-key NGC_API_KEY=nvapi-xxx"
  exit 1
fi

NAMESPACE="$1"
SECRET_NAME="$2"
shift 2

# JSON is a Kubernetes Secret serialization and preserves arbitrary string values.
# Stream plaintext directly to kubeseal; no plaintext temporary file survives failure.
python3 - "$NAMESPACE" "$SECRET_NAME" "$@" <<'PYTHON' | kubeseal --cert "$CERT_FILE" --format yaml
import json
import sys

namespace, name, *pairs = sys.argv[1:]
data = {}
for pair in pairs:
    key, separator, value = pair.partition("=")
    if not separator or not key or key in data:
        raise SystemExit("Secret keys must be nonempty, unique key=value pairs")
    data[key] = value
json.dump({"apiVersion": "v1", "kind": "Secret",
           "metadata": {"name": name, "namespace": namespace},
           "type": "Opaque", "stringData": data}, sys.stdout)
PYTHON
