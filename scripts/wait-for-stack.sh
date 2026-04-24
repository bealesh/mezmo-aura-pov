#!/usr/bin/env bash
# Wait for all demo services to be healthy before proceeding.
set -euo pipefail

TIMEOUT=${TIMEOUT:-300}   # seconds
INTERVAL=5

PROMETHEUS_URL="${PROMETHEUS_PORT:-9090}"
AURA_URL="http://localhost:${AURA_PORT:-3030}"
FRONTEND_URL="http://localhost:${FRONTEND_PORT:-8080}"

start=$(date +%s)

wait_for() {
    local name="$1"
    local url="$2"
    local elapsed=0
    echo -n "  Waiting for $name at $url"
    while ! curl -sf "$url" > /dev/null 2>&1; do
        elapsed=$(( $(date +%s) - start ))
        if (( elapsed >= TIMEOUT )); then
            echo ""
            echo "✗ TIMEOUT after ${TIMEOUT}s waiting for $name"
            return 1
        fi
        echo -n "."
        sleep $INTERVAL
    done
    echo " ✓"
}

echo "╔══════════════════════════════════════════╗"
echo "║  Waiting for demo stack to be healthy    ║"
echo "╚══════════════════════════════════════════╝"

# OTel Demo services
wait_for "Prometheus"   "http://localhost:${PROMETHEUS_PORT:-9090}/-/ready"
wait_for "Grafana"      "http://localhost:${GRAFANA_PORT:-3000}/api/health"
wait_for "Frontend"     "${FRONTEND_URL}"

# Our services
wait_for "Aura"         "${AURA_URL}/health"
wait_for "MCP-Prometheus" "http://localhost:${MCP_PROMETHEUS_PORT:-8082}/health"

elapsed=$(( $(date +%s) - start ))
echo ""
echo "✓ All services healthy after ${elapsed}s"
