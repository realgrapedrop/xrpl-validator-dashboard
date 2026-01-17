#!/usr/bin/env python3
"""
Real-time State and Peers Exporter for rippled

Polls rippled HTTP API for:
- Server state every 2 seconds
- Peer metrics every 5 seconds

Exposes both /metrics and /api/v1/query endpoints for Grafana.

Purpose: Provide instant state and peer updates for Grafana dashboard (2-5s latency)
bypassing VictoriaMetrics storage lag (20-30s latency).

Key feature: Implements minimal Prometheus query API so Grafana can query
directly without going through VictoriaMetrics.
"""
import os
import asyncio
import logging
import time
import json
import re
from datetime import datetime, timezone
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import threading
import httpx

# Configuration
HTTP_URL = os.getenv("XRPL_HTTP_URL", "http://localhost:5005")
POLL_INTERVAL = float(os.getenv("POLL_INTERVAL", "2"))
PEERS_POLL_INTERVAL = float(os.getenv("PEERS_POLL_INTERVAL", "5"))
EXPORTER_PORT = int(os.getenv("EXPORTER_PORT", "9103"))
INSTANCE = os.getenv("INSTANCE_LABEL", "validator")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

# Setup logging
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL.upper()),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# State value mapping (aligned with collector)
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

# Global state storage (updated by polling loop)
current_metrics = {
    'state_value': 0,
    'state_name': 'down',
    'timestamp': time.time(),
    # Server info metrics
    'build_version': '',
    'pubkey_validator': '',
    # Node mode (validator vs stock_node)
    'node_mode': 'unknown',
    # New real-time metrics (from server_info)
    'ledger_sequence': 0,
    'ledger_age': 0,
    'base_fee_xrp': 0,
    'reserve_base_xrp': 0,
    'reserve_inc_xrp': 0,
    'load_factor': 0,
    'validation_quorum': 0,
    # UNL expiry (days until validator list expires)
    'unl_expiry_days': 0,
    # Proposers (from consensus_info)
    'proposers': 0,
    # Peer metrics
    'peer_count': 0,
    'peers_inbound': 0,
    'peers_outbound': 0,
    'peers_insane': 0,
    'peer_latency_p90': 0,
    'peers_timestamp': time.time()
}
metrics_lock = threading.Lock()


