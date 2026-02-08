#!/bin/bash

# Copyright (c) 2026 Cisco and/or its affiliates.
# Licensed under the Cisco Sample Code License, Version 1.1
# See LICENSE in the project root.

# Generate Sealed Secrets shared key pair
# Run this ONCE to create the master key for all clusters
#
# Output:
#   sealed-secrets.key  - Private key (KEEP SECRET, add to GitHub Secrets)
#   sealed-secrets.crt  - Public key (used with kubeseal)

set -e

OUTPUT_DIR="${1:-.}"

echo "Generating Sealed Secrets key pair..."

openssl req -x509 -nodes -newkey rsa:4096 \
  -keyout "${OUTPUT_DIR}/sealed-secrets.key" \
  -out "${OUTPUT_DIR}/sealed-secrets.crt" \
  -subj "/CN=sealed-secrets/O=saif" \
  -days 3650

echo ""
echo "Generated files:"
echo "  ${OUTPUT_DIR}/sealed-secrets.key  (PRIVATE - keep secret!)"
echo "  ${OUTPUT_DIR}/sealed-secrets.crt  (PUBLIC - use with kubeseal)"
echo ""
echo "Next steps:"
echo ""
echo "1. Add to GitHub Secrets (base64 encoded):"
echo "   SEALED_SECRETS_CERT=\$(base64 -w0 ${OUTPUT_DIR}/sealed-secrets.crt)"
echo "   SEALED_SECRETS_KEY=\$(base64 -w0 ${OUTPUT_DIR}/sealed-secrets.key)"
echo ""
echo "2. Seal a secret:"
echo "   kubeseal --cert ${OUTPUT_DIR}/sealed-secrets.crt --format yaml < secret.yaml > sealedsecret.yaml"
echo ""
echo "3. Store backup of sealed-secrets.key in a secure location!"
echo "   If lost, all SealedSecrets must be re-encrypted."
