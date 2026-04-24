# Troubleshooting Guide

## Quick Diagnosis

```bash
make ps           # Are all containers running?
make smoke        # Which specific check is failing?
make logs         # What are Aura and MCP-Prometheus saying?
make logs-otel    # What is the OTel Demo saying?
```

---

## Common Issues

### `make up` fails — "network opentelemetry-demo not found"

**Cause**: The OTel Demo hasn't started yet, so the shared network doesn't exist.

**Fix**:
```bash
cd otel-demo && docker compose up -d
# Wait for network to be created, then:
docker compose up -d --build
```

The Makefile's `up` target handles this order, but if you run `docker compose up -d` directly in the project root it will fail if otel-demo isn't running.

---

### Aura container exits immediately

**Cause A**: Missing or invalid API key.

**Fix**: Check `.env` for `OPENAI_API_KEY` (or `ANTHROPIC_API_KEY`). Verify the key is valid:
```bash
curl https://api.openai.com/v1/models -H "Authorization: Bearer $OPENAI_API_KEY" | jq '.data[0].id'
```

**Cause B**: `config.toml` syntax error.

**Fix**: Validate TOML syntax:
```bash
docker compose logs aura | grep -i "error\|toml\|config"
```

**Cause C**: Aura binary failed to build.

**Fix**: Rebuild with verbose output:
```bash
docker compose build --no-cache aura 2>&1 | tail -50
```
Rust compilation takes ~8 minutes cold. Subsequent builds use cache.

---

### `make query` returns empty or "connection refused"

**Cause**: Aura container isn't healthy yet.

**Fix**: Wait for the healthcheck:
```bash
watch docker compose ps
# Wait until aura shows "(healthy)"
```

---

### MCP-Prometheus /health returns `"prometheus_reachable": false`

**Cause**: The MCP server can't reach `http://prometheus:9090` inside the `opentelemetry-demo` network.

**Fix**:
1. Verify the OTel Demo Prometheus is running: `cd otel-demo && docker compose ps | grep prometheus`
2. Verify the MCP container is on the right network:
   ```bash
   docker inspect mcp-prometheus | jq '.[0].NetworkSettings.Networks | keys'
   # Should include "opentelemetry-demo"
   ```
3. If missing the network, restart our services:
   ```bash
   docker compose down && docker compose up -d
   ```

---

### Fault injection has no effect (error rates don't climb)

**Cause A**: Load generator isn't running or has no users active.

**Fix**: Check Locust at http://localhost:8089. If "0 users", click "Start" and set user count to 10.

**Cause B**: flagd didn't reload the JSON.

**Fix**: Verify the flag is set:
```bash
jq '.flags.paymentFailure.defaultVariant' otel-demo/src/flagd/demo.flagd.json
# Should output "on"
```
If it shows "off", re-run `make fault-fail`. If it shows "on" but errors aren't climbing, wait 60s — Prometheus scrapes every 60 seconds by default.

**Cause C**: jq not installed.

**Fix**: `brew install jq` (macOS) or `apt-get install jq` (Linux).

---

### `make reset` / `recover` doesn't fully clear faults

**Cause**: The jq expression silently skipped a flag name (typo in `scenarios.env`).

**Fix**: Manually reset by restoring the original flagd config:
```bash
cd otel-demo && git checkout src/flagd/demo.flagd.json
```

---

### Aura returns tool call errors (MCP connection refused)

**Cause**: The MCP-Prometheus container isn't running or failed its healthcheck.

**Fix**:
```bash
docker compose ps mcp-prometheus    # Check status
docker compose logs mcp-prometheus  # Check startup errors
docker compose restart mcp-prometheus
```

---

### Open WebUI doesn't show "aura-observability" model

**Cause A**: Open WebUI is using a cached model list.

**Fix**: In Open WebUI, go to Settings → Models → Refresh. Or hard-refresh the browser.

**Cause B**: Aura URL configured incorrectly.

**Fix**: Verify the `OPENAI_API_BASE_URL` in docker-compose.yml is `http://aura:3030/v1` (internal Docker hostname, not localhost).

---

### Docker build fails for Aura (Rust compile error)

**Cause**: Network issue cloning the Aura repo during build.

**Fix**:
```bash
# Check connectivity from Docker build context
docker build --no-cache --progress=plain ./build/aura 2>&1 | grep -A5 "git clone"
```

If the clone fails, try building with a specific ref:
```bash
docker build --build-arg AURA_REF=main ./build/aura
```

---

## Port Conflicts

If any of these ports are in use, override them in `.env`:

| Service | Default Port | Env Var |
|---|---|---|
| Frontend | 8080 | `FRONTEND_PORT` |
| Aura | 3030 | `AURA_PORT` |
| Prometheus | 9090 | `PROMETHEUS_PORT` |
| Grafana | 3000 | `GRAFANA_PORT` |
| MCP-Prometheus | 8082 | `MCP_PROMETHEUS_PORT` |
| Open WebUI | 8081 | `OPENWEBUI_PORT` |
| Jaeger | 16686 | `JAEGER_UI_PORT` |

---

## Resource Requirements

The full stack requires approximately:
- **CPU**: 4 cores (8+ recommended for smooth demo)
- **RAM**: 6GB minimum (8GB+ recommended)
- **Disk**: ~15GB for Docker images

If your machine is constrained, reduce OTel Demo services in `otel-demo/docker-compose.yml` by removing less-critical services (adservice, emailservice, fraud-detection).
