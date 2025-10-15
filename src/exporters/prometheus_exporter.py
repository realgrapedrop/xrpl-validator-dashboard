#!/usr/bin/env python3
"""
Prometheus Exporter for XRPL Monitor
Exposes validator metrics in Prometheus format
"""

from prometheus_client import start_http_server, Gauge, Counter, Info
import time


class PrometheusExporter:
    """
    Exports XRPL validator metrics to Prometheus
    """
    
    def __init__(self, port: int = 9091, host: str = '0.0.0.0'):
        """
        Initialize Prometheus exporter
        
        Args:
            port: Port to expose metrics on
            host: Host to bind to
        """
        self.port = port
        self.host = host
        
        # State metrics
        self.validator_state = Gauge('xrpl_validator_state_value', 'Validator state as numeric value')
        self.validator_state_info = Info('xrpl_validator_state', 'Current validator state')
        self.time_in_state = Gauge('xrpl_time_in_current_state_seconds', 'Time spent in current state (seconds)')
        self.server_state_duration = Gauge('xrpl_server_state_duration_seconds', 'Time in current state from server')
        
        # Ledger metrics
        self.ledger_sequence = Gauge('xrpl_ledger_sequence', 'Current validated ledger sequence')
        self.ledger_age = Gauge('xrpl_ledger_age_seconds', 'Age of last validated ledger')
        self.base_fee = Gauge('xrpl_base_fee_xrp', 'Network base transaction fee (XRP)')
        self.reserve_base = Gauge('xrpl_reserve_base_xrp', 'Base account reserve (XRP)')
        self.reserve_inc = Gauge('xrpl_reserve_inc_xrp', 'Owner reserve increment (XRP)')
        
        # Peer metrics
        self.peer_count = Gauge('xrpl_peer_count', 'Number of connected peers')
        self.peers_inbound = Gauge('xrpl_peers_inbound', 'Number of inbound peers')
        self.peers_outbound = Gauge('xrpl_peers_outbound', 'Number of outbound peers')
        self.peers_insane = Gauge('xrpl_peers_insane', 'Number of peers on wrong ledger')
        self.peer_latency_p90 = Gauge('xrpl_peer_latency_p90_ms', '90th percentile peer latency (ms)')
        self.peer_disconnects = Counter('xrpl_peer_disconnects_total', 'Total peer disconnections')
        self.peer_disconnects_resources = Counter('xrpl_peer_disconnects_resources_total', 'Disconnections due to resources')
        
        # Performance metrics
        self.load_factor = Gauge('xrpl_load_factor', 'Server load factor')
        self.io_latency = Gauge('xrpl_io_latency_ms', 'Disk I/O latency (ms)')
        self.converge_time = Gauge('xrpl_consensus_converge_time_seconds', 'Time to reach consensus (seconds)')
        self.jq_trans_overflow = Counter('xrpl_jq_trans_overflow_total', 'Transaction queue overflows')
        
        # Transaction metrics
        self.transaction_rate = Gauge('xrpl_transaction_rate', 'Transactions per second')
        
        # Validation metrics
        self.validation_quorum = Gauge('xrpl_validation_quorum', 'Validators needed for consensus')
        self.proposers = Gauge('xrpl_proposers', 'Proposers in last consensus round')
        self.validations_checked = Counter('xrpl_validations_checked_total', 'Total validations checked')
        self.validation_agreement_rate = Gauge('xrpl_validation_agreement_rate', 'Validation agreement rate (%)')
        self.validation_rate = Gauge('xrpl_validation_rate', 'Validation rate (%)')
        
        # Validation period stats
        self.validation_agreements_1h = Gauge('xrpl_validation_agreements_1h', 'Validations agreed in last 1h')
        self.validation_missed_1h = Gauge('xrpl_validation_missed_1h', 'Validations missed in last 1h')
        self.validation_agreements_24h = Gauge('xrpl_validation_agreements_24h', 'Validations agreed in last 24h')
        self.validation_missed_24h = Gauge('xrpl_validation_missed_24h', 'Validations missed in last 24h')
        self.validation_agreement_pct_1h = Gauge('xrpl_validation_agreement_pct_1h', 'Agreement percentage last 1h')
        self.validation_agreement_pct_24h = Gauge('xrpl_validation_agreement_pct_24h', 'Agreement percentage last 24h')
        
        # State accounting
        self.state_duration = Gauge('xrpl_state_accounting_duration_seconds', 'Time in each state', ['state'])
        self.state_transitions = Gauge('xrpl_state_accounting_transitions', 'Transitions to each state', ['state'])
        
        # System metrics
        self.uptime = Gauge('xrpl_validator_uptime_seconds', 'Validator uptime (seconds)')
        self.initial_sync_duration = Gauge('xrpl_initial_sync_duration_seconds', 'Initial sync duration (seconds)')
        self.monitor_uptime = Gauge('xrpl_monitor_uptime_seconds', 'Monitor uptime (seconds)')
        
        # Database size metrics
        self.ledger_db_size = Gauge('xrpl_ledger_db_bytes', 'Main ledger database size (bytes)')
        self.nudb_size = Gauge('xrpl_ledger_nudb_bytes', 'NuDB size (bytes)')
        
        # Counters
        self.state_changes = Counter('xrpl_state_changes_total', 'Total state changes')
        self.alerts_sent = Counter('xrpl_alerts_sent_total', 'Total alerts sent')
        self.api_errors = Counter('xrpl_api_errors_total', 'Total API errors')
        
        # Info metrics
        self.server_info = Info('xrpl_server', 'Server information')
        
        # Start time & state mapping
        self.start_time = time.time()
        self.state_values = {
            'unknown': 0, 'disconnected': 1, 'connected': 2, 'syncing': 3,
            'tracking': 4, 'full': 5, 'proposing': 6, 'unreachable': 7
        }
    
    def start(self):
        """Start the Prometheus HTTP server"""
        start_http_server(self.port, addr=self.host)
        print(f"Prometheus exporter listening on {self.host}:{self.port}")
    
    # State methods
    def update_state(self, state: str, time_in_state: float = 0):
        """Update validator state metrics"""
        state_value = self.state_values.get(state.lower(), 0)
        self.validator_state.set(state_value)
        self.validator_state_info.info({'state': state})
        self.time_in_state.set(time_in_state)
    
    # Ledger methods
    def update_ledger(self, ledger_seq: int):
        """Update ledger sequence"""
        self.ledger_sequence.set(ledger_seq)
    
    def update_ledger_details(self, age: int, base_fee: float, reserve_base: float, reserve_inc: float):
        """Update ledger details"""
        self.ledger_age.set(age)
        self.base_fee.set(base_fee)
        self.reserve_base.set(reserve_base)
        self.reserve_inc.set(reserve_inc)
    
    # Peer methods
    def update_peers(self, peers: int):
        """Update peer count"""
        self.peer_count.set(peers)
    
    def update_peer_details(self, inbound: int, outbound: int, insane: int, p90_latency: float):
        """Update detailed peer metrics"""
        self.peers_inbound.set(inbound)
        self.peers_outbound.set(outbound)
        self.peers_insane.set(insane)
        self.peer_latency_p90.set(p90_latency)
    
    def update_peer_disconnects(self, total: int, resources: int):
        """Update peer disconnect counters"""
        if not hasattr(self, '_last_peer_disconnects'):
            self._last_peer_disconnects = 0
            self._last_peer_disconnects_resources = 0
        
        total_inc = total - self._last_peer_disconnects
        resources_inc = resources - self._last_peer_disconnects_resources
        
        if total_inc > 0:
            self.peer_disconnects.inc(total_inc)
        if resources_inc > 0:
            self.peer_disconnects_resources.inc(resources_inc)
        
        self._last_peer_disconnects = total
        self._last_peer_disconnects_resources = resources
    
    # Performance methods
    def update_load_factor(self, load_factor: float):
        """Update load factor"""
        self.load_factor.set(load_factor)
    
    def update_performance(self, io_latency: int, converge_time: float):
        """Update performance metrics"""
        self.io_latency.set(io_latency)
        self.converge_time.set(converge_time)
    
    def update_jq_trans_overflow(self, count: int):
        """Update job queue overflow counter"""
        if not hasattr(self, '_last_jq_overflow'):
            self._last_jq_overflow = 0
        inc = count - self._last_jq_overflow
        if inc > 0:
            self.jq_trans_overflow.inc(inc)
        self._last_jq_overflow = count
    
    def update_transaction_rate(self, rate: float):
        """Update transaction rate"""
        self.transaction_rate.set(rate)
    
    # Validation methods
    def update_validation_quorum(self, quorum: int):
        """Update validation quorum"""
        self.validation_quorum.set(quorum)
    
    def update_proposers(self, proposers: int):
        """Update proposers count"""
        self.proposers.set(proposers)
    
    def increment_validations_checked(self):
        """Increment validations checked counter"""
        self.validations_checked.inc()
    
    def update_validation_stats(self, agreement_rate: float, validation_rate: float):
        """Update validation statistics"""
        self.validation_agreement_rate.set(agreement_rate)
        self.validation_rate.set(validation_rate)
    
    def update_validation_period_stats(self, stats_1h: dict, stats_24h: dict):
        """Update validation period statistics"""
        self.validation_agreements_1h.set(stats_1h.get('validated_count', 0))
        self.validation_missed_1h.set(stats_1h.get('missed_count', 0))
        self.validation_agreement_pct_1h.set(stats_1h.get('agreement_rate', 0))
        
        self.validation_agreements_24h.set(stats_24h.get('validated_count', 0))
        self.validation_missed_24h.set(stats_24h.get('missed_count', 0))
        self.validation_agreement_pct_24h.set(stats_24h.get('agreement_rate', 0))
    
    # State accounting
    def update_state_accounting(self, state_accounting: dict):
        """Update state accounting metrics"""
        for state_name, state_data in state_accounting.items():
            duration_us = int(state_data.get('duration_us', 0))
            duration_s = duration_us / 1_000_000
            self.state_duration.labels(state=state_name).set(duration_s)
            
            transitions = int(state_data.get('transitions', 0))
            self.state_transitions.labels(state=state_name).set(transitions)
    
    # System methods
    def update_system_metrics(self, uptime: int, initial_sync_us: int, server_state_duration_us: int):
        """Update system metrics"""
        self.uptime.set(uptime)
        self.initial_sync_duration.set(initial_sync_us / 1_000_000)
        self.server_state_duration.set(server_state_duration_us / 1_000_000)
    
    def update_database_sizes(self, ledger_db: int, nudb: int):
        """Update database size metrics"""
        self.ledger_db_size.set(ledger_db)
        self.nudb_size.set(nudb)
    
    def update_server_info(self, build_version: str, node_size: str, pubkey_validator: str, complete_ledgers: str):
        """Update server info metadata"""
        self.server_info.info({
            'build_version': build_version,
            'node_size': node_size,
            'pubkey_validator': pubkey_validator,
            'complete_ledgers': complete_ledgers
        })
    
    # Counter methods
    def increment_state_changes(self):
        """Increment state changes counter"""
        self.state_changes.inc()
    
    def increment_alerts_sent(self):
        """Increment alerts sent counter"""
        self.alerts_sent.inc()
    
    def increment_api_errors(self):
        """Increment API errors counter"""
        self.api_errors.inc()
    
    # Uptime methods
    def update_monitor_uptime(self):
        """Update monitor uptime"""
        uptime = time.time() - self.start_time
        self.monitor_uptime.set(uptime)
    
    def update_uptime(self):
        """Alias for update_monitor_uptime()"""
        self.update_monitor_uptime()
