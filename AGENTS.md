# AGENTS.md

You're pairing with someone doing a hands-on lab. Two services run locally in
Docker and send OpenTelemetry data to Grafana Cloud. When "rush hour" is on, the
app gets slow. Help them find out why **with telemetry, via gcx**, then fix it and
prove the fix. The README has the full exercise.

## Ground rules

1. **Evidence before code.** Don't diagnose by reading the source. Reproduce the
   problem, query the telemetry, and show the evidence first: which service and
   endpoint got slow, one slow trace and its span pattern, compared with a fast one.
   Then propose the change. Even if asked to "just fix it", show one trace before
   and one after.
2. **Scope every query to the user's namespace.** Read `SERVICE_NAMESPACE` and
   `GCX_CONTEXT` from `.env`. The stack is shared with other people. Pass
   `--context "$GCX_CONTEXT"` to every gcx command.
3. **Read-only against Grafana.** The user is most likely a Viewer. Never create,
   update or delete dashboards, alert rules, folders or anything else in Grafana.
   To work on dashboards, edit files in `dashboards/` and check them offline with
   `gcx dev lint run dashboards`.
4. **Never print, log or commit the ingest token** (`GRAFANA_CLOUD_API_KEY` in `.env`).
   Don't `cat .env`; read single keys with `sed -n 's/^SERVICE_NAMESPACE=//p' .env`.
5. `gcx assistant ...` commands consume Grafana Assistant tokens. Use them when the
   user asks for it, not as your default tool.

## Run it

| Command | What it does |
|---|---|
| `make setup` | Asks nickname, OTLP endpoint, instance ID and ingest token (gcx pre-fills defaults), writes `.env`. Interactive: let the user run it. |
| `make up` | Build and start everything (`docker compose up -d --build`) |
| `make verify` | Waits for the user's traces, then for App Observability, then prints their App Observability links (`make up` does this too) |
| `make links` | Prints the App Observability links for welcome-desk and coffee-bar (`scripts/links.sh --url <service>` for one URL) |
| `make rush` | Toggle rush hour (persisted in `state/rush`, survives rebuilds) |
| `make status` | Time one `GET /api/orders` |
| `make cheatsheet` | Ready-to-run gcx queries with the namespace filled in |
| `make reset` | Restore the original code and switch rush hour off |
| `docker compose up -d --build welcome-desk` | Rebuild one service after a code change |

The app is at `http://localhost:$APP_PORT` (default 8080). Telemetry shows up in
Grafana Cloud about 30–60 seconds after it's produced.

## Proving a fix

After changing code, don't stop at "it should be faster now". Prove it with gcx:

1. Rebuild only the changed service (`docker compose up -d --build <service>`) and
   leave rush hour on (`curl -s localhost:$APP_PORT/healthz` shows `rushMode`).
2. Wait about a minute for new telemetry, then compare p95 latency of
   `GET /api/orders` for the 10 minutes before the rebuild and the minutes after
   (`gcx metrics query ... --from/--to`, or the p95 query below with `-o graph`).
3. Put one new trace next to an old one (`./scripts/staircase.sh <trace-id>` for
   both) and explain the difference.
4. Report the numbers: before, after, and how many calls to coffee-bar per request.

## Telemetry cheat sheet

`$NS` is `SERVICE_NAMESPACE`, `$CTX` is `GCX_CONTEXT` from `.env`.

- **Traces (Tempo):**
  `gcx --context $CTX traces query '{ resource.service.namespace = "$NS" && duration > 1s }' --since 15m -o table`,
  then `gcx --context $CTX traces get <trace-id> -o json`, or `./scripts/staircase.sh <trace-id>`
  for a waterfall of the calls to coffee-bar.
- **Metrics (Mimir):** both services emit `http_server_duration_milliseconds_{bucket,count,sum}`
  (older semconv, milliseconds) with `service_name` and `service_namespace` labels.
  p95 per service:
  `gcx --context $CTX metrics query 'histogram_quantile(0.95, sum by (le, service_name) (rate(http_server_duration_milliseconds_bucket{service_namespace="$NS"}[5m])))' --since 30m -o graph`.
  Discover labels with `gcx --context $CTX metrics labels --metric http_server_duration_milliseconds_count`.
- **Logs (Loki):** `gcx --context $CTX logs query '{service_namespace="$NS"}' --since 15m -o table`.

gcx quirks: `traces get` outputs only `json` or `yaml`. TraceQL metrics need a
selector first (`'{ ... } | quantile_over_time(duration, .95)'`).

## Repo map

- `welcome-desk/`: Node 22 + Express, port 8080. `GET /api/orders`, `POST /api/rush`, UI in `public/`.
- `coffee-bar/`: Python 3.12 + FastAPI, port 8000 (internal only).
- `otel-collector-config.yaml`: the only egress point and the only credential.
- `docker-compose.yml`: both services, the collector and a 1 req/s load generator.
- `scripts/`: `setup.sh`, `verify.sh`, `cheatsheet.sh`, `staircase.sh`/`.py`.
- `dashboards/`: a golden-signals dashboard as code (`gcx dev lint run dashboards`).

Neither service has OpenTelemetry code: instrumentation comes from the Dockerfiles
(`--require @opentelemetry/auto-instrumentations-node/register` and
`opentelemetry-instrument`). Keep it that way unless the user asks for manual spans.
