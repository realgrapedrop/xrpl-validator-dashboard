#!/usr/bin/env python3
"""
Ledger Stream Handler

Processes ledger stream events from rippled WebSocket and extracts ledger metrics.
"""

import logging
import time
from collections import deque
from typing import Optional, Dict, Deque, TYPE_CHECKING
from datetime import datetime

from clients.victoria_client import VictoriaMetricsClient, create_gauge, create_counter

if TYPE_CHECKING:
    from handlers.validations_handler import ValidationsHandler

logger = logging.getLogger(__name__)


# XRP Ledger epoch offset (946684800 = seconds from Unix epoch to Ripple epoch)
# Ripple epoch: January 1, 2000 00:00 UTC
RIPPLE_EPOCH_OFFSET = 946684800

# Drops to XRP conversion (1 XRP = 1,000,000 drops)
DROPS_PER_XRP = 1_000_000

# Ledger hash buffer size (keep last 1000 ledgers for validation comparison)
LEDGER_HASH_BUFFER_SIZE = 1000


class LedgerHandler:
    """
    Handles ledger stream events and writes ledger metrics to VictoriaMetrics

    Subscribes to: 'ledger' stream
    Event frequency: Every 3-5 seconds (ledger close)
    Metrics collected: 6

    Metrics:
    - xrpl_ledger_sequence: Ledger sequence number
    - xrpl_ledger_age_seconds: Age of last validated ledger
    - xrpl_base_fee_xrp: Base transaction fee (XRP)
    - xrpl_reserve_base_xrp: Base account reserve (XRP)
    - xrpl_reserve_inc_xrp: Owner reserve increment (XRP)
    - xrpl_transaction_rate: Transactions per second
    """

    def __init__(
        self,
        victoria_client: VictoriaMetricsClient,
        validation_handler: Optional['ValidationsHandler'] = None
    ):
        """
        Initialize ledger handler

        Args:
            victoria_client: VictoriaMetrics client for writing metrics
            validation_handler: Optional reference to validation handler for callbacks
        """
        self.victoria_client = victoria_client
        self.validation_handler = validation_handler
        self._last_ledger_time: Optional[float] = None
        self._last_ledger_index: Optional[int] = None
        self._ledger_count = 0

        # Counter for total ledgers closed (for validation tracking)
        self._ledgers_closed_total = 0

        # Ring buffer to store recent ledger hashes for validation comparison
        # Format: {ledger_index: ledger_hash}
        self._ledger_hashes: Deque[tuple[int, str]] = deque(maxlen=LEDGER_HASH_BUFFER_SIZE)
        self._ledger_hash_lookup: Dict[int, str] = {}

        logger.info(f"LedgerHandler initialized (validation_handler={'configured' if validation_handler else 'not set'})")

    async def handle(self, message: dict):
        """
        Handle ledger stream message

        Expected message format:
        {
            "type": "ledgerClosed",
            "ledger_index": 93847123,
            "ledger_hash": "ABC123...",
            "ledger_time": 778825230,
            "fee_base": 10,
            "reserve_base": 10000000,
            "reserve_inc": 2000000,
            "txn_count": 25,
            "validated_ledgers": "32570-93847123"
        }

        Args:
            message: Ledger event message from rippled
        """
        try:
            self._ledger_count += 1

            # Extract fields
            ledger_index = message.get('ledger_index')
            ledger_hash = message.get('ledger_hash')
            ledger_time_ripple = message.get('ledger_time')  # Ripple epoch seconds
            fee_base = message.get('fee_base', 10)  # drops
            reserve_base = message.get('reserve_base', 10000000)  # drops
            reserve_inc = message.get('reserve_inc', 2000000)  # drops
            txn_count = message.get('txn_count', 0)

            if not ledger_index or not ledger_time_ripple:
                logger.warning(f"Ledger message missing required fields: {message}")
                return

            # Increment ledgers closed counter (for validation tracking)
            self._ledgers_closed_total += 1

            # Store ledger hash for validation comparison
            if ledger_hash:
                self._ledger_hashes.append((ledger_index, ledger_hash))
                self._ledger_hash_lookup[ledger_index] = ledger_hash

                # Clean up old entries from lookup dict if buffer is full
                if len(self._ledger_hash_lookup) > LEDGER_HASH_BUFFER_SIZE:
                    # Remove entries that are no longer in the deque
                    valid_indices = {idx for idx, _ in self._ledger_hashes}
                    self._ledger_hash_lookup = {
                        idx: h for idx, h in self._ledger_hash_lookup.items()
                        if idx in valid_indices
                    }

                # Notify validation handler about ledger close (for reconciliation)
                if self.validation_handler:
                    await self.validation_handler.on_ledger_closed(ledger_index, ledger_hash)

            # Convert Ripple epoch to Unix timestamp
            ledger_time_unix = ledger_time_ripple + RIPPLE_EPOCH_OFFSET

            # Calculate ledger age
            # Note: Clamp to 0 to avoid negative values due to clock drift or network latency
            current_time = time.time()
            ledger_age = max(0, current_time - ledger_time_unix)

            # Calculate transaction rate (TPS)
            transaction_rate = 0.0
            if self._last_ledger_time and self._last_ledger_index:
                time_diff = ledger_time_unix - self._last_ledger_time
                if time_diff > 0:
                    transaction_rate = txn_count / time_diff

            # Update tracking
            self._last_ledger_time = ledger_time_unix
            self._last_ledger_index = ledger_index

            # Prepare metrics
            timestamp_ms = int(current_time * 1000)

            metrics = [
                # Counter: Total ledgers closed (for validation tracking)
                create_counter(
                    "xrpl_ledgers_closed_total",
                    self._ledgers_closed_total,
                    timestamp=timestamp_ms
                ),
                # Gauge: Current ledger sequence
                create_gauge(
                    "xrpl_ledger_sequence",
                    ledger_index,
                    timestamp=timestamp_ms
                ),
                create_gauge(
                    "xrpl_ledger_age_seconds",
                    ledger_age,
                    timestamp=timestamp_ms
                ),
                create_gauge(
                    "xrpl_base_fee_xrp",
                    fee_base / DROPS_PER_XRP,
                    timestamp=timestamp_ms
                ),
                create_gauge(
                    "xrpl_reserve_base_xrp",
                    reserve_base / DROPS_PER_XRP,
                    timestamp=timestamp_ms
                ),
                create_gauge(
                    "xrpl_reserve_inc_xrp",
                    reserve_inc / DROPS_PER_XRP,
                    timestamp=timestamp_ms
                ),
                create_gauge(
                    "xrpl_transaction_rate",
                    transaction_rate,
                    timestamp=timestamp_ms
                )
            ]

            # Write to VictoriaMetrics
            # Flush immediately for real-time ledger updates in dashboard
            await self.victoria_client.write_metrics(metrics, flush_immediately=True)

            # Log every 10 ledgers
            if self._ledger_count % 10 == 0:
                logger.debug(
                    f"Ledger {ledger_index}: age={ledger_age:.1f}s, "
                    f"txns={txn_count}, rate={transaction_rate:.2f} TPS"
                )

        except Exception as e:
            logger.error(f"Error handling ledger event: {e}", exc_info=True)

    @property
    def ledger_count(self) -> int:
        """Get total number of ledgers processed"""
        return self._ledger_count

    @property
    def last_ledger_index(self) -> Optional[int]:
        """Get last processed ledger index"""
        return self._last_ledger_index

    @property
    def ledgers_closed_total(self) -> int:
        """Get total number of ledgers closed (counter)"""
        return self._ledgers_closed_total

    def get_consensus_hash(self, ledger_index: int) -> Optional[str]:
        """
        Get the consensus ledger hash for a given ledger index

        Args:
            ledger_index: The ledger index to look up

        Returns:
            The consensus ledger hash, or None if not found
        """
        return self._ledger_hash_lookup.get(ledger_index)

    def __repr__(self) -> str:
        return (
            f"LedgerHandler(ledgers_processed={self._ledger_count}, "
            f"last_index={self._last_ledger_index}, "
            f"ledgers_closed_total={self._ledgers_closed_total})"
        )
