#!/usr/bin/env bash
# Comprehensive stack health test. Checks all service endpoints
# and validates data integrity (not just port reachability).
set -euo pipefail

PASS=0
FAIL=0
ERRORS=()

ok()   { echo "  ✓ $1"; (( PASS++ )) || true; }
fail() { echo "  ✗ $1"; ERRORS+=("$1"); (( FAIL++ )) || true; }

check_http() {
    local name="$1"; local url="$2"; local expected="${3:-}"
    local out
    out=$(curl -sf "$url" 2>&1) || { fail "$name — unreachable ($url)"; return; }
    if [[ -n "$expected" ]] && ! echo "$out" | grep -q "$expected"; then
        fail "$name — response missing '$expected'"
    else
        ok "$name"
    fi
}

echo "══════════════════════════════════════════"
echo "  Stack Integration Test"
echo "══════════════════════════════════════════"

echo ""
echo "── OTel Demo ──────────────────────────────"
check_http "Frontend HTTP 200"      "http://localhost:${FRONTEND_PORT:-8080}"
check_http "Prometheus ready"       "http://localhost:${PROMETHEUS_PORT:-9090}/-/ready"
check_http "Grafana health"         "http://localhost:${GRAFANA_PORT:-3000}/api/health" '"ok"'
check_http "Jaeger UI"              "http://localhost:${JAEGER_UI_PORT:-16686}"
check_http "Load Generator"        "http://localhost:${LOCUST_WEB_PORT:-8089}"

echo ""
echo "── Aura + MCP ─────────────────────────────"
check_http "Aura /health"           "http://localhost:${AURA_PORT:-3030}/health"
check_http "Aura /v1/models"        "http://localhost:${AURA_PORT:-3030}/v1/models" "aura"
check_http "MCP-Prometheus /health" "http://localhost:${MCP_PROMETHEUS_PORT:-8082}/health" '"status"'

echo ""
echo "── Data Validation ────────────────────────"
# Prometheus has live OTLP metric data (OTel demo is push-based, no scrape targets)
prom_result=$(curl -sf "http://localhost:${PROMETHEUS_PORT:-9090}/api/v1/query?query=http_server_request_duration_seconds_count" 2>/dev/null)
if echo "$prom_result" | python3 -c "import sys,json; d=json.load(sys.stdin); assert len(d['data']['result'])>0" 2>/dev/null; then
    ok "Prometheus receiving live OTLP metrics"
else
    fail "Prometheus has no OTLP metrics yet (services may still be warming up)"
fi

# Aura lists at least one agent model
models=$(curl -sf "http://localhost:${AURA_PORT:-3030}/v1/models" 2>/dev/null)
if echo "$models" | python3 -c "import sys,json; d=json.load(sys.stdin); assert len(d.get('data',[])) > 0" 2>/dev/null; then
    ok "Aura has at least one agent loaded"
else
    fail "Aura returned no models"
fi

echo ""
echo "══════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
    echo "  Failed checks:"
    for e in "${ERRORS[@]}"; do echo "    - $e"; done
    echo "══════════════════════════════════════════"
    exit 1
fi
echo "  All checks passed ✓"
echo "══════════════════════════════════════════"
