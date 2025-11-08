# How It Works

## Introduction

The XRPL Validator Dashboard is a lightweight monitoring system that continuously observes your XRPL validator's health and performance. It collects metrics every 3 seconds, stores them locally, and makes them available for visualization in Grafana.

**Key Design Principles:**
- **Non-invasive**: Read-only access via Docker commands, zero impact on validator
- **Real-time**: 3-second polling captures rapid state transitions
- **Reliable**: SQLite persistence with Prometheus metrics export
- **Self-contained**: All components bundled together
- **Simple**: One wizard to set everything up

---

## System Architecture

```
┌─────────────────────────────────────────────┐
│  XRPL Validator (rippled) - Docker          │
│  Your existing validator container          │
│  Admin API: localhost:5005                  │
└─────────────────────────────────────────────┘
                     │
                     │ docker exec commands
                     │ (server_info, validator_list_sites, peers, etc.)
                     ▼
┌─────────────────────────────────────────────┐
│  XRPL Monitor Service (systemd)             │
│  /usr/bin/python3 fast_poller.py            │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ Polling Loop (every 3 seconds)      │   │
│  │ - Fetch server_info                 │   │
│  │ - Parse state & metrics             │   │
│  │ - Track validation performance      │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ SQLite Database (data/monitor.db)   │   │
│  │ - validator_metrics table           │   │
│  │ - validation_stats table            │   │
│  │ - Historical data storage           │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ Prometheus Exporter (:9094)         │   │
│  │ - Converts metrics to Prometheus    │   │
│  │ - Serves /metrics endpoint          │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
                     │
                     │ HTTP scrape every 5s
                     ▼
┌─────────────────────────────────────────────┐
│  Prometheus (Docker) - Port 9092            │
│  - Scrapes xrpl-monitor:9094                │
│  - Scrapes node-exporter:9100               │
│  - Stores time-series data (30 days)        │
└─────────────────────────────────────────────┘
                     │
                     │ PromQL queries
                     ▼
┌─────────────────────────────────────────────┐
│  Grafana (Docker) - Port 3003               │
│  - Pre-configured dashboard                 │
│  - Real-time visualization                  │
│  - Alert management                         │
└─────────────────────────────────────────────┘
                     │
                     ▼
                  You!
```

---

## Data Flow

### 1. Data Collection (Every 3 Seconds)

The `fast_poller.py` script runs as a systemd service and continuously polls the validator:

```python
while True:
    # Fetch validator state via Docker
    result = docker exec rippledvalidator rippled server_info

    # Parse and extract metrics
    state = result['state']           # proposing, full, syncing, etc.
    ledger_seq = result['ledger_seq'] # Current ledger
    peers = result['peers']           # Peer connections

    # Store in SQLite
    db.insert_metrics(timestamp, state, ledger_seq, peers, ...)

    # Update Prometheus metrics
    prometheus.set_state(state)
    prometheus.set_ledger(ledger_seq)
    prometheus.set_peers(peers)

    # Sleep 3 seconds
    time.sleep(3)
```

### 2. Metrics Export (On Demand)

Prometheus scrapes the `/metrics` endpoint every 5 seconds:

```
# HELP xrpl_validator_state Current validator state (0-6)
# TYPE xrpl_validator_state gauge
xrpl_validator_state{container="rippledvalidator"} 6

# HELP xrpl_ledger_sequence Current validated ledger
# TYPE xrpl_ledger_sequence counter
xrpl_ledger_sequence{container="rippledvalidator"} 87654321

# HELP xrpl_peer_count Total connected peers
# TYPE xrpl_peer_count gauge
xrpl_peer_count{container="rippledvalidator"} 53
```

### 3. Time-Series Storage

Prometheus stores these metrics with timestamps:

```
xrpl_validator_state{...} 6 @1699392000
xrpl_validator_state{...} 6 @1699392005
xrpl_validator_state{...} 4 @1699392010  # State changed!
xrpl_validator_state{...} 6 @1699392015  # Back to proposing
```

### 4. Visualization

Grafana queries Prometheus using PromQL:

```promql
# Show current state
xrpl_validator_state

# State over time
xrpl_validator_state[1h]

# Agreement rate (24h)
rate(xrpl_validations_agreed_total[24h]) / rate(xrpl_validations_total[24h]) * 100

# Peer count trend
avg_over_time(xrpl_peer_count[5m])
```

---

## Component Details

### XRPL Monitor Service

**Location**: `/home/grapedrop/projects/xrpl-validator-dashboard/src/collectors/fast_poller.py`

