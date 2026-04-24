#!/usr/bin/env bash
# Validates Prometheus is healthy and returning OTel Demo metrics.
set -euo pipefail

PROM="http://localhost:${PROMETHEUS_PORT:-9090}"
PASS=0; FAIL=0

ok()   { echo "  ✓ $1"; (( PASS++ )) || true; }
fail() { echo "  ✗ $1"; (( FAIL++ )) || true; }

prom_query() {
    curl -sf "${PROM}/api/v1/query?query=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1")"
}

has_data() {
    python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['status'] == 'success'
assert len(d['data']['result']) > 0
"
}

echo "── Prometheus Tests ───────────────────────"

# Connectivity
curl -sf "${PROM}/-/ready" > /dev/null 2>&1 && ok "Prometheus /ready" || { fail "Prometheus /ready"; exit 1; }
curl -sf "${PROM}/-/healthy" > /dev/null 2>&1 && ok "Prometheus /healthy" || fail "Prometheus /healthy"

# Core OTel metrics are being scraped
for metric in \
    "up" \
    "http_server_request_duration_seconds_count" \
    "process_cpu_seconds_total"; do
    if prom_query "$metric" 2>/dev/null | has_data 2>/dev/null; then
        ok "Metric available: $metric"
    else
        fail "Metric missing: $metric (OTel Demo may still be starting)"
    fi
done

# At least 5 targets are up
targets=$(curl -sf "${PROM}/api/v1/targets" 2>/dev/null)
up_count=$(echo "$targets" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(sum(1 for t in d['data']['activeTargets'] if t['health']=='up'))
" 2>/dev/null || echo 0)

if (( up_count >= 5 )); then
    ok "Active scrape targets: $up_count"
else
    fail "Too few active targets: $up_count (expected ≥5)"
fi

echo "  Results: $PASS passed, $FAIL failed"
(( FAIL == 0 )) || exit 1
