#!/usr/bin/env python3
"""
Validations Stream Handler

Processes validation stream events from rippled WebSocket and tracks validation metrics.
This is a HIGH VOLUME stream (150-300 messages per ledger, ~50-100 msg/sec).

Uses application-side windowing (v2 pattern):
- Track validations in time-windowed deques (1h, 24h)
- Calculate agreement %, agreements, missed in application
- Emit simple gauge metrics with pre-calculated values
- Dashboard queries just reference metric names
"""

import asyncio
import logging
import time
from collections import deque
from dataclasses import dataclass
from typing import Optional, Dict, TYPE_CHECKING

from clients.victoria_client import VictoriaMetricsClient, create_gauge, create_counter

if TYPE_CHECKING:
    from handlers.ledger_handler import LedgerHandler


logger = logging.getLogger(__name__)


class ValidationRecord:
    """Represents a single validation event"""
    def __init__(self, timestamp: float, ledger_index: int, agreed: bool):
        self.timestamp = timestamp
        self.ledger_index = ledger_index
        self.agreed = agreed


@dataclass
class PendingLedgerRecord:
    """
    Tracks a ledger awaiting validation reconciliation

    Stores both consensus hash (from ledger stream) and our validation hash
    (from validations stream) to determine if we agreed, disagreed, or missed
    the validation entirely.

    Reconciliation logic:
    - Grace period: 8 seconds after ledger close before marking as missed
    - Late repair: 5 minutes window to fix false positives
    """
    ledger_index: int
    consensus_hash: Optional[str] = None
    our_hash: Optional[str] = None
    closed_at: Optional[float] = None      # time.monotonic() when ledger closed
    validated_at: Optional[float] = None    # time.monotonic() when we validated
    finalized: bool = False
    finalized_as_missed_at: Optional[float] = None  # For late repair tracking


