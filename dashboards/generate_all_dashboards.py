#!/usr/bin/env python3
"""
Generate 6 category dashboards for XRPL Validator Monitoring
"""
import json
import os

# Use relative path within this project
DASH_DIR = os.path.join(os.path.dirname(__file__), "categories")
os.makedirs(DASH_DIR, exist_ok=True)

def create_panel(title, panel_type, x, y, w, h, expr, refId="A", **kwargs):
    """Helper to create panel"""
    panel = {
        "title": title,
        "type": panel_type,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "targets": [{"expr": expr, "refId": refId}]
    }
    
    # Merge any additional config
    for key, value in kwargs.items():
        panel[key] = value
    
    return panel

def create_dashboard(title, tags, panels):
    """Create dashboard structure"""
    return {
        "title": title,
        "tags": tags,
        "timezone": "browser",
        "editable": True,
        "refresh": "5s",
        "time": {"from": "now-6h", "to": "now"},
        "panels": panels,
        "schemaVersion": 38,
        "style": "dark",
        "version": 1
    }

# Dashboard 1: Overview & Status
print("Creating Dashboard 1: Overview & Status...")
panels_1 = [
    create_panel("Validator State", "stat", 0, 0, 6, 5, "xrpl_validator_state_value",
        options={"colorMode": "background", "graphMode": "none", "textMode": "value"},
        fieldConfig={"defaults": {
            "mappings": [{"type": "value", "options": {
                "0": {"color": "red", "text": "Unknown"},
                "1": {"color": "red", "text": "Disconnected"},
                "2": {"color": "yellow", "text": "Connected"},
                "3": {"color": "yellow", "text": "Syncing"},
                "4": {"color": "yellow", "text": "Tracking"},
                "5": {"color": "green", "text": "Full"},
                "6": {"color": "green", "text": "Proposing"},
                "7": {"color": "red", "text": "Unreachable"}
            }}]
        }}
    ),
    create_panel("Current Ledger", "stat", 6, 0, 6, 5, "xrpl_ledger_sequence",
        options={"colorMode": "value", "graphMode": "area"},
        fieldConfig={"defaults": {"unit": "none", "decimals": 0}}
    ),
    create_panel("Validator Uptime", "stat", 12, 0, 6, 5, "xrpl_validator_uptime_seconds",
        options={"colorMode": "value", "graphMode": "area"},
        fieldConfig={"defaults": {"unit": "s"}}
    ),
    create_panel("Monitor Uptime", "stat", 18, 0, 6, 5, "xrpl_monitor_uptime_seconds",
        options={"colorMode": "value", "graphMode": "area"},
        fieldConfig={"defaults": {"unit": "s"}}
    ),
    create_panel("Validation Agreement (24h)", "gauge", 0, 5, 8, 5, "xrpl_validation_agreement_pct_24h",
        fieldConfig={"defaults": {"unit": "percent", "min": 0, "max": 100}}
    ),
    create_panel("Validation Agreement (1h)", "gauge", 8, 5, 8, 5, "xrpl_validation_agreement_pct_1h",
        fieldConfig={"defaults": {"unit": "percent", "min": 0, "max": 100}}
    ),
    create_panel("Ledger Age", "stat", 16, 5, 4, 5, "xrpl_ledger_age_seconds",
        fieldConfig={"defaults": {"unit": "s"}}
    ),
    create_panel("Load Factor", "gauge", 20, 5, 4, 5, "xrpl_load_factor",
        fieldConfig={"defaults": {"min": 0, "max": 10}}
    ),
]

dashboard_1 = create_dashboard("XRPL - 1. Overview & Status", ["xrpl", "overview"], panels_1)
with open(f"{DASH_DIR}/1-overview-status.json", "w") as f:
    json.dump(dashboard_1, f, indent=2)

