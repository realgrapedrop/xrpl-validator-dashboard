#!/usr/bin/env python3
"""
Lightweight WebSocket-based uptime exporter for rippled.
Updates every 5 seconds via WebSocket, exposes Prometheus metrics on /metrics.
"""
import os
import asyncio
import logging
from prometheus_client import Gauge, start_http_server
from xrpl.asyncio.clients import AsyncWebsocketClient
from xrpl.models.requests import ServerState

# Configuration
WS_URL = os.getenv("XRPL_WS_URL", "ws://localhost:6006")
SCRAPE_INTERVAL = float(os.getenv("SCRAPE_INTERVAL", "5"))
EXPORTER_PORT = int(os.getenv("EXPORTER_PORT", "9102"))
INSTANCE = os.getenv("INSTANCE_LABEL", "validator")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

# Setup logging
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL.upper()),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Prometheus metrics
uptime_gauge = Gauge(
    "xrpl_rippled_uptime_seconds",
    "Rippled process uptime in seconds",
    ["instance"],
)

uptime_formatted_gauge = Gauge(
    "xrpl_rippled_uptime_formatted",
    "Formatted uptime (always 1, display the 'uptime' label)",
    ["instance", "uptime"],
)

# Track last formatted value to detect changes
last_formatted_value = None


def format_uptime(seconds: int) -> str:
    """Format uptime seconds as 'Xd:Xh:Xm' (no seconds, with colons)."""
    if seconds < 0:
        return "0m"

    days = seconds // 86400
    hours = (seconds % 86400) // 3600
    minutes = (seconds % 3600) // 60

    parts = []
    if days > 0:
        parts.append(f"{days}d")
    if hours > 0 or days > 0:
        parts.append(f"{hours}h")
    parts.append(f"{minutes}m")

    return ":".join(parts)


async def fetch_uptime_seconds(client: AsyncWebsocketClient) -> int:
    """Fetch uptime from rippled via WebSocket."""
    request = ServerState()
    response = await client.request(request)

    if response.is_successful():
        uptime = int(response.result["state"]["uptime"])
        return uptime
    else:
        raise Exception(f"ServerState request failed: {response}")


async def run_loop():
    """Main loop: connect to rippled WebSocket and update uptime metric every 5s."""
    backoff = 1

    while True:
        try:
            logger.info(f"Connecting to rippled WebSocket at {WS_URL}")
            async with AsyncWebsocketClient(WS_URL) as client:
                logger.info("Connected to rippled WebSocket")
                backoff = 1  # Reset backoff on successful connection

                while True:
                    try:
                        global last_formatted_value
                        uptime = await fetch_uptime_seconds(client)
                        # Floor to current minute (not round) to prevent bouncing
                        uptime_floored = (uptime // 60) * 60
                        formatted = format_uptime(uptime_floored)

                        # Clear all old label combinations when value changes
                        if last_formatted_value != formatted:
                            uptime_formatted_gauge.clear()
                            last_formatted_value = formatted
                            logger.info(f"Uptime changed to: {formatted}")

                        uptime_gauge.labels(instance=INSTANCE).set(uptime)
                        uptime_formatted_gauge.labels(instance=INSTANCE, uptime=formatted).set(1)
                        logger.debug(f"Updated uptime: {uptime}s ({formatted})")
                    except Exception as e:
                        # Keep last value; just skip this tick
                        logger.warning(f"Failed to fetch uptime (keeping last value): {e}")

                    await asyncio.sleep(SCRAPE_INTERVAL)

        except Exception as e:
            logger.error(f"WebSocket connection lost: {e}. Retrying in {backoff}s...")
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 30)  # Exponential backoff up to 30s


def main():
    """Start Prometheus HTTP server and run the update loop."""
    logger.info(f"Starting uptime exporter on port {EXPORTER_PORT}")
    logger.info(f"Scrape interval: {SCRAPE_INTERVAL}s")
    logger.info(f"Instance label: {INSTANCE}")

    # Start Prometheus HTTP server
    start_http_server(EXPORTER_PORT)
    logger.info(f"Prometheus metrics available at http://0.0.0.0:{EXPORTER_PORT}/metrics")

    # Run the update loop
    asyncio.run(run_loop())


if __name__ == "__main__":
    main()
