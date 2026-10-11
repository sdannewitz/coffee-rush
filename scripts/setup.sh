#!/usr/bin/env bash
# Writes a ready-to-use .env for Coffee Rush. Asks four questions; gcx pre-fills
# what it can detect from your login, so Enter accepts and pasting overrides:
#   1. your nickname         → service.namespace = homework-<nickname>
#   2. OTLP endpoint         (from your facilitator, or detected via gcx)
#   3. instance ID           (from your facilitator, or detected via gcx)
#   4. ingest token          (from your facilitator; gcx can't create it)
# Re-running is safe: your previous answers become the defaults.
#
# Non-interactive: set ATTENDEE, GRAFANA_CLOUD_OTLP_ENDPOINT,
# GRAFANA_CLOUD_INSTANCE_ID, GRAFANA_CLOUD_API_KEY (and optionally GCX_CONTEXT,
# APP_PORT, ENV_FILE) and those questions are skipped.
set -euo pipefail
cd "$(dirname "$0")/.."
ENV_FILE="${ENV_FILE:-.env}"

ok()   { printf '\033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
die()  { printf '\033[31m✘\033[0m %s\n' "$*" >&2; exit 1; }
str()  { tr -d '"\n'; }                        # gcx --jq prints JSON strings
# q ARGS...: run gcx, print its (unquoted) answer; print nothing if gcx failed or reported an error
q()    { local out; out=$(gcx "$@" 2>/dev/null) || return 0
         case "$out" in *gcx.error*|null) return 0 ;; esac; printf '%s' "$out" | str; }
old()  { [ -f "$ENV_FILE" ] && sed -n "s/^$1=//p" "$ENV_FILE" | tail -1 || true; }
slug() { tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed -e 's/^-*//' -e 's/-*$//' | cut -c1-40; }
TTY=0; [ -t 0 ] && TTY=1

# read_secret VAR: read a line without echoing it, printing one * per character
read_secret() {
  local c s=""
  while IFS= read -rs -n1 c; do
    case "$c" in
      "")             break ;;                                        # Enter
      $'\177'|$'\b')  [ -n "$s" ] && { s=${s%?}; printf '\b \b'; } ;; # Backspace
      *)              s+=$c; printf '*' ;;
    esac
  done
  echo
  printf -v "$1" '%s' "$s"
}

# ask VAR "question" "default" [secret]: prompt with a default; Enter keeps it.
ask() {
  local var=$1 q=$2 def=$3 secret=${4:-} ans=""
  if [ "$TTY" = 1 ]; then
    if [ -n "$secret" ]; then
      printf '%s%s: ' "$q" "${def:+ [Enter keeps the current one]}"; read_secret ans
    else
      printf '%s%s: ' "$q" "${def:+ [$def]}"; read -r ans
    fi
  fi
  printf -v "$var" '%s' "${ans:-$def}"
}

command -v docker >/dev/null 2>&1 || die "docker not found. Install Docker Desktop, OrbStack, Rancher Desktop or Docker Engine."
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 not found (docker compose version)."

# ── What gcx knows (optional: everything can also be typed in) ───────────────
CTX="" LOGIN="" DET_ID="" DET_ENDPOINT="" DET_URL=""
if command -v gcx >/dev/null 2>&1; then
  CTX="${GCX_CONTEXT:-$(q config current-context --jq '.["current-context"]')}"
  if [ -n "$CTX" ]; then
    LOGIN=$(q --context "$CTX" api /api/user --jq .login)
  fi
  if [ -n "$LOGIN" ]; then
    ok "gcx is logged in to '$CTX' as $LOGIN"
    STACK=$(q config view --jq ".contexts[\"$CTX\"].stack")
    STACK="${STACK:-$CTX}"
    DET_ID=$(q config view --jq ".stacks[\"$STACK\"].grafana[\"stack-id\"]")
    DET_URL=$(q config view --jq ".stacks[\"$STACK\"].grafana.server" | sed 's:/*$::')
    region_of() { grep -oE 'prod-[a-z]+-[a-z]+-[0-9]+' | head -1 || true; }
    REGION=$(q config view --jq ".stacks[\"$STACK\"].grafana[\"proxy-endpoint\"]" | region_of)
    [ -n "$REGION" ] || REGION=$(q --context "$CTX" datasources list \
      --jq '.datasources[] | select(.uid=="grafanacloud-prom") | .url' | region_of)
    DET_ENDPOINT="${REGION:+https://otlp-gateway-$REGION.grafana.net/otlp}"
  else
    CTX=""
    warn "gcx isn't logged in, so nothing is pre-filled. You'll need the login for the exercise:"
    note "gcx login workshop --server https://<your-stack>.grafana.net --oauth"
  fi
else
  warn "gcx not found. Install it for the exercise: brew install gcx"
fi
echo

