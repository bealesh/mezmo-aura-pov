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

# OTel demo uses OTLP push — no scrape targets, check for pushed metrics instead
for metric in \
    "http_server_request_duration_seconds_count" \
    "rpc_server_duration_milliseconds_count"; do
    if prom_query "$metric" 2>/dev/null | has_data 2>/dev/null; then
        ok "OTLP metric flowing: $metric"
    else
        fail "OTLP metric missing: $metric (services may still be warming up)"
    fi
done

# Confirm at least 3 distinct service_name values are present across all metrics
service_count=$(curl -sf "${PROM}/api/v1/label/service_name/values" \
    2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(len(d.get('data', [])))
" 2>/dev/null || echo 0)

if (( service_count >= 3 )); then
    ok "Services reporting HTTP metrics: $service_count"
else
    fail "Too few services reporting HTTP metrics: $service_count (expected ≥3, demo may still be warming up)"
fi

echo "  Results: $PASS passed, $FAIL failed"
(( FAIL == 0 )) || exit 1
