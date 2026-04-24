#!/usr/bin/env bash
# Validates Aura is running, has agents loaded, and can reach the Prometheus MCP.
set -euo pipefail

AURA="http://localhost:${AURA_PORT:-3030}"
PASS=0; FAIL=0

ok()   { echo "  ✓ $1"; (( PASS++ )) || true; }
fail() { echo "  ✗ $1"; (( FAIL++ )) || true; }

echo "── Aura Health Tests ──────────────────────"

# /health endpoint
curl -sf "${AURA}/health" > /dev/null 2>&1 && ok "Aura /health" || { fail "Aura /health — not reachable"; exit 1; }

# /v1/models lists our agent
models_json=$(curl -sf "${AURA}/v1/models" 2>/dev/null)
if echo "$models_json" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ids=[m['id'] for m in d.get('data',[])]
assert any('aura' in i or 'observability' in i for i in ids), f'No aura model in {ids}'
" 2>/dev/null; then
    ok "Aura agent 'aura-observability' registered"
else
    fail "Agent not found in /v1/models — check configs/aura/config.toml"
fi

# Basic inference round-trip (no tool calls, just LLM connectivity)
response=$(curl -sf \
  -X POST "${AURA}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"aura-observability","messages":[{"role":"user","content":"Reply with exactly: READY"}],"max_tokens":10}' \
  2>/dev/null)

if echo "$response" | python3 -c "
import sys,json
d=json.load(sys.stdin)
content=d['choices'][0]['message']['content']
assert len(content) > 0
" 2>/dev/null; then
    ok "Aura LLM inference working"
else
    fail "Aura inference failed — check OPENAI_API_KEY or ANTHROPIC_API_KEY"
fi

# Confirm MCP Prometheus tool is discoverable (requires Aura tool listing if available)
mcp_health=$(curl -sf "http://localhost:${MCP_PROMETHEUS_PORT:-8082}/health" 2>/dev/null || echo "")
if echo "$mcp_health" | grep -q '"status"'; then
    ok "MCP-Prometheus reachable from host"
else
    fail "MCP-Prometheus not responding (Aura may lack tool access)"
fi

echo "  Results: $PASS passed, $FAIL failed"
(( FAIL == 0 )) || exit 1
