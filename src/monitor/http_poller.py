#!/usr/bin/env python3
"""
HTTP Poller for XRPL Metrics

Polls rippled HTTP/WebSocket API for metrics not available via real-time streams.
Runs periodic polling tasks at different intervals.
"""

import asyncio
import httpx
import json
import logging
import os
import subprocess
import time
from pathlib import Path
from typing import Optional, Dict, List

from clients.victoria_client import VictoriaMetricsClient, create_gauge, create_counter, create_info
from clients.xrpl_client import XRPLWebSocketClient
from monitor.cpu_monitor import RippledCPUMonitor


logger = logging.getLogger(__name__)


# Drops to XRP conversion
DROPS_PER_XRP = 1_000_000


def format_uptime(seconds: int) -> str:
    """
    Format uptime seconds as 'Xd Xh Xm' (no seconds component)

    Examples:
        - 3661 seconds -> "1h 1m"
        - 90061 seconds -> "1d 1h 1m"
        - 691860 seconds -> "8d 0h 11m"

    Args:
        seconds: Uptime in seconds

    Returns:
        Formatted string like "7d 21h 12m"
    """
    if seconds < 0:
        return "0m"

    days = seconds // 86400
    hours = (seconds % 86400) // 3600
    minutes = (seconds % 3600) // 60

    parts = []
    if days > 0:
        parts.append(f"{days}d")
    if hours > 0 or days > 0:  # Show hours if we have days (e.g., "1d 0h 5m")
        parts.append(f"{hours}h")
    parts.append(f"{minutes}m")  # Always show minutes

    return ":".join(parts)


def discover_nudb_path() -> Optional[str]:
    """
    Auto-discover NuDB directory path with fallback locations

    Checks in order:
    1. Environment variable RIPPLED_NUDB_PATH (explicit override)
    2. ${RIPPLED_DATA_PATH}/db/nudb (current standard Docker/host mount)
    3. ${RIPPLED_DATA_PATH}/nudb (legacy location)
    4. /var/lib/rippled/db/nudb (native install standard)
    5. /var/lib/rippled/nudb (native install legacy)

    Returns:
        Path to NuDB directory, or None if not found
    """
    # Check for explicit override
    explicit_path = os.environ.get('RIPPLED_NUDB_PATH')
    if explicit_path:
        if Path(explicit_path).exists():
            logger.info(f"Using NuDB path from RIPPLED_NUDB_PATH: {explicit_path}")
            return explicit_path
        else:
            logger.warning(f"RIPPLED_NUDB_PATH set but path doesn't exist: {explicit_path}")

    # Get base data path from environment or use default
    data_path = os.environ.get('RIPPLED_DATA_PATH', '/var/lib/rippled')

    # Build list of candidate paths to check
    candidate_paths = [
        f"{data_path}/db/nudb",      # Current standard (post-2019)
        f"{data_path}/nudb",          # Legacy location (pre-2019)
    ]

    # If no custom data path, also try absolute defaults
    if not os.environ.get('RIPPLED_DATA_PATH'):
        candidate_paths.extend([
            "/var/lib/rippled/db/nudb",
            "/var/lib/rippled/nudb",
        ])

    # Try each candidate path
    for path in candidate_paths:
        dir_path = Path(path)

        if not dir_path.exists() or not dir_path.is_dir():
            continue

        # Validate this is actually a NuDB directory by checking for rippledb.* subdirectories
        try:
            subdirs = [d.name for d in dir_path.iterdir() if d.is_dir()]
            rippledb_dirs = [d for d in subdirs if d.startswith('rippledb.')]

            if rippledb_dirs:
                logger.info(f"Found NuDB path: {path} (contains {len(rippledb_dirs)} rippledb.* subdirs)")
                return path
            else:
                logger.debug(f"Path exists but doesn't contain rippledb.* subdirectories: {path}")
        except (OSError, PermissionError) as e:
            logger.debug(f"Cannot access path {path}: {e}")
            continue

    logger.warning(
        "Could not auto-discover NuDB path. Checked: " +
        ", ".join(candidate_paths) +
        ". Set RIPPLED_DATA_PATH or RIPPLED_NUDB_PATH environment variable to specify location."
    )
    return None


