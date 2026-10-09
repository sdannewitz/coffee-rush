SHELL := /bin/bash
PORT = $$(sed -n 's/^APP_PORT=//p' .env 2>/dev/null || echo 8080)

.DEFAULT_GOAL := help
.PHONY: help setup up verify links open cheatsheet rush status reset down

help: ## Show the commands
	@grep -hE '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-11s %s\n", $$1, $$2}'

setup: ## Answer 4 questions (nickname, endpoint, instance ID, token) and get a ready .env
	@./scripts/setup.sh

.env:
	@./scripts/setup.sh

up: .env ## Build and start the app, wait for your telemetry, print your App Observability links
	docker compose up -d --build
	@echo "→ the app runs at http://localhost:$(PORT)"
	@./scripts/verify.sh

verify: ## Wait for your telemetry in Grafana Cloud, then print your App Observability links
	@./scripts/verify.sh

links: ## Print your services' App Observability links
	@./scripts/links.sh

open: ## Open your welcome-desk page in App Observability
	@u=$$(./scripts/links.sh --url welcome-desk) && { open "$$u" 2>/dev/null || xdg-open "$$u" 2>/dev/null || echo "$$u"; }

cheatsheet: ## Print the lab's gcx queries with your namespace filled in
	@./scripts/cheatsheet.sh

rush: ## Toggle rush hour from the terminal (same as the button in the UI)
	@curl -s -X POST http://localhost:$(PORT)/api/rush; echo

status: ## Time one request to the app
	@curl -s -o /dev/null -w "GET /api/orders took %{time_total}s\n" http://localhost:$(PORT)/api/orders

reset: ## Undo code changes and switch rush hour off, to start the exercise over
	git checkout -- welcome-desk coffee-bar
	@printf false > state/rush
	docker compose up -d --build welcome-desk coffee-bar

down: ## Stop everything
	docker compose down
