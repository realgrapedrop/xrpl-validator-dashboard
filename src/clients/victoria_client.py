#!/usr/bin/env python3
"""
VictoriaMetrics Client for XRPL Monitor

Async HTTP client for writing metrics to VictoriaMetrics in Prometheus exposition format.
"""

import asyncio
import logging
from typing import Dict, List, Optional, Union
from datetime import datetime

import httpx


logger = logging.getLogger(__name__)


class MetricType:
    """Metric type constants"""
    GAUGE = "gauge"
    COUNTER = "counter"
    INFO = "info"


class Metric:
    """
    Represents a single metric to be written to VictoriaMetrics

    Attributes:
        name: Metric name (e.g., 'xrpl_ledger_sequence')
        value: Metric value (numeric for gauge/counter, always 1 for info)
        labels: Optional dict of label key-value pairs
        timestamp: Optional timestamp in milliseconds (defaults to current time)
        metric_type: Type of metric (gauge, counter, or info)
    """

    def __init__(
        self,
        name: str,
        value: Union[int, float],
        labels: Optional[Dict[str, str]] = None,
        timestamp: Optional[int] = None,
        metric_type: str = MetricType.GAUGE
    ):
        self.name = name
        self.value = value
        self.labels = labels or {}
        self.timestamp = timestamp or int(datetime.now().timestamp() * 1000)
        self.metric_type = metric_type

    def to_prometheus_format(self) -> str:
        """
        Convert metric to Prometheus exposition format

        Returns:
            String in format: metric_name{label="value"} value timestamp

        Examples:
            xrpl_ledger_sequence 93847123 1699564823000
            xrpl_validator_state_info{state="proposing"} 1 1699564823000
        """
        # Format labels if present
        if self.labels:
            labels_str = ",".join(f'{k}="{v}"' for k, v in self.labels.items())
            metric_line = f"{self.name}{{{labels_str}}} {self.value} {self.timestamp}"
        else:
            metric_line = f"{self.name} {self.value} {self.timestamp}"

        return metric_line

    def __repr__(self) -> str:
        return f"Metric(name={self.name}, value={self.value}, labels={self.labels})"


