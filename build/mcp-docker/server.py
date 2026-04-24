"""
Docker Ops MCP Server — stretch goal closed-loop remediation.
Allows Aura to restart, scale, and inspect OTel Demo containers via chat.
Mounts the Docker socket read/write — do NOT expose outside localhost.
"""

import os
import json
import logging
from typing import Optional

import docker
from fastmcp import FastMCP
from fastmcp.server.http import create_streamable_http_app
import uvicorn
from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Route

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO").upper())
log = logging.getLogger("mcp-docker")

OTEL_DEMO_PROJECT = os.getenv("COMPOSE_PROJECT_NAME", "otel-demo")
OTEL_DEMO_DIR = os.getenv("OTEL_DEMO_PROJECT_DIR", "/workspace/otel-demo")

client = docker.from_env()

mcp = FastMCP(
    name="docker-ops",
    instructions=(
        "Manage Docker Compose services in the OTel Demo stack. "
        "Use restart_service() to recover a crashed or misbehaving container. "
        "Use scale_service() to add replicas under load. "
        "Always confirm with the user before taking destructive actions."
    ),
)


def _get_demo_containers() -> list[docker.models.containers.Container]:
    return client.containers.list(
        filters={"label": f"com.docker.compose.project={OTEL_DEMO_PROJECT}"}
    )


@mcp.tool()
def list_services() -> str:
    """List all OTel Demo containers with their current status.

    Returns service name, container ID (short), status, and health state.
    """
    containers = _get_demo_containers()
    summary = []
    for c in sorted(containers, key=lambda x: x.name):
        health = c.attrs.get("State", {}).get("Health", {})
        summary.append({
            "name": c.name,
            "id": c.short_id,
            "status": c.status,
            "health": health.get("Status", "none"),
            "started": c.attrs.get("State", {}).get("StartedAt", ""),
        })
    return json.dumps(summary, indent=2)


@mcp.tool()
def restart_service(service_name: str) -> str:
    """Restart a named OTel Demo service container.

    Args:
        service_name: Docker container name, e.g. "checkoutservice", "paymentservice".
                      The container does not need the project prefix.
    """
    matches = [
        c for c in _get_demo_containers()
        if service_name.lower() in c.name.lower()
    ]
    if not matches:
        return f"No container matching '{service_name}' found in project {OTEL_DEMO_PROJECT}."
    if len(matches) > 1:
        names = [c.name for c in matches]
        return f"Ambiguous: multiple containers match '{service_name}': {names}. Be more specific."

    container = matches[0]
    log.info("Restarting container: %s (%s)", container.name, container.short_id)
    container.restart(timeout=30)
    container.reload()
    return json.dumps({
        "action": "restart",
        "container": container.name,
        "new_status": container.status,
    }, indent=2)


@mcp.tool()
def get_logs(service_name: str, lines: int = 100) -> str:
    """Retrieve the last N log lines from an OTel Demo container.

    Args:
        service_name: Container name (partial match accepted).
        lines: Number of tail lines to return. Max 500.
    """
    lines = min(lines, 500)
    matches = [
        c for c in _get_demo_containers()
        if service_name.lower() in c.name.lower()
    ]
    if not matches:
        return f"No container matching '{service_name}' found."
    container = matches[0]
    log_bytes = container.logs(tail=lines, timestamps=True)
    return log_bytes.decode("utf-8", errors="replace")


@mcp.tool()
def container_stats(service_name: str) -> str:
    """Get current CPU and memory usage for a service container.

    Args:
        service_name: Container name (partial match accepted).
    """
    matches = [
        c for c in _get_demo_containers()
        if service_name.lower() in c.name.lower()
    ]
    if not matches:
        return f"No container matching '{service_name}' found."
    container = matches[0]
    stats = container.stats(stream=False)

    cpu_delta = stats["cpu_stats"]["cpu_usage"]["total_usage"] - \
                stats["precpu_stats"]["cpu_usage"]["total_usage"]
    system_delta = stats["cpu_stats"]["system_cpu_usage"] - \
                   stats["precpu_stats"]["system_cpu_usage"]
    num_cpus = stats["cpu_stats"].get("online_cpus", 1)
    cpu_pct = (cpu_delta / system_delta) * num_cpus * 100.0 if system_delta > 0 else 0.0

    mem_usage = stats["memory_stats"].get("usage", 0)
    mem_limit = stats["memory_stats"].get("limit", 1)
    mem_pct = (mem_usage / mem_limit) * 100.0

    return json.dumps({
        "container": container.name,
        "cpu_percent": round(cpu_pct, 2),
        "memory_mb": round(mem_usage / 1_048_576, 1),
        "memory_limit_mb": round(mem_limit / 1_048_576, 1),
        "memory_percent": round(mem_pct, 2),
    }, indent=2)


# ── Health endpoint ───────────────────────────────────────────────────────────

async def health(request):
    try:
        client.ping()
        docker_ok = True
    except Exception:
        docker_ok = False
    return JSONResponse({"status": "ok" if docker_ok else "degraded", "docker_socket": docker_ok})


def build_app():
    mcp_app = create_streamable_http_app(mcp, streamable_http_path="/mcp", stateless_http=True)
    health_route = Route("/health", health)
    return Starlette(routes=[health_route] + list(mcp_app.routes))


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8083"))
    log.info("Starting Docker Ops MCP server on :%d", port)
    uvicorn.run(build_app(), host="0.0.0.0", port=port, log_level="info")
