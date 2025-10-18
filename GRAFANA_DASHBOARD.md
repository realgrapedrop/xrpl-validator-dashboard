# Grafana XRPL Validator Dashboard Panels

## Introduction

This document provides a comprehensive reference for all panels in the XRPL Validator Dashboard. Each panel is documented with its configuration, PromQL query, and purpose.

## Dashboard Preview

![XRPL Validator Dashboard](images/xrpl-validator-monitor-dashboard-inaction.gif)

*Real-time monitoring of XRPL validator performance, consensus state, and network metrics*

### Dashboard Overview

The XRPL Validator Dashboard provides real-time and historical monitoring of your validator node through 40+ panels organized into 8 rows:

- **Row 1**: Critical health status indicators
- **Row 2**: Key performance metrics
- **Row 3**: Short-term validation performance (1 hour)
- **Row 4**: Long-term validation performance (24 hours)
- **Row 5**: Time-series graphs for CPU, network, and activity
- **Row 6**: Historical load and transaction trends
- **Row 7**: Validation and consensus analysis
- **Row 8**: System resource monitoring

### Prerequisites

- XRPL Validator Monitor installed and running (`xrpl-monitor.service`)
- Prometheus scraping metrics from `localhost:9091`
- Grafana connected to Prometheus data source
- rippled validator running and accessible

### How to Use This Document

1. **Quick Reference**: Jump to specific rows to find panel configurations
2. **Manual Setup**: Use the configuration details to recreate panels
3. **Troubleshooting**: Verify your queries match these examples
4. **Customization**: Modify queries and thresholds for your needs

---

## Row 1: Critical Health Status

### Panel 1.1: Uptime

**Purpose**: Shows how long the validator has been running since last restart

**Configuration:**
- **Visualization**: Stat
- **Query**: `xrpl_uptime_seconds`
- **Unit**: `duration (s)`
- **Decimals**: 0
- **Thresholds**: N/A
- **Description**: Validator uptime in human-readable format (e.g., 27h:18m:22s)

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "dtdurations",
      "decimals": 0
    }
  }
}
```

---

### Panel 1.2: State

**Purpose**: Current validator server state

**Configuration:**
- **Visualization**: Stat
- **Query**: `xrpl_server_state`
- **Unit**: None (text mapping)
- **Value Mappings**:
  - `0` → "disconnected" (red)
  - `1` → "connected" (yellow)
  - `2` → "syncing" (orange)
  - `3` → "tracking" (blue)
  - `4` → "full" (light green)
  - `5` → "validating" (green)
  - `6` → "proposing" (dark green)
- **Thresholds**: 
  - Red: < 3
  - Yellow: 3-4
  - Green: >= 5

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "mappings": [
        {"type": "value", "value": "0", "text": "disconnected"},
        {"type": "value", "value": "1", "text": "connected"},
        {"type": "value", "value": "2", "text": "syncing"},
        {"type": "value", "value": "3", "text": "tracking"},
        {"type": "value", "value": "4", "text": "full"},
        {"type": "value", "value": "5", "text": "validating"},
        {"type": "value", "value": "6", "text": "proposing"}
      ],
      "thresholds": {
        "steps": [
          {"value": 0, "color": "red"},
          {"value": 3, "color": "yellow"},
          {"value": 5, "color": "green"}
        ]
      }
    }
  }
}
```

---

### Panel 1.3: Validation Rate

**Purpose**: Percentage of ledgers successfully validated

