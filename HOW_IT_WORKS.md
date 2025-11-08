# How It Works

## Introduction

The XRPL Validator Dashboard is a lightweight monitoring system that continuously observes your XRPL validator's health and performance. It collects metrics every 3 seconds, stores them in SQLite for historical analysis, and exports them to Prometheus for real-time visualization in Grafana.

**Key Design Principles:**
- **Non-invasive**: Read-only access via Docker commands, zero impact on validator
- **Real-time**: 3-second polling captures rapid state transitions
- **Dual-storage**: SQLite for persistence, Prometheus for visualization
- **Self-contained**: All components bundled together
- **Simple**: One service doing everything

---

## System Architecture

```
┌─────────────────────────────────────────────┐
│  XRPL Validator (rippled) - Docker          │
│  Your existing validator container          │
│  Admin API: localhost:5005                  │
└─────────────────────────────────────────────┘
                     │
                     │ docker exec commands every 3 seconds
                     │ (server_info, peers, etc.)
                     ▼
┌─────────────────────────────────────────────┐
│  fast_poller.py (systemd service)           │
│  Single Python service doing everything     │
│                                             │
│  Every 3 seconds:                           │
│  1. Poll rippled API                        │
│  2. Parse metrics                           │
│  3. Write to SQLite                         │
│  4. Update Prometheus gauges                │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ SQLite (data/monitor.db)            │   │
│  │ - State transitions                 │   │
│  │ - Validation history                │   │
│  │ - Performance metrics               │   │
│  │ Used for: 24h stats, persistence    │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ Prometheus Exporter (port 9094)     │   │
│  │ - In-memory gauges/counters         │   │
│  │ - HTTP /metrics endpoint            │   │
│  │ Used for: Real-time dashboards      │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
                     │
                     │ HTTP scrape every 5-15s
                     ▼
┌─────────────────────────────────────────────┐
│  Prometheus (Docker) - Port 9092            │
│  - Scrapes :9094/metrics endpoint           │
│  - Scrapes node-exporter:9100 (system)      │
│  - 30-day time-series retention             │
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

## The Monitoring Loop

### What Happens Every 3 Seconds

```python
# Simplified view of fast_poller.py main loop

while True:
    # 1. Poll rippled
    state_info = docker_exec("rippled server_info")

    # 2. Extract metrics
    server_state = state_info['server_state']      # proposing, full, etc.
    ledger_seq = state_info['validated_ledger']['seq']
    peers = state_info['peers']
    load_factor = state_info['load_factor']
    # ... 40+ more metrics

    # 3. Write to SQLite (for history)
    db.write_metrics(
        timestamp=now(),
        server_state=server_state,
        ledger_seq=ledger_seq,
        peers=peers,
        # ... all metrics
    )

    # 4. Update Prometheus (for real-time)
    prometheus.set_state(server_state)
    prometheus.set_ledger(ledger_seq)
    prometheus.set_peers(peers)
    # ... all metrics

    # 5. Check for state changes
    if state changed:
        db.write_state_transition(old, new, duration)
        alerter.notify(state_change)

    # 6. Track validations
    validation_tracker.check_ledger_validation(ledger_seq)

    # 7. Sleep
    sleep(3 seconds)
```

---

## Dual-Write Strategy

### Why Both SQLite AND Prometheus?

**SQLite Database (`data/monitor.db`):**
- ✅ **Persistence** - Data survives service restarts
- ✅ **Historical queries** - Calculate 24-hour agreement rates
- ✅ **Validation tracking** - Ledger-by-ledger validation results
- ✅ **State transitions** - Complete history of state changes
- ✅ **Backup** - Export data if needed

**Prometheus Metrics (in-memory):**
- ✅ **Real-time dashboards** - Instant visualization
- ✅ **PromQL queries** - Powerful query language for Grafana
- ✅ **Industry standard** - Works with existing tools
- ✅ **Efficient scraping** - Optimized for time-series
- ✅ **Alert integration** - Native alerting support

**They complement each other:**
```
SQLite:     Long-term storage, complex queries
            ↓
            Used by: 24h agreement %, validation history

Prometheus: Fast access, standard format
            ↓
            Used by: Real-time graphs, alerts
```

---

## Data Flow

### From rippled to Dashboard

```
1. fast_poller.py polls rippled
   └─> docker exec rippledvalidator rippled server_info

2. Parse JSON response
   └─> Extract 40+ metrics

3. Write to SQLite
   └─> INSERT INTO validator_metrics (...)
   └─> Persistent storage, survives restarts

