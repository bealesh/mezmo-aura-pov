#!/usr/bin/env bash
# Scenario: Error Spike
# Activates partial payment failure to generate a realistic 5xx spike
# without taking the service fully down (mimics a real-world flap).
set -euo pipefail

source "$(dirname "$0")/../configs/fault/scenarios.env"

FLAGD_JSON="$FLAGD_JSON_PATH"

if [[ ! -f "$FLAGD_JSON" ]]; then
    echo "✗ flagd config not found at $FLAGD_JSON — run: make bootstrap"
    exit 1
fi

command -v jq &>/dev/null || { echo "✗ jq required: brew install jq"; exit 1; }

echo "═══════════════════════════════════════════════"
echo "  Injecting ERROR SPIKE scenario"
echo "  Flag: paymentFailure (partial — ~50% of charges fail)"
echo "═══════════════════════════════════════════════"

tmp=$(mktemp)
jq '
  .flags.paymentFailure.defaultVariant = "on"
' "$FLAGD_JSON" > "$tmp" && mv "$tmp" "$FLAGD_JSON"

echo "✓ Flags updated"
echo ""
echo "What to expect:"
echo "  • ~50% of payment.ChargeRequest calls return errors"
echo "  • Intermittent 5xx responses on the checkout endpoint"
echo "  • Error rate anomaly visible in Prometheus within ~1 minute"
echo "  • Service does NOT go fully down — realistic partial failure"
echo ""
echo "Good Aura prompt: 'We're seeing intermittent checkout errors. What's happening?'"