class MetricsHandler(BaseHTTPRequestHandler):
    """HTTP handler for /metrics and /api/v1/query endpoints"""

    def log_message(self, format, *args):
        """Suppress default HTTP logging (too noisy)"""
        pass

    def do_GET(self):
        """Handle GET requests"""
        parsed = urlparse(self.path)

        if parsed.path == '/metrics':
            self.serve_metrics()
        elif parsed.path == '/api/v1/query':
            self.serve_query(parsed)
        elif parsed.path == '/health' or parsed.path == '/':
            self.serve_health()
        else:
            self.send_error(404, "Not Found")

    def do_POST(self):
        """Handle POST requests (Grafana sometimes uses POST for queries)"""
        parsed = urlparse(self.path)

        if parsed.path == '/api/v1/query':
            # Read POST body for query parameter
            content_length = int(self.headers.get('Content-Length', 0))
            post_body = self.rfile.read(content_length).decode('utf-8')
            # Parse form data
            params = parse_qs(post_body)
            self.serve_query(parsed, post_params=params)
        else:
            self.send_error(404, "Not Found")

    def serve_health(self):
        """Serve health check endpoint"""
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'OK')

    def serve_metrics(self):
        """Serve Prometheus exposition format metrics"""
        with metrics_lock:
            state_value = current_metrics['state_value']
            state_name = current_metrics['state_name']
            build_version = current_metrics['build_version']
            pubkey_validator = current_metrics['pubkey_validator']
            # New real-time metrics
            ledger_sequence = current_metrics['ledger_sequence']
            ledger_age = current_metrics['ledger_age']
            base_fee_xrp = current_metrics['base_fee_xrp']
            reserve_base_xrp = current_metrics['reserve_base_xrp']
            reserve_inc_xrp = current_metrics['reserve_inc_xrp']
            load_factor = current_metrics['load_factor']
            validation_quorum = current_metrics['validation_quorum']
            unl_expiry_days = current_metrics['unl_expiry_days']
            proposers = current_metrics['proposers']
            # Peer metrics
            peer_count = current_metrics['peer_count']
            peers_inbound = current_metrics['peers_inbound']
            peers_outbound = current_metrics['peers_outbound']
            peers_insane = current_metrics['peers_insane']
            peer_latency_p90 = current_metrics['peer_latency_p90']

        lines = []

        # === State metrics ===
        # xrpl_state_realtime_value
        lines.append('# HELP xrpl_state_realtime_value Real-time validator state as numeric value (0-7)')
        lines.append('# TYPE xrpl_state_realtime_value gauge')
        lines.append(f'xrpl_state_realtime_value{{instance="{INSTANCE}"}} {state_value}')

        # xrpl_state_realtime (one line per state)
        lines.append('# HELP xrpl_state_realtime Real-time validator state (1=current state, 0=other states)')
        lines.append('# TYPE xrpl_state_realtime gauge')
        for name in STATE_VALUES.keys():
            value = 1 if name == state_name else 0
            lines.append(f'xrpl_state_realtime{{instance="{INSTANCE}",state="{name}"}} {value}')

        # === Server info metrics ===
        # xrpl_build_version_realtime
        if build_version:
            lines.append('# HELP xrpl_build_version_realtime Real-time rippled build version (1=current)')
            lines.append('# TYPE xrpl_build_version_realtime gauge')
            lines.append(f'xrpl_build_version_realtime{{instance="{INSTANCE}",version="{build_version}"}} 1')

        # xrpl_pubkey_realtime
        if pubkey_validator:
            lines.append('# HELP xrpl_pubkey_realtime Real-time validator public key (1=current)')
            lines.append('# TYPE xrpl_pubkey_realtime gauge')
            lines.append(f'xrpl_pubkey_realtime{{instance="{INSTANCE}",pubkey="{pubkey_validator}"}} 1')

        # xrpl_node_mode_realtime (validator vs stock_node)
        with metrics_lock:
            node_mode = current_metrics['node_mode']
        lines.append('# HELP xrpl_node_mode_realtime Node mode indicator (1=current mode)')
        lines.append('# TYPE xrpl_node_mode_realtime gauge')
        for mode in ['validator', 'stock_node', 'unknown']:
            value = 1 if mode == node_mode else 0
            lines.append(f'xrpl_node_mode_realtime{{instance="{INSTANCE}",mode="{mode}"}} {value}')

        # === New real-time metrics ===
        # xrpl_ledger_sequence_realtime
        lines.append('# HELP xrpl_ledger_sequence_realtime Real-time validated ledger sequence')
        lines.append('# TYPE xrpl_ledger_sequence_realtime gauge')
        lines.append(f'xrpl_ledger_sequence_realtime{{instance="{INSTANCE}"}} {ledger_sequence}')

        # xrpl_ledger_age_realtime
        lines.append('# HELP xrpl_ledger_age_realtime Real-time validated ledger age in seconds')
        lines.append('# TYPE xrpl_ledger_age_realtime gauge')
        lines.append(f'xrpl_ledger_age_realtime{{instance="{INSTANCE}"}} {ledger_age}')

        # xrpl_base_fee_xrp_realtime
        lines.append('# HELP xrpl_base_fee_xrp_realtime Real-time base transaction fee in XRP')
        lines.append('# TYPE xrpl_base_fee_xrp_realtime gauge')
        lines.append(f'xrpl_base_fee_xrp_realtime{{instance="{INSTANCE}"}} {base_fee_xrp}')

        # xrpl_reserve_base_xrp_realtime
        lines.append('# HELP xrpl_reserve_base_xrp_realtime Real-time base reserve in XRP')
        lines.append('# TYPE xrpl_reserve_base_xrp_realtime gauge')
        lines.append(f'xrpl_reserve_base_xrp_realtime{{instance="{INSTANCE}"}} {reserve_base_xrp}')

        # xrpl_reserve_inc_xrp_realtime
        lines.append('# HELP xrpl_reserve_inc_xrp_realtime Real-time reserve increment in XRP')
        lines.append('# TYPE xrpl_reserve_inc_xrp_realtime gauge')
        lines.append(f'xrpl_reserve_inc_xrp_realtime{{instance="{INSTANCE}"}} {reserve_inc_xrp}')

        # xrpl_load_factor_realtime
        lines.append('# HELP xrpl_load_factor_realtime Real-time server load factor')
        lines.append('# TYPE xrpl_load_factor_realtime gauge')
        lines.append(f'xrpl_load_factor_realtime{{instance="{INSTANCE}"}} {load_factor}')

        # xrpl_validation_quorum_realtime
        lines.append('# HELP xrpl_validation_quorum_realtime Real-time validation quorum')
        lines.append('# TYPE xrpl_validation_quorum_realtime gauge')
        lines.append(f'xrpl_validation_quorum_realtime{{instance="{INSTANCE}"}} {validation_quorum}')

        # xrpl_proposers_realtime
        lines.append('# HELP xrpl_proposers_realtime Real-time number of proposers in consensus')
        lines.append('# TYPE xrpl_proposers_realtime gauge')
        lines.append(f'xrpl_proposers_realtime{{instance="{INSTANCE}"}} {proposers}')

        # xrpl_unl_expiry_days_realtime
        lines.append('# HELP xrpl_unl_expiry_days_realtime Days until Validator List (UNL) expires')
        lines.append('# TYPE xrpl_unl_expiry_days_realtime gauge')
        lines.append(f'xrpl_unl_expiry_days_realtime{{instance="{INSTANCE}"}} {unl_expiry_days}')

        # === Peer metrics ===
        # xrpl_peer_count_realtime
        lines.append('# HELP xrpl_peer_count_realtime Real-time total peer count')
        lines.append('# TYPE xrpl_peer_count_realtime gauge')
        lines.append(f'xrpl_peer_count_realtime{{instance="{INSTANCE}"}} {peer_count}')

        # xrpl_peers_inbound_realtime
        lines.append('# HELP xrpl_peers_inbound_realtime Real-time inbound peer count')
        lines.append('# TYPE xrpl_peers_inbound_realtime gauge')
        lines.append(f'xrpl_peers_inbound_realtime{{instance="{INSTANCE}"}} {peers_inbound}')

        # xrpl_peers_outbound_realtime
        lines.append('# HELP xrpl_peers_outbound_realtime Real-time outbound peer count')
        lines.append('# TYPE xrpl_peers_outbound_realtime gauge')
        lines.append(f'xrpl_peers_outbound_realtime{{instance="{INSTANCE}"}} {peers_outbound}')

        # xrpl_peers_insane_realtime
        lines.append('# HELP xrpl_peers_insane_realtime Real-time insane peer count')
        lines.append('# TYPE xrpl_peers_insane_realtime gauge')
        lines.append(f'xrpl_peers_insane_realtime{{instance="{INSTANCE}"}} {peers_insane}')

        # xrpl_peer_latency_p90_realtime
        lines.append('# HELP xrpl_peer_latency_p90_realtime Real-time P90 peer latency in milliseconds')
        lines.append('# TYPE xrpl_peer_latency_p90_realtime gauge')
        lines.append(f'xrpl_peer_latency_p90_realtime{{instance="{INSTANCE}"}} {peer_latency_p90}')

        content = '\n'.join(lines) + '\n'

        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.end_headers()
        self.wfile.write(content.encode('utf-8'))

    def serve_query(self, parsed, post_params=None):
        """Serve Prometheus query API response"""
        # Get query from URL params or POST body
        if post_params:
            query = post_params.get('query', [''])[0]
        else:
            params = parse_qs(parsed.query)
            query = params.get('query', [''])[0]

        with metrics_lock:
            state_value = current_metrics['state_value']
            state_name = current_metrics['state_name']
            timestamp = current_metrics['timestamp']
            build_version = current_metrics['build_version']
            pubkey_validator = current_metrics['pubkey_validator']
            # New real-time metrics
            ledger_sequence = current_metrics['ledger_sequence']
            ledger_age = current_metrics['ledger_age']
            base_fee_xrp = current_metrics['base_fee_xrp']
            reserve_base_xrp = current_metrics['reserve_base_xrp']
            reserve_inc_xrp = current_metrics['reserve_inc_xrp']
            load_factor = current_metrics['load_factor']
            validation_quorum = current_metrics['validation_quorum']
            unl_expiry_days = current_metrics['unl_expiry_days']
            proposers = current_metrics['proposers']
            # Peer metrics
            peer_count = current_metrics['peer_count']
            peers_inbound = current_metrics['peers_inbound']
            peers_outbound = current_metrics['peers_outbound']
            peers_insane = current_metrics['peers_insane']
            peer_latency_p90 = current_metrics['peer_latency_p90']
            peers_timestamp = current_metrics['peers_timestamp']

        # Handle different queries
        result = []

        if 'xrpl_state_realtime_value' in query:
            # Return numeric state value
            result.append({
                "metric": {
                    "__name__": "xrpl_state_realtime_value",
                    "instance": INSTANCE
                },
                "value": [timestamp, str(state_value)]
            })
        elif 'xrpl_state_realtime' in query:
            # Check if query filters by state label
            state_filter = None
            match = re.search(r'state\s*=\s*["\']?(\w+)["\']?', query)
            if match:
                state_filter = match.group(1)

            for name in STATE_VALUES.keys():
                if state_filter and name != state_filter:
                    continue
                value = 1 if name == state_name else 0
                result.append({
                    "metric": {
                        "__name__": "xrpl_state_realtime",
                        "instance": INSTANCE,
                        "state": name
                    },
                    "value": [timestamp, str(value)]
                })
        elif 'xrpl_peer_count_realtime' in query:
            result.append({
                "metric": {
                    "__name__": "xrpl_peer_count_realtime",
                    "instance": INSTANCE
                },
                "value": [peers_timestamp, str(peer_count)]
            })
        elif 'xrpl_peers_inbound_realtime' in query:
            result.append({
                "metric": {
                    "__name__": "xrpl_peers_inbound_realtime",
                    "instance": INSTANCE
                },
                "value": [peers_timestamp, str(peers_inbound)]
            })
        elif 'xrpl_peers_outbound_realtime' in query:
            result.append({
                "metric": {
                    "__name__": "xrpl_peers_outbound_realtime",
                    "instance": INSTANCE
                },
                "value": [peers_timestamp, str(peers_outbound)]
            })
        elif 'xrpl_peers_insane_realtime' in query:
            result.append({
                "metric": {
                    "__name__": "xrpl_peers_insane_realtime",
                    "instance": INSTANCE
                },
                "value": [peers_timestamp, str(peers_insane)]
            })
        elif 'xrpl_peer_latency_p90_realtime' in query:
            result.append({
                "metric": {
                    "__name__": "xrpl_peer_latency_p90_realtime",
                    "instance": INSTANCE
                },
                "value": [peers_timestamp, str(peer_latency_p90)]
            })
        elif 'xrpl_build_version_realtime' in query:
            if build_version:
                result.append({
                    "metric": {
                        "__name__": "xrpl_build_version_realtime",
                        "instance": INSTANCE,
                        "version": build_version
                    },
                    "value": [timestamp, "1"]
                })
        elif 'xrpl_pubkey_realtime' in query:
            if pubkey_validator:
                result.append({
                    "metric": {
                        "__name__": "xrpl_pubkey_realtime",
                        "instance": INSTANCE,
                        "pubkey": pubkey_validator
                    },
                    "value": [timestamp, "1"]
                })
        elif 'xrpl_node_mode_realtime' in query:
            # Check if query filters by mode label
            mode_filter = None
            match = re.search(r'mode\s*=\s*["\']?(\w+)["\']?', query)
            if match:
                mode_filter = match.group(1)

            with metrics_lock:
                node_mode = current_metrics['node_mode']

            for mode in ['validator', 'stock_node', 'unknown']:
                if mode_filter and mode != mode_filter:
                    continue
                value = 1 if mode == node_mode else 0
                result.append({
                    "metric": {
                        "__name__": "xrpl_node_mode_realtime",
                        "instance": INSTANCE,
                        "mode": mode
                    },
                    "value": [timestamp, str(value)]
                })
        # === New real-time metrics ===
        elif 'xrpl_ledger_sequence_realtime' in query:
            result.append({
                "metric": {
                    "__name__": "xrpl_ledger_sequence_realtime",
                    "instance": INSTANCE
                },
                "value": [timestamp, str(ledger_sequence)]
            })
        elif 'xrpl_ledger_age_realtime' in query:
            result.append({
                "metric": {
                    "__name__": "xrpl_ledger_age_realtime",
                    "instance": INSTANCE
                },
                "value": [timestamp, str(ledger_age)]
            })
        elif 'xrpl_base_fee_xrp_realtime' in query:
            result.append({
                "metric": {
                    "__name__": "xrpl_base_fee_xrp_realtime",
                    "instance": INSTANCE
                },
                "value": [timestamp, str(base_fee_xrp)]
            })
        elif 'xrpl_reserve_base_xrp_realtime' in query:
            result.append({
                "metric": {
                    "__name__": "xrpl_reserve_base_xrp_realtime",
                    "instance": INSTANCE
                },
                "value": [timestamp, str(reserve_base_xrp)]
            })
        elif 'xrpl_reserve_inc_xrp_realtime' in query:
            result.append({
                "metric": {
                    "__name__": "xrpl_reserve_inc_xrp_realtime",
                    "instance": INSTANCE
                },
                "value": [timestamp, str(reserve_inc_xrp)]
            })
        elif 'xrpl_load_factor_realtime' in query:
            result.append({
                "metric": {
                    "__name__": "xrpl_load_factor_realtime",
                    "instance": INSTANCE
                },
                "value": [timestamp, str(load_factor)]
            })
        elif 'xrpl_validation_quorum_realtime' in query:
            result.append({
                "metric": {
                    "__name__": "xrpl_validation_quorum_realtime",
                    "instance": INSTANCE
                },
                "value": [timestamp, str(validation_quorum)]
            })
        elif 'xrpl_proposers_realtime' in query:
            result.append({
                "metric": {
                    "__name__": "xrpl_proposers_realtime",
                    "instance": INSTANCE
                },
                "value": [timestamp, str(proposers)]
            })
        elif 'xrpl_unl_expiry_days_realtime' in query:
            result.append({
                "metric": {
                    "__name__": "xrpl_unl_expiry_days_realtime",
                    "instance": INSTANCE
                },
                "value": [timestamp, str(unl_expiry_days)]
            })
        else:
            # Unknown metric - return empty result
            pass

        response = {
            "status": "success",
            "data": {
                "resultType": "vector",
                "result": result
            }
        }

        content = json.dumps(response)

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(content.encode('utf-8'))


