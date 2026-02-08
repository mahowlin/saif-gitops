#!/usr/bin/env bash

# Copyright (c) 2026 Cisco and/or its affiliates.
# Licensed under the Cisco Sample Code License, Version 1.1
# See LICENSE in the project root.

# Validate SealedSecret names match expected patterns
#
# This script ensures SealedSecrets have correct names before deployment.
# Run in CI or before committing to catch naming issues early.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEALED_SECRETS_DIR="${SCRIPT_DIR}/../apps/sealed-secrets"

# Expected secret names per namespace
declare -A EXPECTED_SECRETS
EXPECTED_SECRETS["hubble-timescape"]="hubble-timescape-ingester-creds hubble-timescape-migrate-creds hubble-timescape-server-creds hubble-timescape-analyzer-creds hubble-timescape-trimmer-creds vector-push-credentials"
EXPECTED_SECRETS["nim-llm"]="ngc-api-key"
EXPECTED_SECRETS["splunk-otel"]="splunk-otel-secret"
EXPECTED_SECRETS["intersight-otel"]="intersight-api-credentials splunk-credentials"

ERRORS=0

echo "Validating SealedSecrets..."
echo ""

# Check each namespace directory
for ns_dir in "$SEALED_SECRETS_DIR"/*/; do
    [ -d "$ns_dir" ] || continue

    ns=$(basename "$ns_dir")
    echo "Checking namespace: $ns"

    # Skip if no expected secrets defined
    if [ -z "${EXPECTED_SECRETS[$ns]:-}" ]; then
        echo "  ⚠️  No expected secrets defined for namespace '$ns'"
        continue
    fi

    # Check each SealedSecret file
    for file in "$ns_dir"/*.yaml; do
        [ -f "$file" ] || continue

        # Extract secret name from metadata.name
        secret_name=$(grep -E '^\s+name:' "$file" | head -1 | awk '{print $2}' | tr -d '"')

        if [ -z "$secret_name" ]; then
            echo "  ❌ Cannot extract name from: $(basename "$file")"
            ERRORS=$((ERRORS + 1))
            continue
        fi

        # Check if name is in expected list
        expected="${EXPECTED_SECRETS[$ns]}"
        if echo "$expected" | grep -qw "$secret_name"; then
            echo "  ✅ $secret_name"
        else
            echo "  ❌ $secret_name (unexpected name!)"
            echo "     Expected one of: $expected"
            ERRORS=$((ERRORS + 1))
        fi
    done

    echo ""
done

# Summary
if [ $ERRORS -gt 0 ]; then
    echo "❌ Validation failed with $ERRORS error(s)"
    echo ""
    echo "Fix the SealedSecret names or update EXPECTED_SECRETS in this script."
    echo "Run: gh workflow run sealed-secrets-sync.yaml -f secrets_to_seal=all"
    exit 1
else
    echo "✅ All SealedSecrets have valid names"
fi