**Service file**: `/etc/systemd/system/xrpl-validator-dashboard.service`

**What it does**:
1. Connects to rippled via Docker exec
2. Polls every 3 seconds for real-time state tracking
3. Stores raw data in SQLite for historical analysis
4. Exports formatted metrics for Prometheus
5. Runs continuously as a background service

**Key Metrics Collected**:
- **State**: disconnected, connected, syncing, tracking, full, validating, proposing
- **Ledger**: Sequence number, age, close times
- **Validation**: Agreement rate, misses, participation
- **Peers**: Count, inbound/outbound, latency
- **Performance**: Load factor, I/O latency, convergence time
- **System**: CPU, memory, disk usage (from node-exporter)

### SQLite Database

**Location**: `data/monitor.db`

**Tables**:
- `validator_metrics` - Time-series data (one row every 3 seconds)
- `validation_stats` - Aggregated validation performance
- `state_transitions` - State change events

**Purpose**:
- Persistent storage survives restarts
- Historical analysis and debugging
- Backup if Prometheus data is lost
- Raw data for custom queries

### Prometheus

**Configuration**: `compose/prometheus/prometheus.yml`

**Scrape targets**:
- `xrpl-monitor` (port 9094) - Validator metrics
- `node-exporter` (port 9100) - System metrics
- `prometheus` (port 9090) - Self-monitoring

**Retention**: 30 days (configurable in docker-compose.yml)

### Grafana

**Dashboard**: Auto-imported during setup

**Features**:
- Pre-configured panels for all key metrics
- Template variables for dynamic filtering
- Auto-refresh every 5 seconds
- Alert rules for critical events

---

## Setup Process

The `setup.py` wizard automates everything:

### Phase 1: Prerequisites
```
✓ Check Python 3.6+
✓ Check Docker
✓ Check Docker Compose
✓ Check pip3
```

### Phase 2: Validator Detection
```
✓ Scan for rippled containers
✓ Test connectivity (docker exec)
✓ Verify API access
✓ Extract validator info
```

### Phase 3: Port Configuration
```
✓ Check port 3003 (Grafana)
✓ Check port 9092 (Prometheus)
✓ Check port 9102 (Node Exporter)
✓ Check port 9094 (Monitor)
✓ Suggest alternatives if conflicts
```

### Phase 4: Installation
```
✓ Install Python dependencies (pip3)
✓ Generate config.yaml
✓ Update docker-compose.yml ports
✓ Update Prometheus scrape config
```

### Phase 5: Deployment (Optional)
```
✓ Start Docker services (docker compose up -d)
✓ Create systemd service file
✓ Start monitor service
✓ Import Grafana dashboard
✓ Set dashboard as home page
✓ Configure template variables
```

---

## State Tracking

### Validator States

The monitor tracks 7 possible states:

| State | Value | Color | Meaning |
|-------|-------|-------|---------|
| disconnected | 0 | Red | Cannot connect to validator |
| connected | 1 | Yellow | Connected but not synced |
| syncing | 2 | Orange | Downloading ledger history |
| tracking | 3 | Blue | Following consensus |
| full | 4 | Light Green | Fully synced |
| validating | 5 | Green | Participating in consensus |
| proposing | 6 | Dark Green | Actively proposing (ideal) |

### State Transitions

The monitor detects state changes:

```
2025-11-07 19:30:00 | proposing → full (network issue)
2025-11-07 19:30:15 | full → proposing (recovered)
2025-11-07 19:35:00 | proposing → syncing (restart)
2025-11-07 19:35:45 | syncing → tracking
2025-11-07 19:35:50 | tracking → full
2025-11-07 19:35:55 | full → proposing (healthy)
```

Fast polling (3s) ensures quick transitions are caught.

---

## Validation Tracking

### How Validations Work

1. Validator proposes a ledger
2. UNL validators vote on the proposal
3. Agreement reached when ≥80% agree
4. Ledger is validated

### What We Track

**Agreement Rate**: Percentage of validations where your validator agreed with consensus

```
Agreement Rate = (Agreed Validations / Total Validations) × 100
```

**Target**: >95% agreement rate indicates healthy participation

**Misses**: Validations where your validator didn't participate or disagreed

**Checked**: Total validations your validator evaluated

### Time Windows

- **1-hour rate**: Recent performance (rolling window)
- **24-hour rate**: Long-term trend

---

## Performance Monitoring

### System Metrics (Node Exporter)

