#!/usr/bin/env python3
"""
XRPL WebSocket Client Wrapper

Async client for connecting to rippled via WebSocket and subscribing to real-time streams.
Wraps xrpl-py's AsyncWebsocketClient with additional features for the monitor.
"""

import asyncio
import logging
from typing import Dict, List, Optional, Callable, Any
from datetime import datetime

import httpx
from xrpl.asyncio.clients import AsyncWebsocketClient
from xrpl.models.requests import Subscribe, StreamParameter
from xrpl.models.response import Response


logger = logging.getLogger(__name__)


class XRPLWebSocketClient:
    """
    Async WebSocket client for rippled with stream subscription support

    Features:
    - Connect to rippled WebSocket
    - Subscribe to multiple streams
    - Route messages to handlers
    - Auto-reconnect on disconnection
    - Health monitoring

    Usage:
        client = XRPLWebSocketClient(url="ws://localhost:6006")
        await client.connect()

        handlers = {
            'ledgerClosed': ledger_handler,
            'serverStatus': server_handler,
            'validationReceived': validations_handler
        }

        await client.listen(handlers)
    """

    def __init__(
        self,
        url: str = "ws://localhost:6006",
        http_url: Optional[str] = None,
        auto_reconnect: bool = True,
        reconnect_delay: int = 5,
        heartbeat_interval: int = 30,
        heartbeat_timeout: int = 10
    ):
        """
        Initialize XRPL WebSocket client

        Args:
            url: rippled WebSocket URL (default: ws://localhost:6006)
            http_url: rippled HTTP admin API URL (optional, for peers command)
            auto_reconnect: Automatically reconnect on disconnection (default: True)
            reconnect_delay: Seconds to wait before reconnecting (default: 5)
            heartbeat_interval: Seconds between heartbeat pings (default: 30)
            heartbeat_timeout: Seconds to wait for heartbeat response (default: 10)
        """
        self.url = url
        self.http_url = http_url or "http://localhost:5005"
        self.auto_reconnect = auto_reconnect
        self.reconnect_delay = reconnect_delay
        self.heartbeat_interval = heartbeat_interval
        self.heartbeat_timeout = heartbeat_timeout

        self._client: Optional[AsyncWebsocketClient] = None
        self._is_connected = False
        self._subscribed_streams: List[str] = []
        self._message_count = 0
        self._last_message_time: Optional[float] = None

        # Reconnection tracking
        self._reconnect_attempts = 0
        self._max_reconnect_attempts = 10
        self._reconnect_backoff = [1, 2, 5, 10, 30]  # Exponential backoff sequence

        # Heartbeat tracking
        self._heartbeat_task: Optional[asyncio.Task] = None
        self._last_heartbeat_time: Optional[float] = None
        self._heartbeat_failures = 0
        self._connection_healthy = True

        # Listen task tracking (for forced reconnection)
        self._listen_task: Optional[asyncio.Task] = None

        logger.info(f"XRPL WebSocket client initialized: {self.url}")
        logger.info(f"XRPL HTTP API client configured: {self.http_url}")
        logger.info(f"Heartbeat configured: interval={heartbeat_interval}s, timeout={heartbeat_timeout}s")

    async def connect(self):
        """
        Connect to rippled WebSocket

        Returns:
            True if connection successful, False otherwise
        """
        try:
            self._client = AsyncWebsocketClient(self.url)
            await self._client.open()
            self._is_connected = True
            self._connection_healthy = True
            self._reconnect_attempts = 0  # Reset on successful connection

            # Start heartbeat monitoring
            if not self._heartbeat_task or self._heartbeat_task.done():
                self._heartbeat_task = asyncio.create_task(self._heartbeat_monitor())

            logger.info(f"Connected to rippled WebSocket: {self.url}")
            return True

        except Exception as e:
            logger.error(f"Failed to connect to rippled WebSocket: {e}")
            self._is_connected = False
            self._connection_healthy = False
            return False

    async def disconnect(self):
        """Disconnect from rippled WebSocket"""
        # Stop heartbeat task
        if self._heartbeat_task and not self._heartbeat_task.done():
            self._heartbeat_task.cancel()
            try:
                await self._heartbeat_task
            except asyncio.CancelledError:
                pass

        if self._client and self._is_connected:
            await self._client.close()
            self._is_connected = False
            self._connection_healthy = False
            logger.info("Disconnected from rippled WebSocket")

    async def _heartbeat_monitor(self):
        """
        Background task to monitor connection health via periodic pings

        Sends ping every heartbeat_interval seconds and expects response within
        heartbeat_timeout. If no response, marks connection as unhealthy and
        triggers reconnection.
        """
        import time

        logger.info("Heartbeat monitor started")

        try:
            while self._is_connected:
                await asyncio.sleep(self.heartbeat_interval)

                if not self._is_connected:
                    break

                # Send ping and wait for response
                try:
                    ping_start = time.time()
                    success = await asyncio.wait_for(
                        self.health_check(),
                        timeout=self.heartbeat_timeout
                    )

                    if success:
                        ping_duration = time.time() - ping_start
                        self._last_heartbeat_time = time.time()
                        self._heartbeat_failures = 0
                        self._connection_healthy = True
                        logger.debug(f"Heartbeat OK (latency: {ping_duration:.2f}s)")
                    else:
                        self._heartbeat_failures += 1
                        logger.warning(
                            f"Heartbeat failed ({self._heartbeat_failures} consecutive failures)"
                        )

                        # After 3 failures, mark connection as unhealthy and force reconnection
                        if self._heartbeat_failures >= 3:
                            logger.error("Connection appears stuck (3 heartbeat failures), forcing reconnection")
                            self._connection_healthy = False
                            self._is_connected = False

                            # Cancel the listen task to force reconnection logic to run
                            if self._listen_task and not self._listen_task.done():
                                logger.info("Cancelling listen task to trigger reconnection...")
                                self._listen_task.cancel()

                            # Also close the WebSocket
                            if self._client:
                                try:
                                    await self._client.close()
                                except Exception as e:
                                    logger.debug(f"Error closing stuck connection: {e}")

                            break

                except asyncio.TimeoutError:
                    self._heartbeat_failures += 1
                    logger.warning(
                        f"Heartbeat timeout ({self._heartbeat_failures} consecutive failures)"
                    )

                    # After 3 timeouts, mark connection as unhealthy and force reconnection
                    if self._heartbeat_failures >= 3:
                        logger.error("Connection appears stuck (3 heartbeat timeouts), forcing reconnection")
                        self._connection_healthy = False
                        self._is_connected = False

                        # Cancel the listen task to force reconnection logic to run
                        if self._listen_task and not self._listen_task.done():
                            logger.info("Cancelling listen task to trigger reconnection...")
                            self._listen_task.cancel()

                        # Also close the WebSocket
                        if self._client:
                            try:
                                await self._client.close()
                            except Exception as e:
                                logger.debug(f"Error closing stuck connection: {e}")

                        break

        except asyncio.CancelledError:
            logger.info("Heartbeat monitor cancelled")
            raise
        except Exception as e:
            logger.error(f"Heartbeat monitor error: {e}")
            self._connection_healthy = False

    async def __aenter__(self):
        """Async context manager entry"""
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit"""
        await self.disconnect()

    @property
    def is_connected(self) -> bool:
        """Check if client is currently connected"""
        return self._is_connected

    @property
    def is_healthy(self) -> bool:
        """Check if connection is healthy (connected and passing heartbeats)"""
        return self._is_connected and self._connection_healthy

    @property
    def message_count(self) -> int:
        """Get total number of messages received"""
        return self._message_count

    @property
    def last_message_time(self) -> Optional[float]:
        """Get timestamp of last received message"""
        return self._last_message_time

    @property
    def last_heartbeat_time(self) -> Optional[float]:
        """Get timestamp of last successful heartbeat"""
        return self._last_heartbeat_time

    @property
    def heartbeat_failures(self) -> int:
        """Get count of consecutive heartbeat failures"""
        return self._heartbeat_failures

    @property
    def reconnect_attempts(self) -> int:
        """Get number of reconnection attempts"""
        return self._reconnect_attempts

    async def subscribe(
        self,
        streams: Optional[List[str]] = None,
        stream_params: Optional[List[StreamParameter]] = None
    ):
        """
        Subscribe to rippled WebSocket streams

        Args:
            streams: List of stream names (string format like "ledger", "server")
            stream_params: List of StreamParameter enums (preferred)

        Example:
            # Using string names
            await client.subscribe(streams=["ledger", "server", "validations"])

            # Using StreamParameter enums (type-safe)
            await client.subscribe(stream_params=[
                StreamParameter.LEDGER,
                StreamParameter.SERVER,
                StreamParameter.VALIDATIONS
            ])
        """
        if not self._client or not self._is_connected:
            raise RuntimeError("Not connected to rippled WebSocket")

        # Convert streams to StreamParameters if needed
        if streams:
            stream_list = streams
        elif stream_params:
            stream_list = stream_params
        else:
            raise ValueError("Must provide either streams or stream_params")

        try:
            # Create subscription request
            subscribe_request = Subscribe(streams=stream_list)

            # Send subscription
            response = await self._client.request(subscribe_request)

            if response.is_successful():
                self._subscribed_streams = stream_list
                logger.info(f"Subscribed to streams: {stream_list}")
            else:
                logger.error(f"Subscription failed: {response}")
                raise RuntimeError(f"Subscription failed: {response.result.get('error')}")

        except Exception as e:
            logger.error(f"Error subscribing to streams: {e}")
            raise

    async def listen(
        self,
        handlers: Dict[str, Callable[[dict], Any]],
        on_error: Optional[Callable[[Exception], None]] = None
    ):
        """
        Listen for WebSocket messages and route to handlers

        Messages are routed based on their 'type' field:
        - 'ledgerClosed' → handlers['ledgerClosed']
        - 'serverStatus' → handlers['serverStatus']
        - 'validationReceived' → handlers['validationReceived']

        Args:
            handlers: Dict mapping message types to async handler functions
            on_error: Optional error callback

        Example:
            handlers = {
                'ledgerClosed': ledger_handler.handle,
                'serverStatus': server_handler.handle,
                'validationReceived': validations_handler.handle
            }

            await client.listen(handlers)
        """
        if not self._client or not self._is_connected:
            raise RuntimeError("Not connected to rippled WebSocket")

        # Store reference to this listen task for forced reconnection
        self._listen_task = asyncio.current_task()

        logger.info("Starting to listen for WebSocket messages...")

        try:
            async for message in self._client:
                # Check if we're still connected (heartbeat may have closed connection)
                if not self._is_connected:
                    logger.warning("Connection marked as closed, exiting listen loop")
                    break

                self._message_count += 1
                self._last_message_time = datetime.now().timestamp()

                # Log message rate (every 100 messages)
                if self._message_count % 100 == 0:
                    logger.debug(f"Received {self._message_count} total messages")

                # Extract message type
                message_type = message.get('type')

                if not message_type:
                    logger.warning(f"Message missing 'type' field: {message}")
                    continue

                # Route to appropriate handler
                handler = handlers.get(message_type)

                if handler:
                    try:
                        # Call handler (async or sync)
                        if asyncio.iscoroutinefunction(handler):
                            await handler(message)
                        else:
                            handler(message)

                    except Exception as e:
                        logger.error(f"Handler error for {message_type}: {e}")
                        if on_error:
                            on_error(e)
                else:
                    # Unhandled message type (debug logging)
                    logger.debug(f"No handler for message type: {message_type}")

            # If loop exits normally (no exception), connection was closed gracefully
            if self._is_connected:
                logger.warning("WebSocket message stream ended (connection closed by server)")
                self._is_connected = False
                self._connection_healthy = False

                # Trigger reconnection for graceful disconnects (e.g., rippled restart)
                if self.auto_reconnect and self._reconnect_attempts < self._max_reconnect_attempts:
                    self._reconnect_attempts += 1
                    backoff_index = min(self._reconnect_attempts - 1, len(self._reconnect_backoff) - 1)
                    delay = self._reconnect_backoff[backoff_index]

                    logger.warning(
                        f"Reconnection attempt {self._reconnect_attempts}/{self._max_reconnect_attempts} "
                        f"in {delay} seconds (graceful disconnect)..."
                    )
                    await asyncio.sleep(delay)

                    if await self.connect():
                        logger.info("✓ Reconnected successfully after graceful disconnect, resubscribing...")
                        await self.subscribe(streams=self._subscribed_streams)
                        await self.listen(handlers, on_error)
                    else:
                        logger.error("Reconnection failed after graceful disconnect, will retry...")
                        await self.listen(handlers, on_error)
                else:
                    if self._reconnect_attempts >= self._max_reconnect_attempts:
                        logger.error(
                            f"Max reconnection attempts ({self._max_reconnect_attempts}) reached "
                            f"after graceful disconnect. Giving up."
                        )

        except asyncio.CancelledError:
            # Listen task was cancelled (likely by heartbeat monitor detecting stuck connection)
            logger.warning("Listen task cancelled (forced reconnection)")
            self._is_connected = False
            self._connection_healthy = False

            if self.auto_reconnect and self._reconnect_attempts < self._max_reconnect_attempts:
                self._reconnect_attempts += 1
                backoff_index = min(self._reconnect_attempts - 1, len(self._reconnect_backoff) - 1)
                delay = self._reconnect_backoff[backoff_index]

                logger.warning(
                    f"Reconnection attempt {self._reconnect_attempts}/{self._max_reconnect_attempts} "
                    f"in {delay} seconds (after forced reconnection)..."
                )
                await asyncio.sleep(delay)

                if await self.connect():
                    logger.info("✓ Reconnected successfully after forced reconnection, resubscribing...")
                    await self.subscribe(streams=self._subscribed_streams)
                    await self.listen(handlers, on_error)
                else:
                    logger.error("Reconnection failed after forced reconnection, will retry...")
                    await self.listen(handlers, on_error)
            else:
                if self._reconnect_attempts >= self._max_reconnect_attempts:
                    logger.error(
                        f"Max reconnection attempts ({self._max_reconnect_attempts}) reached "
                        f"after forced reconnection. Giving up."
                    )
                raise

        except Exception as e:
            logger.error(f"WebSocket listen error: {e}")
            self._is_connected = False
            self._connection_healthy = False

            if self.auto_reconnect and self._reconnect_attempts < self._max_reconnect_attempts:
                self._reconnect_attempts += 1

                # Calculate backoff delay using exponential backoff sequence
                backoff_index = min(self._reconnect_attempts - 1, len(self._reconnect_backoff) - 1)
                delay = self._reconnect_backoff[backoff_index]

                logger.warning(
                    f"Reconnection attempt {self._reconnect_attempts}/{self._max_reconnect_attempts} "
                    f"in {delay} seconds..."
                )
                await asyncio.sleep(delay)

                # Attempt reconnection
                if await self.connect():
                    logger.info("✓ Reconnected successfully, resubscribing to streams...")
                    await self.subscribe(streams=self._subscribed_streams)
                    await self.listen(handlers, on_error)
                else:
                    logger.error("Reconnection failed, will retry...")
                    # Recursive call will increment reconnect_attempts again
                    await self.listen(handlers, on_error)
            else:
                if self._reconnect_attempts >= self._max_reconnect_attempts:
                    logger.error(
                        f"Max reconnection attempts ({self._max_reconnect_attempts}) reached. "
                        f"Giving up."
                    )
                raise

    async def request(self, request_obj: Any) -> Response:
        """
        Send a request to rippled and wait for response

        Args:
            request_obj: xrpl-py request object (e.g., ServerInfo(), Ledger(), etc.)

        Returns:
            Response object from rippled

        Example:
            from xrpl.models.requests import ServerInfo

            response = await client.request(ServerInfo())
            print(response.result['info']['server_state'])
        """
        if not self._client or not self._is_connected:
            raise RuntimeError("Not connected to rippled WebSocket")

        try:
            response = await self._client.request(request_obj)
            return response

        except Exception as e:
            logger.error(f"Request error: {e}")
            raise

    async def health_check(self) -> bool:
        """
        Check if connection to rippled is healthy

        Returns:
            True if connected and responsive, False otherwise
        """
        if not self._is_connected:
            return False

        try:
            from xrpl.models.requests import Ping

            response = await self.request(Ping())
            return response.is_successful()

        except Exception as e:
            logger.error(f"Health check failed: {e}")
            return False

    async def emit_health_metrics(self, victoria_client):
        """
        Emit WebSocket connection health metrics to VictoriaMetrics

        Metrics:
        - xrpl_websocket_connected: Connection status (1=connected, 0=disconnected)
        - xrpl_websocket_healthy: Health status (1=healthy, 0=unhealthy)
        - xrpl_websocket_heartbeat_failures: Count of consecutive heartbeat failures
        - xrpl_websocket_reconnect_attempts: Count of reconnection attempts
        - xrpl_websocket_message_count: Total messages received
        - xrpl_websocket_last_message_age_seconds: Time since last message

        Args:
            victoria_client: VictoriaMetrics client for writing metrics
        """
        try:
            import time
            from clients.victoria_client import create_gauge

            timestamp_ms = int(time.time() * 1000)

            metrics = [
                # Connection status
                create_gauge(
                    "xrpl_websocket_connected",
                    1 if self._is_connected else 0,
                    timestamp=timestamp_ms
                ),
                # Health status
                create_gauge(
                    "xrpl_websocket_healthy",
                    1 if self.is_healthy else 0,
                    timestamp=timestamp_ms
                ),
                # Heartbeat failures
                create_gauge(
                    "xrpl_websocket_heartbeat_failures",
                    self._heartbeat_failures,
                    timestamp=timestamp_ms
                ),
                # Reconnection attempts
                create_gauge(
                    "xrpl_websocket_reconnect_attempts",
                    self._reconnect_attempts,
                    timestamp=timestamp_ms
                ),
                # Message count
                create_gauge(
                    "xrpl_websocket_message_count",
                    self._message_count,
                    timestamp=timestamp_ms
                ),
            ]

            # Last message age (if we have received messages)
            if self._last_message_time:
                message_age = time.time() - self._last_message_time
                metrics.append(
                    create_gauge(
                        "xrpl_websocket_last_message_age_seconds",
                        message_age,
                        timestamp=timestamp_ms
                    )
                )

            await victoria_client.write_metrics(metrics, flush_immediately=False)

        except Exception as e:
            logger.error(f"Error emitting WebSocket health metrics: {e}", exc_info=True)

    async def get_server_info(self) -> Optional[dict]:
        """
        Get server info from rippled

        Returns:
            Server info dict or None on error
        """
        try:
            from xrpl.models.requests import ServerInfo

            response = await self.request(ServerInfo())

            if response.is_successful():
                return response.result.get('info', {})
            else:
                logger.error(f"server_info request failed: {response}")
                return None

        except Exception as e:
            logger.error(f"Error getting server info: {e}")
            return None

    async def get_server_state(self) -> Optional[dict]:
        """
        Get server state from rippled (via WebSocket)

        This returns more accurate real-time state information including "proposing" state,
        whereas server_info HTTP endpoint may return "full" even when proposing.

        Returns:
            Server state dict or None on error
        """
        try:
            from xrpl.models.requests import GenericRequest

            response = await self.request(GenericRequest(command="server_state"))

            if response.is_successful():
                return response.result.get('state', {})
            else:
                logger.error(f"server_state request failed: {response}")
                return None

        except Exception as e:
            logger.error(f"Error getting server state: {e}")
            return None

    async def get_peers(self) -> Optional[List[dict]]:
        """
        Get peer list from rippled using HTTP admin API

        Note: Uses HTTP instead of WebSocket due to WebSocket admin auth issues.
        The HTTP admin API properly authenticates admin commands, while WebSocket
        may reject the 'peers' command even with correct admin network configuration.

        Returns:
            List of peer dicts or None on error
        """
        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    self.http_url,
                    json={"method": "peers", "params": [{}]},
                    headers={"Content-Type": "application/json"},
                    timeout=10.0
                )

                if response.status_code == 200:
                    data = response.json()
                    if data.get('result', {}).get('status') == 'success':
                        return data['result'].get('peers', [])
                    else:
                        logger.error(f"peers request failed: {data}")
                        return None
                else:
                    logger.error(f"HTTP error getting peers: {response.status_code}")
                    return None

        except Exception as e:
            logger.error(f"Error getting peers via HTTP: {e}")
            return None

    def __repr__(self) -> str:
        status = "connected" if self._is_connected else "disconnected"
        return (
            f"XRPLWebSocketClient(url={self.url}, status={status}, "
            f"messages={self._message_count}, streams={self._subscribed_streams})"
        )