**Configuration:**
- **Visualization**: Stat
- **Query**: `xrpl_validation_rate_percent`
- **Unit**: `percent (0-100)`
- **Decimals**: 0
- **Thresholds**:
  - Red: < 95%
  - Yellow: 95-99%
  - Green: >= 99%

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "percent",
      "decimals": 0,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "red"},
          {"value": 95, "color": "yellow"},
          {"value": 99, "color": "green"}
        ]
      }
    }
  }
}
```

---

### Panel 1.4: Release Version

**Purpose**: rippled software version currently running

**Configuration:**
- **Visualization**: Stat
- **Query**: `xrpl_server_info`
- **Display**: Filter to show only `build_version` field
- **Unit**: None (text)
- **Transformation**: Filter fields by name → Select only `build_version`

**Settings:**
```json
{
  "transformations": [
    {
      "id": "filterFieldsByName",
      "options": {
        "include": {
          "names": ["build_version"]
        }
      }
    }
  ]
}
```

---

### Panel 1.5: Pubkey

**Purpose**: Validator's public key (for verification)

**Configuration:**
- **Visualization**: Stat
- **Query**: `xrpl_server_info`
- **Display**: Filter to show only `pubkey_validator` field
- **Unit**: None (text)
- **Transformation**: Filter fields by name → Uncheck all except `pubkey_validator` and `Value`

**Settings:**
```json
{
  "transformations": [
    {
      "id": "filterFieldsByName",
      "options": {
        "include": {
          "names": ["pubkey_validator", "Value"]
        }
      }
    }
  ]
}
```

---

### Panel 1.6: XRP Fees (USD)

**Purpose**: Current XRP transaction fees converted to USD (requires additional data source)

**Configuration:**
- **Visualization**: Stat
- **Query**: Custom (combines `xrpl_base_fee_xrp` with external USD price feed)
- **Unit**: `currency (USD)`
- **Decimals**: 5

**Note**: This panel requires integration with an external price API or manual configuration.

---

## Row 2: Key Performance Metrics

### Panel 2.1: Current Ledger

**Purpose**: Latest validated ledger sequence number

**Configuration:**
- **Visualization**: Stat
- **Query**: `xrpl_ledger_sequence`
- **Unit**: None
- **Decimals**: 0
- **Color**: Green background

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 0,
      "color": {
        "mode": "fixed",
        "fixedColor": "green"
      }
    }
  }
}
```

---

### Panel 2.2: Ledger Age

**Purpose**: How old the current validated ledger is (should be < 10 seconds)

**Configuration:**
- **Visualization**: Stat
- **Query**: `xrpl_ledger_age_seconds`
- **Unit**: `seconds (s)`
- **Decimals**: 1
- **Thresholds**:
  - Green: < 10s
  - Yellow: 10-30s
  - Red: > 30s

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "s",
      "decimals": 1,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "green"},
          {"value": 10, "color": "yellow"},
          {"value": 30, "color": "red"}
        ]
      }
    }
  }
}
```

---

### Panel 2.3: Ledgers Per Minute

**Purpose**: Rate of ledger validation (should be ~15-20/min)

**Configuration:**
- **Visualization**: Stat
- **Query**: `rate(xrpl_ledger_sequence[1m]) * 60`
- **Unit**: None
- **Decimals**: 1
- **Sparkline**: Enabled (shows trend)

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 1
    }
  },
  "options": {
    "graphMode": "area"
  }
}
```

---

### Panel 2.4: Load Factor

**Purpose**: Server load indicator (1 = normal, >1 = high load)

**Configuration:**
- **Visualization**: Stat
- **Query**: `xrpl_load_factor`
- **Unit**: None
- **Decimals**: 0
- **Thresholds**:
  - Green: = 1
  - Yellow: 2-10
  - Red: > 10

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 0,
      "thresholds": {
        "steps": [
          {"value": 1, "color": "green"},
          {"value": 2, "color": "yellow"},
          {"value": 10, "color": "red"}
        ]
      }
    }
  }
}
```

---

### Panel 2.5: Validations Checked

**Purpose**: Total number of validations processed by the monitor

**Configuration:**
- **Visualization**: Stat
- **Query**: `xrpl_validations_checked_total`
- **Unit**: `short`
- **Decimals**: 1
- **Note**: Counter resets when monitor restarts

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "short",
      "decimals": 1
    }
  }
}
```

---

### Panel 2.6: Peer Latency (P90)

**Purpose**: 90th percentile peer latency (90% of peers have lower latency)

**Configuration:**
- **Visualization**: Stat
- **Query**: `xrpl_peer_latency_p90_milliseconds`
- **Unit**: `milliseconds (ms)`
- **Decimals**: 0
- **Sparkline**: Enabled
- **Thresholds**:
  - Green: < 200ms
  - Yellow: 200-400ms
  - Red: > 400ms

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "ms",
      "decimals": 0,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "green"},
          {"value": 200, "color": "yellow"},
          {"value": 400, "color": "red"}
        ]
      }
    }
  },
  "options": {
    "graphMode": "area"
  }
}
```

---

### Panel 2.7: Ledger DB

**Purpose**: Size of the ledger database on disk

**Configuration:**
- **Visualization**: Stat
- **Query**: `xrpl_ledger_db_size_bytes`
- **Unit**: `bytes (IEC)`
- **Decimals**: 1
- **Sparkline**: Enabled

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "decbytes",
      "decimals": 1
    }
  },
  "options": {
    "graphMode": "area"
  }
}
```

