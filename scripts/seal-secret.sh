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

set -e

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

# Build stringData section
STRING_DATA=""
for KV in "$@"; do
  KEY="${KV%%=*}"
  VALUE="${KV#*=}"
  STRING_DATA+="  ${KEY}: \"${VALUE}\"\n"
done

# Create temporary plain secret
PLAIN_SECRET=$(mktemp)
cat > "$PLAIN_SECRET" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
type: Opaque
stringData:
$(echo -e "$STRING_DATA")
EOF

# Seal it
echo "Sealing secret ${SECRET_NAME} in namespace ${NAMESPACE}..."
kubeseal --cert "$CERT_FILE" --format yaml < "$PLAIN_SECRET"

# Cleanup
rm -f "$PLAIN_SECRET"
