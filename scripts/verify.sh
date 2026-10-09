#!/usr/bin/env bash
# Is my telemetry arriving? Waits for traces from my namespace, then until App
# Observability has built my service pages, and prints the links to them.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] || { echo "No .env yet: run make setup" >&2; exit 1; }
NS=$(sed -n 's/^SERVICE_NAMESPACE=//p' .env)
CTX=$(sed -n 's/^GCX_CONTEXT=//p' .env)
G() { gcx ${CTX:+--context "$CTX"} "$@"; }
ok()  { printf '\033[32m✔\033[0m %s\n' "$*"; }

# ── 1. Traces ────────────────────────────────────────────────────────────────
Q="{ resource.service.namespace = \"$NS\" }"
echo "→ waiting for your traces: gcx traces query '$Q'"
found=""
for i in 1 2 3 4 5 6 7 8; do
  if out=$(G traces query "$Q" --since 10m --limit 5 -o table 2>/dev/null) \
     && [ "$(printf '%s\n' "$out" | grep -c .)" -gt 1 ]; then
    printf '%s\n' "$out"; found=1; break
  fi
  echo "  nothing yet, waiting 15 s ($i/8)…"
  sleep 15
done
if [ -z "$found" ]; then
  printf '\033[31m✘\033[0m no traces after 2 minutes. Check the collector:\n' >&2
  echo "    docker compose logs otel-collector | grep -i -E 'error|401|403'" >&2
  exit 1
fi
ok "your telemetry arrives in Grafana Cloud as service.namespace=$NS"

# ── 2. App Observability (built from span metrics, takes a little longer) ───
echo "→ waiting for App Observability to pick up welcome-desk and coffee-bar (usually 1–3 min)…"
ready=""
for i in $(seq 1 16); do
  n=$(G metrics query "count by (service) (traces_spanmetrics_calls_total{service_namespace=\"$NS\"})" \
        --jq '.data.result | length' 2>/dev/null || echo 0)
  if [ "${n:-0}" -ge 2 ] 2>/dev/null; then ready=1; break; fi
  sleep 15
done
if [ -n "$ready" ]; then ok "App Observability knows your services"
else echo "  App Observability needs a bit longer. The links below will work in a few minutes."; fi

./scripts/links.sh || true
