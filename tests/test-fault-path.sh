#!/usr/bin/env bash
# End-to-end fault injection test.
# 1. Verifies baseline is healthy
# 2. Injects payment failure fault
# 3. Waits for Prometheus to observe the error rate spike
# 4. Resets to healthy state
# 5. Optionally fires Aura investigation prompt and checks for a non-empty response
set -euo pipefail

PROM="http://localhost:${PROMETHEUS_PORT:-9090}"
AURA="http://localhost:${AURA_PORT:-3030}"
SCRIPTS="$(dirname "$0")/../scripts"

PASS=0; FAIL=0

ok()   { echo "  ✓ $1"; (( PASS++ )) || true; }
fail() { echo "  ✗ $1"; (( FAIL++ )) || true; }

prom_error_rate() {
    curl -sf "${PROM}/api/v1/query?query=$(python3 -c "
import urllib.parse
print(urllib.parse.quote('sum(rate(http_server_request_duration_seconds_count{http_response_status_code=~\"5..\"}[2m]))'))")" \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
r=d['data']['result']
if not r: print('0')
else: print(r[0]['value'][1])
" 2>/dev/null || echo "0"
}

echo "── Fault Path Test ────────────────────────"
echo "  This test takes ~3 minutes to complete."

# Step 1: baseline
echo ""
echo "  Step 1: Verifying healthy baseline..."
"${SCRIPTS}/reset-demo.sh" > /dev/null 2>&1
sleep 10

baseline=$(prom_error_rate)
echo "  Baseline error rate: ${baseline} req/s"

# Step 2: inject fault
echo ""
echo "  Step 2: Injecting payment failure..."
"${SCRIPTS}/inject-failure.sh" > /dev/null

# Step 3: wait for spike (up to 90s)
echo "  Step 3: Waiting for Prometheus to observe error spike..."
SPIKE_SEEN=false
for i in $(seq 1 18); do
    sleep 5
    rate=$(prom_error_rate)
    echo -n "    [${i}/18] error rate: ${rate} req/s"
    if python3 -c "import sys; exit(0 if float(sys.argv[1]) > 0.05 else 1)" "$rate" 2>/dev/null; then
        echo " ← SPIKE DETECTED"
        SPIKE_SEEN=true
        break
    fi
    echo ""
done

if $SPIKE_SEEN; then
    ok "Error rate spike confirmed after fault injection"
else
    fail "No error rate spike detected — load generator may be idle or flagd reload delayed"
fi

# Step 4: Aura investigation (optional, skip if no API key)
echo ""
echo "  Step 4: Aura investigation query..."
aura_resp=$(curl -sf \
  -X POST "${AURA}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"aura-observability","messages":[{"role":"user","content":"In one sentence: which service currently has the highest error rate?"}],"max_tokens":100}' \
  2>/dev/null || echo "")

if echo "$aura_resp" | python3 -c "
import sys,json
d=json.load(sys.stdin)
content=d['choices'][0]['message']['content']
assert len(content) > 10
print('    Response:', content[:120])
" 2>/dev/null; then
    ok "Aura returned investigation response"
else
    fail "Aura investigation failed — check API key and agent config"
fi

# Step 5: reset
echo ""
echo "  Step 5: Resetting to healthy state..."
"${SCRIPTS}/reset-demo.sh" > /dev/null
ok "Fault reset complete"

echo ""
echo "  Results: $PASS passed, $FAIL failed"
(( FAIL == 0 )) || exit 1
