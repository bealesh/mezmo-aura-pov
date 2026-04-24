# Mezmo Aura PoV — AI-Powered Observability & Remediation

A proof-of-value demo environment connecting **Mezmo Aura** to the **OpenTelemetry Demo** via Model Context Protocol. Compresses a 45-minute incident war room into a 60-second AI conversation.

## Architecture

```
Engineer → Aura (AI agent) → Prometheus MCP → Prometheus → OTel Demo metrics
                           → Docker MCP*   → Docker socket → container restart
```

*stretch goal*

[Full architecture diagram](docs/architecture.md)

## Prerequisites

- Docker Desktop ≥ 4.25 with Compose v2.20+
- `make`, `jq`, `git`, `curl`
- OpenAI API key (`gpt-4o`) **or** Anthropic API key (`claude-sonnet-4-6`)
- 8GB RAM, 15GB disk

## Quick Start

```bash
# 1. Bootstrap (clones opentelemetry-demo, copies .env)
make bootstrap

# 2. Set your API key
echo "OPENAI_API_KEY=sk-..." >> .env

# 3. Start everything + verify health (first run ~10 min, Rust build)
make demo-ready
```

That's it. When `demo-ready` finishes you'll see URLs for all services.

## Running the Demo

```bash
# Inject a failure scenario
make fault-fail

# Wait ~60s, then ask Aura to investigate
make query

# Reset to healthy
make recover
```

Available scenarios:

| Command | Scenario |
|---|---|
| `make fault-fail` | Payment + cart service failure |
| `make fault-latency` | Kafka queue overload + slow image loads |
| `make fault-errors` | Intermittent 5xx error spike (~50% payment failures) |

## Stretch Goals

**Open WebUI (single-pane-of-glass)**
```bash
docker compose --profile stretch up -d open-webui
# http://localhost:8081 → select model: aura-observability
```

**Closed-loop remediation via Docker MCP**
```bash
# Uncomment [mcp.servers.docker] in configs/aura/config.toml, then:
docker compose --profile stretch up -d mcp-docker
docker compose restart aura
# Now ask Aura: "Restart the paymentservice and confirm recovery"
```

## Available Commands

```
make help
```

Key targets:

| Command | Description |
|---|---|
| `make demo-ready` | Full prep: bootstrap + up + health + smoke |
| `make fault-fail` | Inject failing service scenario |
| `make fault-latency` | Inject latency scenario |
| `make fault-errors` | Inject error spike |
| `make recover` | Reset all faults |
| `make query` | Fire canned investigation prompt at Aura |
| `make test` | Run full test suite |
| `make screenshots` | Capture metric snapshots for backup |
| `make down` | Stop all services |

## Service URLs

| Service | URL |
|---|---|
| OTel Demo Frontend | http://localhost:8080 |
| Grafana | http://localhost:3000 |
| Prometheus | http://localhost:9090 |
| Jaeger | http://localhost:16686 |
| Load Generator | http://localhost:8089 |
| Aura API | http://localhost:3030 |
| Open WebUI (stretch) | http://localhost:8081 |

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Demo Script](docs/demo-script.md)
- [Business Narrative](docs/business-narrative.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Technical Handover](docs/handoff.md)

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for common issues.

Quick fixes:

```bash
make logs          # Aura + MCP logs
make logs-otel     # OTel Demo logs
make smoke         # Which check is failing?
docker compose ps  # Container status
```