4. Update Prometheus gauges
   └─> prometheus.set_state(6)
   └─> prometheus.set_peers(53)
   └─> In-memory, fast access

5. Prometheus scrapes
   └─> HTTP GET http://host.docker.internal:9094/metrics
   └─> Every 5-15 seconds

6. Grafana queries Prometheus
   └─> PromQL: xrpl_validator_state
   └─> Renders graphs in real-time

7. User views dashboard
   └─> http://localhost:3003
```

---

## Metrics Collected

### Every 3 Seconds

**Validator State:**
- Server state (proposing, full, syncing, etc.)
- Time in current state
- State transitions

**Ledger:**
- Validated ledger sequence
- Ledger age
- Base fee, reserves

**Validation:**
- Validation quorum
- Proposer count
- Ledger-by-ledger validation tracking

**Network:**
- Total peers
- Peer details (every 10 polls)
- Disconnections

**Performance:**
- Load factor
- I/O latency
- Consensus convergence time

**System:**
- Uptime
- Database sizes (every 60 polls)
- Transaction rate

### Calculated from Database

**24-Hour Agreement Rate:**
```python
# Query SQLite for last 24 hours of validations
stats = db.get_validation_stats_period(hours=24)
rate = (stats['agreed'] / stats['total']) * 100
prometheus.set_validation_agreement_rate_24h(rate)
```

**1-Hour Agreement Rate:**
```python
stats = db.get_validation_stats_period(hours=1)
rate = (stats['agreed'] / stats['total']) * 100
prometheus.set_validation_agreement_rate_1h(rate)
```

---

## Service Management

### Systemd Service

**File:** `/etc/systemd/system/xrpl-validator-dashboard.service`

**What it does:**
- Runs `fast_poller.py` as background service
- Auto-starts on boot
- Auto-restarts on crash (10-second delay)
- Logs to `logs/monitor.log` and `logs/error.log`
- Resource limits: 512MB RAM, 50% CPU

**Commands:**
```bash
# Check status
sudo systemctl status xrpl-validator-dashboard

# View logs
sudo journalctl -u xrpl-validator-dashboard -f

# Restart
sudo systemctl restart xrpl-validator-dashboard
```

---

## Performance

### Resource Usage

| Component | CPU | Memory | Disk I/O | Network |
|-----------|-----|--------|----------|---------|
| fast_poller.py | 0.5% | 30-50 MB | 5 KB/s | 10 KB/s |
| SQLite | - | 50 MB cache | 5 KB/s | - |
| Prometheus | 0.3% | 100 MB | 10 KB/s | 5 KB/s |
| Grafana | 0.2% | 100 MB | minimal | 5 KB/s |
| **Total** | **~1%** | **~280 MB** | **~20 KB/s** | **~20 KB/s** |

**Validator impact:** Effectively zero

### Data Growth

- **SQLite:** ~50-100 MB per month
- **Prometheus:** Auto-managed, 30-day retention
- **Logs:** Unlimited (manual rotation recommended)

---

## Configuration

### config.yaml

Generated by `setup.py`:

```yaml
monitoring:
  poll_interval: 3              # Seconds between polls
  container_name: rippledvalidator

prometheus:
  enabled: true
  port: 9094                    # Metrics export port
  host: 0.0.0.0

database:
  path: ./data/monitor.db       # SQLite database

logging:
  level: INFO
  file: ./logs/monitor.log
```

---

## Error Handling

**rippled Unreachable:**
- Service keeps running
- Retries every 3 seconds
- Alerts after multiple failures

**Database Lock:**
- SQLite WAL mode (Write-Ahead Logging)
- Readers don't block writers
- Concurrent access supported

**Service Crash:**
- Systemd auto-restarts (10-second delay)
- SQLite data preserved
- Prometheus metrics rebuilt on startup

---

## Summary

The XRPL Validator Dashboard uses a **single Python service** (`fast_poller.py`) that:

1. **Polls** rippled every 3 seconds
2. **Writes** to SQLite for persistence and history
3. **Exports** to Prometheus for real-time visualization
4. **Tracks** validations, state changes, and performance

**Key Benefits:**
- Simple architecture (one service does everything)
- Dual-storage strategy (best of both worlds)
- Zero impact on validator performance
- Complete historical record in SQLite
- Real-time dashboards via Prometheus/Grafana

**Latency:** <4 seconds typical from event to dashboard

For more details, see [README.md](README.md) and [GRAFANA_DASHBOARD.md](GRAFANA_DASHBOARD.md).