---

### Panel 2.8: Ledger NuDB

**Purpose**: Size of the NuDB database on disk

**Configuration:**
- **Visualization**: Stat
- **Query**: `xrpl_nudb_size_bytes`
- **Unit**: `bytes (IEC)`
- **Decimals**: 1
- **Sparkline**: Enabled

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "decbytes",
      "decimals": 1
    }
  },
  "options": {
    "graphMode": "area"
  }
}
```

---

## Row 3: Short-Term Validation Performance (1 Hour)

### Panel 3.1: Agreements % (1h)

**Purpose**: Percentage of ledgers where validator agreed with consensus (last hour)

**Configuration:**
- **Visualization**: Stat
- **Query**: `xrpl_agreement_rate_1h_percent`
- **Unit**: `percent (0-100)`
- **Decimals**: 0
- **Thresholds**:
  - Red: < 95%
  - Yellow: 95-99%
  - Green: >= 99%

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "percent",
      "decimals": 0,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "red"},
          {"value": 95, "color": "yellow"},
          {"value": 99, "color": "green"}
        ]
      }
    }
  }
}
```

---

### Panel 3.2: Agreements (1h)

**Purpose**: Total number of ledgers agreed upon in the last hour

**Configuration:**
- **Visualization**: Stat
- **Query**: `increase(xrpl_agreements_total[1h])`
- **Unit**: None
- **Decimals**: 0
- **Sparkline**: Enabled

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 0
    }
  },
  "options": {
    "graphMode": "area"
  }
}
```

---

### Panel 3.3: Missed (1h)

**Purpose**: Number of ledgers missed/disagreed in the last hour

**Configuration:**
- **Visualization**: Stat
- **Query**: `increase(xrpl_missed_total[1h])`
- **Unit**: None
- **Decimals**: 0
- **Thresholds**:
  - Green: = 0
  - Yellow: 1-5
  - Red: > 5

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 0,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "green"},
          {"value": 1, "color": "yellow"},
          {"value": 5, "color": "red"}
        ]
      }
    }
  }
}
```

---

### Panel 3.4: Total Peers

**Purpose**: Current number of connected peer nodes

**Configuration:**
- **Visualization**: Gauge
- **Query**: `xrpl_total_peers`
- **Unit**: None
- **Decimals**: 0
- **Min**: 0
- **Max**: 50
- **Thresholds**:
  - Red: < 5
  - Yellow: 5-10
  - Green: >= 10

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 0,
      "min": 0,
      "max": 50,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "red"},
          {"value": 5, "color": "yellow"},
          {"value": 10, "color": "green"}
        ]
      }
    }
  },
  "options": {
    "orientation": "auto",
    "showThresholdLabels": false,
    "showThresholdMarkers": true
  }
}
```

---

## Row 4: Long-Term Validation Performance (24 Hours)

### Panel 4.1: Agreements % (24h)

**Purpose**: Percentage of ledgers where validator agreed with consensus (last 24 hours)

**Configuration:**
- **Visualization**: Stat
- **Query**: `xrpl_agreement_rate_24h_percent`
- **Unit**: `percent (0-100)`
- **Decimals**: 0
- **Thresholds**:
  - Red: < 95%
  - Yellow: 95-99%
  - Green: >= 99%

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "percent",
      "decimals": 0,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "red"},
          {"value": 95, "color": "yellow"},
          {"value": 99, "color": "green"}
        ]
      }
    }
  }
}
```

---

### Panel 4.2: Agreements (24h)

**Purpose**: Total number of ledgers agreed upon in the last 24 hours

