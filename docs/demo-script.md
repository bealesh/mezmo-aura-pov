# Demo Script — Mezmo Aura PoV

**Total time: 15–20 minutes**  
**Audience: VP Engineering / SRE Lead + technical observers**

---

## Pre-Demo Checklist (do the night before)

- [ ] `make demo-ready` completed without errors
- [ ] `make recover` run to ensure clean baseline
- [ ] All services show green in `make ps`
- [ ] Grafana dashboards loading at http://localhost:3000
- [ ] Aura responding at http://localhost:3030/health
- [ ] `make screenshots` artifacts saved to `artifacts/screenshots/` (backup insurance)
- [ ] Browser tabs pre-opened: Grafana, Frontend, Jaeger
- [ ] Terminal windows: one for commands, one for `make logs`

---

## Section 1 — Executive Framing (2 min)

> "Let me set the scene. Your team gets paged at 2am. An engineer wakes up, opens their laptop, and stares at a wall of dashboards. They've got Prometheus, Jaeger, maybe OpenSearch — telemetry everywhere. But no intelligence layer to tell them what actually matters.
>
> They spend 30-45 minutes in a war room, comparing charts, asking each other questions.
>
> What I'm about to show you is what that same incident looks like with Mezmo Aura."

**Show**: `docs/architecture.md` diagram (or equivalent slide)  
**Transition**: "Let me walk you through the environment, then we'll fire an actual incident."

---

## Section 2 — Environment Walk (3 min)

**Show the Frontend** → http://localhost:8080  
> "This is the OpenTelemetry Demo — a realistic e-commerce app with 15+ microservices. Think checkout, payment, cart, catalog, recommendations. It's generating live traffic right now via a load generator."

**Show Grafana** → http://localhost:3000  
> "All the telemetry flows into Prometheus and surfaces in Grafana. This is what your current on-call sees."  
> *Point out the service error rate and latency panels.*

**Show Aura** → run `curl http://localhost:3030/v1/models | jq`  
> "And here's Aura. It's an AI agent running locally, connected to your Prometheus instance via a tool called MCP — Model Context Protocol. Aura can query your live metrics in real time."

---

## Section 3 — Fire the Incident (1 min)

Run in terminal:
```bash
make fault-fail
```

Expected output:
```
Injecting FAILING SERVICE scenario
Flags: paymentFailure, paymentUnreachable, cartFailure
✓ Flags updated — flagd will reload within 1-2 seconds
```

> "I've just injected a real fault into the system. Payment processing is now failing. Cart service is degraded. Users trying to check out are hitting errors."

*Wait 30–60 seconds for metrics to propagate. Watch Grafana error rate climb.*

> "Watch the Grafana dashboard — error rates are climbing. In a real incident this is when PagerDuty fires."

---

## Section 4 — The Aura Investigation (5 min)

Run in terminal:
```bash
make query
```

*Or, if using Open WebUI (`--profile stretch`):*  
→ Open http://localhost:8081  
→ Select model: `aura-observability`  
→ Paste: *"Our checkout pipeline is reporting elevated error rates. On-call was just paged. What's happening?"*

**Walk through Aura's response live:**

> "Notice what's happening. Aura isn't just reading a dashboard — it's querying your Prometheus directly, in real time. It called `top_error_services()`, ranked services by error rate, then drilled into payment and cart with a latency analysis."

**Key talking points while Aura responds:**
1. **No PromQL required** — the engineer typed plain English
2. **Automatic triage** — Aura distinguished root cause (paymentservice) from cascading victims (checkoutservice)  
3. **Quantified impact** — exact error rates, P95 latencies, timestamps
4. **Actionable** — ends with a concrete recommendation, not a list of dashboards to check

Expected Aura response themes:
- Root cause: paymentservice and/or cartservice
- Evidence: specific error rate numbers from Prometheus
- Recommendation: restart paymentservice to clear the failure state

---

## Section 5 — Closed-Loop Remediation (3 min, stretch goal)

*Only if `--profile stretch` is running and Docker MCP is active.*

In Open WebUI or via curl, follow up:
```
Based on your investigation, I authorize you to restart the paymentservice. 
Please restart it and confirm the error rate drops.
```

> "This is the closed loop. The same interface where the engineer asked the question is where they fix it. No Kubernetes dashboard, no SSH, no context switching. Aura executes the restart via the Docker MCP, then re-queries Prometheus to verify recovery."

*Watch Aura confirm error rate returning to baseline.*

---

## Section 6 — Reset and Second Scenario (optional, if time allows)

```bash
make recover
# Wait 30s
make fault-latency
```

> "Let me show you a subtler scenario — high latency, no hard errors. This is the hardest kind of incident to diagnose manually. Error rates are flat, but customers are complaining."

Follow-up Aura prompt:
```
Checkout is slow but there are no obvious errors. What's causing the latency?
```

---

## Section 7 — Close (2 min)

> "Let me tie this back to what matters for your business.
>
> Before Aura: 45-minute war room. Senior engineers pulled out of sleep. PromQL expertise required. Manual correlation across four tools.
>
> After Aura: 60 seconds. Plain English. Root cause identified. Fix executed. Incident closed.
>
> That's MTTR reduction you can measure. That's engineer burnout you can prevent. And that's SLA breach exposure you can eliminate.
>
> What questions do you have?"

---

## Handling Questions

**"What if the AI gets it wrong?"**  
> "Aura shows its work — every claim is backed by a Prometheus query. You can see exactly what data it used. It's transparent, not a black box."

**"Can this connect to our existing Prometheus?"**  
> "Yes — you point the MCP server at any Prometheus URL. There's nothing OTel-specific here. If it speaks PromQL, Aura can use it."

**"What about Datadog / Grafana Cloud / New Relic?"**  
> "The MCP pattern is backend-agnostic. Mezmo has MCP integrations for multiple backends. What you saw here is the same architecture."

**"Is this production-ready?"**  
> "Mezmo Aura is production software. This demo environment is a PoV setup — a real deployment would be configured against your actual observability backends."

---

## Backup Plan

If live demo breaks:
1. Open `artifacts/screenshots/` for pre-captured metric snapshots
2. Narrate from screenshots: "Here's what Prometheus showed during the fault..."
3. Demo Aura against pre-recorded interaction if needed
4. The architecture story and business value narrative stand independently