async def fetch_server_state(client: httpx.AsyncClient) -> dict:
    """
    Fetch server_info from rippled HTTP API

    Returns:
        dict with keys: server_state, state_value, build_version, pubkey_validator,
        ledger_sequence, ledger_age, base_fee_xrp, reserve_base_xrp, reserve_inc_xrp,
        load_factor, validation_quorum
        Returns 'down' state if rippled is not responding or returns null
    """
    default_result = {
        'server_state': 'down',
        'state_value': 0,
        'build_version': '',
        'pubkey_validator': '',
        'ledger_sequence': 0,
        'ledger_age': 0,
        'base_fee_xrp': 0,
        'reserve_base_xrp': 0,
        'reserve_inc_xrp': 0,
        'load_factor': 0,
        'validation_quorum': 0,
        'unl_expiry_days': 0
    }

    try:
        response = await client.post(
            HTTP_URL,
            json={"method": "server_info", "params": [{}]},
            timeout=5.0
        )

        if response.status_code == 200:
            data = response.json()

            if 'result' in data and 'info' in data['result']:
                info = data['result']['info']
                server_state = info.get('server_state')

                # Handle null or missing server_state as DOWN
                if not server_state or server_state == 'null':
                    logger.debug("rippled returned null server_state (still starting up)")
                    return default_result

                server_state = server_state.lower()
                state_value = STATE_VALUES.get(server_state, 0)

                # Extract build_version and pubkey_validator
                build_version = info.get('build_version', '')
                pubkey_validator = info.get('pubkey_validator', '')

                # Extract load_factor and validation_quorum
                load_factor = info.get('load_factor', 0)
                validation_quorum = info.get('validation_quorum', 0)

                # Extract validated_ledger info
                validated_ledger = info.get('validated_ledger', {})
                ledger_sequence = validated_ledger.get('seq', 0)
                ledger_age = validated_ledger.get('age', 0)
                base_fee_xrp = validated_ledger.get('base_fee_xrp', 0)
                reserve_base_xrp = validated_ledger.get('reserve_base_xrp', 0)
                reserve_inc_xrp = validated_ledger.get('reserve_inc_xrp', 0)

                # Extract UNL (validator list) expiration
                unl_expiry_days = 0
                validator_list = info.get('validator_list', {})
                expiration_str = validator_list.get('expiration', '')
                if expiration_str:
                    try:
                        # Format: "2026-Mar-11 15:55:38.000000000 UTC"
                        # Parse the date part (ignore nanoseconds)
                        exp_clean = expiration_str.split('.')[0]  # Remove nanoseconds
                        exp_date = datetime.strptime(exp_clean, "%Y-%b-%d %H:%M:%S")
                        exp_date = exp_date.replace(tzinfo=timezone.utc)
                        now = datetime.now(timezone.utc)
                        delta = exp_date - now
                        unl_expiry_days = max(0, delta.days)
                    except Exception as e:
                        logger.debug(f"Error parsing validator_list expiration: {e}")

                return {
                    'server_state': server_state,
                    'state_value': state_value,
                    'build_version': build_version,
                    'pubkey_validator': pubkey_validator,
                    'ledger_sequence': ledger_sequence,
                    'ledger_age': ledger_age,
                    'base_fee_xrp': base_fee_xrp,
                    'reserve_base_xrp': reserve_base_xrp,
                    'reserve_inc_xrp': reserve_inc_xrp,
                    'load_factor': load_factor,
                    'validation_quorum': validation_quorum,
                    'unl_expiry_days': unl_expiry_days
                }
            else:
                logger.warning(f"Unexpected response format: {data}")
                return default_result
        else:
            logger.error(f"HTTP {response.status_code}: {response.text}")
            return default_result

    except httpx.ConnectError:
        logger.debug("rippled not reachable (connection refused)")
        return default_result
    except httpx.TimeoutException:
        logger.warning("rippled HTTP timeout")
        return default_result
    except Exception as e:
        logger.error(f"Error fetching server_info: {e}", exc_info=True)
        return default_result