**Configuration:**
- **Visualization**: Stat
- **Query**: `increase(xrpl_agreements_total[24h])`
- **Unit**: None
- **Decimals**: 0

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 0
    }
  }
}
```

---

### Panel 4.3: Missed (24h)

**Purpose**: Number of ledgers missed/disagreed in the last 24 hours

**Configuration:**
- **Visualization**: Stat
- **Query**: `increase(xrpl_missed_total[24h])`
- **Unit**: None
- **Decimals**: 0
- **Thresholds**:
  - Green: = 0
  - Yellow: 1-10
  - Red: > 10

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 0,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "green"},
          {"value": 1, "color": "yellow"},
          {"value": 10, "color": "red"}
        ]
      }
    }
  }
}
```

---

### Panel 4.4: Transaction Rate

**Purpose**: Current transaction processing rate

**Configuration:**
- **Visualization**: Gauge
- **Query**: `xrpl_transaction_rate`
- **Unit**: `transactions/sec`
- **Decimals**: 0
- **Min**: 0
- **Max**: 50

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "short",
      "decimals": 0,
      "min": 0,
      "max": 50,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "green"}
        ]
      }
    }
  }
}
```

---

### Panel 4.5: Inbound Peers

**Purpose**: Number of peer connections initiated by other nodes

**Configuration:**
- **Visualization**: Gauge
- **Query**: `xrpl_inbound_peers`
- **Unit**: None
- **Decimals**: 0
- **Min**: 0
- **Max**: 40

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 0,
      "min": 0,
      "max": 40,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "green"}
        ]
      }
    }
  }
}
```

---

### Panel 4.6: Proposers

**Purpose**: Number of validators currently proposing

**Configuration:**
- **Visualization**: Gauge
- **Query**: `xrpl_proposers`
- **Unit**: None
- **Decimals**: 0
- **Min**: 0
- **Max**: 50

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 0,
      "min": 0,
      "max": 50,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "yellow"},
          {"value": 20, "color": "green"}
        ]
      }
    }
  }
}
```

---

### Panel 4.7: Outbound Peers

**Purpose**: Number of peer connections initiated by this validator

**Configuration:**
- **Visualization**: Gauge
- **Query**: `xrpl_outbound_peers`
- **Unit**: None
- **Decimals**: 0
- **Min**: 0
- **Max**: 20

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 0,
      "min": 0,
      "max": 20,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "green"}
        ]
      }
    }
  }
}
```

---

### Panel 4.8: Quorum

**Purpose**: Current validation quorum size

**Configuration:**
- **Visualization**: Gauge
- **Query**: `xrpl_quorum`
- **Unit**: None
- **Decimals**: 0
- **Min**: 0
- **Max**: 40

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 0,
      "min": 0,
      "max": 40,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "red"},
          {"value": 20, "color": "green"}
        ]
      }
    }
  }
}
```

---

### Panel 4.9: Insane Peers

**Purpose**: Number of peers with problematic behavior (should be 0)

**Configuration:**
- **Visualization**: Gauge
- **Query**: `xrpl_insane_peers`
- **Unit**: None
- **Decimals**: 0
- **Min**: 0
- **Max**: 5
- **Thresholds**:
  - Green: = 0
  - Yellow: 1
  - Red: > 1

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 0,
      "min": 0,
      "max": 5,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "green"},
          {"value": 1, "color": "yellow"},
          {"value": 2, "color": "red"}
        ]
      }
    }
  }
}
```

---

### Panel 4.10: Consensus

**Purpose**: Average consensus time in seconds

**Configuration:**
- **Visualization**: Gauge
- **Query**: `xrpl_consensus_time_seconds`
- **Unit**: `seconds (s)`
- **Decimals**: 1
- **Min**: 0
- **Max**: 10

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "s",
      "decimals": 1,
      "min": 0,
      "max": 10,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "green"},
          {"value": 5, "color": "yellow"}
        ]
      }
    }
  }
}
```

---

### Panel 4.11: Peer Disconnects

**Purpose**: Rate of peer disconnections (operations per second)

**Configuration:**
- **Visualization**: Stat
- **Query**: `rate(xrpl_peer_disconnects_total[5m])`
- **Unit**: `ops/sec`
- **Decimals**: 3

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "ops",
      "decimals": 3
    }
  }
}
```

---

### Panel 4.12: Job Queue

**Purpose**: Number of jobs waiting in queue (should be 0)

