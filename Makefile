SHELL := /bin/bash

.PHONY: help up down restart logs ps clean reset \
        bootstrap health smoke test demo-ready \
        fault-fail fault-latency fault-errors \
        recover query screenshots

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "%-20s %s\n", $$1, $$2}'

bootstrap: ## Clone deps, copy env, set permissions
	@echo "→ Cloning OpenTelemetry Demo..."
	@[ -d otel-demo ] || git clone --depth=1 https://github.com/open-telemetry/opentelemetry-demo.git otel-demo
	@echo "→ Setting up environment..."
	@cp -n .env.example .env 2>/dev/null || true
	@chmod +x scripts/*.sh tests/*.sh
	@echo "✓ Bootstrap complete. Edit .env and set OPENAI_API_KEY before continuing."

up: ## Start full demo environment (OTel Demo + Aura + MCP)
	@echo "→ Starting OpenTelemetry Demo..."
	@cd otel-demo && docker compose up -d
	@echo "→ Starting Aura + MCP services..."
	@docker compose up -d --build

down: ## Stop all services
	docker compose down
	@cd otel-demo && docker compose down

restart: down up ## Restart entire stack

logs: ## Tail Aura + MCP logs
	docker compose logs -f --tail=200

logs-otel: ## Tail OTel Demo logs
	cd otel-demo && docker compose logs -f --tail=100

ps: ## Show all running services
	@echo "=== Aura + MCP ==="
	@docker compose ps
	@echo ""
	@echo "=== OTel Demo ==="
	@cd otel-demo && docker compose ps

health: ## Wait for services and verify health
	./scripts/wait-for-stack.sh
	./tests/test-prometheus.sh
	./tests/test-aura-health.sh

smoke: ## Fast sanity check
	./scripts/smoke-test.sh

test: ## Run all tests
	./tests/test-stack.sh
	./tests/test-prometheus.sh
	./tests/test-aura-health.sh
	./tests/test-fault-path.sh

fault-fail: ## Inject failing service scenario (payment + cart)
	./scripts/inject-failure.sh

fault-latency: ## Inject latency scenario (kafka + image load)
	./scripts/inject-latency.sh

fault-errors: ## Inject 5xx error spike scenario
	./scripts/inject-errors.sh

recover: ## Restore healthy state (reset all faults)
	./scripts/reset-demo.sh

query: ## Run canned Aura investigation query
	./scripts/demo-query.sh

screenshots: ## Capture backup artifacts for demo insurance
	./scripts/capture-artifacts.sh

clean: ## Remove built images and volumes
	docker compose down -v --rmi local
	@cd otel-demo && docker compose down -v --rmi local

reset: recover ## Alias for recover

demo-ready: bootstrap up health smoke ## Full prep path — run this before demo day
	@echo ""
	@echo "╔══════════════════════════════════════════╗"
	@echo "║  Demo environment is READY               ║"
	@echo "║                                          ║"
	@echo "║  Frontend:   http://localhost:8080       ║"
	@echo "║  Grafana:    http://localhost:3000       ║"
	@echo "║  Prometheus: http://localhost:9090       ║"
	@echo "║  Aura API:   http://localhost:3030       ║"
	@echo "║  Jaeger:     http://localhost:16686      ║"
	@echo "║  Load Gen:   http://localhost:8089       ║"
	@echo "╚══════════════════════════════════════════╝"
	@echo ""
	@echo "Next: make fault-fail && make query"
