#!/usr/bin/env python3
"""
State Manager - Persistent State Backup & Recovery System

Provides dual-layer state persistence:
1. Primary: VictoriaMetrics (fast, queryable, time-series)
2. Backup: JSON files in /app/state/ (disaster recovery)

Features:
- Startup validation (ensures /app/state/ is writable)
- Real-time state backup to VM with type="server_state_backup" label
- Automatic recovery from VM or file backups
- Health monitoring metrics
- 24h auto-purge of backup metrics (via VM retention filter)
"""

import json
import logging
import os
import time
from pathlib import Path
from typing import Dict, Optional, Any

from clients.victoria_client import VictoriaMetricsClient, create_gauge

logger = logging.getLogger(__name__)


class StateManager:
    """
    Manages persistent state for counters and gauges with dual-layer backup

    This prevents the catastrophic data loss scenario where:
    - 30K validations sent → lost on restart
    - 21K agreements (24h) → lost on restart
    - Weeks of data accumulation → gone

    State is persisted to:
    1. VictoriaMetrics (primary, with backup label)
    2. JSON files in /app/state/ (secondary, for volume recovery)
    """

    def __init__(
        self,
        victoria_client: VictoriaMetricsClient,
        state_dir: str = "/app/state"
    ):
        """
        Initialize state manager

        Args:
            victoria_client: VictoriaMetrics client for writing metrics
            state_dir: Directory for state JSON files (default: /app/state)
        """
        self.victoria_client = victoria_client
        self.state_dir = Path(state_dir)

        # Health tracking
        self._health_status = 1  # 1=ok, 0.5=degraded, 0=failed
        self._last_save_time = 0
        self._last_save_error = None
        self._save_failures = 0
        self._recovery_info = None

        logger.info(f"StateManager initialized (state_dir={state_dir})")

    def validate_state_directory(self) -> bool:
        """
        Validate state directory exists and is writable

        Called on startup to fail fast if state can't be persisted.

        Returns:
            True if directory is accessible and writable, False otherwise

        Raises:
            RuntimeError: If directory validation fails (intentional fail-fast)
        """
        try:
            # Check if directory exists
            if not self.state_dir.exists():
                logger.info(f"State directory does not exist, creating: {self.state_dir}")
                self.state_dir.mkdir(parents=True, exist_ok=True)

            # Check if directory is writable by writing a test file
            test_file = self.state_dir / ".write_test"
            try:
                test_file.write_text("test")
                test_file.unlink()
                logger.info(f"✓ State directory validated: {self.state_dir}")
                return True
            except (OSError, PermissionError) as e:
                logger.error(f"✗ State directory is not writable: {self.state_dir}")
                logger.error(f"  Error: {e}")
                raise RuntimeError(
                    f"State directory is not writable: {self.state_dir}. "
                    f"This will cause data loss on restart. Please fix permissions or volume mount."
                ) from e

        except Exception as e:
            logger.error(f"✗ State directory validation failed: {e}")
            raise RuntimeError(
                f"State directory validation failed: {e}. "
                f"State persistence is required for reliable operation."
            ) from e

    async def save_state(
        self,
        metric_name: str,
        value: float,
        metadata: Optional[Dict[str, Any]] = None
    ):
        """
        Save state to both VictoriaMetrics and JSON file

        Dual-layer persistence:
        1. Write to VictoriaMetrics with type="server_state_backup" label
        2. Write to JSON file in /app/state/

        Args:
            metric_name: Name of the metric (e.g., "validations_sent")
            value: Current value to save
            metadata: Optional metadata to save with state
        """
        try:
            timestamp_ms = int(time.time() * 1000)

            # Layer 1: Write backup to VictoriaMetrics
            # This is queryable and survives collector restarts
            backup_metric = create_gauge(
                "xrpl_state_backup",
                value,
                labels={
                    "metric": metric_name,
                    "type": "server_state_backup"
                },
                timestamp=timestamp_ms
            )
            await self.victoria_client.write_metric(backup_metric, flush_immediately=False)

            # Layer 2: Write to JSON file
            # This survives VM restarts and provides local backup
            state_data = {
                "value": value,
                "timestamp": time.time(),
                "metadata": metadata or {}
            }

            state_file = self.state_dir / f"{metric_name}.json"
            state_file.write_text(json.dumps(state_data, indent=2))

            # Update health tracking
            self._last_save_time = time.time()
            self._save_failures = 0
            self._health_status = 1  # OK

            logger.debug(f"State saved: {metric_name}={value}")

        except Exception as e:
            logger.error(f"Error saving state for {metric_name}: {e}", exc_info=True)
            self._save_failures += 1
            self._last_save_error = str(e)

            # Update health status based on failure count
            if self._save_failures >= 3:
                self._health_status = 0  # Failed
            else:
                self._health_status = 0.5  # Degraded

    async def recover_state(
        self,
        metric_name: str
    ) -> Optional[float]:
        """
        Recover state from backups (VM or file)

        Recovery order:
        1. Try VictoriaMetrics backup (most recent)
        2. Fall back to JSON file if VM query fails
        3. Return None if no backup found

        Args:
            metric_name: Name of the metric to recover

        Returns:
            Recovered value or None if not found
        """
        try:
            # Try recovery from VictoriaMetrics first (most authoritative)
            vm_value = await self._recover_from_vm(metric_name)
            if vm_value is not None:
                self._recovery_info = f"Recovered {metric_name} from VictoriaMetrics: {vm_value}"
                logger.info(self._recovery_info)
                return vm_value

            # Fall back to JSON file
            file_value = self._recover_from_file(metric_name)
            if file_value is not None:
                self._recovery_info = f"Recovered {metric_name} from file: {file_value}"
                logger.info(self._recovery_info)
                return file_value

            logger.info(f"No backup found for {metric_name} (starting fresh)")
            return None

        except Exception as e:
            logger.error(f"Error recovering state for {metric_name}: {e}", exc_info=True)
            return None

    async def _recover_from_vm(self, metric_name: str) -> Optional[float]:
        """Recover state from VictoriaMetrics backup"""
        try:
            # Query the backup metric
            query = f'xrpl_state_backup{{metric="{metric_name}", type="server_state_backup"}}'
            result = await self.victoria_client.query(query)

            if not result or result.get('status') != 'success':
                return None

            data = result.get('data', {})
            results = data.get('result', [])

            if not results:
                return None

            # Extract value
            value_pair = results[0].get('value', [])
            if len(value_pair) >= 2:
                return float(value_pair[1])

            return None

        except Exception as e:
            logger.debug(f"VM recovery failed for {metric_name}: {e}")
            return None

    def _recover_from_file(self, metric_name: str) -> Optional[float]:
        """Recover state from JSON file"""
        try:
            state_file = self.state_dir / f"{metric_name}.json"

            if not state_file.exists():
                return None

            state_data = json.loads(state_file.read_text())
            return float(state_data.get('value'))

        except Exception as e:
            logger.debug(f"File recovery failed for {metric_name}: {e}")
            return None

    async def emit_health_metrics(self):
        """
        Emit state health monitoring metrics

        Metrics:
        - xrpl_state_health: Overall health (1=ok, 0.5=degraded, 0=failed)
        - xrpl_state_last_save_timestamp: When state was last saved
        - xrpl_state_save_failures_total: Count of save failures
        """
        try:
            timestamp_ms = int(time.time() * 1000)

            metrics = [
                # Overall health status
                create_gauge(
                    "xrpl_state_health",
                    self._health_status,
                    labels={"status": self._get_health_label()},
                    timestamp=timestamp_ms
                ),
                # Last save timestamp
                create_gauge(
                    "xrpl_state_last_save_timestamp",
                    self._last_save_time,
                    timestamp=timestamp_ms
                ),
                # Save failure counter
                create_gauge(
                    "xrpl_state_save_failures_total",
                    self._save_failures,
                    timestamp=timestamp_ms
                )
            ]

            await self.victoria_client.write_metrics(metrics, flush_immediately=False)

        except Exception as e:
            logger.error(f"Error emitting health metrics: {e}", exc_info=True)

    def _get_health_label(self) -> str:
        """Get health status label"""
        if self._health_status >= 1:
            return "ok"
        elif self._health_status >= 0.5:
            return "degraded"
        else:
            return "failed"

    def check_stale_state(self) -> bool:
        """
        Check if state files are stale (haven't been updated recently)

        Returns:
            True if state is stale (>10 minutes old while running), False otherwise
        """
        if self._last_save_time == 0:
            return False  # No saves yet, can't be stale

        time_since_save = time.time() - self._last_save_time

        # If more than 10 minutes since last save, state might be stale
        if time_since_save > 600:
            logger.warning(
                f"State may be stale: Last save was {time_since_save:.0f}s ago "
                f"(>10 minutes). Possible write issue."
            )
            return True

        return False

    async def backup_critical_metrics(self):
        """
        Backup critical metrics from VictoriaMetrics to JSON files

        This provides a secondary backup layer for disaster recovery.
        Queries current values from VM and writes to local JSON files.

        Critical metrics backed up:
        - validations_total
        - validation_agreements_1h
        - validation_agreements_24h
        - validation_missed_1h
        - validation_missed_24h
        """
        metrics_to_backup = [
            "xrpl_validations_total",
            "xrpl_validation_agreements_1h",
            "xrpl_validation_missed_1h",
            "xrpl_validation_agreements_24h",
            "xrpl_validation_missed_24h"
        ]

        for metric_name in metrics_to_backup:
            try:
                # Query current value from VM
                result = await self.victoria_client.query(metric_name)

                if not result or result.get('status') != 'success':
                    continue

                data = result.get('data', {})
                results = data.get('result', [])

                if not results:
                    continue

                # Extract value
                value_pair = results[0].get('value', [])
                if len(value_pair) >= 2:
                    value = float(value_pair[1])

                    # Save to both VM backup and file
                    # Remove xrpl_ prefix for cleaner metric names in backup
                    backup_name = metric_name.replace("xrpl_", "")
                    await self.save_state(backup_name, value)

            except Exception as e:
                logger.debug(f"Error backing up {metric_name}: {e}")
