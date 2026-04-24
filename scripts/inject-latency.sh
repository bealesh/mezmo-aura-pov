#!/usr/bin/env bash
# Scenario: High Latency
# Overloads the Kafka queue (consumer-side delays) and slows image loads.
# Users see slow checkout completions and image rendering.
set -euo pipefail

source "$(dirname "$0")/../configs/fault/scenarios.env"

FLAGD_JSON="$FLAGD_JSON_PATH"

if [[ ! -f "$FLAGD_JSON" ]]; then
    echo "✗ flagd config not found at $FLAGD_JSON — run: make bootstrap"
    exit 1
fi

command -v jq &>/dev/null || { echo "✗ jq required: brew install jq"; exit 1; }

echo "═══════════════════════════════════════════════"
echo "  Injecting HIGH LATENCY scenario"
echo "  Flags: kafkaQueueProblems, imageSlowLoad"
echo "═══════════════════════════════════════════════"

tmp=$(mktemp)
jq '
  .flags.kafkaQueueProblems.defaultVariant = "on" |
  .flags.imageSlowLoad.defaultVariant      = "on"
' "$FLAGD_JSON" > "$tmp" && mv "$tmp" "$FLAGD_JSON"

echo "✓ Flags updated"
echo ""
echo "What to expect:"
echo "  • Kafka consumer introduces processing delays (5-10s)"
echo "  • Product images take 5-10s to load"
echo "  • P95 latency climbs across checkout and recommendation flows"
echo "  • No hard errors — latency is the only signal"
echo ""
echo "Good Aura prompt: 'Why is checkout so slow? Investigate latency in the last 10 minutes.'"
