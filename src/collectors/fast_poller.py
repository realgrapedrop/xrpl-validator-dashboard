# Path templating applied - INSTALL_DIR will be set during installation
#!/usr/bin/env python3
"""
Fast Poller - Monitors validator with Prometheus metrics export
Supports both Docker and native rippled deployments
"""

import sys
import os
import time
from datetime import datetime

# Add project root to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from src.utils.rippled_api import RippledAPI, RippledAPIError
from src.storage.database import Database
from src.collectors.validation_tracker import ValidationTracker
from src.alerts.alerter import Alerter
from src.exporters.prometheus_exporter import PrometheusExporter
from src.utils.config import Config


class FastPoller:
    """
    Polls validator with full tracking and Prometheus export
    """
    
    def __init__(self, api: RippledAPI, db: Database, alerter: Alerter, 
                 prometheus: PrometheusExporter = None, interval: int = 3):
        """
        Initialize fast poller
        """
        self.api = api
        self.db = db
        self.alerter = alerter
        self.prometheus = prometheus
        self.interval = interval
        
        # State tracking
        self.last_state = None
        self.state_entered_at = None
        self.last_ledger_seq = None
        self.last_ledger_time = None
        self.last_ledger_txn_count = None
        
        # Validation tracker
        self.validation_tracker = ValidationTracker(api, db)
        
        # Track ledgers checked
        self.checked_ledgers = set()
        
        # Error tracking
        self.consecutive_errors = 0
        self.max_errors_before_alert = 2
        
        # Statistics
        self.poll_count = 0
        self.state_changes = 0
        self.validations_checked = 0
        self.alerts_sent = 0
        self.api_errors = 0
        
        # Update server info once at startup
        if self.prometheus:
            self._update_server_info()
    
    def _update_server_info(self):
        """Update static server info metrics once"""
        try:
            state_info = self.api.get_server_state()
            self.prometheus.update_server_info(
                build_version=state_info.get('build_version', 'unknown'),
                node_size=state_info.get('node_size', 'unknown'),
                pubkey_validator=state_info.get('pubkey_validator', 'unknown'),
                complete_ledgers=state_info.get('complete_ledgers', 'unknown')
            )
        except Exception as e:
            print(f"Warning: Could not update server info: {e}")
    
    def poll(self):
        """Poll validator once and update all metrics"""
        try:
            state_info = self.api.get_server_state()
            
            # Reset error counter on success
            self.consecutive_errors = 0
            
            # Extract basic metrics with type safety
            current_state = state_info.get('server_state', 'unknown')
            current_seq = int(state_info.get('validated_ledger', {}).get('seq', 0))
            peers = int(state_info.get('peers', 0))
            load_factor = float(state_info.get('load_factor', 0))
            
            # Extract validation metrics
            validation_quorum = int(state_info.get('validation_quorum', 0))
            proposers = int(state_info.get('last_close', {}).get('proposers', 0))
            
            # Extract performance metrics
            io_latency = int(state_info.get('io_latency_ms', 0))
            converge_time = float(state_info.get('last_close', {}).get('converge_time_s', 0))
            jq_trans_overflow = int(state_info.get('jq_trans_overflow', 0))
            
            # Extract peer metrics
            peer_disconnects = int(state_info.get('peer_disconnects', 0))
            peer_disconnects_resources = int(state_info.get('peer_disconnects_resources', 0))
            
            # Extract system metrics
            uptime = int(state_info.get('uptime', 0))
            initial_sync_us = int(state_info.get('initial_sync_duration_us', 0))
            server_state_duration_us = int(state_info.get('server_state_duration_us', 0))
            
            # Extract validated ledger details
            validated_ledger = state_info.get('validated_ledger', {})
            ledger_age = int(validated_ledger.get('age', 0))
            base_fee = float(validated_ledger.get('base_fee_xrp', 0))
            reserve_base = float(validated_ledger.get('reserve_base_xrp', 0))
            reserve_inc = float(validated_ledger.get('reserve_inc_xrp', 0))
            
            # Extract state accounting
            state_accounting = state_info.get('state_accounting', {})
            
            # Get detailed peer information (every 10 polls to reduce overhead)
            peer_details = {'inbound': 0, 'outbound': 0, 'insane': 0, 'p90_latency': 0}
            if self.poll_count % 10 == 0:
                try:
                    peer_details = self._get_peer_details()
                except Exception as e:
                    print(f"Warning: Could not get peer details: {e}")
            
            # Get database sizes (every 60 polls = 3 minutes)
            db_sizes = {'ledger_db': 0, 'nudb': 0}
            if self.poll_count % 60 == 0:
                try:
                    db_sizes = self.api.get_database_sizes()
                except Exception as e:
                    print(f"Warning: Could not get DB sizes: {e}")
            
            # Calculate transaction rate
            txn_rate = 0
            if self.last_ledger_seq and self.last_ledger_time:
                try:
                    txn_rate = self._calculate_transaction_rate(current_seq)
                except Exception as e:
                    print(f"Warning: Could not calculate txn rate: {e}")
            
            self.poll_count += 1
            timestamp = time.time()
            timestamp_str = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            
            # Check for state change
            if self.last_state and current_state != self.last_state:
                duration = timestamp - self.state_entered_at
                
                # Record to database
                self.db.write_state_transition(
                    timestamp=timestamp,
                    old_state=self.last_state,
                    new_state=current_state,
                    duration=duration,
                    ledger_seq=current_seq,
                    peers=peers,
                    load_factor=load_factor
                )
                
                self.state_changes += 1
                
                # Send alert
                self.alerter.state_change(
                    old_state=self.last_state,
                    new_state=current_state,
                    duration=duration,
                    ledger_seq=current_seq
                )
                self.alerts_sent += 1
                
                # Update Prometheus
                if self.prometheus:
                    self.prometheus.increment_state_changes()
                    self.prometheus.increment_alerts_sent()
                
                self.state_entered_at = timestamp
            elif self.last_state is None:
                self.state_entered_at = timestamp
            
            # Check validations
            if self.last_ledger_seq:
                for seq in range(self.last_ledger_seq, current_seq):
                    if seq not in self.checked_ledgers and seq > 0:
                        self.validation_tracker.check_ledger_validation(
                            ledger_seq=seq,
                            server_state=self.last_state or current_state,
                            peers=peers,
                            load_factor=load_factor
                        )
                        self.checked_ledgers.add(seq)
                        self.validations_checked += 1
                        
                        # Update Prometheus
                        if self.prometheus:
                            self.prometheus.increment_validations_checked()
                        
                        if len(self.checked_ledgers) > 1000:
                            oldest = sorted(self.checked_ledgers)[:500]
                            self.checked_ledgers -= set(oldest)
            
            # Check for ledger gaps
            if self.last_ledger_seq:
                gap = current_seq - self.last_ledger_seq
                if gap > 1:
                    print(f"\n[WARNING] LEDGER GAP: Jumped {gap} ledgers ({self.last_ledger_seq} -> {current_seq})\n")
            
            # Calculate time in state
            time_in_state = timestamp - self.state_entered_at if self.state_entered_at else 0
            
            # Update Prometheus metrics
            if self.prometheus:
                # State metrics
                self.prometheus.update_state(current_state, time_in_state)
                
                # Ledger metrics
                self.prometheus.update_ledger(current_seq)
                self.prometheus.update_ledger_details(ledger_age, base_fee, reserve_base, reserve_inc)
                
                # Peer metrics
                self.prometheus.update_peers(peers)
                self.prometheus.update_peer_disconnects(peer_disconnects, peer_disconnects_resources)
                
                # Peer details (only update if we fetched them)
                if peer_details['inbound'] > 0 or peer_details['outbound'] > 0:
                    self.prometheus.update_peer_details(
                        peer_details['inbound'],
                        peer_details['outbound'],
                        peer_details['insane'],
                        peer_details['p90_latency']
                    )
                
                # Performance metrics
                self.prometheus.update_load_factor(load_factor)
                self.prometheus.update_performance(io_latency, converge_time)
                self.prometheus.update_jq_trans_overflow(jq_trans_overflow)
                
                # Transaction rate
                if txn_rate > 0:
                    self.prometheus.update_transaction_rate(txn_rate)
                
                # Validation metrics
                self.prometheus.update_validation_quorum(validation_quorum)
                self.prometheus.update_proposers(proposers)
                
                # State accounting
                self.prometheus.update_state_accounting(state_accounting)
                
                # System metrics
                self.prometheus.update_system_metrics(uptime, initial_sync_us, server_state_duration_us)
                self.prometheus.update_monitor_uptime()
                
                # Database sizes (only if we fetched them)
                if db_sizes['ledger_db'] > 0 or db_sizes['nudb'] > 0:
                    self.prometheus.update_database_sizes(db_sizes['ledger_db'], db_sizes['nudb'])
                
                # Update validation stats every 10 polls
                if self.poll_count % 10 == 0:
                    stats = self.db.get_validation_stats(hours=24)
                    self.prometheus.update_validation_stats(
                        stats['agreement_rate'],
                        stats['validation_rate']
                    )
                    
                    # Update period validation stats
                    stats_1h = self.db.get_validation_stats_period(hours=1)
                    stats_24h = self.db.get_validation_stats_period(hours=24)
                    self.prometheus.update_validation_period_stats(stats_1h, stats_24h)
            
            # Print status
            print(f"[{timestamp_str}] Poll #{self.poll_count:4d} | "
                  f"State: {current_state:10s} ({time_in_state:6.0f}s) | "
                  f"Ledger: {current_seq:9d} (age: {ledger_age}s) | "
                  f"Peers: {peers:2d} | "
                  f"Quorum: {validation_quorum:2d} | "
                  f"Proposers: {proposers:2d} | "
                  f"IO: {io_latency}ms | "
                  f"Validated: {self.validations_checked:4d}")
            
            # Write to database
            self.db.write_metrics(
                timestamp=timestamp,
                server_state=current_state,
                ledger_seq=current_seq,
                peers=peers,
                load_factor=load_factor
            )
            
            # Update tracking
            self.last_state = current_state
            self.last_ledger_seq = current_seq
            self.last_ledger_time = timestamp
            
        except RippledAPIError as e:
            self._handle_api_error(e)
        except Exception as e:
            self._handle_unexpected_error(e)
    
    def _get_peer_details(self) -> dict:
        """Get detailed peer information"""
        peers_list = self.api.get_peers()
        
        inbound_count = 0
        outbound_count = 0
        insane_count = 0
        latencies = []
        
        for peer in peers_list:
            # Count inbound vs outbound
            if peer.get('inbound', False):
                inbound_count += 1
            else:
                outbound_count += 1
            
            # Count insane peers
            if peer.get('sanity') == 'insane':
                insane_count += 1
            
            # Collect latencies
            latency = peer.get('latency')
            if latency is not None:
                latencies.append(int(latency))
        
        # Calculate P90 (90th percentile)
        if latencies:
            latencies_sorted = sorted(latencies)
            p90_index = int(len(latencies_sorted) * 0.90)
            if p90_index >= len(latencies_sorted):
                p90_index = len(latencies_sorted) - 1
            p90_latency = latencies_sorted[p90_index]
        else:
            p90_latency = 0
        
        return {
            'inbound': inbound_count,
            'outbound': outbound_count,
            'insane': insane_count,
            'p90_latency': p90_latency
        }
    
    def _calculate_transaction_rate(self, current_seq: int) -> float:
        """Calculate transactions per second from fee info"""
        try:
            # Get fee info which includes current ledger size
            fee_info = self.api.get_fee()
            current_ledger_size = int(fee_info.get('current_ledger_size', 0))
            
            # Average ledger close time is ~3.5 seconds
            avg_ledger_time = 3.5
            
            # Calculate TPS
            if current_ledger_size > 0:
                rate = current_ledger_size / avg_ledger_time
                return rate
            return 0
        except Exception:
            return 0
    
    def _handle_api_error(self, error: Exception):
        """Handle API errors gracefully"""
        self.consecutive_errors += 1
        self.api_errors += 1
        
        # Update Prometheus
        if self.prometheus:
            self.prometheus.increment_api_errors()
        
        timestamp = time.time()
        timestamp_str = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        current_state = 'unreachable'
        
        if self.consecutive_errors == 1:
            print(f"[{timestamp_str}] [WARNING] Validator unreachable (attempt {self.consecutive_errors})")
        elif self.consecutive_errors <= self.max_errors_before_alert:
            print(f"[{timestamp_str}] [WARNING] Still unreachable (attempt {self.consecutive_errors})")
        else:
            if self.last_state and self.last_state != 'unreachable':
                duration = timestamp - self.state_entered_at if self.state_entered_at else 0
                
                self.db.write_state_transition(
                    timestamp=timestamp,
                    old_state=self.last_state,
                    new_state=current_state,
                    duration=duration,
                    ledger_seq=self.last_ledger_seq or 0,
                    peers=0,
                    load_factor=0
                )
                
                self.state_changes += 1
                
                self.alerter.alert(
                    level='CRITICAL',
                    title='Validator Unreachable',
                    message=f'Unable to connect to validator after {self.consecutive_errors} attempts.\n'
                            f'Previous state: {self.last_state}\n'
                            f'Likely cause: Validator down, restarting, or network issue'
                )
                self.alerts_sent += 1
                
                # Update Prometheus
                if self.prometheus:
                    self.prometheus.increment_state_changes()
                    self.prometheus.increment_alerts_sent()
                    self.prometheus.update_state(current_state, 0)
                
                self.state_entered_at = timestamp
            
            print(f"[{timestamp_str}] [CRITICAL] Validator unreachable (attempt {self.consecutive_errors})")
        
        if self.consecutive_errors > self.max_errors_before_alert:
            self.last_state = 'unreachable'
    
    def _handle_unexpected_error(self, error: Exception):
        """Handle unexpected errors"""
        timestamp_str = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f"[{timestamp_str}] [ERROR] Unexpected error: {error}")
        import traceback
        traceback.print_exc()
    
    def run(self):
        """Run polling loop"""
        print("=" * 80)
        print("XRPL Monitor - Fast Poller (Full Tracking + Prometheus)")
        print("=" * 80)
        print(f"Polling every {self.interval} seconds")
        print(f"Database: {self.db.db_path}")
        print(f"Alerts: {self.alerter.alerts_file}")
        if self.prometheus:
            print(f"Prometheus: http://localhost:{self.prometheus.port}/metrics")
        
        # FIXED: Handle None validator_pubkey
        if self.validation_tracker.validator_pubkey:
            print(f"Validator: {self.validation_tracker.validator_pubkey[:25]}...")
        else:
            print("Validator: Pubkey not detected (will retry from rippled API)")
        
        print("Press Ctrl+C to stop")
        print("=" * 80)
        print()
        
        try:
            while True:
                self.poll()
                time.sleep(self.interval)
        
        except KeyboardInterrupt:
            print("\n")
            print("=" * 80)
            print("Polling stopped by user")
            print(f"Total polls: {self.poll_count}")
            print(f"State changes: {self.state_changes}")
            print(f"Alerts sent: {self.alerts_sent}")
            print(f"API errors: {self.api_errors}")
            print(f"Validations checked: {self.validations_checked}")
            print("=" * 80)