class VictoriaMetricsClient:
    """
    Async client for writing metrics to VictoriaMetrics

    VictoriaMetrics accepts Prometheus exposition format via HTTP import API.
    This client provides async batch writing with error handling and retries.

    Usage:
        client = VictoriaMetricsClient(url="http://localhost:8428")
        await client.start()

        metric = Metric(name="xrpl_ledger_sequence", value=93847123)
        await client.write_metric(metric)

        await client.close()
    """

    def __init__(
        self,
        url: str = "http://localhost:8428",
        timeout: float = 10.0,
        max_retries: int = 3,
        batch_size: int = 100
    ):
        """
        Initialize VictoriaMetrics client

        Args:
            url: VictoriaMetrics base URL (default: http://localhost:8428)
            timeout: HTTP request timeout in seconds (default: 10.0)
            max_retries: Maximum retry attempts on failures (default: 3)
            batch_size: Maximum metrics per batch write (default: 100)
        """
        self.url = url.rstrip('/')
        self.import_endpoint = f"{self.url}/api/v1/import/prometheus"
        self.timeout = timeout
        self.max_retries = max_retries
        self.batch_size = batch_size

        self._client: Optional[httpx.AsyncClient] = None
        self._batch: List[Metric] = []
        self._batch_lock = asyncio.Lock()

        logger.info(
            f"VictoriaMetrics client initialized: url={self.url}, "
            f"timeout={timeout}s, batch_size={batch_size}"
        )

    async def start(self):
        """Start the HTTP client session"""
        if self._client is None:
            self._client = httpx.AsyncClient(timeout=self.timeout)
            logger.info("VictoriaMetrics HTTP client started")

    async def close(self):
        """Close the HTTP client session and flush any pending metrics"""
        if self._batch:
            await self.flush()

        if self._client:
            await self._client.aclose()
            self._client = None
            logger.info("VictoriaMetrics HTTP client closed")

    async def __aenter__(self):
        """Async context manager entry"""
        await self.start()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit"""
        await self.close()

    async def health_check(self) -> bool:
        """
        Check if VictoriaMetrics is reachable

        Returns:
            True if VictoriaMetrics is healthy, False otherwise
        """
        if not self._client:
            await self.start()

        try:
            response = await self._client.get(f"{self.url}/health")
            is_healthy = response.status_code == 200

            if is_healthy:
                logger.debug("VictoriaMetrics health check: OK")
            else:
                logger.warning(f"VictoriaMetrics health check failed: {response.status_code}")

            return is_healthy

        except Exception as e:
            logger.error(f"VictoriaMetrics health check error: {e}")
            return False

    async def write_metric(self, metric: Metric, flush_immediately: bool = False):
        """
        Write a single metric to VictoriaMetrics

        Metrics are batched by default and written when batch_size is reached.
        Set flush_immediately=True to bypass batching.

        Args:
            metric: Metric instance to write
            flush_immediately: If True, write immediately without batching
        """
        async with self._batch_lock:
            self._batch.append(metric)

            if flush_immediately or len(self._batch) >= self.batch_size:
                await self._flush_batch()

    async def write_metrics(self, metrics: List[Metric], flush_immediately: bool = True):
        """
        Write multiple metrics to VictoriaMetrics

        Args:
            metrics: List of Metric instances to write
            flush_immediately: If True, write immediately (default: True for batch writes)
        """
        async with self._batch_lock:
            self._batch.extend(metrics)

            if flush_immediately or len(self._batch) >= self.batch_size:
                await self._flush_batch()

    async def flush(self):
        """Flush any pending metrics in the batch"""
        async with self._batch_lock:
            if self._batch:
                await self._flush_batch()

    async def _flush_batch(self):
        """
        Internal method to flush the current batch to VictoriaMetrics

        Must be called with _batch_lock held
        """
        if not self._batch:
            return

        if not self._client:
            await self.start()

        # Convert metrics to Prometheus format
        metrics_data = "\n".join(m.to_prometheus_format() for m in self._batch)
        batch_count = len(self._batch)

        # Attempt to write with retries
        for attempt in range(1, self.max_retries + 1):
            try:
                response = await self._client.post(
                    self.import_endpoint,
                    content=metrics_data,
                    headers={"Content-Type": "text/plain"}
                )

                if response.status_code in (200, 204):
                    logger.debug(f"Successfully wrote {batch_count} metrics to VictoriaMetrics")
                    self._batch.clear()
                    return
                else:
                    logger.warning(
                        f"VictoriaMetrics write failed (attempt {attempt}/{self.max_retries}): "
                        f"status={response.status_code}, body={response.text[:200]}"
                    )

            except httpx.TimeoutException:
                logger.warning(
                    f"VictoriaMetrics write timeout (attempt {attempt}/{self.max_retries})"
                )

            except Exception as e:
                logger.error(
                    f"VictoriaMetrics write error (attempt {attempt}/{self.max_retries}): {e}"
                )

            # Retry with exponential backoff
            if attempt < self.max_retries:
                await asyncio.sleep(2 ** attempt)

        # All retries failed
        logger.error(
            f"Failed to write {batch_count} metrics to VictoriaMetrics after "
            f"{self.max_retries} attempts. Metrics discarded."
        )
        self._batch.clear()

    async def query(self, query: str) -> Optional[Dict]:
        """
        Execute a PromQL query against VictoriaMetrics

        Args:
            query: PromQL query string

        Returns:
            JSON response dict or None on error

        Example:
            result = await client.query("xrpl_ledger_sequence")
        """
        if not self._client:
            await self.start()

        try:
            response = await self._client.get(
                f"{self.url}/api/v1/query",
                params={"query": query}
            )

            if response.status_code == 200:
                return response.json()
            else:
                logger.error(f"Query failed: {response.status_code} - {response.text}")
                return None

        except Exception as e:
            logger.error(f"Query error: {e}")
            return None

    async def query_range(
        self,
        query: str,
        start: int,
        end: int,
        step: str = "1m"
    ) -> Optional[Dict]:
        """
        Execute a PromQL range query against VictoriaMetrics

        Args:
            query: PromQL query string
            start: Start timestamp (Unix seconds)
            end: End timestamp (Unix seconds)
            step: Query resolution step (e.g., "1m", "5m", "1h")

        Returns:
            JSON response dict or None on error

        Example:
            # Get last 24h of validation events
            end_time = int(time.time())
            start_time = end_time - 86400
            result = await client.query_range(
                "xrpl_validation_event",
                start_time,
                end_time,
                "1m"
            )
        """
        if not self._client:
            await self.start()

        try:
            response = await self._client.get(
                f"{self.url}/api/v1/query_range",
                params={
                    "query": query,
                    "start": start,
                    "end": end,
                    "step": step
                }
            )

            if response.status_code == 200:
                return response.json()
            else:
                logger.error(
                    f"Range query failed: {response.status_code} - {response.text[:200]}"
                )
                return None

        except Exception as e:
            logger.error(f"Range query error: {e}")
            return None


# Convenience functions for creating common metric types

def create_gauge(
    name: str,
    value: Union[int, float],
    labels: Optional[Dict[str, str]] = None,
    timestamp: Optional[int] = None
) -> Metric:
    """Create a gauge metric"""
    return Metric(name, value, labels, timestamp, MetricType.GAUGE)


def create_counter(
    name: str,
    value: Union[int, float],
    labels: Optional[Dict[str, str]] = None,
    timestamp: Optional[int] = None
) -> Metric:
    """Create a counter metric"""
    return Metric(name, value, labels, timestamp, MetricType.COUNTER)


def create_info(
    name: str,
    labels: Dict[str, str],
    timestamp: Optional[int] = None
) -> Metric:
    """Create an info metric (value is always 1, data is in labels)"""
    return Metric(name, 1, labels, timestamp, MetricType.INFO)
