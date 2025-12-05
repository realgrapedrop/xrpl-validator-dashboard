#!/usr/bin/env python3
"""
XRPL Monitor - Main Monitor

Async monitoring application that connects to rippled via WebSocket,
processes real-time event streams, and writes metrics to VictoriaMetrics.
"""

import asyncio
import logging
import os
import signal
import sys
from pathlib import Path

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

# Load .env file if it exists
try:
    from dotenv import load_dotenv
    env_path = Path(__file__).parent.parent.parent / '.env'
    if env_path.exists():
        load_dotenv(env_path)
        logging.info(f"Loaded environment from {env_path}")
except ImportError:
    # python-dotenv not installed, manually load .env
    env_path = Path(__file__).parent.parent.parent / '.env'
    if env_path.exists():
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    os.environ[key.strip()] = value.strip()

from aiohttp import web
from clients.victoria_client import VictoriaMetricsClient
from clients.xrpl_client import XRPLWebSocketClient
from handlers.ledger_handler import LedgerHandler
from handlers.server_handler import ServerHandler
from handlers.validations_handler import ValidationsHandler
from monitor.http_poller import HTTPPoller
from monitor.state_manager import StateManager


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger(__name__)


# Global shutdown flag
shutdown_event = asyncio.Event()


def signal_handler(signum, frame):
    """Handle shutdown signals (SIGINT, SIGTERM)"""
    logger.info(f"Received signal {signum}, initiating graceful shutdown...")
    shutdown_event.set()


class MonitorConfig:
    """Configuration loaded from environment variables"""

    def __init__(self):
        # rippled connection
        self.rippled_ws_url = os.getenv('RIPPLED_WS_URL', 'ws://localhost:6006')
        self.rippled_http_url = os.getenv('RIPPLED_HTTP_URL', 'http://localhost:5005')

        # VictoriaMetrics connection
        self.victoria_url = os.getenv('VICTORIA_METRICS_URL', 'http://localhost:8428')

        # Logging
        self.log_level = os.getenv('LOG_LEVEL', 'INFO')

        # Validator key (optional - for filtering our validations)
        self.our_validator_key = os.getenv('VALIDATOR_PUBLIC_KEY', None)

        # Docker container name (optional - for peer metrics fallback)
        # If rippled runs in Docker and peers API is restricted, use docker exec
        self.rippled_docker_container = os.getenv('RIPPLED_DOCKER_CONTAINER', None)

        # Apply log level
        logging.getLogger().setLevel(getattr(logging, self.log_level.upper()))

    def __repr__(self):
        return (
            f"MonitorConfig(\n"
            f"  rippled_ws={self.rippled_ws_url}\n"
            f"  rippled_http={self.rippled_http_url}\n"
            f"  victoria={self.victoria_url}\n"
            f"  log_level={self.log_level}\n"
            f"  validator_key={'***' if self.our_validator_key else 'not set'}\n"
            f")"
        )


async def health_metrics_task(state_manager: StateManager, xrpl_client, victoria_client: VictoriaMetricsClient):
    """
    Background task to backup critical metrics and emit health metrics

    Runs every 30 seconds to:
    1. Emit WebSocket health metrics
    2. Emit state health metrics

    Runs every 5 minutes to:
    3. Backup critical metrics from VictoriaMetrics to JSON files
    """
    try:
        iteration = 0
        while not shutdown_event.is_set():
            # Emit health metrics every 30 seconds
            await xrpl_client.emit_health_metrics(victoria_client)
            await state_manager.emit_health_metrics()

            iteration += 1

            # Every 5 minutes (10 iterations × 30s), do backup
            if iteration % 10 == 0:
                await state_manager.backup_critical_metrics()
                state_manager.check_stale_state()

            # Run every 30 seconds
            try:
                await asyncio.wait_for(shutdown_event.wait(), timeout=30)
            except asyncio.TimeoutError:
                pass

    except Exception as e:
        logger.error(f"Health metrics task error: {e}", exc_info=True)