def main():
    """Main entry point"""
    
    # Load configuration
    config = Config()
    
    # FIXED: Support both Docker and native rippled
    rippled_mode = config.get('monitoring.rippled_mode', 'native')  # Default to native
    
    if rippled_mode == 'docker':
        # Docker mode - connect via container name
        container_name = config.get('monitoring.container_name', 'rippledvalidator')
        api = RippledAPI(container_name=container_name)
        print(f"Connecting to rippled via Docker container: {container_name}")
    else:
        # Native mode - connect via host:port
        rippled_host = config.get('monitoring.rippled_host', 'localhost')
        rippled_port = config.get('monitoring.rippled_port', 5005)
        api = RippledAPI(host=rippled_host, port=rippled_port)
        print(f"Connecting to native rippled at {rippled_host}:{rippled_port}")
    
    # Create database
    db_path = config.get('database.path', '${INSTALL_DIR}/data/monitor.db')
    db = Database(db_path)
    
    # Create alerter
    alerter = Alerter()
    
    # Create Prometheus exporter if enabled
    prometheus = None
    if config.get('prometheus.enabled', True):
        prom_port = config.get('prometheus.port', 9091)
        prom_host = config.get('prometheus.host', '0.0.0.0')
        prometheus = PrometheusExporter(port=prom_port, host=prom_host)
        prometheus.start()
    
    # Get poll interval
    interval = config.get('monitoring.poll_interval', 3)
    
    # Create and run poller
    poller = FastPoller(api, db, alerter, prometheus, interval=interval)
    poller.run()


if __name__ == '__main__':
    main()
