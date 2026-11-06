/*
 * welcome-desk: the Node.js front counter of Coffee Rush.
 *
 * There is no OpenTelemetry import in this file. Traces, metrics and logs come
 * from the `--require @opentelemetry/auto-instrumentations-node/register` flag
 * in the Dockerfile.
 */
import express from "express";
import { readFileSync, writeFileSync } from "node:fs";

const app = express();
const COFFEE_BAR = process.env.COFFEE_BAR_URL || "http://localhost:8000";
const NAMESPACE = process.env.SERVICE_NAMESPACE || "coffee-rush";
const QUEUE_SIZE = Number(process.env.QUEUE_SIZE || 25);
const PORT = 8080;
// Optional sub-path when a reverse proxy serves the app under one (e.g. a
// Cloudflare tunnel route /coffee). Normalized to "/coffee", or "" for none.
const BASE_PATH = (process.env.BASE_PATH || "").replace(/^\/*|\/*$/g, "").replace(/^(.+)$/, "/$1");

// Rush hour: the whole queue orders at once. Persisted to disk so it survives
// a rebuild of this service.
const STATE = "/state/rush";
const readRush = () => { try { return readFileSync(STATE, "utf8").trim() === "true"; } catch { return false; } };
const writeRush = (v) => { try { writeFileSync(STATE, String(v)); } catch {} };

let rushMode = readRush();
let nextTicket = 1;

const ticket = () => `#${String(nextTicket++).padStart(3, "0")}`;

// The proxy passes the path through unchanged, so strip the prefix here. Routes
// (and so the telemetry) stay /api/orders either way, and requests without the
// prefix (the load generator, make status) keep working.
if (BASE_PATH) {
  app.use((req, res, next) => {
    if (req.path === BASE_PATH) return res.redirect(302, `${BASE_PATH}/${req.url.slice(BASE_PATH.length)}`);
    if (req.url.startsWith(`${BASE_PATH}/`)) req.url = req.url.slice(BASE_PATH.length);
    next();
  });
}

app.use(express.json());
app.use(express.static("public"));

// One order normally, the whole queue during rush hour.
async function placeOrders(tickets) {
  const drinks = [];
  for (const t of tickets) {
    const res = await fetch(`${COFFEE_BAR}/pull`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ticket: t }),
    });
    drinks.push(await res.json());
  }
  return drinks;
}

app.get("/api/orders", async (_req, res) => {
  const tickets = Array.from({ length: rushMode ? QUEUE_SIZE : 1 }, ticket);
  const started = Date.now();
  try {
    const drinks = await placeOrders(tickets);
    res.json({
      namespace: NAMESPACE,
      rushMode,
      queueLength: tickets.length,
      latencyMs: Date.now() - started,
      drinks,
    });
  } catch (err) {
    console.error("welcome desk failed:", err.message);
    res.status(502).json({ error: "the coffee bar is not responding" });
  }
});

app.post("/api/rush", (_req, res) => {
  rushMode = !rushMode;
  writeRush(rushMode);
  console.warn(`rush mode ${rushMode ? "ON: the whole queue orders at once" : "OFF"}`);
  res.json({ rushMode });
});

app.get("/healthz", (_req, res) => res.json({ status: "ok", rushMode }));

app.listen(PORT, () => console.log(`welcome-desk listening on :${PORT}${BASE_PATH ? ` and under ${BASE_PATH}/` : ""} (service.namespace=${NAMESPACE})`));