**Configuration:**
- **Visualization**: Gauge
- **Query**: `xrpl_job_queue`
- **Unit**: None
- **Decimals**: 0
- **Min**: 0
- **Max**: 100
- **Thresholds**:
  - Green: = 0
  - Yellow: 1-10
  - Red: > 10

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 0,
      "min": 0,
      "max": 100,
      "thresholds": {
        "steps": [
          {"value": 0, "color": "green"},
          {"value": 1, "color": "yellow"},
          {"value": 10, "color": "red"}
        ]
      }
    }
  }
}
```

---

## Row 5: Time-Series Analysis

### Panel 5.1: Validator CPU Load

**Purpose**: Historical view of validator CPU usage over time

**Configuration:**
- **Visualization**: Time series (line graph)
- **Query**: `xrpl_cpu_load_percent`
- **Unit**: `percent (0-100)`
- **Decimals**: 1
- **Legend**: Bottom

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "percent",
      "decimals": 1,
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "smooth",
        "fillOpacity": 10
      }
    }
  },
  "options": {
    "legend": {
      "displayMode": "list",
      "placement": "bottom"
    }
  }
}
```

---

### Panel 5.2: Network TCP In / Out

**Purpose**: Network traffic in/out over time

**Configuration:**
- **Visualization**: Time series (stacked area)
- **Queries**:
  - TCP Rx In: `rate(xrpl_network_tcp_rx_bytes[1m]) * 8 / 1000000`
  - TCP Tx Out: `rate(xrpl_network_tcp_tx_bytes[1m]) * 8 / 1000000`
- **Unit**: `bits/sec (Mbps)`
- **Decimals**: 1
- **Stack**: Enabled

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "bps",
      "decimals": 1,
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "smooth",
        "fillOpacity": 50,
        "stacking": {
          "mode": "normal"
        }
      }
    }
  }
}
```

---

### Panel 5.3: Activity Rates

**Purpose**: Multiple activity metrics over time

**Configuration:**
- **Visualization**: Time series (multi-line)
- **Queries**:
  - Validations/sec: `rate(xrpl_validations_checked_total[1m])`
  - State Changes/sec: `rate(xrpl_state_changes_total[1m])`
  - Alerts/sec: `rate(xrpl_alerts_total[1m])`
- **Unit**: `operations/sec`
- **Decimals**: 2

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "ops",
      "decimals": 2,
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "smooth"
      }
    }
  }
}
```

---

## Row 6: Historical Trends

### Panel 6.1: Load Factor Over Time

**Purpose**: Historical view of server load factor

**Configuration:**
- **Visualization**: Time series (line graph)
- **Query**: `xrpl_load_factor`
- **Unit**: None
- **Decimals**: 1
- **Reference Line**: Y = 1 (normal load)

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 1,
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "smooth"
      }
    }
  }
}
```

---

### Panel 6.2: Transaction Rate

**Purpose**: Historical transaction processing rate

**Configuration:**
- **Visualization**: Time series (line graph)
- **Query**: `xrpl_transaction_rate`
- **Unit**: `transactions/sec`
- **Decimals**: 1

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "short",
      "decimals": 1,
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "smooth",
        "fillOpacity": 20
      }
    }
  }
}
```

---

### Panel 6.3: Agreement % Trend

**Purpose**: Historical validation agreement percentage

**Configuration:**
- **Visualization**: Time series (line graph)
- **Query**: `xrpl_agreement_rate_1h_percent`
- **Unit**: `percent (0-100)`
- **Decimals**: 1
- **Min**: 0
- **Max**: 100

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "percent",
      "decimals": 1,
      "min": 0,
      "max": 100,
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "smooth"
      }
    }
  }
}
```

---

### Panel 6.4: IO Latency

**Purpose**: Disk I/O latency over time

**Configuration:**
- **Visualization**: Time series (line graph)
- **Query**: `xrpl_io_latency_milliseconds`
- **Unit**: `milliseconds (ms)`
- **Decimals**: 1

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "ms",
      "decimals": 1,
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "smooth"
      }
    }
  }
}
```

---

## Row 7: Validation & Consensus Analysis

### Panel 7.1: Validation Rate

**Purpose**: Historical validation rate over time

