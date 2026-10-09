FROM node:22-slim

WORKDIR /app
COPY package.json .
RUN npm install --omit=dev

COPY server.js .
COPY public ./public

EXPOSE 8080

# ── The entire instrumentation story for this service ──────────────────
# One --require. Express routes, outbound fetch calls, and runtime
# metrics are all discovered automatically. Zero lines in server.js.
ENV NODE_OPTIONS="--require @opentelemetry/auto-instrumentations-node/register"

CMD ["node", "server.js"]
