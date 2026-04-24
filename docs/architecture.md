# Architecture Overview

## System Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Engineer / Prospect                       │
│                     "What's causing checkout failures?"          │
└──────────────────────────┬──────────────────────────────────────┘
                           │  HTTP (OpenAI-compatible API)
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Mezmo Aura  :3030                          │
│                                                                  │
│  • OpenAI-compatible /v1/chat/completions endpoint               │
│  • Declarative TOML agent config (config.toml)                  │
│  • LLM: OpenAI gpt-4o or Anthropic Claude                       │
│  • MCP client — discovers and invokes tools dynamically          │
└──────────┬───────────────────────────────────────────┬──────────┘
           │ MCP (Streamable HTTP)                     │ MCP (Streamable HTTP)
           ▼                                           ▼
┌─────────────────────────┐              ┌─────────────────────────┐
│  Prometheus MCP  :8082  │              │  Docker MCP  :8083       │
│  (mcp-prometheus)       │              │  (mcp-docker) [stretch] │
│                         │              │                          │
│  Tools:                 │              │  Tools:                  │
│  • query()              │              │  • restart_service()     │
│  • query_range()        │              │  • get_logs()            │
│  • top_error_services() │              │  • list_services()       │
│  • service_latency_...  │              │  • container_stats()     │
│  • get_alerts()         │              │                          │
│  • get_targets()        │              │  Mounts: /var/run/       │
└──────────┬──────────────┘              │          docker.sock     │
           │ HTTP PromQL API             └─────────────────────────┘
           ▼
┌─────────────────────────────────────────────────────────────────┐
│                 OpenTelemetry Demo Stack                         │
│               (docker compose — separate project)               │
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ frontend │  │ checkout │  │ payment  │  │ cart (Valkey) │  │
│  └──────────┘  └──────────┘  └──────────┘  └───────────────┘  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ catalog  │  │recommend │  │ shipping │  │  email / ad   │  │
│  └──────────┘  └──────────┘  └──────────┘  └───────────────┘  │
│       │              │               │                           │
│       └──────────────┴───────────────┘                          │
│                             │                                    │
│                 OTel Collector  :4317/:4318                     │
│                    /                   \                         │
│           ┌──────────────┐    ┌──────────────────┐             │
│           │  Prometheus  │    │    Jaeger / OS    │             │
│           │  :9090       │    │    :16686 / :9200 │             │
│           └──────────────┘    └──────────────────┘             │
│                    │                                             │
│           ┌──────────────┐    ┌──────────────────┐             │
│           │   Grafana    │    │    flagd  :8013   │             │
│           │   :3000      │    │  (fault injection)│             │
│           └──────────────┘    └──────────────────┘             │
└─────────────────────────────────────────────────────────────────┘

Shared Docker network: opentelemetry-demo (bridge)
```

## Component Roles

| Component | Role in Demo |
|---|---|
| **OTel Demo** | Realistic e-commerce microservices generating live telemetry |
| **flagd** | Feature flag service — our fault injection mechanism |
| **Prometheus** | Metrics backend; Aura queries this for root cause analysis |
| **Grafana** | Visual dashboard for the audience during the demo |
| **Jaeger** | Distributed traces — manual deep-dive reference |
| **OpenSearch** | Log storage backend |
| **Mezmo Aura** | AI agent; orchestrates investigation + remediation via MCP |
| **MCP-Prometheus** | Translates natural language to PromQL; returns structured metric data |
| **MCP-Docker** | *(Stretch)* Gives Aura the ability to restart containers |
| **Open WebUI** | *(Stretch)* Chat interface for the demo — no CLI during presentation |

## Key Design Decisions

**External network join, not compose `include:`**  
The OTel Demo runs as its own Docker Compose project (preserving upstream defaults), and our services join the `opentelemetry-demo` bridge network as an external. This makes it easy to upgrade the OTel Demo independently.

**Fault injection via flagd JSON**  
flagd watches its config file for changes and reloads within ~1 second. Modifying `demo.flagd.json` with `jq` is instant, reliable, and reversible — no container restarts needed for fault injection.

**MCP over Streamable HTTP, not stdio**  
Stdio MCP servers can't easily be composed into Docker Compose services. The custom Python FastMCP servers expose the MCP protocol over HTTP, which Aura's `http_streamable` transport consumes directly over the internal network.

**OpenAI-compatible API**  
Aura exposes `/v1/chat/completions`, making it a drop-in endpoint for Open WebUI, LibreChat, or any OpenAI SDK client. The demo UI layer is swappable without changing Aura.

## Data Flow During Incident Investigation

1. Engineer types: *"What's causing checkout failures?"*
2. Aura receives the message via `/v1/chat/completions`
3. Aura calls `top_error_services(window="5m")` via the Prometheus MCP
4. MCP executes PromQL against `http://prometheus:9090`
5. Prometheus returns error rate vectors ranked by service
6. Aura calls `service_latency_percentiles("paymentservice")` for depth
7. Aura synthesizes: *"Root cause: paymentservice, 12.3 req/s 5xx errors since 14:32 UTC..."*
8. *(Stretch)* Engineer says *"restart paymentservice"*
9. Aura calls `restart_service("paymentservice")` via Docker MCP
10. Docker MCP calls `container.restart()` via Docker socket
11. Aura polls `query()` to confirm error rate drops
12. Aura confirms: *"Error rate returned to baseline (0.02 req/s). Incident resolved."*
