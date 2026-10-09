FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
 && opentelemetry-bootstrap -a install

COPY app.py .

EXPOSE 8000

# ── The entire instrumentation story for this service ──────────────────
# `opentelemetry-instrument` wraps the process, discovers FastAPI at
# import time, and wires tracing + metrics + logs. Zero lines in app.py.
CMD ["opentelemetry-instrument", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