async def health_check_handler(request):
    """
    HTTP health check endpoint for Docker healthcheck

    Returns:
        200 OK if WebSocket is connected and healthy
        503 Service Unavailable if WebSocket is disconnected or unhealthy
    """
    xrpl_client = request.app['xrpl_client']

    if xrpl_client and xrpl_client.is_healthy:
        return web.Response(
            text="OK\nWebSocket: connected\nStatus: healthy\n",
            status=200,
            content_type='text/plain'
        )
    elif xrpl_client and xrpl_client.is_connected:
        return web.Response(
            text="DEGRADED\nWebSocket: connected\nStatus: heartbeat failures detected\n",
            status=200,
            content_type='text/plain'
        )
    else:
        return web.Response(
            text="UNHEALTHY\nWebSocket: disconnected\nStatus: not healthy\n",
            status=503,
            content_type='text/plain'
        )


async def start_health_server(xrpl_client, port: int = 8080):
    """
    Start HTTP health check server for Docker healthcheck monitoring

    Args:
        xrpl_client: XRPLWebSocketClient instance to monitor
        port: Port to listen on (default: 8080)

    Returns:
        web.AppRunner instance
    """
    app = web.Application()
    app['xrpl_client'] = xrpl_client
    app.router.add_get('/health', health_check_handler)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, '0.0.0.0', port)
    await site.start()

    logger.info(f"✓ Health check server started on http://0.0.0.0:{port}/health")
    return runner


async def monitor_uptime_updater(victoria_client: VictoriaMetricsClient):
    """
    Background task to update monitor uptime metric

    Updates xrpl_monitor_uptime_seconds every 30 seconds
    """
    from clients.victoria_client import create_gauge
    import time

    start_time = time.time()

    try:
        while not shutdown_event.is_set():
            uptime = time.time() - start_time
            timestamp_ms = int(time.time() * 1000)

            metric = create_gauge(
                "xrpl_monitor_uptime_seconds",
                uptime,
                timestamp=timestamp_ms
            )

            await victoria_client.write_metric(metric, flush_immediately=False)

            # Update every 30 seconds
            try:
                await asyncio.wait_for(shutdown_event.wait(), timeout=30)
            except asyncio.TimeoutError:
                pass

    except Exception as e:
        logger.error(f"Uptime updater error: {e}")


