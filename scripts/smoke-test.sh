#!/usr/bin/env bash
# Fast sanity check — runs in ~10 seconds.
# Fails immediately on the first error so you know exactly what broke.
set -euo pipefail

PROM="http://localhost:${PROMETHEUS_PORT:-9090}"
AURA="http://localhost:${AURA_PORT:-3030}"
MCP_PROM="http://localhost:${MCP_PROMETHEUS_PORT:-8082}"
GRAFANA_PORT_ACTUAL=$(docker port grafana 3000 2>/dev/null | cut -d: -f2 | tr -d '[:space:]')
GRAFANA="http://localhost:${GRAFANA_PORT_ACTUAL}"

pass=0
fail=0

check() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" > /dev/null 2>&1; then
        echo "  ✓ $name"
        (( pass++ )) || true
    else
        echo "  ✗ $name"
        (( fail++ )) || true
    fi
}

echo "── Smoke Test ─────────────────────────────"

check "Prometheus /ready"   "curl -sf ${PROM}/-/ready"
check "Prometheus query"    "curl -sf '${PROM}/api/v1/query?query=up' | grep -q '\"status\":\"success\"'"
check "Aura /health"        "curl -sf ${AURA}/health"
check "Aura /v1/models"     "curl -sf ${AURA}/v1/models | grep -q 'aura'"
check "MCP-Prometheus /health" "curl -sf ${MCP_PROM}/health | grep -q '\"status\"'"
check "Grafana /api/health" "curl -sf ${GRAFANA}/api/health | grep -q 'ok'"
check "Frontend reachable"  "curl -sf http://localhost:${FRONTEND_PORT:-8080} -o /dev/null"

echo ""
echo "  Passed: $pass  Failed: $fail"
echo "───────────────────────────────────────────"

if (( fail > 0 )); then
    echo "SMOKE TEST FAILED — check logs: make logs"
    exit 1
fi
echo "Smoke test passed ✓"