- **CPU**: User, system, idle, wait percentages
- **Memory**: Used, free, cached, swap usage
- **Disk**: Read/write IOPS, latency, usage percentage
- **Network**: Bytes sent/received, packet rates

### Validator Metrics (XRPL Monitor)

- **Load Factor**: Server load (target: 1.0)
- **I/O Latency**: Database performance
- **Consensus Time**: How long to reach consensus
- **Queue Depth**: Transaction backlog

---

## Cleanup Process

The `cleanup.sh` script reverses the setup:

```bash
./cleanup.sh
```

**Steps**:
1. Stop systemd service
2. Disable service autostart
3. Remove service file
4. Stop Docker containers
5. Optionally remove volumes (Prometheus/Grafana data)
6. Optionally remove database and logs
7. Wait for ports to release (15 seconds)

**Safe defaults**: Prompts before destructive operations

---

## Troubleshooting

### Monitor Not Collecting Data

**Check service status**:
```bash
sudo systemctl status xrpl-validator-dashboard
sudo journalctl -u xrpl-validator-dashboard -f
```

**Common issues**:
- Rippled container not running
- Wrong container name in config.yaml
- Permissions issue (run as same user as Docker)

### Metrics Not in Grafana

**Check Prometheus targets**:
```bash
# Visit http://localhost:9092/targets
# xrpl-monitor should show "UP"
```

**Check metrics endpoint**:
```bash
curl http://localhost:9094/metrics | grep xrpl
```

**Common issues**:
- Monitor service not running
- Firewall blocking port 9094
- Wrong Prometheus scrape config

### Dashboard Variables Empty

The setup wizard automatically configures variables. If manually importing:

1. Check nodename matches actual container hostname
2. Verify instance port matches node-exporter (9102)
3. Refresh dashboard (Ctrl+R or dashboard settings)

---

## Advanced Topics

### Custom Metrics

Add new metrics to `src/collectors/fast_poller.py`:

```python
# In collect_metrics():
custom_value = extract_custom_metric(server_info)

# In prometheus exporter:
prometheus_client.Gauge('xrpl_custom_metric', 'Description')
gauge.set(custom_value)
```

### Database Queries

Query SQLite directly:

```bash
sqlite3 data/monitor.db

# Recent states
SELECT datetime(timestamp, 'unixepoch'), server_state
FROM validator_metrics
ORDER BY timestamp DESC
LIMIT 10;

# Validation stats
SELECT * FROM validation_stats
WHERE timestamp > strftime('%s', 'now', '-1 day');
```

### Alert Rules

Configure Grafana alerts:

1. Edit dashboard panel
2. Add alert rule
3. Set condition (e.g., `xrpl_validator_state != 6` for >5 minutes)
4. Configure notification channel
5. Save

---

## Performance Considerations

### Polling Interval

**Default**: 3 seconds

**Trade-offs**:
- **Faster (1-2s)**: Catches every state change, higher CPU usage
- **Slower (5-10s)**: Misses quick transitions, lower resource usage

**Recommendation**: Keep at 3s for validators, increase to 5s for observers

### Database Size

**Growth rate**: ~100 MB per year

**Management**:
```bash
# Check size
ls -lh data/monitor.db

# Vacuum to reclaim space
sqlite3 data/monitor.db "VACUUM;"

# Delete old data (optional)
sqlite3 data/monitor.db "DELETE FROM validator_metrics WHERE timestamp < strftime('%s', 'now', '-30 days');"
```

### Prometheus Retention

**Default**: 30 days

**Adjust in docker-compose.yml**:
```yaml
--storage.tsdb.retention.time=7d   # Lower for less disk usage
--storage.tsdb.retention.time=90d  # Higher for more history
```

---

## Security

**Read-only access**: Monitor only reads data, never modifies validator

**No network exposure**: All services bind to localhost only

**Docker socket**: Uses Docker exec, doesn't require Docker socket access

**Systemd isolation**: Service runs with limited privileges

---

## Summary

The XRPL Validator Dashboard works through a simple pipeline:

1. **Collect** - Poll validator every 3 seconds via Docker
2. **Store** - Save to SQLite and export to Prometheus
3. **Visualize** - Display in Grafana dashboard
4. **Alert** - Notify on critical events

All managed by:
- **setup.py** - One-command installation
- **systemd** - Automatic background operation
- **cleanup.sh** - Clean removal

For more details, see [README.md](README.md) and [GRAFANA_DASHBOARD.md](GRAFANA_DASHBOARD.md).
