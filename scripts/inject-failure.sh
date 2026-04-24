#!/usr/bin/env bash
# Scenario: Failing Service
# Activates payment + cart failure flags in flagd.
# flagd watches the JSON file and reloads within ~1s.
set -euo pipefail

source "$(dirname "$0")/../configs/fault/scenarios.env"

FLAGD_JSON="$FLAGD_JSON_PATH"

if [[ ! -f "$FLAGD_JSON" ]]; then
    echo "✗ flagd config not found at $FLAGD_JSON"
    echo "  Have you run: make bootstrap?"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "✗ jq is required but not installed. Install with: brew install jq"
    exit 1
fi

echo "═══════════════════════════════════════════════"
echo "  Injecting FAILING SERVICE scenario"
echo "  Flags: paymentFailure, paymentUnreachable, cartFailure"
echo "═══════════════════════════════════════════════"

# Atomically update the flagd JSON
tmp=$(mktemp)
jq '
  .flags.paymentFailure.defaultVariant    = "on" |
  .flags.paymentUnreachable.defaultVariant = "on" |
  .flags.cartFailure.defaultVariant       = "on"
' "$FLAGD_JSON" > "$tmp" && mv "$tmp" "$FLAGD_JSON"

echo "✓ Flags updated — flagd will reload within 1-2 seconds"
echo ""
echo "What to expect:"
echo "  • Payment service begins rejecting charges"
echo "  • Cart service becomes unavailable"
echo "  • Frontend checkout flow returns 5xx errors"
echo "  • Error rate spike visible in Prometheus within ~30s"
echo ""
echo "Now run: make query"
echo "Or ask Aura: 'What's causing checkout failures right now?'"