# Dashboard 2: Validation Performance
print("Creating Dashboard 2: Validation Performance...")
panels_2 = [
    create_panel("Agreements (24h)", "stat", 0, 0, 6, 4, "xrpl_validation_agreements_24h",
        options={"colorMode": "value", "graphMode": "none"}
    ),
    create_panel("Missed (24h)", "stat", 6, 0, 6, 4, "xrpl_validation_missed_24h",
        options={"colorMode": "value", "graphMode": "none"}
    ),
    create_panel("Agreements (1h)", "stat", 12, 0, 6, 4, "xrpl_validation_agreements_1h",
        options={"colorMode": "value", "graphMode": "none"}
    ),
    create_panel("Missed (1h)", "stat", 18, 0, 6, 4, "xrpl_validation_missed_1h",
        options={"colorMode": "value", "graphMode": "none"}
    ),
    create_panel("Agreement % Trend", "timeseries", 0, 4, 12, 6, "xrpl_validation_agreement_pct_24h"),
    create_panel("Validation Rate", "timeseries", 12, 4, 12, 6, "xrpl_validation_rate"),
    create_panel("Validation Quorum", "stat", 0, 10, 6, 4, "xrpl_validation_quorum"),
    create_panel("Proposers", "stat", 6, 10, 6, 4, "xrpl_proposers"),
    create_panel("Validations Checked", "stat", 12, 10, 6, 4, "xrpl_validations_checked_total"),
]

dashboard_2 = create_dashboard("XRPL - 2. Validation Performance", ["xrpl", "validation"], panels_2)
with open(f"{DASH_DIR}/2-validation-performance.json", "w") as f:
    json.dump(dashboard_2, f, indent=2)

# Dashboard 3: Network & Peers
print("Creating Dashboard 3: Network & Peers...")
panels_3 = [
    create_panel("Total Peers", "stat", 0, 0, 4, 4, "xrpl_peer_count",
        options={"colorMode": "value", "graphMode": "area"}
    ),
    create_panel("Inbound Peers", "stat", 4, 0, 4, 4, "xrpl_peers_inbound",
        options={"colorMode": "value", "graphMode": "area"}
    ),
    create_panel("Outbound Peers", "stat", 8, 0, 4, 4, "xrpl_peers_outbound",
        options={"colorMode": "value", "graphMode": "area"}
    ),
    create_panel("Insane Peers", "stat", 12, 0, 4, 4, "xrpl_peers_insane",
        options={"colorMode": "value", "graphMode": "none"}
    ),
    create_panel("Peer Latency", "stat", 16, 0, 4, 4, "xrpl_peer_latency_avg_ms",
        fieldConfig={"defaults": {"unit": "ms"}}
    ),
    create_panel("Peer Disconnects", "stat", 20, 0, 4, 4, "rate(xrpl_peer_disconnects_total[5m])",
        fieldConfig={"defaults": {"unit": "ops"}}
    ),
    create_panel("Peer Connections Over Time", "timeseries", 0, 4, 12, 6, "xrpl_peer_count"),
    create_panel("Transaction Rate", "timeseries", 12, 4, 12, 6, "xrpl_transaction_rate",
        fieldConfig={"defaults": {"unit": "short"}}
    ),
]

dashboard_3 = create_dashboard("XRPL - 3. Network & Peers", ["xrpl", "network", "peers"], panels_3)
with open(f"{DASH_DIR}/3-network-peers.json", "w") as f:
    json.dump(dashboard_3, f, indent=2)

# Dashboard 4: System Performance
print("Creating Dashboard 4: System Performance...")
panels_4 = [
    create_panel("IO Latency", "timeseries", 0, 0, 8, 6, "xrpl_io_latency_ms",
        fieldConfig={"defaults": {"unit": "ms"}}
    ),
    create_panel("Consensus Converge Time", "timeseries", 8, 0, 8, 6, "xrpl_consensus_converge_time_seconds",
        fieldConfig={"defaults": {"unit": "s"}}
    ),
    create_panel("Job Queue Overflows", "stat", 16, 0, 8, 6, "xrpl_jq_trans_overflow_total",
        options={"colorMode": "value", "graphMode": "area"}
    ),
    create_panel("Ledger DB Size", "stat", 0, 6, 8, 5, "xrpl_ledger_db_bytes",
        fieldConfig={"defaults": {"unit": "bytes"}}
    ),
    create_panel("NuDB Size", "stat", 8, 6, 8, 5, "xrpl_ledger_nudb_bytes",
        fieldConfig={"defaults": {"unit": "bytes"}}
    ),
    create_panel("Initial Sync Duration", "stat", 16, 6, 8, 5, "xrpl_initial_sync_duration_seconds",
        fieldConfig={"defaults": {"unit": "s"}}
    ),
]

