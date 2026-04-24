#!/usr/bin/env bash
# Fire the canned investigation prompt at Aura and stream the response.
# Designed to be run live during the demo after fault injection.
set -euo pipefail

AURA_URL="http://localhost:${AURA_PORT:-3030}"
PROMPT_FILE="$(dirname "$0")/../configs/aura/prompts/investigate.txt"

if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "✗ Prompt file not found: $PROMPT_FILE"
    exit 1
fi

PROMPT=$(cat "$PROMPT_FILE")

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Sending investigation prompt to Aura (streaming)            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "PROMPT:"
echo "────────────────────────────────────────────────────────────────"
echo "$PROMPT"
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "AURA RESPONSE:"
echo "────────────────────────────────────────────────────────────────"

# Stream the response — delta content chunks are printed as they arrive
curl -sN \
  -X POST "${AURA_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg model "aura-observability" \
    --arg content "$PROMPT" \
    '{
      model: $model,
      stream: true,
      messages: [{role: "user", content: $content}]
    }'
  )" \
  | while IFS= read -r line; do
      # SSE lines look like: data: {...}
      [[ "$line" == data:* ]] || continue
      data="${line#data: }"
      [[ "$data" == "[DONE]" ]] && break
      # Extract and print the delta content
      delta=$(echo "$data" | jq -r '.choices[0].delta.content // empty' 2>/dev/null)
      [[ -n "$delta" ]] && printf "%s" "$delta"
  done

echo ""
echo ""
echo "────────────────────────────────────────────────────────────────"
echo "✓ Investigation complete"
echo ""
echo "Next steps:"
echo "  • make recover    — restore healthy state"
echo "  • make query      — run again (fresh conversation)"
echo "  • Edit configs/aura/prompts/investigate.txt to customize prompt"