async def run_monitor(config: MonitorConfig):
    """
    Main monitor loop

    Args:
        config: Monitor configuration
    """
    victoria_client = None
    xrpl_client = None

    try:
        # Initialize VictoriaMetrics client
        logger.info("Initializing VictoriaMetrics client...")
        victoria_client = VictoriaMetricsClient(url=config.victoria_url)
        await victoria_client.start()

        # Health check VictoriaMetrics
        if not await victoria_client.health_check():
            logger.error("VictoriaMetrics is not healthy, exiting")
            return

        logger.info("✓ VictoriaMetrics connection established")

        # Initialize State Manager
        logger.info("Initializing State Manager...")
        state_manager = StateManager(victoria_client)

        # Validate state directory (fail fast if not writable)
        try:
            if not state_manager.validate_state_directory():
                logger.error("State directory validation failed, exiting")
                return
            logger.info("✓ State directory validated and writable")
        except RuntimeError as e:
            logger.error(f"State directory validation failed: {e}")
            logger.error("Cannot continue without state persistence. Please fix volume mount or permissions.")
            return

        # Initialize XRPL WebSocket client
        logger.info("Initializing XRPL WebSocket client...")
        xrpl_client = XRPLWebSocketClient(
            url=config.rippled_ws_url,
            http_url=config.rippled_http_url
        )

        # Connect to rippled
        if not await xrpl_client.connect():
            logger.error("Failed to connect to rippled, exiting")
            return

        logger.info("✓ Connected to rippled WebSocket")

        # Initialize handlers
        logger.info("Initializing stream handlers...")

        # Create validations_handler first (needed for cross-wiring)
        validations_handler = ValidationsHandler(
            victoria_client,
            ledger_handler=None,  # Will be set after ledger_handler creation
            our_validator_key=config.our_validator_key
        )

        # Create ledger_handler with reference to validations_handler (for reconciliation callbacks)
        ledger_handler = LedgerHandler(
            victoria_client,
            validation_handler=validations_handler
        )

        # Now cross-wire: give validations_handler the ledger_handler reference
        validations_handler.set_ledger_handler(ledger_handler)

        server_handler = ServerHandler(victoria_client)

        logger.info("✓ Handlers initialized (validation tracking uses full reconciliation)")

        # Recover validation history from VictoriaMetrics (if available)
        logger.info("Recovering validation history from VictoriaMetrics...")
        await validations_handler.recover_from_victoria_metrics()

        # Get server info
        server_info = await xrpl_client.get_server_info()
        if server_info:
            server_state = server_info.get('server_state', 'unknown')
            build_version = server_info.get('build_version', 'unknown')
            logger.info(
                f"✓ rippled info: state={server_state}, version={build_version}"
            )

            # If validator key not configured, try to get it from server_info
            # Use HTTP JSON-RPC endpoint which returns pubkey_validator more reliably
            if not config.our_validator_key:
                try:
                    import httpx
                    import json

                    async with httpx.AsyncClient() as client:
                        response = await client.post(
                            config.rippled_http_url,
                            json={"method": "server_info", "params": [{}]},
                            headers={"Content-Type": "application/json"}
                        )
                        if response.status_code == 200:
                            data = response.json()
                            result = data.get('result', {})
                            if "info" in result and "pubkey_validator" in result["info"]:
                                config.our_validator_key = result["info"]["pubkey_validator"]
                                logger.info(f"✓ Detected validator key: {config.our_validator_key}")
                            else:
                                logger.warning("pubkey_validator not found in server_info - validation metrics will not be collected")
                except Exception as e:
                    logger.warning(f"Could not fetch validator key from HTTP endpoint: {e}")

        # Initialize HTTP poller
        logger.info("Initializing HTTP poller...")
        http_poller = HTTPPoller(
            xrpl_client=xrpl_client,
            victoria_client=victoria_client,
            docker_container=config.rippled_docker_container
        )

        logger.info("✓ HTTP poller initialized")

        # Start health check server for Docker healthcheck
        logger.info("Starting health check server...")
        health_server = await start_health_server(xrpl_client, port=8090)

        # Subscribe to streams
        logger.info("Subscribing to WebSocket streams...")
        await xrpl_client.subscribe(streams=[
            "ledger",
            "server",
            "validations"
        ])

        logger.info("✓ Subscribed to streams: ledger, server, validations")

        # Set up message routing
        handlers = {
            'ledgerClosed': ledger_handler.handle,
            'serverStatus': server_handler.handle,
            'validationReceived': validations_handler.handle
        }

        # Start background tasks
        uptime_task = asyncio.create_task(monitor_uptime_updater(victoria_client))
        health_metrics = asyncio.create_task(health_metrics_task(state_manager, xrpl_client, victoria_client))
        reconciliation_task = asyncio.create_task(validations_handler.reconcile_pending_ledgers())
        logger.info("✓ Started reconciliation task (validation agreements with grace period)")

        # Start HTTP poller
        await http_poller.start(shutdown_event)

        logger.info("=" * 70)
        logger.info("🛡️  XRPL Monitor monitoring started")
        logger.info("=" * 70)
        logger.info("Listening for WebSocket events... (Press Ctrl+C to stop)")

        # Supervisor loop: automatically reconnect if WebSocket fails
        # This provides application-level resilience before Docker healthcheck kicks in
        reconnect_attempt = 0
        max_reconnect_attempts = 10

        while not shutdown_event.is_set():
            try:
                # Create listen task
                listen_task = asyncio.create_task(xrpl_client.listen(handlers))

                # Wait for either shutdown signal or listen task to complete
                done, pending = await asyncio.wait(
                    [listen_task, asyncio.create_task(shutdown_event.wait())],
                    return_when=asyncio.FIRST_COMPLETED
                )

                # Check if shutdown was requested
                if shutdown_event.is_set():
                    logger.info("Shutdown requested, cancelling listen task...")
                    listen_task.cancel()
                    try:
                        await listen_task
                    except asyncio.CancelledError:
                        pass
                    break

                # Listen task completed/failed - check if we should reconnect
                if not xrpl_client.is_connected:
                    reconnect_attempt += 1

                    if reconnect_attempt > max_reconnect_attempts:
                        logger.error(
                            f"Failed to reconnect after {max_reconnect_attempts} attempts. "
                            f"Giving up. Docker healthcheck will restart container if configured."
                        )
                        break

                    # Exponential backoff: 2^attempt seconds, capped at 60
                    delay = min(2 ** reconnect_attempt, 60)
                    logger.warning(
                        f"WebSocket disconnected. Reconnection attempt {reconnect_attempt}/{max_reconnect_attempts} "
                        f"in {delay}s..."
                    )

                    await asyncio.sleep(delay)

                    # Attempt to reconnect
                    if await xrpl_client.connect():
                        logger.info("✓ Reconnected to rippled WebSocket!")
                        logger.info("Resubscribing to streams...")

                        await xrpl_client.subscribe(streams=["ledger", "server", "validations"])

                        logger.info("✓ Resubscribed successfully, resuming monitoring")
                        reconnect_attempt = 0  # Reset counter on successful reconnection
                    else:
                        logger.error(f"Reconnection attempt {reconnect_attempt} failed")

            except asyncio.CancelledError:
                logger.info("Listen task cancelled")
                break
            except Exception as e:
                logger.error(f"Error in supervisor loop: {e}", exc_info=True)
                # On unexpected error, wait a bit before retrying
                await asyncio.sleep(5)

        # Cancel background tasks
        uptime_task.cancel()
        health_metrics.cancel()

        # Stop HTTP poller
        if 'http_poller' in locals():
            await http_poller.stop()

    except KeyboardInterrupt:
        logger.info("Interrupted by user")

    except Exception as e:
        logger.error(f"Fatal error in monitor: {e}", exc_info=True)

    finally:
        # Graceful shutdown
        logger.info("Shutting down gracefully...")

        # Stop HTTP poller if not already stopped
        if 'http_poller' in locals():
            try:
                await http_poller.stop()
            except Exception as e:
                logger.error(f"Error stopping HTTP poller: {e}")

        # Flush any pending metrics
        if victoria_client:
            logger.info("Flushing pending metrics...")
            try:
                await victoria_client.flush()
            except Exception as e:
                logger.error(f"Error flushing metrics: {e}")

            logger.info("Closing VictoriaMetrics client...")
            await victoria_client.close()

        # Stop health check server
        if 'health_server' in locals():
            try:
                logger.info("Stopping health check server...")
                await health_server.cleanup()
            except Exception as e:
                logger.error(f"Error stopping health server: {e}")

        # Disconnect from rippled
        if xrpl_client:
            logger.info("Disconnecting from rippled...")
            await xrpl_client.disconnect()

        logger.info("✓ Shutdown complete")


async def main():
    """Main entry point"""
    # Load configuration
    config = MonitorConfig()

    logger.info("=" * 70)
    logger.info("XRPL Monitor - Validator Monitoring System v3.0")
    logger.info("=" * 70)
    logger.info(f"Configuration:\n{config}")
    logger.info("=" * 70)

    # Set up signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Run monitor
    await run_monitor(config)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Exiting")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)
