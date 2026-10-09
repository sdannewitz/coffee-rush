#!/usr/bin/env bash
# Prints your two services' pages in Grafana App Observability.
#   scripts/links.sh                  highlighted block for people
#   scripts/links.sh --url <service>  just one URL (welcome-desk or coffee-bar), for scripts
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] || { echo "No .env yet: run make setup" >&2; exit 1; }
NS=$(sed -n 's/^SERVICE_NAMESPACE=//p' .env)
BASE=$(sed -n 's/^GRAFANA_URL=//p' .env)
if [ -z "$BASE" ] && command -v gcx >/dev/null 2>&1; then   # older .env: ask gcx for the stack URL
  CTX=$(sed -n 's/^GCX_CONTEXT=//p' .env)
  STACK=$(gcx config view --jq ".contexts[\"$CTX\"].stack" 2>/dev/null | tr -d '"\n' || true)
  BASE=$(gcx config view --jq ".stacks[\"${STACK:-$CTX}\"].grafana.server" 2>/dev/null | tr -d '"\n' | sed 's:/*$::' || true)
  case "$BASE" in https://*) ;; *) BASE="" ;; esac
fi
QS='?var-prometheus=grafanacloud-prom&var-environmentValue=$__all&from=now-30m&to=now&var-groupBy=__empty'
page() { printf '%s/a/grafana-app-observability-app/services/service/%s---%s%s' "$BASE" "$NS" "$1" "$QS"; }

if [ -z "$BASE" ]; then
  echo "No GRAFANA_URL in .env yet: log in with gcx, then run make setup again." >&2
  exit 1
fi
if [ "${1:-}" = "--url" ]; then page "${2:-welcome-desk}"; echo; exit 0; fi

H=$'\033[1;38;5;179m'; D=$'\033[2m'; R=$'\033[0m'
printf '\n%s☕ Your services in Grafana App Observability%s  %s(service.namespace = %s)%s\n' "$H" "$R" "$D" "$NS" "$R"
printf '   welcome-desk  %s\n' "$(page welcome-desk)"
printf '   coffee-bar    %s\n' "$(page coffee-bar)"
printf '%s   ⌘/Ctrl-click a link, or run: make open%s\n\n' "$D" "$R"