**Configuration:**
- **Visualization**: Time series (line graph)
- **Query**: `rate(xrpl_validations_checked_total[5m]) * 60`
- **Unit**: `validations/min`
- **Decimals**: 1

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "short",
      "decimals": 1,
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "smooth",
        "fillOpacity": 20
      }
    }
  }
}
```

---

### Panel 7.2: Consensus Converge Time

**Purpose**: Time taken to reach consensus on each ledger

**Configuration:**
- **Visualization**: Time series (line graph)
- **Query**: `xrpl_consensus_time_seconds`
- **Unit**: `seconds (s)`
- **Decimals**: 2

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "unit": "s",
      "decimals": 2,
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "smooth"
      }
    }
  }
}
```

---

### Panel 7.3: Peer Count Over Time

**Purpose**: Historical peer connection count

**Configuration:**
- **Visualization**: Time series (line graph)
- **Query**: `xrpl_total_peers`
- **Unit**: None
- **Decimals**: 0

**Settings:**
```json
{
  "fieldConfig": {
    "defaults": {
      "decimals": 0,
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "smooth",
        "fillOpacity": 10
      }
    }
  }
}
```

---

## Row 8: System Resources

### Panel 8.1: Basic CPU / Mem / Net / Disk

**Purpose**: Combined system resource metrics

**Configuration:**
- **Visualization**: Time series (multi-line)
- **Queries**:
  - CPU: `xrpl_cpu_load_percent`
  - Memory: `xrpl_memory_usage_percent`
  - Network: `rate(xrpl_network_tcp_rx_bytes[1m]) + rate(xrpl_network_tcp_tx_bytes[1m])`
  - Disk: `xrpl_disk_usage_percent`
- **Unit**: `percent (0-100)` for CPU/Mem/Disk, `bytes/sec` for Network
- **Decimals**: 1

**Settings:**
```json
{
  "fieldConfig": {
    "overrides": [
      {
        "matcher": {"id": "byName", "options": "Network"},
        "properties": [
          {"id": "unit", "value": "Bps"}
        ]
      }
    ]
  }
}
```

---

## Appendix A: Quick Reference - All Metrics

### Validator Health
- `xrpl_uptime_seconds` - Validator uptime
- `xrpl_server_state` - Current server state (0-6)
- `xrpl_validation_rate_percent` - Overall validation success rate
- `xrpl_load_factor` - Server load indicator

### Ledger Metrics
- `xrpl_ledger_sequence` - Current ledger number
- `xrpl_ledger_age_seconds` - Age of current ledger
- `rate(xrpl_ledger_sequence[1m]) * 60` - Ledgers per minute
- `xrpl_ledger_db_size_bytes` - Ledger database size
- `xrpl_nudb_size_bytes` - NuDB database size

### Validation Performance
- `xrpl_agreement_rate_1h_percent` - 1-hour agreement rate
- `xrpl_agreement_rate_24h_percent` - 24-hour agreement rate
- `increase(xrpl_agreements_total[1h])` - Agreements in last hour
- `increase(xrpl_agreements_total[24h])` - Agreements in last 24 hours
- `increase(xrpl_missed_total[1h])` - Missed in last hour
- `increase(xrpl_missed_total[24h])` - Missed in last 24 hours
- `xrpl_validations_checked_total` - Total validations checked

### Network & Peers
- `xrpl_total_peers` - Total connected peers
- `xrpl_inbound_peers` - Inbound peer connections
- `xrpl_outbound_peers` - Outbound peer connections
- `xrpl_insane_peers` - Problematic peers
- `xrpl_peer_latency_p90_milliseconds` - P90 peer latency
- `rate(xrpl_peer_disconnects_total[5m])` - Peer disconnect rate
- `rate(xrpl_network_tcp_rx_bytes[1m])` - Network receive rate
- `rate(xrpl_network_tcp_tx_bytes[1m])` - Network transmit rate

### Consensus
- `xrpl_proposers` - Number of proposing validators
- `xrpl_quorum` - Validation quorum size
- `xrpl_consensus_time_seconds` - Time to reach consensus

### System Resources
- `xrpl_cpu_load_percent` - CPU usage percentage
- `xrpl_memory_usage_percent` - Memory usage percentage
- `xrpl_disk_usage_percent` - Disk usage percentage
- `xrpl_io_latency_milliseconds` - Disk I/O latency

