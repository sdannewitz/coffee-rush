#!/usr/bin/env bash
# Prints the lab's gcx queries with your namespace and context filled in.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] || { echo "No .env yet: run make setup" >&2; exit 1; }
NS=$(sed -n 's/^SERVICE_NAMESPACE=//p' .env)
CTX=$(sed -n 's/^GCX_CONTEXT=//p' .env)
G="gcx --context $CTX"

./scripts/links.sh 2>/dev/null || true
cat <<EOF
# Your label: service.namespace = $NS

# Which service got slow? (p95 per service, as a graph in your terminal)
$G metrics query 'histogram_quantile(0.95, sum by (le, service_name) (rate(http_server_duration_milliseconds_bucket{service_namespace="$NS"}[5m])))' --since 30m -o graph

# Slow requests, newest first
$G traces query '{ resource.service.namespace = "$NS" && duration > 1s }' --since 15m --limit 5 -o table

# Fast ones, for comparison
$G traces query '{ resource.service.namespace = "$NS" && duration < 300ms }' --since 15m --limit 5 -o table

# One trace as a waterfall (paste a trace ID from above)
./scripts/staircase.sh <trace-id>

# What did the services log?
$G logs query '{service_namespace="$NS"}' --since 15m --limit 20 -o table

# Ask the Grafana Assistant (uses Assistant tokens)
$G assistant prompt "In service.namespace $NS, welcome-desk GET /api/orders got slow. Look at its traces and the calls to coffee-bar. What pattern do you see?"
EOF