async def fetch_peers(client: httpx.AsyncClient) -> dict:
    """
    Fetch peers from rippled HTTP API

    Returns:
        dict with keys: peer_count, peers_inbound, peers_outbound, peers_insane, peer_latency_p90
        Returns zeros if rippled is not responding
    """
    try:
        response = await client.post(
            HTTP_URL,
            json={"method": "peers", "params": [{}]},
            timeout=5.0
        )

        if response.status_code == 200:
            data = response.json()

            if 'result' in data and 'peers' in data['result']:
                peers = data['result']['peers']

                peer_count = len(peers)
                peers_inbound = sum(1 for p in peers if p.get('inbound') is True)
                # Outbound peers don't have 'inbound' field (it's missing, not False)
                peers_outbound = peer_count - peers_inbound

                # Insane peers: sanity field exists and is not 'sane'
                peers_insane = sum(1 for p in peers if p.get('sanity') and p.get('sanity') != 'sane')

                # Calculate P90 latency
                latencies = [p.get('latency', 0) for p in peers if 'latency' in p]
                if latencies:
                    sorted_lat = sorted(latencies)
                    p90_idx = int(len(latencies) * 0.9)
                    peer_latency_p90 = sorted_lat[min(p90_idx, len(sorted_lat) - 1)]
                else:
                    peer_latency_p90 = 0

                return {
                    'peer_count': peer_count,
                    'peers_inbound': peers_inbound,
                    'peers_outbound': peers_outbound,
                    'peers_insane': peers_insane,
                    'peer_latency_p90': peer_latency_p90
                }
            else:
                # No peers or unexpected format
                return {
                    'peer_count': 0,
                    'peers_inbound': 0,
                    'peers_outbound': 0,
                    'peers_insane': 0,
                    'peer_latency_p90': 0
                }
        else:
            logger.error(f"Peers HTTP {response.status_code}: {response.text}")
            return None

    except httpx.ConnectError:
        logger.debug("rippled not reachable for peers (connection refused)")
        return None
    except httpx.TimeoutException:
        logger.warning("rippled peers HTTP timeout")
        return None
    except Exception as e:
        logger.error(f"Error fetching peers: {e}", exc_info=True)
        return None


