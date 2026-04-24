# Technical Handover — Complete Reproduction Guide

This document contains everything needed to reproduce this PoV environment from scratch on a clean machine.

---

## Prerequisites

| Tool | Required Version | Install |
|---|---|---|
| Docker Desktop | ≥ 4.25 (Engine 24+) | https://www.docker.com/products/docker-desktop |
| Docker Compose | v2.20+ (bundled with Docker Desktop) | `docker compose version` |
| GNU Make | any | macOS: `xcode-select --install` |
| jq | any | `brew install jq` / `apt-get install jq` |
| git | any | bundled on macOS/Linux |
| curl | any | bundled |

**LLM API Key** (one of):
- OpenAI: https://platform.openai.com/api-keys — needs `gpt-4o` access
- Anthropic: https://console.anthropic.com — needs `claude-sonnet-4-6` access

**Hardware**:
- 8GB RAM minimum (16GB recommended)
- 4 CPU cores
- 15GB free disk space

---

## Reproduction Steps

### 1. Clone this repository

```bash
git clone <this-repo-url> mezmo-aura-pov
cd mezmo-aura-pov
```

### 2. Bootstrap

```bash
make bootstrap
```

This will:
- Clone `opentelemetry-demo` to `./otel-demo/`
- Copy `.env.example` → `.env`
- Set executable permissions on all scripts

### 3. Configure API key

```bash
# Edit .env and set your key:
nano .env

# Required: set ONE of these
OPENAI_API_KEY=sk-...
# or
ANTHROPIC_API_KEY=sk-ant-...

# If using Anthropic, also change in configs/aura/config.toml:
#   provider = "anthropic"
#   api_key   = "{{ env.ANTHROPIC_API_KEY }}"
#   model     = "claude-sonnet-4-6"
```

### 4. Start the full stack

```bash
make up
```

This starts the OTel Demo (~19 services) then Aura + MCP services.

**First run note**: Building Aura from source (Rust) takes approximately 8–12 minutes. Subsequent `make up` calls use Docker cache and start in ~30 seconds.

### 5. Wait for health

```bash
make health
```

This polls all service endpoints until healthy (timeout: 5 minutes). Expected output:

```
Waiting for Prometheus at http://localhost:9090/-/ready ....... ✓
Waiting for Grafana at http://localhost:3000/api/health ....... ✓
Waiting for Frontend at http://localhost:8080 ................ ✓
Waiting for Aura at http://localhost:3030/health ............. ✓
Waiting for MCP-Prometheus at http://localhost:8082/health ... ✓
✓ All services healthy after 47s
```

### 6. Run smoke test

```bash
make smoke
```

All 7 checks should pass. If any fail, see `docs/troubleshooting.md`.

### 7. Verify end-to-end

```bash
make test
```

This runs the full test suite including a fault injection test (~3 minutes).

---

## Stretch Goals

### Enable Open WebUI (single-pane-of-glass UI)

```bash
docker compose --profile stretch up -d open-webui
```

Access at http://localhost:8081. Select model `aura-observability`.

### Enable Docker MCP (closed-loop remediation)

1. Uncomment the `[mcp.servers.docker]` block in `configs/aura/config.toml`
2. Start the Docker MCP service:

```bash
docker compose --profile stretch up -d mcp-docker
```

3. Restart Aura to reload config:

```bash
docker compose restart aura
```

Now prompt Aura: *"Restart the paymentservice and confirm recovery."*

---

## Running a Demo Scenario

### Scenario A: Failing Service (recommended for first demo)

```bash
# Terminal 1 — watch logs
make logs

# Terminal 2 — inject fault
make fault-fail

# Wait 60 seconds, then investigate
make query

# Reset when done
make recover
```

### Scenario B: High Latency

```bash
make fault-latency
# Prompt Aura: "Why is checkout so slow? No hard errors but P95 latency is up."
make recover
```

### Scenario C: Error Spike (intermittent)