def get_directory_size(path: str) -> int:
    """
    Calculate total size of a directory (including subdirectories)

    Args:
        path: Directory path to calculate size for

    Returns:
        Total size in bytes, or 0 if directory doesn't exist or error occurs
    """
    try:
        total_size = 0
        dir_path = Path(path)

        if not dir_path.exists() or not dir_path.is_dir():
            return 0

        for entry in dir_path.rglob('*'):
            if entry.is_file():
                try:
                    total_size += entry.stat().st_size
                except (OSError, PermissionError):
                    # Skip files we can't read
                    pass

        return total_size
    except Exception as e:
        logger.debug(f"Error calculating directory size for {path}: {e}")
        return 0


class HTTPPoller:
    """
    Polls rippled for metrics not available via WebSocket streams

    Polling schedule:
    - server_info: Every 5 seconds (~11 metrics)
    - peers: Every 60 seconds (4 metrics)
    - server_state: Every 5 minutes + once at startup (6 metrics)
    - cpu: Every 5 seconds (1 metric)
    """

    def __init__(
        self,
        xrpl_client: XRPLWebSocketClient,
        victoria_client: VictoriaMetricsClient,
        poll_interval_server_info: int = 5,
        poll_interval_peers: int = 60,
        poll_interval_server_state: int = 300,
        poll_interval_cpu: int = 5,
        docker_container: Optional[str] = None
    ):
        """
        Initialize HTTP poller

        Args:
            xrpl_client: XRPL WebSocket client (also used for HTTP-style requests)
            victoria_client: VictoriaMetrics client for writing metrics
            poll_interval_server_info: Seconds between server_info polls (default: 5)
            poll_interval_peers: Seconds between peers polls (default: 60)
            poll_interval_server_state: Seconds between server_state polls (default: 300)
            poll_interval_cpu: Seconds between CPU polls (default: 5)
            docker_container: Optional Docker container name for peer metrics fallback
        """
        self.xrpl_client = xrpl_client
        self.victoria_client = victoria_client
        self.docker_container = docker_container

        self.poll_interval_server_info = poll_interval_server_info
        self.poll_interval_peers = poll_interval_peers
        self.poll_interval_server_state = poll_interval_server_state
        self.poll_interval_cpu = poll_interval_cpu

        self._shutdown_event = asyncio.Event()
        self._tasks = []

        # Track last values for counters
        self._last_peer_disconnects = 0
        self._last_peer_disconnects_resources = 0
        self._last_jq_trans_overflow = 0

        # Server info cache (written once at startup)
        self._server_info_written = False

        # Initialize CPU monitor
        self.cpu_monitor = RippledCPUMonitor(docker_container=docker_container)

        logger.info(
            f"HTTPPoller initialized: server_info={poll_interval_server_info}s, "
            f"peers={poll_interval_peers}s, server_state={poll_interval_server_state}s, "
            f"cpu={poll_interval_cpu}s"
        )

    async def _get_server_info_direct_http(self) -> Optional[Dict]:
        """
        Get server_info directly via HTTP API (bypasses WebSocket)

        This method directly calls the rippled HTTP API, ensuring it works even when
        the WebSocket connection is dead (e.g., during rippled restarts). This provides
        near-instant state updates (5s polling) instead of waiting for WebSocket
        reconnection (~60s heartbeat timeout).

        Implements retry logic for connection failures during rippled restarts.

        Returns:
            Server info dict or None on error
        """
        max_retries = 2
        retry_delay = 0.2  # 200ms between retries

        for attempt in range(max_retries):
            try:
                async with httpx.AsyncClient() as client:
                    response = await client.post(
                        self.xrpl_client.http_url,
                        json={"method": "server_info", "params": [{}]},
                        headers={"Content-Type": "application/json"},
                        timeout=2.0  # Fast timeout - rippled on localhost should respond instantly
                    )

                    if response.status_code == 200:
                        data = response.json()
                        if data.get('result', {}).get('status') == 'success':
                            return data['result'].get('info', {})
                        else:
                            logger.error(f"server_info HTTP request failed: {data}")
                            return None
                    else:
                        logger.error(f"HTTP error getting server_info: {response.status_code}")
                        return None

            except (httpx.ConnectError, httpx.TimeoutException) as e:
                # Connection or timeout errors - rippled might be restarting
                if attempt < max_retries - 1:
                    logger.debug(f"Connection failed (attempt {attempt + 1}/{max_retries}), retrying in {retry_delay}s")
                    await asyncio.sleep(retry_delay)
                    # No exponential backoff - keep it fast for restarts
                else:
                    # Don't log warnings - rippled restarts are expected
                    logger.debug(f"server_info HTTP failed after {max_retries} attempts (rippled may be restarting)")
                    return None
            except Exception as e:
                logger.error(f"Error getting server_info via HTTP: {e}")
                return None

        return None

    async def start(self, shutdown_event: asyncio.Event):
        """
        Start all polling tasks

        Args:
            shutdown_event: Event to signal shutdown
        """
        self._shutdown_event = shutdown_event

        # Poll server_state immediately at startup for server info
        await self._poll_server_state_startup()

        # Start periodic polling tasks
        self._tasks = [
            asyncio.create_task(self._server_info_poller()),
            asyncio.create_task(self._peers_poller()),
            asyncio.create_task(self._server_state_poller()),
            asyncio.create_task(self._cpu_poller())
        ]

        logger.info("HTTP polling tasks started")

    async def stop(self):
        """Stop all polling tasks"""
        logger.info("Stopping HTTP polling tasks...")

        for task in self._tasks:
            task.cancel()

        # Wait for tasks to complete
        await asyncio.gather(*self._tasks, return_exceptions=True)

        logger.info("HTTP polling tasks stopped")

    async def _server_info_poller(self):
        """
        Poll server_info every N seconds

        Metrics collected:
        - xrpl_peer_count
        - xrpl_load_factor
        - xrpl_io_latency_ms
        - xrpl_consensus_converge_time_seconds
        - xrpl_jq_trans_overflow_total (counter)
        - xrpl_peer_disconnects_total (counter)
        - xrpl_peer_disconnects_resources_total (counter)
        - xrpl_validator_uptime_seconds
        - xrpl_server_state_duration_seconds
        - xrpl_validation_quorum
        - xrpl_proposers
        """
        logger.info(f"server_info poller started (interval: {self.poll_interval_server_info}s)")

        try:
            while not self._shutdown_event.is_set():
                try:
                    # Use direct HTTP to bypass WebSocket (works even when WS is dead)
                    server_info = await self._get_server_info_direct_http()

                    if server_info:
                        await self._process_server_info(server_info)
                    else:
                        logger.warning("server_info poll returned no data")

                except Exception as e:
                    logger.error(f"Error polling server_info: {e}")

                # Wait for next poll or shutdown
                try:
                    await asyncio.wait_for(
                        self._shutdown_event.wait(),
                        timeout=self.poll_interval_server_info
                    )
                except asyncio.TimeoutError:
                    pass

        except asyncio.CancelledError:
            logger.info("server_info poller cancelled")

    async def _peers_poller(self):
        """
        Poll peers command every N seconds

        Metrics collected:
        - xrpl_peers_inbound
        - xrpl_peers_outbound
        - xrpl_peers_insane
        - xrpl_peer_latency_p90_ms

        Note: peers command requires admin access and may not be available
        """
        logger.info(f"peers poller started (interval: {self.poll_interval_peers}s)")
        peers_unavailable_logged = False

        try:
            while not self._shutdown_event.is_set():
                try:
                    # Try API first
                    peers = await self.xrpl_client.get_peers()

                    # If API fails and Docker is configured, try docker exec fallback
                    if not peers and self.docker_container:
                        logger.debug("API peers failed, trying docker exec fallback...")
                        peers = self._get_peers_docker()
                        if peers:
                            logger.info("✓ Peer metrics collected via docker exec fallback")

                    if peers:
                        await self._process_peers(peers)
                        peers_unavailable_logged = False  # Reset if it works
                    elif not peers_unavailable_logged:
                        if self.docker_container:
                            logger.warning(
                                "peers command unavailable via API and docker exec - "
                                "skipping peer detail metrics"
                            )
                        else:
                            logger.warning(
                                "peers command unavailable (requires admin access) - "
                                "skipping peer detail metrics. Set RIPPLED_DOCKER_CONTAINER "
                                "env var for docker exec fallback"
                            )
                        peers_unavailable_logged = True

                except Exception as e:
                    if not peers_unavailable_logged:
                        logger.warning(f"peers command error (may need admin access): {e}")
                        peers_unavailable_logged = True

                # Wait for next poll or shutdown
                try:
                    await asyncio.wait_for(
                        self._shutdown_event.wait(),
                        timeout=self.poll_interval_peers
                    )
                except asyncio.TimeoutError:
                    pass

        except asyncio.CancelledError:
            logger.info("peers poller cancelled")

    async def _server_state_poller(self):
        """
        Poll server_state every N minutes

        Metrics collected:
        - xrpl_state_accounting_duration_seconds{state="..."}
        - xrpl_state_accounting_transitions{state="..."}
        - xrpl_ledger_db_bytes
        - xrpl_ledger_nudb_bytes
        - xrpl_initial_sync_duration_seconds
        """
        logger.info(f"server_state poller started (interval: {self.poll_interval_server_state}s)")

        try:
            while not self._shutdown_event.is_set():
                try:
                    from xrpl.models.requests.server_state import ServerState

                    response = await self.xrpl_client.request(ServerState())

                    if response.is_successful():
                        state_data = response.result.get('state', {})
                        await self._process_server_state(state_data)
                    else:
                        logger.warning("server_state poll failed")

                except Exception as e:
                    logger.error(f"Error polling server_state: {e}")

                # Wait for next poll or shutdown
                try:
                    await asyncio.wait_for(
                        self._shutdown_event.wait(),
                        timeout=self.poll_interval_server_state
                    )
                except asyncio.TimeoutError:
                    pass

        except asyncio.CancelledError:
            logger.info("server_state poller cancelled")

    async def _cpu_poller(self):
        """
        Poll rippled CPU usage every N seconds

        Metrics collected:
        - xrpl_rippled_cpu_percent: CPU usage percentage (0-100+)
        - xrpl_rippled_cpu_cores: Number of CPU cores available to rippled
        """
        logger.info(f"CPU poller started (interval: {self.poll_interval_cpu}s)")

        try:
            while not self._shutdown_event.is_set():
                try:
                    cpu_percent = self.cpu_monitor.get_cpu_percent()
                    cpu_cores = self.cpu_monitor.get_cpu_cores()

                    timestamp_ms = int(time.time() * 1000)

                    if cpu_percent is not None:
                        metric = create_gauge(
                            "xrpl_rippled_cpu_percent",
                            cpu_percent,
                            timestamp=timestamp_ms
                        )
                        await self.victoria_client.write_metric(metric, flush_immediately=False)
                        logger.debug(f"rippled CPU: {cpu_percent:.1f}%")
                    else:
                        logger.debug("CPU metric unavailable (rippled process not found)")

                    # Always report CPU cores (static value but needed for dashboard calculations)
                    cores_metric = create_gauge(
                        "xrpl_rippled_cpu_cores",
                        cpu_cores,
                        timestamp=timestamp_ms
                    )
                    await self.victoria_client.write_metric(cores_metric, flush_immediately=False)

                except Exception as e:
                    logger.error(f"Error polling CPU: {e}")

                # Wait for next poll or shutdown
                try:
                    await asyncio.wait_for(
                        self._shutdown_event.wait(),
                        timeout=self.poll_interval_cpu
                    )
                except asyncio.TimeoutError:
                    pass

        except asyncio.CancelledError:
            logger.info("CPU poller cancelled")

    async def _poll_server_state_startup(self):
        """
        Poll server_state once at startup for server info labels

        Writes xrpl_server_info metric with labels:
        - node_size
        - complete_ledgers

        NOTE: build_version and pubkey_validator moved to State Exporter for real-time updates
        """
        try:
            from xrpl.models.requests.server_state import ServerState

            response = await self.xrpl_client.request(ServerState())

            if response.is_successful():
                state_data = response.result.get('state', {})

                # Extract server info
                # NOTE: build_version and pubkey_validator now handled by State Exporter
                node_size = state_data.get('node_size', 'unknown')
                complete_ledgers = state_data.get('complete_ledgers', '')

                # Write server info metric
                timestamp_ms = int(time.time() * 1000)

                metric = create_info(
                    "xrpl_server_info",
                    {
                        "node_size": node_size,
                        "complete_ledgers": complete_ledgers
                    },
                    timestamp=timestamp_ms
                )

                await self.victoria_client.write_metric(metric, flush_immediately=False)
                self._server_info_written = True

                logger.info(f"Server info: node_size={node_size}, complete_ledgers={complete_ledgers}")

        except Exception as e:
            logger.error(f"Error polling server_state at startup: {e}")

    async def _process_server_info(self, server_info: Dict):
        """Process server_info response and write metrics"""
        try:
            timestamp_ms = int(time.time() * 1000)

            # Extract metrics
            peer_count = server_info.get('peers', 0)
            load_factor = server_info.get('load_factor', 1)
            io_latency_ms = server_info.get('io_latency_ms', 0)

            # Last close info
            last_close = server_info.get('last_close', {})
            converge_time_s = last_close.get('converge_time_s', 0)
            proposers = last_close.get('proposers', 0)

            # Peer disconnects
            peer_disconnects = server_info.get('peer_disconnects', 0)
            peer_disconnects_resources = server_info.get('peer_disconnects_resources', 0)

            # Job queue transaction overflow (rippled 2.6.1+)
            jq_trans_overflow = server_info.get('jq_trans_overflow', 0)

            # Uptime (round to nearest minute for cleaner dashboard display)
            uptime_raw = server_info.get('uptime', 0)
            uptime = round(uptime_raw / 60) * 60  # Round to nearest minute
            uptime_formatted = format_uptime(uptime)

            # Server state duration (microseconds → seconds)
            server_state_duration_us = server_info.get('server_state_duration_us', 0)
            server_state_duration_s = int(server_state_duration_us) / 1_000_000 if server_state_duration_us else 0

            # Validation quorum
            validation_quorum = server_info.get('validation_quorum', 0)

            # Server state (for State panel)
            # Note: We use direct HTTP API to localhost which shows true "proposing" state.
            # External/remote APIs may return "full" for healthy validators even when proposing.
            server_state = server_info.get('server_state', 'unknown').lower()
            STATE_VALUES = {
                'down': 0, 'disconnected': 1, 'connected': 2, 'syncing': 3,
                'tracking': 4, 'full': 5, 'validating': 6, 'proposing': 7
            }
            state_value = STATE_VALUES.get(server_state, 0)

            # pubkey_node for node identification
            # NOTE: build_version and pubkey_validator moved to State Exporter for real-time updates
            pubkey_node = server_info.get('pubkey_node', '')

            # Prepare metrics
            metrics = [
                create_gauge("xrpl_peer_count", peer_count, timestamp=timestamp_ms),
                create_gauge("xrpl_load_factor", load_factor, timestamp=timestamp_ms),
                create_gauge("xrpl_io_latency_ms", io_latency_ms, timestamp=timestamp_ms),
                create_gauge("xrpl_consensus_converge_time_seconds", converge_time_s, timestamp=timestamp_ms),
                create_gauge("xrpl_validator_uptime_seconds", uptime, timestamp=timestamp_ms),
                create_info("xrpl_validator_uptime_info", {"pretty": uptime_formatted}, timestamp=timestamp_ms),
                create_gauge("xrpl_server_state_duration_seconds", server_state_duration_s, timestamp=timestamp_ms),
                create_gauge("xrpl_validation_quorum", validation_quorum, timestamp=timestamp_ms),
                create_gauge("xrpl_proposers", proposers, timestamp=timestamp_ms),
                # State metrics (updated every 30s via HTTP polling)
                create_gauge("xrpl_validator_state_value", state_value, timestamp=timestamp_ms),
                # NOTE: xrpl_validator_state_info contains STATIC labels only
                # build_version and pubkey_validator moved to State Exporter (real-time, no stale series)
                create_info("xrpl_validator_state_info", {
                    "pubkey_node": pubkey_node
                }, timestamp=timestamp_ms),
                create_gauge("xrpl_time_in_current_state_seconds", server_state_duration_s, timestamp=timestamp_ms)
            ]

            # Handle counters (write delta) - convert to int first
            jq_trans_overflow_int = int(jq_trans_overflow) if jq_trans_overflow else 0
            peer_disconnects_int = int(peer_disconnects) if peer_disconnects else 0
            peer_disconnects_resources_int = int(peer_disconnects_resources) if peer_disconnects_resources else 0

            # Always write counters (including initial 0 values) to ensure metrics exist in VictoriaMetrics
            # This prevents dashboard panels from showing "N/A" when counters haven't incremented yet
            if jq_trans_overflow_int >= self._last_jq_trans_overflow:
                metrics.append(
                    create_counter("xrpl_jq_trans_overflow_total", jq_trans_overflow_int, timestamp=timestamp_ms)
                )
                self._last_jq_trans_overflow = jq_trans_overflow_int

            # Always write peer disconnect counters, even when 0
            metrics.append(
                create_counter("xrpl_peer_disconnects_total", peer_disconnects_int, timestamp=timestamp_ms)
            )
            self._last_peer_disconnects = peer_disconnects_int

            metrics.append(
                create_counter("xrpl_peer_disconnects_resources_total", peer_disconnects_resources_int, timestamp=timestamp_ms)
            )
            self._last_peer_disconnects_resources = peer_disconnects_resources_int

            # Write metrics
            await self.victoria_client.write_metrics(metrics, flush_immediately=False)

            logger.debug(
                f"server_info: peers={peer_count}, load={load_factor}, "
                f"io_latency={io_latency_ms}ms, quorum={validation_quorum}"
            )

        except Exception as e:
            logger.error(f"Error processing server_info: {e}", exc_info=True)

    async def _process_peers(self, peers: List[Dict]):
        """Process peers response and write metrics"""
        try:
            timestamp_ms = int(time.time() * 1000)

            # Count peer types
            inbound_count = 0
            outbound_count = 0
            insane_count = 0
            latencies = []

            for peer in peers:
                # Check if peer is inbound (boolean field)
                if peer.get('inbound', False):
                    inbound_count += 1
                else:
                    outbound_count += 1

                # Check sanity
                if peer.get('sanity') == 'insane':
                    insane_count += 1

                # Collect latency
                latency = peer.get('latency')
                if latency is not None:
                    latencies.append(latency)

            # Calculate P90 latency
            peer_latency_p90 = 0
            if latencies:
                latencies.sort()
                p90_index = int(len(latencies) * 0.9)
                peer_latency_p90 = latencies[p90_index] if p90_index < len(latencies) else latencies[-1]

            # Prepare metrics
            metrics = [
                create_gauge("xrpl_peers_inbound", inbound_count, timestamp=timestamp_ms),
                create_gauge("xrpl_peers_outbound", outbound_count, timestamp=timestamp_ms),
                create_gauge("xrpl_peers_insane", insane_count, timestamp=timestamp_ms),
                create_gauge("xrpl_peer_latency_p90_ms", peer_latency_p90, timestamp=timestamp_ms)
            ]

            # Write metrics
            await self.victoria_client.write_metrics(metrics, flush_immediately=False)

            logger.debug(
                f"peers: inbound={inbound_count}, outbound={outbound_count}, "
                f"insane={insane_count}, p90_latency={peer_latency_p90}ms"
            )

        except Exception as e:
            logger.error(f"Error processing peers: {e}", exc_info=True)

    def _get_peers_docker(self) -> Optional[List[Dict]]:
        """
        Get peers via docker exec (fallback when API is restricted)

        Returns:
            List of peer dicts or None on error
        """
        if not self.docker_container:
            return None

        try:
            cmd = [
                "docker", "exec", self.docker_container,
                "rippled", "peers"
            ]

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=10
            )

            if result.returncode != 0:
                logger.debug(f"Docker exec peers failed: {result.stderr}")
                return None

            # Parse JSON output
            data = json.loads(result.stdout)

            if data.get('result', {}).get('status') == 'success':
                peers = data['result'].get('peers', [])
                logger.debug(f"Got {len(peers)} peers via docker exec")
                return peers
            else:
                logger.debug(f"Docker exec peers returned non-success: {data}")
                return None

        except subprocess.TimeoutExpired:
            logger.warning(f"Docker exec peers timed out")
            return None
        except json.JSONDecodeError as e:
            logger.warning(f"Failed to parse docker exec output: {e}")
            return None
        except Exception as e:
            logger.debug(f"Docker exec peers error: {e}")
            return None

    async def _process_server_state(self, state_data: Dict):
        """Process server_state response and write metrics"""
        try:
            timestamp_ms = int(time.time() * 1000)

            metrics = []

            # State accounting
            state_accounting = state_data.get('state_accounting', {})
            for state_name, state_info in state_accounting.items():
                duration_us = state_info.get('duration_us', 0)
                duration_s = int(duration_us) / 1_000_000 if duration_us else 0
                transitions = int(state_info.get('transitions', 0)) if state_info.get('transitions') else 0

                metrics.append(
                    create_gauge(
                        "xrpl_state_accounting_duration_seconds",
                        duration_s,
                        labels={"state": state_name},
                        timestamp=timestamp_ms
                    )
                )
                metrics.append(
                    create_gauge(
                        "xrpl_state_accounting_transitions",
                        transitions,
                        labels={"state": state_name},
                        timestamp=timestamp_ms
                    )
                )

            # Database sizes (calculated from filesystem)
            # rippled doesn't expose these via API, so we calculate them directly
            data_path = os.environ.get('RIPPLED_DATA_PATH', '/var/lib/rippled')
            ledger_db_path = f"{data_path}/db"

            # Auto-discover NuDB path (checks multiple locations)
            nudb_path = discover_nudb_path()

            ledger_db = get_directory_size(ledger_db_path)
            nudb = get_directory_size(nudb_path) if nudb_path else 0

            metrics.append(create_gauge("xrpl_ledger_db_bytes", ledger_db, timestamp=timestamp_ms))
            metrics.append(create_gauge("xrpl_ledger_nudb_bytes", nudb, timestamp=timestamp_ms))

            # Initial sync duration
            initial_sync_duration_us = state_data.get('initial_sync_duration_us', 0)
            initial_sync_duration_s = int(initial_sync_duration_us) / 1_000_000 if initial_sync_duration_us else 0

            metrics.append(create_gauge("xrpl_initial_sync_duration_seconds", initial_sync_duration_s, timestamp=timestamp_ms))

            # Write metrics
            await self.victoria_client.write_metrics(metrics, flush_immediately=False)

            logger.debug(
                f"server_state: db_sizes={{ledger={ledger_db}, nudb={nudb}}}, "
                f"states={len(state_accounting)}"
            )

        except Exception as e:
            logger.error(f"Error processing server_state: {e}", exc_info=True)
