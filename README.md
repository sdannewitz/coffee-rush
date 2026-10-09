# Coffee Rush ☕

**A hands-on lab for [gcx](https://github.com/grafana/gcx), the Grafana Cloud CLI.**

Two tiny services, zero lines of OpenTelemetry code, and one performance bug that
only shows up at rush hour. You run them on your laptop, send their telemetry to
Grafana Cloud, break them, find out why with gcx (or let your coding agent do it),
ship the fix, and prove it worked. About 60–90 minutes.

```
  browser ──▶ welcome-desk ──▶ coffee-bar
              (Node 22)        (Python 3.12)
                   │               │
                   └──── OTLP ─────┘
                           ▼
                    otel-collector ──▶ Grafana Cloud
```

## What you need

- **git**, **make**, **Docker** with Compose v2 (Docker Desktop, OrbStack, Rancher Desktop or Docker Engine)
- **gcx 1.5 or newer**: `brew install gcx`, or see the [install docs](https://github.com/grafana/gcx)
- **python3**, only for the trace waterfall helper
- **A coding agent**: Claude Code, Cursor, Codex, Copilot, … (there's a by-hand path too)
- **A Grafana Cloud stack** you can log in to (Viewer is enough), plus its **OTLP endpoint,
  instance ID and an ingest token**. In a workshop, your facilitator gives you all of these.
  On your own, see [Use your own stack](#use-your-own-stack).

On Windows, run everything inside WSL2.

## 1 · Clone and log in

```bash
git clone https://github.com/sdannewitz/coffee-rush.git && cd coffee-rush
gcx login workshop --server https://<your-stack>.grafana.net --oauth
gcx config check
```

## 2 · Start it

```bash
make up        # first run asks 4 questions and writes .env, starts the app, waits for your telemetry
```

The first `make up` runs `make setup`, which asks:

```text
1/4 Your name or nickname [jane-doe]:
2/4 OTLP endpoint [https://otlp-gateway-prod-us-west-0.grafana.net/otlp]:
3/4 Instance ID [1234567]:
4/4 Ingest token (glc_…, input hidden):
```

gcx pre-fills what it can detect from your login (the values in brackets): press
Enter to accept, or paste the values from your facilitator. Out comes a ready-to-use
`.env`. Run `make setup` again any time to change an answer.

`make up` then waits until your traces arrive and App Observability has built your
service pages (2–4 minutes), and ends with your personal links, highlighted:

```text
☕ Your services in Grafana App Observability  (service.namespace = homework-jane-doe)
   welcome-desk  https://<your-stack>.grafana.net/a/grafana-app-observability-app/services/service/homework-jane-doe---welcome-desk?…
   coffee-bar    https://<your-stack>.grafana.net/a/grafana-app-observability-app/services/service/homework-jane-doe---coffee-bar?…
```

`make links` prints them again, `make open` opens your welcome-desk page. Then open
<http://localhost:8080>: one order every second, about 100 ms each. Calm.

**Your label.** Your nickname ends up on every span, metric and log line as
`service.namespace = homework-<nickname>`. The app shows it at the top. The stack is
shared with other people, so **filter every query by it**. (Setup warns you if
someone else already uses that nickname.) `make cheatsheet` prints all the queries
below with your namespace already filled in.

## 3 · Break it

Click **☕ Rush hour** in the app, or run `make rush`. The latency turns red.

Nothing else changed: same code, same services, just more customers at once.

## 4 · Find out why

Pick a path, or try all three. In every path, the goal is the same: **name the
slow component and explain the pattern, with evidence from telemetry, before you
touch the code.**

### A · Your coding agent drives

Start your agent in this folder and ask it. No plugin needed: it runs gcx like any
other command-line tool, and [`AGENTS.md`](AGENTS.md) tells it which queries to run,
which namespace to filter on, and what not to touch.

```bash
claude        # or cursor, codex, copilot, …
```

> The welcome-desk got slow after I switched on rush hour. Use gcx and the telemetry
> in my namespace to find out why. Show me the evidence before you change any code.

<details>
<summary>Optional: gcx skills for your agent</summary>

gcx detects when an agent is driving it and switches to agent-friendly output on
its own. Skills add ready-made Grafana playbooks on top, such as a debugging
workflow:

```text
# Claude Code
/plugin marketplace add grafana/gcx
/plugin install gcx@gcx-marketplace
```

```bash
# Cursor, Codex, Copilot & co.
gcx agent skills install --all
```
</details>

### B · You and gcx

```bash
make cheatsheet          # copy-paste ready versions of these, with your namespace
```

1. Which service got slow? Plot p95 latency per service, right in your terminal:
   `gcx metrics query '<p95 by service_name>' --since 30m -o graph`
2. Find slow requests: `gcx traces query '{ resource.service.namespace = "homework-<you>" && duration > 1s }' -o table`
3. Compare a slow trace with a fast one. `./scripts/staircase.sh <trace-id>` draws the
   calls from welcome-desk to coffee-bar as a waterfall.
4. Check what the services logged: `gcx logs query '{service_namespace="homework-<you>"}' -o table`

### C · Ask the Grafana Assistant from your terminal

```bash
gcx assistant prompt "In service.namespace homework-<you>, welcome-desk GET /api/orders got slow. \
  Look at its traces and the calls to coffee-bar. What pattern do you see?"
gcx assistant prompt "How would you fix it?" --continue
```

Specific prompts work best. "What's wrong?" makes the Assistant guess.

<details>
<summary><b>Stuck? Hint 1</b></summary>

Put a slow trace and a fast one side by side. Count the calls from welcome-desk to
coffee-bar, and look at when each one starts relative to the previous one.
</details>

<details>
<summary><b>Hint 2 (spoiler)</b></summary>

During rush hour, welcome-desk calls coffee-bar's `POST /pull` once per order,
strictly one after another: 25 orders × ~90 ms each. Have a look at what else
coffee-bar offers in [`coffee-bar/app.py`](coffee-bar/app.py).
</details>

## 5 · Fix it with your agent, prove it with gcx

Ask your agent:

> Now fix it. Rebuild only welcome-desk and keep rush hour on. Then prove with gcx
> that it worked: compare the p95 latency of GET /api/orders before and after, and
> show me one new trace next to an old one.

It changes the code, rebuilds that one service, and reports before and after from
Grafana: p95 down from about 2.5 s to about 0.1 s, and new traces that look
completely different. Rush hour is still on (it survives the rebuild), so the queue
is just as long as before.

<details>
<summary>Rather do it by hand?</summary>

Change [`welcome-desk/server.js`](welcome-desk/server.js), then:

```bash
docker compose up -d --build welcome-desk
make status
make cheatsheet   # and run the same queries again
```
</details>

<details>
<summary><b>Solution</b></summary>

In [`welcome-desk/server.js`](welcome-desk/server.js), replace the loop in
`placeOrders()` with one call to coffee-bar's batch endpoint:

```js
async function placeOrders(tickets) {
  const res = await fetch(`${COFFEE_BAR}/pull/batch`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ tickets }),
  });
  const { drinks } = await res.json();
  return drinks;
}
```

Rush hour drops from ~2.5 s to ~0.1 s, still serving 25 drinks.
</details>

## Stretch goals

- **Dashboards as code.** [`dashboards/coffee-rush-golden-signals.json`](dashboards/coffee-rush-golden-signals.json)
  is a golden-signals dashboard for this app. Lint it offline with
  `gcx dev lint run dashboards`: it has findings. Fix them (or have your agent fix
  them) until the linter is happy. On [your own stack](#use-your-own-stack), where you
  can write, push it and look at it:
  `gcx resources push -p dashboards && gcx dashboards snapshot coffee-rush-golden-signals --since 30m`.
- **Check the instrumentation.**
  `gcx instrumentation check collector --collector-config-path otel-collector-config.yaml`
- **Go beyond zero-code.** Ask your agent to add a custom span attribute, such as
  the queue length, to `GET /api/orders`, and find it again in a trace.

## Reset and clean up

```bash
make reset     # undo your code changes and switch rush hour off, to start over
make down      # stop everything
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `make setup` says gcx isn't logged in (nothing pre-filled) | `gcx login workshop --server https://<your-stack>.grafana.net --oauth`, then `make setup` again. Or type the values from your facilitator |
| `make verify` finds no traces | `docker compose logs otel-collector \| grep -i -E 'error\|401\|403'`. A 401 means a wrong or expired ingest token: run `make setup` again |
| gcx prints JSON and hint lines instead of tables | Your terminal inherited a coding agent's environment, so gcx switched to agent mode. Run `unset CLAUDECODE CLAUDE_CODE`, or open a fresh terminal / restart your editor |
| Port 8080 is taken | Set `APP_PORT=8090` in `.env`, then `make up` |
| Latency didn't drop after your fix | `docker compose up -d --build --force-recreate welcome-desk` |
| `staircase.sh` says there are no calls to /pull | You picked a fast trace, or your fix is already live. Pick a trace with `duration > 1s` |

## How it works

- **welcome-desk** is instrumented by one flag in its [Dockerfile](welcome-desk/Dockerfile):
  `NODE_OPTIONS="--require @opentelemetry/auto-instrumentations-node/register"`.
- **coffee-bar** is instrumented by one wrapper word in its [Dockerfile](coffee-bar/Dockerfile):
  `opentelemetry-instrument`.
- The **collector** holds the only credential and forwards everything to the
  Grafana Cloud OTLP endpoint.
- [`scripts/setup.sh`](scripts/setup.sh) pre-fills its questions from gcx: your
  login (default nickname), your stack's ID (instance ID) and its region (OTLP
  endpoint). gcx can't mint ingest tokens, so the token always comes from you.

## Use your own stack

No workshop? Create a free [Grafana Cloud](https://grafana.com/auth/sign-up) account.
In your stack, go to **Connections → Add new connection → OpenTelemetry (OTLP)** and
generate a token. It shows the OTLP endpoint and instance ID too. Then:

```bash
gcx login mystack --server https://<your-stack>.grafana.net --oauth
make up         # answer the 4 questions
```

## For facilitators

- **Hand out three values:** the stack's OTLP endpoint, its instance ID and one
  ingest token for the room. Endpoint and instance ID aren't secret (and gcx usually
  pre-fills them). For the token, in grafana.com → your org → **Access Policies**,
  create a policy for the workshop stack with only `metrics:write`, `logs:write` and
  `traces:write`. Add a token with a short expiry, share it in the workshop chat
  (not in a repo or dashboard), and delete it afterwards.
- **Viewer is enough** for attendees. Apart from telemetry, nothing in this lab
  writes to the stack.
- Every attendee's telemetry is separated by `service.namespace = homework-<nickname>`.
  `deployment.environment = homework` marks all of it.

## License

[Apache License 2.0](LICENSE)