# ── 1. Nickname → your personal label ────────────────────────────────────────
DEF_NICK="$(old ATTENDEE)"
[ -n "$DEF_NICK" ] || DEF_NICK=$(printf '%s' "${LOGIN%%@*}" | slug)
[ -n "$DEF_NICK" ] || DEF_NICK=$(printf '%s' "${USER:-}" | slug)
while :; do
  if [ -n "${ATTENDEE:-}" ]; then NICK="$ATTENDEE"; else ask NICK "1/4 Your name or nickname" "$DEF_NICK"; fi
  NICK=$(printf '%s' "$NICK" | slug)
  if [ -z "$NICK" ]; then
    [ "$TTY" = 1 ] && [ -z "${ATTENDEE:-}" ] || die "The nickname needs at least one letter or digit."
    warn "Use letters or digits."; continue
  fi
  NAMESPACE="homework-$NICK"
  # Someone else already sending as this namespace? (Your own earlier runs are fine.)
  if [ -n "$LOGIN" ] && [ "$TTY" = 1 ] && [ -z "${ATTENDEE:-}" ] && [ "$NAMESPACE" != "$(old SERVICE_NAMESPACE)" ]; then
    IN_USE=$(q --context "$CTX" metrics query \
      "count(last_over_time(target_info{service_namespace=\"$NAMESPACE\"}[1h]))" --jq '.data.result | length')
    if [ "${IN_USE:-0}" != "0" ]; then
      warn "'$NAMESPACE' already sent telemetry in the last hour. If that wasn't you, pick another nickname."
      ask SAME "    Use it anyway? (y/N)" "n"
      case "$SAME" in [yY]*) ;; *) DEF_NICK=""; continue ;; esac
    fi
  fi
  break
done

# ── 2. + 3. Where telemetry goes ─────────────────────────────────────────────
DEF_ENDPOINT="$(old GRAFANA_CLOUD_OTLP_ENDPOINT)"; DEF_ENDPOINT="${DEF_ENDPOINT:-$DET_ENDPOINT}"
DEF_ID="$(old GRAFANA_CLOUD_INSTANCE_ID)";         DEF_ID="${DEF_ID:-$DET_ID}"
if [ -n "${GRAFANA_CLOUD_OTLP_ENDPOINT:-}" ]; then ENDPOINT="$GRAFANA_CLOUD_OTLP_ENDPOINT"
else ask ENDPOINT "2/4 OTLP endpoint" "$DEF_ENDPOINT"; fi
case "$ENDPOINT" in https://*) ;; *) die "The OTLP endpoint should look like https://otlp-gateway-<region>.grafana.net/otlp" ;; esac
if [ -n "${GRAFANA_CLOUD_INSTANCE_ID:-}" ]; then INSTANCE_ID="$GRAFANA_CLOUD_INSTANCE_ID"
else ask INSTANCE_ID "3/4 Instance ID" "$DEF_ID"; fi
case "$INSTANCE_ID" in ''|*[!0-9]*) die "The instance ID is a number, e.g. 1234567." ;; esac

# ── 4. The ingest token ──────────────────────────────────────────────────────
DEF_TOKEN=""
[ "$(old GRAFANA_CLOUD_INSTANCE_ID)" = "$INSTANCE_ID" ] && DEF_TOKEN="$(old GRAFANA_CLOUD_API_KEY)"
if [ -n "${GRAFANA_CLOUD_API_KEY:-}" ]; then TOKEN="$GRAFANA_CLOUD_API_KEY"
else ask TOKEN "4/4 Ingest token (glc_…, input hidden)" "$DEF_TOKEN" secret; fi
[ -n "$TOKEN" ] || die "No ingest token. Ask your facilitator, or run: GRAFANA_CLOUD_API_KEY=glc_... make setup"
case "$TOKEN" in glc_*) ;; *) warn "Grafana Cloud access policy tokens usually start with glc_." ;; esac

PORT="${APP_PORT:-$(old APP_PORT)}"
GRAFANA_URL="${GRAFANA_URL:-${DET_URL:-$(old GRAFANA_URL)}}"   # for the App Observability links

# ── Write .env ───────────────────────────────────────────────────────────────
[ -f "$ENV_FILE" ] && cp "$ENV_FILE" "$ENV_FILE.bak"
umask 077
cat > "$ENV_FILE" <<EOF
# Written by scripts/setup.sh. Re-run \`make setup\` to change anything.
ATTENDEE=$NICK
SERVICE_NAMESPACE=$NAMESPACE
GRAFANA_CLOUD_OTLP_ENDPOINT=$ENDPOINT
GRAFANA_CLOUD_INSTANCE_ID=$INSTANCE_ID
GRAFANA_CLOUD_API_KEY=$TOKEN
APP_PORT=${PORT:-8080}
GCX_CONTEXT=$CTX
GRAFANA_URL=$GRAFANA_URL
EOF

echo
ok "wrote $ENV_FILE"
note "your label   service.namespace = $NAMESPACE"
note "sending to   $ENDPOINT (instance $INSTANCE_ID)"
if [ -n "$CTX" ]; then note "gcx context  $CTX"
else warn "log in with gcx before the exercise: gcx login workshop --server https://<your-stack>.grafana.net --oauth"; fi