### Transaction Processing
- `xrpl_transaction_rate` - Current transaction rate
- `xrpl_job_queue` - Jobs waiting in queue

### Network Fees
- `xrpl_base_fee_xrp` - Base transaction fee
- `xrpl_reserve_base_xrp` - Base account reserve
- `xrpl_reserve_inc_xrp` - Owner reserve increment

### Monitor Metadata
- `xrpl_initial_sync_duration_seconds` - Initial sync duration
- `xrpl_state_changes_total` - Total state changes
- `xrpl_alerts_total` - Total alerts triggered

---

## Appendix B: Panel Creation Quick Guide

### Creating a Stat Panel

1. Click **Add** → **Visualization**
2. Select **Stat** as visualization type
3. In **Query** tab:
   - Enter PromQL query
   - Set metric browser to Prometheus data source
4. In **Panel options**:
   - Set **Title**
   - Set **Description**
5. In **Standard options**:
   - Set **Unit**
   - Set **Decimals**
   - Configure **Min/Max** if needed
6. In **Thresholds**:
   - Add threshold steps with values and colors
7. In **Value mappings** (if needed):
   - Map numeric values to text
8. Enable **Graph mode** for sparklines (optional)
9. Click **Apply**

### Creating a Gauge Panel

1. Click **Add** → **Visualization**
2. Select **Gauge** as visualization type
3. Follow steps 3-7 from Stat panel above
4. In **Gauge** options:
   - Set **Min** and **Max** values
   - Choose **Orientation** (auto/horizontal/vertical)
   - Toggle **Show threshold labels**
   - Toggle **Show threshold markers**
5. Click **Apply**

### Creating a Time Series Panel

1. Click **Add** → **Visualization**
2. Select **Time series** as visualization type
3. In **Query** tab:
   - Enter PromQL query (or multiple queries)
4. In **Panel options**:
   - Set **Title** and **Description**
5. In **Standard options**:
   - Set **Unit** and **Decimals**
6. In **Graph styles**:
   - Set **Style** (lines/bars/points)
   - Set **Line interpolation** (linear/smooth/step)
   - Set **Fill opacity** (0-100)
   - Enable **Stacking** if needed
7. In **Legend**:
   - Set **Display mode** (list/table/hidden)
   - Set **Placement** (bottom/right)
8. Click **Apply**

---

## Appendix C: Troubleshooting Missing Panels

### Panel Shows "No Data"

**Possible causes:**
1. **xrpl-monitor service not running**
   ```bash
   sudo systemctl status xrpl-monitor
   sudo systemctl start xrpl-monitor
   ```

2. **Prometheus not scraping metrics**
   - Check Prometheus targets: http://localhost:9090/targets
   - Verify scrape config includes `localhost:9091`

3. **Metric name incorrect**
   - Check available metrics: `curl http://localhost:9091/metrics`
   - Verify spelling in query

4. **Time range issue**
   - Check dashboard time range (top right)
   - Ensure validator has been running long enough for historical queries

### Panel Shows Wrong Values

**Possible causes:**
1. **Unit mismatch**
   - Verify unit in panel settings matches metric type
   - Example: Use `s` for seconds, `ms` for milliseconds

2. **Query needs rate()**
   - Counters need `rate()` or `increase()` functions
   - Example: `rate(xrpl_validations_checked_total[5m])`

3. **Decimal places**
   - Adjust **Decimals** in Standard options
   - Use 0 for counts, 1-2 for percentages

### Colors Not Working

**Possible causes:**
1. **Thresholds not configured**
   - Check **Thresholds** section in panel settings
   - Add steps with values and colors

2. **Value mapping overriding colors**
   - Check **Value mappings** section
   - Remove if not needed

### Sparklines Missing

**Enable in Stat panels:**
- Set **Graph mode** to "Area" or "Line" in panel options

---

## Support

For issues or questions about dashboard panels:
- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common problems
- Review [HOW_IT_WORKS.md](HOW_IT_WORKS.md) for architecture details
- Open an issue on GitHub with panel name and screenshot

---

**Document Version**: 1.0  
**Last Updated**: October 18, 2025  
**Dashboard Panels**: 40+  
**Rows**: 8
