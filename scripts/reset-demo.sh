#!/usr/bin/env bash
# Restore the demo to a fully healthy baseline.
# Turns off all fault flags so the next scenario starts clean.
set -euo pipefail

source "$(dirname "$0")/../configs/fault/scenarios.env"

FLAGD_JSON="$FLAGD_JSON_PATH"

if [[ ! -f "$FLAGD_JSON" ]]; then
    echo "✗ flagd config not found at $FLAGD_JSON — run: make bootstrap"
    exit 1
fi

command -v jq &>/dev/null || { echo "✗ jq required: brew install jq"; exit 1; }

echo "Resetting all fault flags to OFF..."

# Build a jq expression that sets every known flag to "off"
JQ_EXPR=''
for flag in $ALL_FAULT_FLAGS; do
    JQ_EXPR="${JQ_EXPR} | .flags.${flag}.defaultVariant = \"off\""
done
# Strip leading " | "
JQ_EXPR="${JQ_EXPR:3}"

tmp=$(mktemp)
jq "$JQ_EXPR" "$FLAGD_JSON" > "$tmp" && mv "$tmp" "$FLAGD_JSON"

echo "✓ All flags reset — system returning to healthy baseline"
echo "  Allow ~60s for metrics to stabilize before the next scenario"