async def fetch_consensus_info(client: httpx.AsyncClient) -> dict:
    """
    Fetch consensus_info from rippled HTTP API for proposers count

    Returns:
        dict with key: proposers
        Returns None if rippled is not responding
    """
    try:
        response = await client.post(
            HTTP_URL,
            json={"method": "consensus_info", "params": [{}]},
            timeout=5.0
        )

        if response.status_code == 200:
            data = response.json()

            if 'result' in data and 'info' in data['result']:
                info = data['result']['info']
                proposers = info.get('proposers', 0)
                return {'proposers': proposers}
            else:
                return {'proposers': 0}
        else:
            logger.error(f"consensus_info HTTP {response.status_code}: {response.text}")
            return None

    except httpx.ConnectError:
        logger.debug("rippled not reachable for consensus_info (connection refused)")
        return None
    except httpx.TimeoutException:
        logger.warning("rippled consensus_info HTTP timeout")
        return None
    except Exception as e:
        logger.error(f"Error fetching consensus_info: {e}", exc_info=True)
        return None


# Track last state for change detection
last_state = None
last_peer_count = None


async def run_state_polling_loop(client: httpx.AsyncClient):
    """Poll rippled for state every POLL_INTERVAL seconds"""
    global last_state, current_metrics

    logger.info(f"Starting state polling loop: {HTTP_URL} every {POLL_INTERVAL}s")

    while True:
        try:
            # Fetch server_info and consensus_info concurrently
            server_result, consensus_result = await asyncio.gather(
                fetch_server_state(client),
                fetch_consensus_info(client)
            )

            if server_result:
                server_state = server_result['server_state']
                state_value = server_result['state_value']
                build_version = server_result.get('build_version', '')
                pubkey_validator = server_result.get('pubkey_validator', '')

                # New metrics from server_info
                ledger_sequence = server_result.get('ledger_sequence', 0)
                ledger_age = server_result.get('ledger_age', 0)
                base_fee_xrp = server_result.get('base_fee_xrp', 0)
                reserve_base_xrp = server_result.get('reserve_base_xrp', 0)
                reserve_inc_xrp = server_result.get('reserve_inc_xrp', 0)
                load_factor = server_result.get('load_factor', 0)
                validation_quorum = server_result.get('validation_quorum', 0)
                unl_expiry_days = server_result.get('unl_expiry_days', 0)

                # Proposers from consensus_info
                proposers = consensus_result.get('proposers', 0) if consensus_result else 0

                # Determine node mode based on pubkey_validator
                # rippled returns "none" for stock nodes, or the actual key for validators
                if not pubkey_validator or pubkey_validator.lower() == 'none':
                    node_mode = 'stock_node'
                else:
                    node_mode = 'validator'

                # Update global metrics (thread-safe)
                with metrics_lock:
                    current_metrics['state_value'] = state_value
                    current_metrics['state_name'] = server_state
                    current_metrics['build_version'] = build_version
                    current_metrics['pubkey_validator'] = pubkey_validator
                    current_metrics['node_mode'] = node_mode
                    # New metrics
                    current_metrics['ledger_sequence'] = ledger_sequence
                    current_metrics['ledger_age'] = ledger_age
                    current_metrics['base_fee_xrp'] = base_fee_xrp
                    current_metrics['reserve_base_xrp'] = reserve_base_xrp
                    current_metrics['reserve_inc_xrp'] = reserve_inc_xrp
                    current_metrics['load_factor'] = load_factor
                    current_metrics['validation_quorum'] = validation_quorum
                    current_metrics['unl_expiry_days'] = unl_expiry_days
                    current_metrics['proposers'] = proposers
                    current_metrics['timestamp'] = time.time()

                # Log state changes
                if last_state != server_state:
                    if last_state is not None:
                        logger.info(f"State changed: {last_state} → {server_state} (value={state_value})")
                    else:
                        logger.info(f"Initial state: {server_state} (value={state_value})")
                    last_state = server_state

            await asyncio.sleep(POLL_INTERVAL)

        except Exception as e:
            logger.error(f"Error in state polling loop: {e}", exc_info=True)
            await asyncio.sleep(POLL_INTERVAL)


