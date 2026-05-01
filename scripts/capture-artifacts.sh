#!/usr/bin/env bash
# Capture screenshots and metric exports as demo insurance.
# Run this AFTER injecting a fault so you have evidence for backup slides.
set -euo pipefail

ARTIFACTS="$(dirname "$0")/../artifacts"
SCREENSHOTS="${ARTIFACTS}/screenshots"
TS=$(date +%Y%m%d-%H%M%S)

PROM="http://localhost:${PROMETHEUS_PORT:-9090}"
GRAFANA="http://localhost:${GRAFANA_PORT:-3000}"

mkdir -p "$SCREENSHOTS"

echo "Capturing artifacts at $TS..."

# Export Prometheus metric snapshots as JSON
echo "  → Exporting Prometheus metrics..."

curl -sf "${PROM}/api/v1/query?query=sum+by+(service_name)(rate(http_server_request_duration_seconds_count%7Bhttp_response_status_code%3D~%225..%22%7D%5B5m%5D))" \
  -o "${SCREENSHOTS}/error-rates-${TS}.json" && echo "    ✓ error-rates-${TS}.json"

curl -sf "${PROM}/api/v1/query?query=histogram_quantile(0.95%2C+sum+by+(le%2Cservice_name)(rate(http_server_request_duration_seconds_bucket%5B5m%5D)))" \
  -o "${SCREENSHOTS}/latency-p95-${TS}.json" && echo "    ✓ latency-p95-${TS}.json"

curl -sf "${PROM}/api/v1/targets" \
  -o "${SCREENSHOTS}/targets-${TS}.json" && echo "    ✓ targets-${TS}.json"

# Browser screenshot via puppeteer if available
if command -v npx &>/dev/null; then
    echo "  → Attempting browser screenshots via puppeteer..."

    for page in \
        "grafana:${GRAFANA_PORT:-3000}:Grafana" \
        "prometheus:${PROMETHEUS_PORT:-9090}:Prometheus" \
        "frontend:${FRONTEND_PORT:-8080}:Frontend"; do

        IFS=: read -r svc port label <<< "$page"
        label_lower=$(echo "$label" | tr '[:upper:]' '[:lower:]')
        npx --yes puppeteer screenshot \
            "http://localhost:${port}" \
            "${SCREENSHOTS}/${label_lower}-${TS}.png" \
            --viewport "1920x1080" 2>/dev/null \
            && echo "    ✓ ${label_lower}-${TS}.png" \
            || echo "    ⚠ Could not screenshot ${label} (puppeteer may not be available)"
    done
else
    echo "  ⚠ npx not found — skipping browser screenshots"
    echo "    Install Node.js for automatic screenshots, or capture manually:"
    echo "      Grafana:    ${GRAFANA}"
    echo "      Prometheus: ${PROM}/graph"
fi

echo ""
echo "✓ Artifacts saved to: artifacts/screenshots/"
echo "  Use these as backup slides if live demo gremlins strike."
