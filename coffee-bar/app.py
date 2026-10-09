"""
coffee-bar: the Python barista behind the Coffee Rush counter.

Note what is NOT in this file: no OpenTelemetry import, no tracer, no
exporter, no middleware. Instrumentation is added at run time by the
`opentelemetry-instrument` wrapper in the Dockerfile.
"""
import asyncio
import logging
import os
import random

from fastapi import FastAPI
from pydantic import BaseModel

PULL_MS = int(os.getenv("PULL_MS", "90"))

log = logging.getLogger("coffee-bar")
logging.basicConfig(level=logging.INFO)

app = FastAPI(title="coffee-bar")

MENU = [
    "Espresso",
    "Doppio",
    "Americano",
    "Flat White",
    "Latte Macchiato",
    "Cappuccino",
    "Cortado",
    "Mocha",
    "Filter Coffee",
    "Cold Brew",
]

MILK = ["whole", "oat", "none"]


class Order(BaseModel):
    ticket: str


class BatchOrder(BaseModel):
    tickets: list[str]


async def _pull_one(ticket: str) -> dict:
    """Pulling a shot takes time. This is the only latency in the system."""
    await asyncio.sleep(PULL_MS / 1000)
    return {
        "ticket": ticket,
        "drink": random.choice(MENU),
        "milk": random.choice(MILK),
    }


@app.post("/pull")
async def pull(order: Order):
    log.info("pulling one shot for ticket %s", order.ticket)
    return await _pull_one(order.ticket)


@app.post("/pull/batch")
async def pull_batch(order: BatchOrder):
    """Runs the whole queue on the machine at once."""
    log.info("pulling %d shots in one round", len(order.tickets))
    drinks = await asyncio.gather(*(_pull_one(t) for t in order.tickets))
    return {"drinks": drinks}


@app.get("/healthz")
async def healthz():
    return {"status": "ok", "pull_ms": PULL_MS}