async def run_peers_polling_loop(client: httpx.AsyncClient):
    """Poll rippled for peers every PEERS_POLL_INTERVAL seconds"""
    global last_peer_count, current_metrics

    logger.info(f"Starting peers polling loop: {HTTP_URL} every {PEERS_POLL_INTERVAL}s")

    while True:
        try:
            result = await fetch_peers(client)

            if result:
                # Update global metrics (thread-safe)
                with metrics_lock:
                    current_metrics['peer_count'] = result['peer_count']
                    current_metrics['peers_inbound'] = result['peers_inbound']
                    current_metrics['peers_outbound'] = result['peers_outbound']
                    current_metrics['peers_insane'] = result['peers_insane']
                    current_metrics['peer_latency_p90'] = result['peer_latency_p90']
                    current_metrics['peers_timestamp'] = time.time()

                # Log peer count changes
                if last_peer_count != result['peer_count']:
                    if last_peer_count is not None:
                        logger.info(f"Peer count changed: {last_peer_count} → {result['peer_count']} "
                                    f"(in={result['peers_inbound']}, out={result['peers_outbound']})")
                    else:
                        logger.info(f"Initial peer count: {result['peer_count']} "
                                    f"(in={result['peers_inbound']}, out={result['peers_outbound']})")
                    last_peer_count = result['peer_count']

            await asyncio.sleep(PEERS_POLL_INTERVAL)

        except Exception as e:
            logger.error(f"Error in peers polling loop: {e}", exc_info=True)
            await asyncio.sleep(PEERS_POLL_INTERVAL)


async def run_polling_loops():
    """Run both state and peers polling loops concurrently"""
    async with httpx.AsyncClient() as client:
        await asyncio.gather(
            run_state_polling_loop(client),
            run_peers_polling_loop(client)
        )


def run_http_server():
    """Run the HTTP server in a separate thread"""
    server = HTTPServer(('0.0.0.0', EXPORTER_PORT), MetricsHandler)
    logger.info(f"HTTP server started on port {EXPORTER_PORT}")
    logger.info(f"Endpoints: /metrics, /api/v1/query, /health")
    server.serve_forever()


def main():
    """Start HTTP server and run polling loops"""
    try:
        # Start HTTP server in background thread
        server_thread = threading.Thread(target=run_http_server, daemon=True)
        server_thread.start()

        # Run polling loops in main thread
        asyncio.run(run_polling_loops())

    except KeyboardInterrupt:
        logger.info("Exporter stopped by user")
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        raise


if __name__ == "__main__":
    main()
