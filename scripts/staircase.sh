#!/usr/bin/env bash
# staircase.sh <trace-id>: draw a trace's calls to coffee-bar as a waterfall.
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 <trace-id>" >&2; exit 1; }
cd "$(dirname "$0")/.."
CTX=$( [ -f .env ] && sed -n 's/^GCX_CONTEXT=//p' .env || true )
gcx ${CTX:+--context "$CTX"} traces get "$1" -o json 2>/dev/null | python3 scripts/staircase.py
