#!/usr/bin/env python3
"""
Server Stream Handler

Processes server stream events from rippled WebSocket and tracks validator state.
"""

import logging
import time
from typing import Optional

from clients.victoria_client import VictoriaMetricsClient, create_gauge, create_counter, create_info


logger = logging.getLogger(__name__)


# State value mapping (aligned with state_exporter.py)
# 0 = DOWN (rippled not responding or null status)
# 1-7 = rippled states
STATE_VALUES = {
    'down': 0,
    'disconnected': 1,
    'connected': 2,
    'syncing': 3,
    'tracking': 4,
    'full': 5,
    'validating': 6,
    'proposing': 7
}


class ServerHandler:
    """
    Handles server stream events and tracks validator state

    Subscribes to: 'server' stream
    Event frequency: On state changes (seconds to minutes)
    Metrics collected: 4

    Metrics:
    - xrpl_validator_state_value: Numeric state (0-6)
    - xrpl_validator_state_info: String state label
    - xrpl_time_in_current_state_seconds: Time in current state
    - xrpl_state_changes_total: Counter of state transitions
    """

    def __init__(self, victoria_client: VictoriaMetricsClient):
        """
        Initialize server handler

        Args:
            victoria_client: VictoriaMetrics client for writing metrics
        """
        self.victoria_client = victoria_client

        self._current_state: Optional[str] = None
        self._state_since: Optional[float] = None
        self._state_changes = 0
        self._last_state_changes_written = 0

        logger.info("ServerHandler initialized")

    async def handle(self, message: dict):
        """
        Handle server stream message

        Expected message format:
        {
            "type": "serverStatus",
            "server_status": "proposing",
            "load_base": 256,
            "load_factor": 256,
            "base_fee": 10
        }

        Args:
            message: Server event message from rippled
        """
        try:
            # Extract server status
            server_status = message.get('server_status')

            if not server_status:
                logger.warning(f"Server message missing 'server_status': {message}")
                return

            # Normalize state name (lowercase)
            new_state = server_status.lower()

            # Check if state changed
            state_changed = False
            if new_state != self._current_state:
                state_changed = True
                self._state_changes += 1

                logger.info(
                    f"State transition: {self._current_state} → {new_state} "
                    f"(total changes: {self._state_changes})"
                )

                self._current_state = new_state
                self._state_since = time.time()

            # Calculate time in current state
            time_in_state = 0.0
            if self._state_since:
                time_in_state = time.time() - self._state_since

            # Get numeric state value
            state_value = STATE_VALUES.get(new_state, 0)

            # Prepare metrics
            timestamp_ms = int(time.time() * 1000)

            metrics = [
                create_gauge(
                    "xrpl_validator_state_value",
                    state_value,
                    timestamp=timestamp_ms
                ),
                # NOTE: xrpl_validator_state_info is written by HTTPPoller with complete labels
                # (pubkey_validator, pubkey_node, build_version). Not written here to avoid
                # duplicate time series with different label sets.
                create_gauge(
                    "xrpl_time_in_current_state_seconds",
                    time_in_state,
                    timestamp=timestamp_ms
                )
            ]

            # Add state changes counter (write if value changed or first write)
            if self._state_changes >= self._last_state_changes_written:
                metrics.append(
                    create_counter(
                        "xrpl_state_changes_total",
                        self._state_changes,
                        timestamp=timestamp_ms
                    )
                )
                self._last_state_changes_written = self._state_changes

            # Write to VictoriaMetrics
            await self.victoria_client.write_metrics(metrics, flush_immediately=False)

            # Log state updates (every 60 seconds)
            if int(time_in_state) % 60 == 0 and int(time_in_state) > 0:
                logger.debug(
                    f"State: {new_state} ({state_value}) for {time_in_state:.0f}s"
                )

        except Exception as e:
            logger.error(f"Error handling server event: {e}", exc_info=True)

    @property
    def current_state(self) -> Optional[str]:
        """Get current validator state"""
        return self._current_state

    @property
    def state_changes(self) -> int:
        """Get total state change count"""
        return self._state_changes

    @property
    def time_in_state(self) -> float:
        """Get seconds in current state"""
        if self._state_since:
            return time.time() - self._state_since
        return 0.0

    def __repr__(self) -> str:
        return (
            f"ServerHandler(state={self._current_state}, "
            f"time_in_state={self.time_in_state:.0f}s, "
            f"changes={self._state_changes})"
        )
