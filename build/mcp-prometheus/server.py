"""
Prometheus MCP Server for Mezmo Aura PoV Demo.
Exposes Prometheus query tools over MCP Streamable HTTP transport.
"""

import os
import json
import logging
from typing import Optional

import httpx
import uvicorn
from fastmcp import FastMCP
from fastmcp.server.http import create_streamable_http_app
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO").upper())
log = logging.getLogger("mcp-prometheus")

PROMETHEUS_URL = os.getenv("PROMETHEUS_URL", "http://prometheus:9090").rstrip("/")

mcp = FastMCP(
    name="prometheus",
    instructions=(
        "Query live metrics from the OpenTelemetry Demo's Prometheus instance. "
        "Use query() for instant snapshots and query_range() for time-series analysis. "
        "When investigating incidents, start with top_error_services() then drill into latency."
    ),
)


async def _prom_get(path: str, params: dict) -> dict:
    async with httpx.AsyncClient(timeout=15.0) as client:
        r = await client.get(f"{PROMETHEUS_URL}{path}", params=params)
        r.raise_for_status()
        return r.json()


@mcp.tool()
async def query(promql: str, time_rfc3339: Optional[str] = None) -> str:
    """Execute an instant PromQL query against Prometheus.

    Args:
        promql: A valid PromQL expression. Examples:
            - rate(http_server_request_duration_seconds_count{http_response_status_code=~"5.."}[5m])
            - histogram_quantile(0.95, rate(http_server_request_duration_seconds_bucket[5m]))
        time_rfc3339: Optional evaluation time in RFC3339 format. Defaults to now.
    """
    params = {"query": promql}
    if time_rfc3339:
        params["time"] = time_rfc3339
    result = await _prom_get("/api/v1/query", params)
    return json.dumps(result, indent=2)


@mcp.tool()
async def query_range(
    promql: str,
    start_rfc3339: str,
    end_rfc3339: str,
    step: str = "60s",
) -> str:
    """Execute a range PromQL query to retrieve a time-series of values.

    Args:
        promql: A valid PromQL expression.
        start_rfc3339: Range start time in RFC3339 format, e.g. "2024-01-15T14:00:00Z".
        end_rfc3339: Range end time in RFC3339 format.
        step: Resolution step, e.g. "30s", "1m", "5m".
    """
    result = await _prom_get("/api/v1/query_range", {
        "query": promql,
        "start": start_rfc3339,
        "end": end_rfc3339,
        "step": step,
    })
    return json.dumps(result, indent=2)


@mcp.tool()
async def list_metrics(match: Optional[str] = None) -> str:
    """List all metric names known to Prometheus, optionally filtered by a substring.

    Args:
        match: Optional substring filter, e.g. "http_server" or "kafka".
    """
    result = await _prom_get("/api/v1/label/__name__/values", {})
    names: list[str] = result.get("data", [])
    if match:
        names = [n for n in names if match.lower() in n.lower()]
    return json.dumps(sorted(names), indent=2)


@mcp.tool()
async def get_alerts() -> str:
    """Return all currently firing Prometheus alerts with their labels and annotations."""
    result = await _prom_get("/api/v1/alerts", {})
    return json.dumps(result, indent=2)


@mcp.tool()
async def get_targets() -> str:
    """Return Prometheus scrape target health — shows which services are up/down."""
    result = await _prom_get("/api/v1/targets", {"state": "any"})
    targets = result.get("data", {}).get("activeTargets", [])
    summary = [
        {
            "job": t.get("labels", {}).get("job"),
            "instance": t.get("labels", {}).get("instance"),
            "health": t.get("health"),
            "lastError": t.get("lastError") or None,
        }
        for t in targets
    ]
    return json.dumps(summary, indent=2)


@mcp.tool()
async def top_error_services(window: str = "5m", threshold: float = 0.005) -> str:
    """Find services with the highest error rates.

    Uses span-derived error metrics (traces_span_metrics_calls_total) which cover ALL OTel Demo
    services uniformly. Also includes per-span breakdown to help identify root cause vs. cascades.

    Args:
        window: Time window for rate calculation, e.g. "5m", "15m".
        threshold: Minimum error rate to include (errors/sec). Default 0.005.
    """
    # Primary: span-level errors — covers all services, includes span name for root cause analysis
    span_promql = (
        f"sort_desc(sum by (service_name, span_name) ("
        f"rate(traces_span_metrics_calls_total"
        f"{{status_code=\"STATUS_CODE_ERROR\"}}[{window}])))"
    )
    result = await _prom_get("/api/v1/query", {"query": span_promql})
    vectors = result.get("data", {}).get("result", [])

    hits: list[dict] = []
    for v in vectors:
        rate_val = float(v["value"][1])
        if rate_val < threshold:
            continue
        hits.append({
            "service": v["metric"].get("service_name", "unknown"),
            "span": v["metric"].get("span_name", "unknown"),
            "error_rate_per_sec": round(rate_val, 5),
        })

    if not hits:
        return f"No services exceed error threshold {threshold} errors/sec in the last {window}."

    output = {
        "errors_by_span": hits,
        "note": (
            "Look for the most upstream span that errors — that is the root cause. "
            "Downstream services cascade from there."
        ),
    }
    return json.dumps(output, indent=2)


@mcp.tool()
async def service_latency_percentiles(service_name: str, window: str = "5m") -> str:
    """Get P50/P95/P99 request latency for a named service.

    Args:
        service_name: Exact service_name label value, e.g. "checkout".
        window: Time window for histogram calculation, e.g. "5m".
    """
    results = {}
    for pct, quantile in [("p50", "0.5"), ("p95", "0.95"), ("p99", "0.99")]:
        promql = (
            f"histogram_quantile({quantile}, sum by (le) ("
            f"rate(http_server_request_duration_seconds_bucket"
            f"{{service_name=\"{service_name}\"}}[{window}])))"
        )
        r = await _prom_get("/api/v1/query", {"query": promql})
        vecs = r.get("data", {}).get("result", [])
        results[pct] = (
            round(float(vecs[0]["value"][1]) * 1000, 2)
            if vecs and vecs[0]["value"][1] != "NaN"
            else None
        )
    results["service"] = service_name
    results["window"] = window
    results["unit"] = "milliseconds"
    return json.dumps(results, indent=2)


# ── Health endpoint ───────────────────────────────────────────────────────────

async def health(request: Request) -> JSONResponse:
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            r = await client.get(f"{PROMETHEUS_URL}/-/healthy")
            prom_ok = r.status_code == 200
    except Exception:
        prom_ok = False
    return JSONResponse({"status": "ok" if prom_ok else "degraded", "prometheus_reachable": prom_ok})


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8082"))
    log.info("Starting Prometheus MCP server on :%d (PROMETHEUS_URL=%s)", port, PROMETHEUS_URL)

    app = create_streamable_http_app(
        mcp,
        streamable_http_path="/mcp",
        stateless_http=True,
        routes=[Route("/health", health, methods=["GET"])],
    )

    uvicorn.run(app, host="0.0.0.0", port=port, lifespan="on", log_level="info")