class ValidationsHandler:
    """
    Handles validation tracking with application-side windowing (v2 pattern)

    Subscribes to: 'validations' stream (validationReceived events)
    Tracks when our validator sends validations and compares hashes with consensus

    Metrics emitted (simple gauges):
    - xrpl_validation_agreement_pct_1h: Agreement % over last 1 hour
    - xrpl_validation_agreements_1h: Total agreements over last 1 hour
    - xrpl_validation_missed_1h: Missed validations over last 1 hour
    - xrpl_validation_agreement_pct_24h: Agreement % over last 24 hours
    - xrpl_validation_agreements_24h: Total agreements over last 24 hours
    - xrpl_validation_missed_24h: Missed validations over last 24 hours
    """

    def __init__(
        self,
        victoria_client: VictoriaMetricsClient,
        ledger_handler: Optional['LedgerHandler'] = None,
        our_validator_key: Optional[str] = None
    ):
        """
        Initialize validations handler

        Args:
            victoria_client: VictoriaMetrics client for writing metrics
            ledger_handler: Reference to ledger handler for consensus hash lookups
            our_validator_key: Our validator's public key (master_key or validation_public_key)
        """
        self.victoria_client = victoria_client
        self.ledger_handler = ledger_handler
        self.our_validator_key = our_validator_key

        # Time-windowed validation tracking
        self._validations_1h: deque[ValidationRecord] = deque()
        self._validations_24h: deque[ValidationRecord] = deque()

        # Metrics write control
        self._last_metrics_write = time.time()
        self._metrics_write_interval = 10  # Write metrics every 10 seconds

        # De-duplication tracking (prevent counting same ledger twice)
        self._seen_ledgers = set()
        self._seen_ledgers_max_size = 2000  # Keep last 2000 ledger indices

        # Time window constants (in seconds)
        self._window_1h = 3600
        self._window_24h = 86400

        # Counter for total validations checked (ALL validations from network)
        self._validations_checked_total = 0

        # Counter for total validations (for rate calculation - only our validator)
        self._validations_total = 0

        # Counters for agreements and misses (Phase 1: parallel with gauges)
        # These monotonic counters enable restart-proof metrics via increase() queries
        self._agreements_total = 0
        self._missed_total = 0

        # Recovered gauge values (used as BASELINE during recovery period)
        # These represent the window state at restart time
        # We ADD deque values to these during recovery to get the true current value
        self._recovered_gauges = {
            "agreements_1h": None,
            "missed_1h": None,
            "agreements_24h": None,
            "missed_24h": None
        }

        # Track when recovery happened (to know when to stop using recovered values)
        self._recovery_time = None

        # Track deque snapshots at recovery time (to calculate delta)
        self._recovery_deque_snapshots = {
            "agreements_1h": 0,
            "missed_1h": 0,
            "agreements_24h": 0,
            "missed_24h": 0
        }

        # Pending ledger reconciliation (Option 2: Full Reconciliation)
        # Maps ledger_index -> PendingLedgerRecord for tracking validation completeness
        self._pending_ledgers: Dict[int, PendingLedgerRecord] = {}

        # Reconciliation timing constants
        self._grace_period = 8.0  # seconds to wait before marking ledger as missed
        self._late_repair_window = 300.0  # 5 minutes to fix false positives
        self._cleanup_age = 600.0  # Clean up finalized records after 10 minutes

        # Reconciliation control
        self._reconciliation_running = False
        self._reconciliation_interval = 1.0  # Check every 1 second

        logger.info(
            f"ValidationsHandler initialized (v2 pattern with time windows) "
            f"(validator_key={'configured' if our_validator_key else 'not set'})"
        )

    async def recover_from_victoria_metrics(self):
        """
        Recover validation history from VictoriaMetrics on startup

        Queries the last 24 hours of xrpl_validation_event metrics and rebuilds
        the 1h and 24h deques. Also recovers the total validations checked counter.
        This enables the dashboard to show correct agreement percentages and
        validation counts immediately after a restart instead of starting from 0.

        Called during monitor initialization.
        """
        try:
            logger.info("Recovering validation history from VictoriaMetrics...")

            # Step 1: Recover total validations checked counter (network-wide, not validator-specific)
            await self._recover_validations_checked_counter()

            # Step 2: Recover validations_total counter with rippled restart detection
            await self._recover_validations_total_counter()

            # Step 3: Recover agreement/missed counters (Phase 1: parallel with gauges)
            await self._recover_agreement_counters()

            # Step 4: Recover agreement/missed gauges (1h and 24h windows)
            await self._recover_agreement_gauges()

            logger.info("Validation recovery complete. Counters and gauges restored from VictoriaMetrics.")

        except Exception as e:
            logger.error(f"Error recovering validation history from VictoriaMetrics: {e}", exc_info=True)

    async def _recover_validation_events(self):
        """
        Recover validation events from VictoriaMetrics to rebuild the deques

        Queries the last 24 hours of xrpl_validation_event metrics and rebuilds
        the 1h and 24h deques. Uses the 'agreed' label to determine if each
        validation was an agreement or miss.
        """
        try:
            logger.info("Recovering validation events from VictoriaMetrics...")

            # Query last 24 hours of validation events
            lookback_seconds = self._window_24h  # 86400 seconds = 24 hours
            current_time = int(time.time())
            start_time = current_time - lookback_seconds

            # Query both agreed and missed events
            result_agreed = await self.victoria_client.query_range(
                query='xrpl_validation_event{agreed="true"}',
                start=start_time,
                end=current_time,
                step="1s"  # 1 second granularity
            )

            result_missed = await self.victoria_client.query_range(
                query='xrpl_validation_event{agreed="false"}',
                start=start_time,
                end=current_time,
                step="1s"
            )

            # Parse and rebuild deques
            events_recovered = 0

            # Process agreed validations
            if result_agreed and result_agreed.get('status') == 'success':
                data = result_agreed.get('data', {})
                results = data.get('result', [])

                for result in results:
                    values = result.get('values', [])
                    for timestamp, _ in values:
                        # Add to deques as agreed validation
                        self._validations_24h.append((timestamp, True))
                        if current_time - timestamp <= self._window_1h:
                            self._validations_1h.append((timestamp, True))
                        events_recovered += 1

            # Process missed validations
            if result_missed and result_missed.get('status') == 'success':
                data = result_missed.get('data', {})
                results = data.get('result', [])

                for result in results:
                    values = result.get('values', [])
                    for timestamp, _ in values:
                        # Add to deques as missed validation
                        self._validations_24h.append((timestamp, False))
                        if current_time - timestamp <= self._window_1h:
                            self._validations_1h.append((timestamp, False))
                        events_recovered += 1

            if events_recovered > 0:
                # Sort deques by timestamp (oldest first)
                self._validations_1h = deque(sorted(self._validations_1h, key=lambda x: x[0]), maxlen=10000)
                self._validations_24h = deque(sorted(self._validations_24h, key=lambda x: x[0]), maxlen=100000)

                logger.info(f"Recovered {events_recovered} validation events from VictoriaMetrics")
                logger.info(f"Rebuilt deques: 1h={len(self._validations_1h)}, 24h={len(self._validations_24h)}")
            else:
                logger.info("No validation events found in VictoriaMetrics (fresh start)")

        except Exception as e:
            logger.error(f"Error recovering validation events: {e}", exc_info=True)

    async def _recover_validations_checked_counter(self):
        """
        Recover the total validations checked counter from VictoriaMetrics

        Queries the maximum value of xrpl_validations_checked_total over the last 24h
        and initializes the counter with that value. This ensures the counter
        continues from its highest historical value instead of resetting to 0 on restart.
        """
        try:
            # Query the maximum value of the validations checked counter over last 24h
            result = await self.victoria_client.query("max_over_time(xrpl_validations_checked_total[24h])")

            if not result or result.get('status') != 'success':
                logger.info("No previous validations checked counter found in VictoriaMetrics (starting from 0)")
                return

            # Parse response
            data = result.get('data', {})
            results = data.get('result', [])

            if not results:
                logger.info("No previous validations checked counter found in VictoriaMetrics (starting from 0)")
                return

            # Get the value from the first result
            # Format: {"metric": {...}, "value": [timestamp, "value_string"]}
            value_pair = results[0].get('value', [])
            if len(value_pair) >= 2:
                recovered_value = int(float(value_pair[1]))
                self._validations_checked_total = recovered_value
                logger.info(f"Recovered validations checked counter: {recovered_value:,}")
            else:
                logger.info("No previous validations checked counter found in VictoriaMetrics (starting from 0)")

        except Exception as e:
            logger.error(f"Error recovering validations checked counter: {e}", exc_info=True)

    async def _recover_agreement_counters(self):
        """
        Recover agreement and missed counters from VictoriaMetrics (Phase 1)

        Queries the maximum values of xrpl_validation_agreements_total and
        xrpl_validation_missed_total over the last 24h and initializes the counters with those values.
        This ensures the counters continue from their highest historical value instead of
        resetting to 0 on restart.

        These counters run in parallel with the existing gauges during Phase 1,
        allowing us to validate accuracy before switching the dashboard queries.
        """
        try:
            # Recover agreements counter (use max over 24h to get highest historical value)
            result_agreements = await self.victoria_client.query("max_over_time(xrpl_validation_agreements_total[24h])")

            if result_agreements and result_agreements.get('status') == 'success':
                data = result_agreements.get('data', {})
                results = data.get('result', [])
                if results:
                    value_pair = results[0].get('value', [])
                    if len(value_pair) >= 2:
                        recovered_value = int(float(value_pair[1]))
                        self._agreements_total = recovered_value
                        logger.info(f"Recovered agreements counter: {recovered_value:,}")
                    else:
                        logger.info("No previous agreements counter found (starting from 0)")
                else:
                    logger.info("No previous agreements counter found (starting from 0)")
            else:
                logger.info("No previous agreements counter found (starting from 0)")

            # Recover missed counter (use max over 24h to get highest historical value)
            result_missed = await self.victoria_client.query("max_over_time(xrpl_validation_missed_total[24h])")

            if result_missed and result_missed.get('status') == 'success':
                data = result_missed.get('data', {})
                results = data.get('result', [])
                if results:
                    value_pair = results[0].get('value', [])
                    if len(value_pair) >= 2:
                        recovered_value = int(float(value_pair[1]))
                        self._missed_total = recovered_value
                        logger.info(f"Recovered missed counter: {recovered_value:,}")
                    else:
                        logger.info("No previous missed counter found (starting from 0)")
                else:
                    logger.info("No previous missed counter found (starting from 0)")
            else:
                logger.info("No previous missed counter found (starting from 0)")

        except Exception as e:
            logger.error(f"Error recovering agreement/missed counters: {e}", exc_info=True)

    async def _recover_agreement_gauges(self):
        """
        Recover validation agreement/missed gauges from VictoriaMetrics

        Queries the most recent values of the 1h and 24h agreement/missed metrics
        and writes them back to VictoriaMetrics. This prevents the dashboard panels
        from resetting to zero on collector restart, eliminating user frustration
        with metrics that need to "count up again" over the window period.

        Metrics recovered:
        - xrpl_validation_agreements_1h: Number of agreements in last hour
        - xrpl_validation_missed_1h: Number of missed validations in last hour
        - xrpl_validation_agreements_24h: Number of agreements in last 24 hours
        - xrpl_validation_missed_24h: Number of missed validations in last 24 hours
        - xrpl_validation_agreement_pct_1h: Agreement percentage (calculated from counts)
        - xrpl_validation_agreement_pct_24h: Agreement percentage (calculated from counts)

        As new validation events arrive, these gauges will update normally.
        The recovery just provides continuity across collector restarts.
        """
        # Use last_over_time to get the most recent value before restart
        # These are windowed gauges that can go up AND down as events age out,
        # so we need the current value, not the historical maximum
        metrics_to_recover = {
            "xrpl_validation_agreements_1h": ("1h agreements", "5m"),
            "xrpl_validation_missed_1h": ("1h missed", "5m"),
            "xrpl_validation_agreements_24h": ("24h agreements", "5m"),
            "xrpl_validation_missed_24h": ("24h missed", "5m")
        }

        # Store recovered values for percentage calculation and batch writing
        recovered_values = {}
        recovered_count = 0
        recovered_metrics = []  # Collect all recovered metrics for batch write

        for metric_name, (display_name, lookback) in metrics_to_recover.items():
            try:
                # Query the last value over a short lookback period to get current value
                # Using last_over_time instead of max_over_time because these gauges
                # can decrease as old events age out of the window
                query = f"last_over_time({metric_name}[{lookback}])"
                result = await self.victoria_client.query(query)

                if not result or result.get('status') != 'success':
                    logger.info(f"No previous {display_name} gauge found (will start fresh)")
                    continue

                # Parse response
                data = result.get('data', {})
                results = data.get('result', [])

                if not results:
                    logger.info(f"No previous {display_name} gauge found (will start fresh)")
                    continue

                # Get the value from the first result
                # Format: {"metric": {...}, "value": [timestamp, "value_string"]}
                value_pair = results[0].get('value', [])
                if len(value_pair) >= 2:
                    recovered_value = int(float(value_pair[1]))

                    # Store for percentage calculation and internal tracking
                    recovered_values[metric_name] = recovered_value

                    # Store in internal state to prevent overwriting by empty deques
                    if "1h" in metric_name and "agreements" in metric_name:
                        self._recovered_gauges["agreements_1h"] = recovered_value
                    elif "1h" in metric_name and "missed" in metric_name:
                        self._recovered_gauges["missed_1h"] = recovered_value
                    elif "24h" in metric_name and "agreements" in metric_name:
                        self._recovered_gauges["agreements_24h"] = recovered_value
                    elif "24h" in metric_name and "missed" in metric_name:
                        self._recovered_gauges["missed_24h"] = recovered_value

                    # Collect metric for batch write (don't write individually)
                    metric = create_gauge(metric_name, recovered_value)
                    recovered_metrics.append(metric)

                    logger.info(f"Recovered {display_name}: {recovered_value}")
                    recovered_count += 1
                else:
                    logger.info(f"No previous {display_name} gauge found (will start fresh)")

            except Exception as e:
                logger.error(f"Error recovering {display_name} gauge: {e}", exc_info=True)

        # Calculate and collect agreement percentages from recovered counts
        if recovered_count > 0:
            try:
                # Calculate 1h percentage
                agreements_1h = recovered_values.get("xrpl_validation_agreements_1h", 0)
                missed_1h = recovered_values.get("xrpl_validation_missed_1h", 0)
                total_1h = agreements_1h + missed_1h

                if total_1h > 0:
                    pct_1h = (agreements_1h / total_1h) * 100
                    metric_pct_1h = create_gauge("xrpl_validation_agreement_pct_1h", pct_1h)
                    recovered_metrics.append(metric_pct_1h)
                    logger.info(f"Recovered 1h agreement %: {pct_1h:.2f}%")
                    recovered_count += 1

                # Calculate 24h percentage
                agreements_24h = recovered_values.get("xrpl_validation_agreements_24h", 0)
                missed_24h = recovered_values.get("xrpl_validation_missed_24h", 0)
                total_24h = agreements_24h + missed_24h

                if total_24h > 0:
                    pct_24h = (agreements_24h / total_24h) * 100
                    metric_pct_24h = create_gauge("xrpl_validation_agreement_pct_24h", pct_24h)
                    recovered_metrics.append(metric_pct_24h)
                    logger.info(f"Recovered 24h agreement %: {pct_24h:.2f}%")
                    recovered_count += 1

            except Exception as e:
                logger.error(f"Error calculating agreement percentages: {e}", exc_info=True)

        # Write all recovered metrics in a single batch with immediate flush
        # This ensures values are visible on dashboard immediately after recovery
        if recovered_metrics:
            await self.victoria_client.write_metrics(recovered_metrics, flush_immediately=True)
            logger.info(f"Flushed {len(recovered_metrics)} recovered metrics to VictoriaMetrics")

        # Record recovery time to know when to stop using recovered values
        if recovered_count > 0:
            self._recovery_time = time.time()
            logger.info(f"Agreement gauge recovery complete: {recovered_count}/6 metrics restored")
        else:
            logger.info("No previous agreement gauges found (fresh start)")

    async def _recover_validations_total_counter(self):
        """
        Recover the validations sent counter from VictoriaMetrics with rippled restart detection

        This method implements smart counter recovery:
        1. Query rippled uptime from 5 minutes ago
        2. Query current rippled uptime
        3. If current < past → rippled restarted → reset counter to 0
        4. If current >= past → rippled still running → restore counter value

        This ensures the counter tracks "validations sent since rippled last restarted"
        and survives monitor restarts without losing count.
        """
        try:
            logger.info("Starting validations_total counter recovery with rippled restart detection...")

            # Step 1: Query rippled uptime from 5 minutes ago (300 seconds)
            # This serves as our "baseline" to detect if rippled restarted
            lookback_seconds = 300
            current_time = int(time.time())
            past_time = current_time - lookback_seconds

            past_uptime_result = await self.victoria_client.query_range(
                query="xrpl_validator_uptime_seconds",
                start=past_time,
                end=current_time,
                step="60s"  # Sample every minute (uptime changes every 60s due to rounding)
            )

            if not past_uptime_result or past_uptime_result.get('status') != 'success':
                logger.info("No historical rippled uptime data (first run or insufficient data) - recovering counter")
                # No historical data, just try to recover the counter
                await self._try_recover_validations_counter()
                return

            # Parse past uptime
            past_uptime_data = past_uptime_result.get('data', {})
            past_uptime_results = past_uptime_data.get('result', [])

            if not past_uptime_results:
                logger.info("No historical rippled uptime data (first run or insufficient data) - recovering counter")
                await self._try_recover_validations_counter()
                return

            # Get the oldest value from the range (first value in matrix)
            past_values = past_uptime_results[0].get('values', [])
            if not past_values:
                logger.info("No historical rippled uptime data (first run or insufficient data) - recovering counter")
                await self._try_recover_validations_counter()
                return

            # Format: [[timestamp, "value"], ...]
            past_uptime = float(past_values[0][1])

            # Step 2: Get current rippled uptime
            current_uptime_result = await self.victoria_client.query("xrpl_validator_uptime_seconds")

            if not current_uptime_result or current_uptime_result.get('status') != 'success':
                logger.warning("Cannot determine current rippled uptime for restart detection - recovering counter")
                await self._try_recover_validations_counter()
                return

            current_uptime_data = current_uptime_result.get('data', {})
            current_uptime_results = current_uptime_data.get('result', [])

            if not current_uptime_results:
                logger.warning("Cannot determine current rippled uptime for restart detection - recovering counter")
                await self._try_recover_validations_counter()
                return

            current_uptime_pair = current_uptime_results[0].get('value', [])
            if len(current_uptime_pair) < 2:
                logger.warning("Cannot determine current rippled uptime for restart detection - recovering counter")
                await self._try_recover_validations_counter()
                return

            current_uptime = float(current_uptime_pair[1])

            # Step 3: Compare uptimes to detect rippled restart
            # Allow 120 second tolerance for clock skew and rounding (uptime is rounded to nearest minute)
            uptime_tolerance = 120

            if current_uptime < (past_uptime - uptime_tolerance):
                # Uptime decreased significantly → rippled restarted
                logger.info(
                    f"Rippled restart detected: uptime decreased from {past_uptime:.0f}s to {current_uptime:.0f}s. "
                    f"Resetting validations counter to 0."
                )
                self._validations_total = 0
            else:
                # Uptime same or increased → rippled still running, recover counter
                logger.info(
                    f"Rippled still running: uptime {current_uptime:.0f}s (was {past_uptime:.0f}s {lookback_seconds}s ago). "
                    f"Recovering validations counter..."
                )
                await self._try_recover_validations_counter()

        except Exception as e:
            logger.error(f"Error in validations_total recovery with restart detection: {e}", exc_info=True)
            logger.info("Falling back to basic recovery without restart detection")
            # On error, try basic recovery anyway
            await self._try_recover_validations_counter()

    async def _try_recover_validations_counter(self):
        """
        Helper method to recover validations_total counter value from VictoriaMetrics

        This is called when we determine rippled did NOT restart and we should
        continue counting from the highest historical value.
        """
        try:
            # Query the maximum value of the validations total counter over last 24h
            result = await self.victoria_client.query("max_over_time(xrpl_validations_total[24h])")

            if not result or result.get('status') != 'success':
                logger.info("No previous validations_total counter found in VictoriaMetrics (starting from 0)")
                return

            # Parse response
            data = result.get('data', {})
            results = data.get('result', [])

            if not results:
                logger.info("No previous validations_total counter found in VictoriaMetrics (starting from 0)")
                return

            # Get the value from the first result
            # Format: {"metric": {...}, "value": [timestamp, "value_string"]}
            value_pair = results[0].get('value', [])
            if len(value_pair) >= 2:
                recovered_value = int(float(value_pair[1]))
                self._validations_total = recovered_value
                logger.info(f"Recovered validations_total counter: {recovered_value:,}")
            else:
                logger.info("No previous validations_total counter found in VictoriaMetrics (starting from 0)")

        except Exception as e:
            logger.error(f"Error recovering validations_total counter: {e}", exc_info=True)

    async def handle(self, message: dict):
        """
        Handle validation stream message

        Expected message format:
        {
            "type": "validationReceived",
            "validation_public_key": "n9...",  # ephemeral key
            "master_key": "nH...",              # permanent master key
            "ledger_index": 93847123,
            "ledger_hash": "ABC...",
            "flags": 1
        }

        Logic:
        1. Check if validation is from our validator (match master_key or validation_public_key)
        2. Look up consensus hash from ledger_handler to determine agreement
        3. Create ValidationRecord and add to time-windowed deques
        4. Prune old records outside time windows
        5. Write metrics periodically

        Args:
            message: Validation event message from rippled
        """
        try:
            # Extract fields
            validation_public_key = message.get('validation_public_key')
            master_key = message.get('master_key')
            ledger_index = message.get('ledger_index')
            validation_ledger_hash = message.get('ledger_hash')

            if not ledger_index:
                logger.warning(f"Validation message missing ledger_index: {message}")
                return

            # Increment counter for ALL validations checked (network-wide)
            self._validations_checked_total += 1

            # Skip if no validator key configured
            if not self.our_validator_key:
                return

            # Check if this validation is from our validator
            is_our_validator = (
                (validation_public_key and validation_public_key == self.our_validator_key) or
                (master_key and master_key == self.our_validator_key)
            )

            if not is_our_validator:
                # Not from our validator - skip
                return

            # De-duplicate: only count each ledger once
            if ledger_index in self._seen_ledgers:
                logger.debug(f"Skipping duplicate validation for ledger {ledger_index}")
                return

            # Mark as seen
            self._seen_ledgers.add(ledger_index)

            # Clean up old entries if set gets too large
            if len(self._seen_ledgers) > self._seen_ledgers_max_size:
                # Remove oldest 500 entries
                sorted_ledgers = sorted(self._seen_ledgers)
                for old_ledger in sorted_ledgers[:500]:
                    self._seen_ledgers.discard(old_ledger)

            # === Option 2: Full Reconciliation - Register our validation ===
            # Record our validation hash for pending ledger reconciliation
            # The reconciliation task will compare with consensus hash after grace period
            if validation_ledger_hash:
                await self.on_our_validation(ledger_index, validation_ledger_hash)

            # OLD METHOD (immediate hash comparison) - kept for reference
            # This is the backup/fallback logic (still used for gauge metrics in deques)
            # The reconciliation approach above is now authoritative for counters
            agreed = True  # Default: assume agreement
            if self.ledger_handler and validation_ledger_hash:
                consensus_hash = self.ledger_handler.get_consensus_hash(ledger_index)

                if consensus_hash:
                    if validation_ledger_hash == consensus_hash:
                        # Our validation matched consensus!
                        agreed = True
                        logger.debug(f"Ledger {ledger_index}: AGREED (hash match - old method)")
                    else:
                        # We validated but disagreed with consensus
                        agreed = False
                        logger.debug(
                            f"Ledger {ledger_index}: DISAGREED (old method) - "
                            f"(ours: {validation_ledger_hash[:8]}..., "
                            f"consensus: {consensus_hash[:8]}...)"
                        )

            # Create validation record (still needed for gauge metrics in time windows)
            current_time = time.time()
            record = ValidationRecord(
                timestamp=current_time,
                ledger_index=ledger_index,
                agreed=agreed
            )

            # Increment total validations counter
            self._validations_total += 1

            # NOTE: Counters now managed by reconciliation task, not here
            # The _agreements_total and _missed_total are updated in reconcile_pending_ledgers()
            # after the grace period expires

            # Add to time-windowed deques
            self._validations_1h.append(record)
            self._validations_24h.append(record)

            # Write individual validation event to VictoriaMetrics for persistence
            # This allows recovery of validation history on restart
            await self._write_validation_event(record)

            # Prune old records outside time windows
            self._prune_old_records()

            # Write metrics immediately for real-time dashboard updates
            # This is safe since we only track OUR validator's validations (~every 3-5 seconds)
            await self._write_metrics()
            self._last_metrics_write = current_time

        except Exception as e:
            logger.error(f"Error handling validation event: {e}", exc_info=True)

    def _prune_old_records(self):
        """Remove records outside time windows"""
        current_time = time.time()

        # Prune 1h window
        while self._validations_1h and (current_time - self._validations_1h[0].timestamp) > self._window_1h:
            self._validations_1h.popleft()

        # Prune 24h window
        while self._validations_24h and (current_time - self._validations_24h[0].timestamp) > self._window_24h:
            self._validations_24h.popleft()

    def _calculate_window_stats(self, window_deque: deque) -> tuple[int, int, int, float]:
        """
        Calculate statistics for a time window

        Args:
            window_deque: Deque containing ValidationRecord objects

        Returns:
            Tuple of (total_validations, agreements, missed, agreement_pct)
        """
        if not window_deque:
            return (0, 0, 0, 0.0)

        total = len(window_deque)
        agreed = sum(1 for record in window_deque if record.agreed)
        missed = total - agreed
        agreement_pct = (agreed / total * 100) if total > 0 else 0.0

        return (total, agreed, missed, agreement_pct)

    async def _write_validation_event(self, record: ValidationRecord):
        """
        Write individual validation event to VictoriaMetrics for persistence

        This stores each validation with labels for ledger_index and agreed status.
        Enables historical recovery on restart by querying VictoriaMetrics.

        Args:
            record: ValidationRecord containing timestamp, ledger_index, and agreed status
        """
        try:
            timestamp_ms = int(record.timestamp * 1000)

            # Write validation event with labels
            # Value: 1=agreed, 0=disagreed
            # NOTE: ledger_index removed to prevent cardinality explosion
            # (was creating 25k+ time series per day = 638M data points)
            metric = create_gauge(
                "xrpl_validation_event",
                1 if record.agreed else 0,
                labels={
                    "agreed": "true" if record.agreed else "false"
                },
                timestamp=timestamp_ms
            )

            await self.victoria_client.write_metric(metric, flush_immediately=False)

        except Exception as e:
            logger.error(f"Error writing validation event to VictoriaMetrics: {e}", exc_info=True)

    async def _write_metrics(self):
        """Write validation gauge metrics to VictoriaMetrics"""
        try:
            current_time = time.time()
            timestamp_ms = int(current_time * 1000)

            # Calculate stats for both windows from deques
            stats_1h = self._calculate_window_stats(self._validations_1h)
            stats_24h = self._calculate_window_stats(self._validations_24h)

            total_1h, agreed_1h, missed_1h, pct_1h = stats_1h
            total_24h, agreed_24h, missed_24h, pct_24h = stats_24h

            # Agreement gauges use LINEAR DECAY recovery:
            # 1. On startup, recover last gauge values from VictoriaMetrics
            # 2. As new validations arrive, deques track events since restart
            # 3. Recovered values decay linearly over the window period:
            #    - At T=0: 100% recovered + 0% deque
            #    - At T=30min: 50% recovered + deque (for 1h window)
            #    - At T=1h: 0% recovered + 100% deque
            # 4. This models the sliding window correctly as old events age out
            #
            # Benefits:
            # - Values don't drop to 0 on restart (user frustration eliminated)
            # - No double-counting (decay prevents inflated values)
            # - Smooth transition to deque-only values
            # - Mathematically accurate sliding window behavior

            # Apply linear decay to recovered gauge values
            if self._recovery_time is not None:
                recovery_age = current_time - self._recovery_time

                # 1h window: decay recovered values over 3600 seconds
                if recovery_age < 3600 and self._recovered_gauges.get("agreements_1h") is not None:
                    decay_factor_1h = 1.0 - (recovery_age / 3600)
                    recovered_agreed_1h = int(self._recovered_gauges["agreements_1h"] * decay_factor_1h)
                    recovered_missed_1h = int((self._recovered_gauges.get("missed_1h") or 0) * decay_factor_1h)
                    agreed_1h += recovered_agreed_1h
                    missed_1h += recovered_missed_1h
                    total_1h = agreed_1h + missed_1h
                    pct_1h = (agreed_1h / total_1h * 100) if total_1h > 0 else 0.0

                # 24h window: decay recovered values over 86400 seconds
                if recovery_age < 86400 and self._recovered_gauges.get("agreements_24h") is not None:
                    decay_factor_24h = 1.0 - (recovery_age / 86400)
                    recovered_agreed_24h = int(self._recovered_gauges["agreements_24h"] * decay_factor_24h)
                    recovered_missed_24h = int((self._recovered_gauges.get("missed_24h") or 0) * decay_factor_24h)
                    agreed_24h += recovered_agreed_24h
                    missed_24h += recovered_missed_24h
                    total_24h = agreed_24h + missed_24h
                    pct_24h = (agreed_24h / total_24h * 100) if total_24h > 0 else 0.0

            metrics = [
                # Total validations checked from network (ALL validators)
                create_counter(
                    "xrpl_validations_checked_total",
                    self._validations_checked_total,
                    timestamp=timestamp_ms
                ),
                # Total validations counter (for rate calculation - our validator only)
                create_counter(
                    "xrpl_validations_total",
                    self._validations_total,
                    timestamp=timestamp_ms
                ),
                # Agreement/missed counters (Phase 1: parallel with gauges)
                create_counter(
                    "xrpl_validation_agreements_total",
                    self._agreements_total,
                    timestamp=timestamp_ms
                ),
                create_counter(
                    "xrpl_validation_missed_total",
                    self._missed_total,
                    timestamp=timestamp_ms
                ),
                # 1 hour window
                create_gauge(
                    "xrpl_validation_agreement_pct_1h",
                    pct_1h,
                    timestamp=timestamp_ms
                ),
                create_gauge(
                    "xrpl_validation_agreements_1h",
                    agreed_1h,
                    timestamp=timestamp_ms
                ),
                create_gauge(
                    "xrpl_validation_missed_1h",
                    missed_1h,
                    timestamp=timestamp_ms
                ),
                # 24 hour window
                create_gauge(
                    "xrpl_validation_agreement_pct_24h",
                    pct_24h,
                    timestamp=timestamp_ms
                ),
                create_gauge(
                    "xrpl_validation_agreements_24h",
                    agreed_24h,
                    timestamp=timestamp_ms
                ),
                create_gauge(
                    "xrpl_validation_missed_24h",
                    missed_24h,
                    timestamp=timestamp_ms
                ),
            ]

            # Write to VictoriaMetrics
            await self.victoria_client.write_metrics(metrics, flush_immediately=False)

            logger.debug(
                f"Validation metrics: 1h({total_1h} total, {agreed_1h} agreed, {pct_1h:.1f}%), "
                f"24h({total_24h} total, {agreed_24h} agreed, {pct_24h:.1f}%)"
            )

        except Exception as e:
            logger.error(f"Error writing validation metrics: {e}", exc_info=True)

    async def flush_metrics(self):
        """Force immediate write of metrics (called on shutdown)"""
        await self._write_metrics()

    def set_ledger_handler(self, ledger_handler: 'LedgerHandler'):
        """
        Set reference to ledger handler for consensus hash lookups

        Args:
            ledger_handler: LedgerHandler instance
        """
        self.ledger_handler = ledger_handler
        logger.info("Ledger handler reference set for validation hash comparison")

    def set_our_validator_key(self, key: str):
        """
        Set our validator's public key

        Args:
            key: Validator public key (starts with 'nH')
        """
        self.our_validator_key = key
        logger.info(f"Our validator key set: {key}")

    # =========================================================================
    # PENDING LEDGER RECONCILIATION (Option 2: Full Reconciliation)
    # =========================================================================

    async def on_ledger_closed(self, ledger_index: int, consensus_hash: str):
        """
        Callback from ledger_handler when a ledger closes

        Records the consensus hash for a ledger and creates/updates pending ledger record.
        This starts the grace period clock for validation reconciliation.

        Args:
            ledger_index: Ledger sequence number
            consensus_hash: Consensus hash for this ledger
        """
        now = time.monotonic()

        if ledger_index in self._pending_ledgers:
            # Update existing record with consensus hash
            record = self._pending_ledgers[ledger_index]
            record.consensus_hash = consensus_hash
            if record.closed_at is None:
                record.closed_at = now

            logger.debug(
                f"Ledger {ledger_index}: Updated with consensus hash "
                f"{consensus_hash[:8]}... (our_hash={'set' if record.our_hash else 'pending'})"
            )
        else:
            # Create new pending ledger record
            self._pending_ledgers[ledger_index] = PendingLedgerRecord(
                ledger_index=ledger_index,
                consensus_hash=consensus_hash,
                closed_at=now
            )

            logger.debug(
                f"Ledger {ledger_index}: Created pending record with consensus hash "
                f"{consensus_hash[:8]}..."
            )

    async def on_our_validation(self, ledger_index: int, our_hash: str):
        """
        Callback when we detect OUR validator sent a validation

        Records our validation hash for a ledger and creates/updates pending ledger record.
        This hash will be compared with consensus hash during reconciliation.

        Args:
            ledger_index: Ledger sequence number
            our_hash: Our validator's hash for this ledger
        """
        now = time.monotonic()

        if ledger_index in self._pending_ledgers:
            # Update existing record with our validation hash
            record = self._pending_ledgers[ledger_index]
            record.our_hash = our_hash
            if record.validated_at is None:
                record.validated_at = now

            logger.debug(
                f"Ledger {ledger_index}: Our validation {our_hash[:8]}... "
                f"(consensus={'set' if record.consensus_hash else 'pending'})"
            )
        else:
            # Create new pending ledger record (rare: validation arrives before ledger close)
            self._pending_ledgers[ledger_index] = PendingLedgerRecord(
                ledger_index=ledger_index,
                our_hash=our_hash,
                validated_at=now
            )

            logger.debug(
                f"Ledger {ledger_index}: Created pending record with our hash "
                f"{our_hash[:8]}... (consensus pending)"
            )

    async def reconcile_pending_ledgers(self):
        """
        Background task to reconcile pending ledgers with grace period and late repair

        Reconciliation logic:
        1. Grace period (8 seconds): Wait after ledger close before finalizing
        2. Finalization: Check if we have both consensus hash and our validation
        3. Late repair (5 minutes): Fix false positives if late validation arrives
        4. Cleanup (10 minutes): Remove old finalized records to prevent memory leak

        Runs continuously until stopped. Call this as an asyncio task in the event loop.
        """
        self._reconciliation_running = True
        logger.info(
            f"Reconciliation task started (grace: {self._grace_period}s, "
            f"late repair: {self._late_repair_window}s, "
            f"cleanup: {self._cleanup_age}s)"
        )

        try:
            while self._reconciliation_running:
                await asyncio.sleep(self._reconciliation_interval)
                await self._reconcile_cycle()

        except asyncio.CancelledError:
            logger.info("Reconciliation task cancelled")
            raise
        except Exception as e:
            logger.error(f"Reconciliation task failed: {e}", exc_info=True)
            raise

    async def _reconcile_cycle(self):
        """Single reconciliation cycle - process all pending ledgers"""
        now = time.monotonic()
        ledgers_to_remove = []

        for ledger_index, record in self._pending_ledgers.items():
            # Skip if no consensus hash yet (ledger hasn't closed)
            if record.consensus_hash is None:
                continue

            # Skip if no closed_at timestamp (shouldn't happen, but safety check)
            if record.closed_at is None:
                continue

            # Calculate age since ledger close
            age_since_close = now - record.closed_at

            # === LATE REPAIR: Fix false positives ===
            if record.finalized and record.finalized_as_missed_at is not None:
                # Check if our validation arrived late (within repair window)
                if record.our_hash is not None:
                    repair_age = now - record.finalized_as_missed_at
                    if repair_age <= self._late_repair_window:
                        # Undo the missed count, add to agreed count
                        logger.info(
                            f"Ledger {ledger_index}: LATE REPAIR - validation arrived "
                            f"{repair_age:.1f}s after marked as missed"
                        )
                        self._missed_total -= 1  # Undo missed

                        # Check if it was agreement or disagreement
                        if record.our_hash == record.consensus_hash:
                            self._agreements_total += 1
                            logger.info(f"Ledger {ledger_index}: Repaired as AGREEMENT")
                        else:
                            self._missed_total += 1  # Re-add as disagreement
                            logger.info(f"Ledger {ledger_index}: Repaired as DISAGREEMENT")

                        record.finalized_as_missed_at = None  # Clear repair marker

            # === CLEANUP: Remove old finalized records ===
            if record.finalized and age_since_close > self._cleanup_age:
                ledgers_to_remove.append(ledger_index)
                continue

            # === FINALIZATION: Grace period expired, time to decide ===
            if not record.finalized and age_since_close > self._grace_period:
                if record.our_hash is not None:
                    # We validated this ledger - check if we agreed
                    if record.our_hash == record.consensus_hash:
                        self._agreements_total += 1
                        logger.debug(f"Ledger {ledger_index}: AGREED (reconciled)")
                    else:
                        self._missed_total += 1
                        logger.debug(
                            f"Ledger {ledger_index}: DISAGREED (reconciled) - "
                            f"ours: {record.our_hash[:8]}..., "
                            f"consensus: {record.consensus_hash[:8]}..."
                        )
                else:
                    # No validation from us - mark as missed (unsent)
                    self._missed_total += 1
                    record.finalized_as_missed_at = now  # Enable late repair

                    # Add missed validation to deques for time-windowed gauge metrics
                    # This ensures Missed (1h) and Missed (24h) panels show actual misses
                    missed_record = ValidationRecord(
                        timestamp=time.time(),
                        ledger_index=ledger_index,
                        agreed=False  # Missed = not agreed
                    )
                    self._validations_1h.append(missed_record)
                    self._validations_24h.append(missed_record)

                    # Write missed event to VictoriaMetrics for persistence/recovery
                    await self._write_validation_event(missed_record)

                    logger.debug(
                        f"Ledger {ledger_index}: MISSED (reconciled) - "
                        f"no validation sent (grace period expired)"
                    )

                record.finalized = True

        # Remove old finalized records
        for ledger_index in ledgers_to_remove:
            del self._pending_ledgers[ledger_index]

        if ledgers_to_remove:
            logger.debug(f"Cleaned up {len(ledgers_to_remove)} old pending ledger records")

    def stop_reconciliation(self):
        """Stop the reconciliation background task"""
        self._reconciliation_running = False
        logger.info("Reconciliation task stop requested")

    # =========================================================================
    # END PENDING LEDGER RECONCILIATION
    # =========================================================================

    def __repr__(self) -> str:
        stats_1h = self._calculate_window_stats(self._validations_1h)
        return (
            f"ValidationsHandler(1h: {stats_1h[0]} total, {stats_1h[1]} agreed, "
            f"{stats_1h[3]:.1f}%)"
        )