```bash
make fault-errors
# Prompt Aura: "We're seeing intermittent checkout errors. Investigate."
make recover
```

---

## Repository Structure

```
mezmo-aura-pov/
├── Makefile                    # All demo commands
├── .env.example                # Environment template
├── docker-compose.yml          # Aura + MCP services
├── docker-compose.override.yml # Local dev overrides
│
├── build/
│   ├── aura/                   # Dockerfile that builds Aura from source
│   ├── mcp-prometheus/         # Custom Prometheus MCP server (FastMCP/Python)
│   └── mcp-docker/             # Docker Ops MCP server (stretch goal)
│
├── configs/
│   ├── aura/
│   │   ├── config.toml         # Aura agent config (LLM + MCP + system prompt)
│   │   ├── system-prompt.md    # Detailed agent instructions
│   │   └── prompts/            # Canned investigation/remediation prompts
│   └── fault/
│       └── scenarios.env       # Flag names and paths for fault injection
│
├── scripts/
│   ├── wait-for-stack.sh       # Polls until all services healthy
│   ├── smoke-test.sh           # 7-check fast sanity test
│   ├── inject-failure.sh       # Activates payment + cart failure flags
│   ├── inject-latency.sh       # Activates Kafka + image slow-load flags
│   ├── inject-errors.sh        # Activates partial payment failure flag
│   ├── reset-demo.sh           # Turns off all fault flags
│   ├── demo-query.sh           # Fires investigation prompt at Aura
│   └── capture-artifacts.sh    # Exports metrics + screenshots for backup
│
├── tests/
│   ├── test-stack.sh           # Full service connectivity + data validation
│   ├── test-prometheus.sh      # Prometheus health + metric availability
│   ├── test-aura-health.sh     # Aura health + agent loaded + inference working
│   └── test-fault-path.sh      # End-to-end fault inject → detect → reset
│
├── docs/
│   ├── architecture.md         # System diagram + component roles
│   ├── demo-script.md          # Step-by-step demo guide
│   ├── business-narrative.md   # VP-level pitch + objection handling
│   ├── troubleshooting.md      # Common issues + fixes
│   └── handoff.md              # This file
│
├── artifacts/
│   └── screenshots/            # Captured by capture-artifacts.sh
│
└── otel-demo/                  # Cloned by make bootstrap (gitignored)
```

---

## Key Configuration Files

### `configs/aura/config.toml`

The single file that defines the Aura agent. Key sections:

```toml
[llm]           # Which LLM provider and model
[mcp]           # MCP server connections (Prometheus, Docker)
[agent]         # Agent name, turn depth, system prompt
```

To switch from OpenAI to Anthropic: change `[llm]` section, set `ANTHROPIC_API_KEY` in `.env`.

To add a new MCP server:
```toml
[mcp.servers.my_new_tool]
transport = "http_streamable"
url = "http://my-mcp-server:PORT/mcp"
description = "..."
```

### `build/mcp-prometheus/server.py`

The Prometheus MCP server. Add new tools as Python functions decorated with `@mcp.tool()`. The FastMCP library handles JSON schema generation and MCP protocol automatically.

### Fault Injection

All fault injection is implemented by modifying `otel-demo/src/flagd/demo.flagd.json` with `jq`. The flagd service watches this file and reloads within ~1 second.

Available flags: see `configs/fault/scenarios.env` → `ALL_FAULT_FLAGS`.

---

## Tearing Down

```bash
make down    # Stop all services, preserve volumes
make clean   # Stop + remove volumes + local images (full reset)
```

The `otel-demo/` directory is gitignored. To remove it:
```bash
rm -rf otel-demo/
```

---

## Tested On

- macOS 14 Sonoma, Apple M2 Pro, Docker Desktop 4.28
- Ubuntu 22.04 LTS, 8-core x86_64, Docker Engine 25.0

---

## Contact

Questions about this setup: david@grzly.io