dashboard_4 = create_dashboard("XRPL - 4. System Performance", ["xrpl", "performance"], panels_4)
with open(f"{DASH_DIR}/4-system-performance.json", "w") as f:
    json.dump(dashboard_4, f, indent=2)

# Dashboard 5: State Accounting
print("Creating Dashboard 5: State Accounting...")
panels_5 = [
    create_panel("Time in Current State", "stat", 0, 0, 6, 4, "xrpl_time_in_current_state_seconds",
        fieldConfig={"defaults": {"unit": "s"}}
    ),
    create_panel("Server State Duration", "stat", 6, 0, 6, 4, "xrpl_server_state_duration_seconds",
        fieldConfig={"defaults": {"unit": "s"}}
    ),
    create_panel("State Duration (All States)", "timeseries", 0, 4, 12, 8, "xrpl_state_accounting_duration_seconds",
        fieldConfig={"defaults": {"unit": "s"}}
    ),
    create_panel("State Transitions", "timeseries", 12, 4, 12, 8, "xrpl_state_accounting_transitions"),
]

dashboard_5 = create_dashboard("XRPL - 5. State Accounting", ["xrpl", "state"], panels_5)
with open(f"{DASH_DIR}/5-state-accounting.json", "w") as f:
    json.dump(dashboard_5, f, indent=2)

# Dashboard 6: Network Parameters
print("Creating Dashboard 6: Network Parameters...")
panels_6 = [
    create_panel("Base Fee", "stat", 0, 0, 6, 4, "xrpl_base_fee_xrp",
        fieldConfig={"defaults": {"unit": "XRP", "decimals": 6}}
    ),
    create_panel("Reserve Base", "stat", 6, 0, 6, 4, "xrpl_reserve_base_xrp",
        fieldConfig={"defaults": {"unit": "XRP"}}
    ),
    create_panel("Reserve Increment", "stat", 12, 0, 6, 4, "xrpl_reserve_inc_xrp",
        fieldConfig={"defaults": {"unit": "XRP"}}
    ),
    create_panel("Validation Quorum", "stat", 18, 0, 6, 4, "xrpl_validation_quorum"),
    create_panel("Base Fee Over Time", "timeseries", 0, 4, 12, 6, "xrpl_base_fee_xrp",
        fieldConfig={"defaults": {"unit": "XRP", "decimals": 6}}
    ),
    create_panel("Load Factor Over Time", "timeseries", 12, 4, 12, 6, "xrpl_load_factor"),
]

dashboard_6 = create_dashboard("XRPL - 6. Network Parameters", ["xrpl", "parameters"], panels_6)
with open(f"{DASH_DIR}/6-network-parameters.json", "w") as f:
    json.dump(dashboard_6, f, indent=2)

print("\n" + "="*60)
print("✅ SUCCESS! All 6 dashboards created!")
print("="*60)
print(f"\n📁 Location: {DASH_DIR}/")
print("\n📊 Import these dashboards in order:")
print("   1. 1-overview-status.json - Main monitoring")
print("   2. 2-validation-performance.json - Validation metrics")
print("   3. 3-network-peers.json - Network & peer stats")
print("   4. 4-system-performance.json - IO, consensus, DB")
print("   5. 5-state-accounting.json - State tracking")
print("   6. 6-network-parameters.json - Fees, reserves")
print("\n🔧 To import:")
print("   1. Go to http://localhost:3000")
print("   2. Dashboards → Import")
print("   3. Upload each JSON file")
print("   4. Select 'Prometheus' as data source")
print("   5. Click Import")
print("\n💡 Tip: After importing all 6, you can copy panels between")
print("   dashboards to create your custom combined view!")
print("="*60)

