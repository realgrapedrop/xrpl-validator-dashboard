# How It Works

## Introduction

The XRPL Validator Dashboard is a lightweight monitoring system that continuously observes your XRPL validator's health and performance. It collects metrics every 5 seconds and exports them to Prometheus for real-time visualization in Grafana.

**Key Design Principles:**
- **Non-invasive**: Read-only access via Docker exec or HTTP JSON-RPC, zero impact on validator
- **Real-time**: 3-second polling captures rapid state transitions
- **Hybrid Architecture**: systemd monitor (efficient) + Docker infrastructure (easy management)
- **Flexible**: Supports both Docker and Native rippled installations
- **Auto-configured**: Installer detects available ports and rippled setup

---

## System Architecture

The dashboard uses a hybrid architecture:
- **XRPL Monitor:** systemd service (native Python process for efficiency)
- **Infrastructure:** Docker containers (Prometheus, Grafana, Node Exporter)

### Docker Mode Architecture

```
┌──────────────────────────────────────────────┐
│  XRPL Validator (rippled)                    │
│  Docker container                            │
│  Container: rippled                          │
└──────────────────────────────────────────────┘
                     │
                     │ docker exec commands
                     │ (server_info, server_state, etc.)
                     │
                     ▼
┌──────────────────────────────────────────────┐
│  XRPL Monitor (systemd service)              │
│  Service: xrpl-monitor.service               │
│  Port: 9094                                  │
│                                              │
│  Every 3 seconds:                            │
│  1. Poll rippled via docker exec             │
│  2. Parse JSON response                      │
│  3. Update Prometheus metrics                │
│  4. Expose /metrics endpoint                 │
└──────────────────────────────────────────────┘
                     │
                     │ HTTP scrape every 5s
                     ▼
┌──────────────────────────────────────────────┐
│  Prometheus (Docker container)               │
│  network_mode: host                          │
│  Port: 9090-9092 (auto-detected)             │
│  - Scrapes xrpl-monitor on localhost:9094   │
│  - Scrapes node-exporter on localhost:9100  │
│  - 15-day time-series retention              │
└──────────────────────────────────────────────┘
                     │
                     │ PromQL queries
                     ▼
┌──────────────────────────────────────────────┐
│  Grafana (Docker container)                  │
│  network_mode: host                          │
│  Port: 3001-3003 (auto-detected)             │
│  - Pre-configured dashboard                  │
│  - Real-time visualization                   │
│  - Auto-imports on startup                   │
└──────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────┐
│  Node Exporter (Docker container)            │
│  network_mode: host                          │
│  Port: 9100-9102 (auto-detected)             │
│  - System metrics (CPU, RAM, Disk, Network)  │
└──────────────────────────────────────────────┘
                     │
                     ▼
                    You!
```

### Native Mode Architecture

```
┌──────────────────────────────────────────────┐
│  XRPL Validator (rippled)                    │
│  Native installation                         │
│  HTTP JSON-RPC: http://127.0.0.1:5005        │
└──────────────────────────────────────────────┘
                     │
                     │ HTTP JSON-RPC calls
                     │ (server_info, server_state, etc.)
                     │
                     ▼
┌──────────────────────────────────────────────┐
│  XRPL Monitor (systemd service)              │
│  Service: xrpl-monitor.service               │
│  Port: 9094                                  │
│                                              │
│  Every 3 seconds:                            │
│  1. Poll rippled via HTTP JSON-RPC           │
│  2. Parse JSON response                      │
│  3. Update Prometheus metrics                │
│  4. Expose /metrics endpoint                 │
└──────────────────────────────────────────────┘
                     │
                     │ (rest of stack same as Docker mode)
                     ▼
                 [Prometheus → Grafana → Node Exporter]
```

**Key Difference:** Docker mode uses `docker exec` commands, Native mode uses HTTP JSON-RPC API.

**Why Hybrid Architecture?**
- **systemd monitor:** Lower resource overhead (0.1% CPU, 30 MB RAM), better logging (journalctl), native process management
- **Docker infrastructure:** Easy deployment and updates for Prometheus/Grafana stack
- **Host networking:** Docker containers use `network_mode: "host"` to bypass Docker bridge networking, avoiding firewall issues (critical on Oracle Cloud Infrastructure)

**Port Auto-Detection:**
- Installer scans for available ports in ranges (e.g., 3001-3003 for Grafana)
- If default port is in use, next available port is selected
- Ports are configurable via environment variables

---

## The Monitoring Loop

### What Happens Every 5 Seconds

```python
# Simplified view of the monitor's main loop

while True:
    # 1. Poll rippled (Docker or Native)
    if mode == 'docker':
        state_info = docker_exec_command('rippled server_info')
    else:  # native
        state_info = http_post('http://127.0.0.1:5005', {'method': 'server_info'})

    # 2. Extract metrics
    server_state = state_info['server_state']      # proposing, full, etc.
    ledger_seq = state_info['validated_ledger']['seq']
    peers = state_info['peers']
    load_factor = state_info['load_factor']
    # ... 50+ more metrics

    # 3. Update Prometheus gauges
    prometheus.set_state(server_state)
    prometheus.set_ledger(ledger_seq)
    prometheus.set_peers(peers)
    prometheus.set_load_factor(load_factor)
    # ... all metrics

    # 4. Check for state changes
    if server_state != previous_state:
        log_state_transition(previous_state, server_state)
        prometheus.increment_state_changes_counter()

    # 5. Track uptime and health
    prometheus.set_uptime(time_since_start)
    prometheus.set_last_poll_success(now())

    # 6. Sleep
    sleep(5 seconds)
```

---

## Data Storage Strategy

### Prometheus Time-Series Storage

The dashboard uses **Prometheus exclusively** for all metrics storage:

**Why Prometheus:**
- ✅ **Time-series optimized** - Designed for metrics storage
- ✅ **Industry standard** - Works with existing tools and alerting
- ✅ **PromQL queries** - Powerful query language for Grafana
- ✅ **Automatic retention** - Configurable data retention (default: 15 days)
- ✅ **Efficient scraping** - Pull-based model, no network overhead
- ✅ **Native dashboards** - Direct integration with Grafana

**Data Retention:**
- Default: 15 days of metrics history
- Configurable via `--storage.tsdb.retention.time` flag
- Automatic cleanup of old data

**Metric Types:**
```
Gauges:    Current state values (server_state, peers, load_factor)
           Updated every 5 seconds

Counters:  Cumulative counts (state_changes, validations_checked)
           Monotonically increasing, reset on restart

Histograms: Distribution of values (peer_latency, consensus_time)
            P50, P90, P95, P99 percentiles
```

---

## Data Flow

### From rippled to Dashboard

```
1. XRPL Monitor polls rippled
   Docker Mode:
   └─> docker exec rippled rippled server_info

   Native Mode:
   └─> HTTP POST http://127.0.0.1:5005
       Body: {"method": "server_info", "params": [{}]}

2. Parse JSON response
   └─> Extract 50+ metrics from server_info, server_state, peers, etc.

3. Update Prometheus metrics in-memory
   └─> xrpl_server_state.set(6)           # State: proposing
   └─> xrpl_total_peers.set(53)           # 53 connected peers
   └─> xrpl_ledger_sequence.set(85000000) # Current ledger
   └─> ... all metrics updated

4. Prometheus scrapes monitor
   └─> HTTP GET http://localhost:9094/metrics (every 5 seconds)
   └─> Receives metrics in Prometheus exposition format:
       # TYPE xrpl_server_state gauge
       xrpl_server_state 6
       # TYPE xrpl_total_peers gauge
       xrpl_total_peers 53

5. Prometheus stores time-series data
   └─> Appends to TSDB (time-series database)
   └─> Maintains 15 days of history by default

6. Grafana queries Prometheus
   └─> PromQL: xrpl_server_state
   └─> PromQL: rate(xrpl_ledger_sequence[1m]) * 60
   └─> Renders graphs and panels in real-time

7. User views dashboard
   └─> Browser: http://localhost:<grafana_port>
   └─> Dashboard updates automatically every 5-30 seconds
```

---

## Metrics Collected

### Every 5 Seconds

**Validator State:**
- Server state (proposing, full, syncing, tracking, connected, disconnected)
- Uptime since last restart
- State change counter

**Ledger:**
- Validated ledger sequence
- Ledger age (seconds since last ledger)
- Base fee, reserves (XRP)
- Ledgers per minute (calculated)

**Validation (Validators only):**
- Validation quorum size
- Proposer count
- Agreement percentage

**Network & Peers:**
- Total peers (inbound + outbound)
- Inbound peer count
- Outbound peer count
- Peer latency (P50, P90, P95, P99)
- Peer disconnects counter

**Performance:**
- Load factor (1 = normal, >1 = high load)
- I/O latency (milliseconds)
- Consensus convergence time
- Job queue depth

**System Resources (from Node Exporter):**
- CPU usage percentage
- Memory usage (total, used, free)
- Disk usage (total, used, free)
- Network traffic (rx/tx bytes)

**Transactions:**
- Transaction rate (transactions/second)
- Queue depth

**Database:**
- Ledger DB size (bytes)
- Transaction DB size (bytes)
- NuDB size (bytes)

### Calculated via PromQL

Grafana dashboards calculate additional metrics using Prometheus queries:

**Ledgers per Minute:**
```promql
rate(xrpl_ledger_sequence[1m]) * 60
```

**Network Throughput:**
```promql
rate(xrpl_network_tcp_rx_bytes[1m]) + rate(xrpl_network_tcp_tx_bytes[1m])
```

**Validation Rate:**
```promql
rate(xrpl_validations_checked_total[5m]) * 60
```

---

## Service Management

### XRPL Monitor (systemd service)

The XRPL Monitor runs as a systemd service for efficiency and native integration.

**Check Status:**
```bash
# View service status
systemctl status xrpl-monitor.service

# Check if service is active
systemctl is-active xrpl-monitor
```

**View Logs:**
```bash
# Monitor logs (follow mode)
journalctl -u xrpl-monitor.service -f

# View last 100 lines
journalctl -u xrpl-monitor.service -n 100

# View logs since today
journalctl -u xrpl-monitor.service --since today
```

**Restart Service:**
```bash
# Restart monitor
sudo systemctl restart xrpl-monitor.service

# Stop monitor
sudo systemctl stop xrpl-monitor.service

# Start monitor
sudo systemctl start xrpl-monitor.service
```

**Service Configuration:**
- **Auto-restart policy**: Automatic restart on failure
- **Start on boot**: Enabled by default
- **User**: Runs as system user (not root)
- **Logs**: Managed by systemd journal (journalctl)

### Docker Container Management

Infrastructure components run as Docker containers managed by Docker Compose.

**Container Names:**
- `xrpl-dashboard-prometheus` - Metrics storage
- `xrpl-dashboard-grafana` - Dashboard UI
- `xrpl-dashboard-node-exporter` - System metrics

**Check Status:**
```bash
# View all containers
docker ps

# View specific container
docker ps | grep xrpl-dashboard
```

**View Logs:**
```bash
# View Grafana logs
docker logs -f xrpl-dashboard-grafana

# View Prometheus logs
docker logs -f xrpl-dashboard-prometheus

# View Node Exporter logs
docker logs -f xrpl-dashboard-node-exporter
```

**Restart Services:**
```bash
# Restart specific container
docker restart xrpl-dashboard-grafana

# Restart all Docker containers
docker compose restart

# Stop all
docker compose down

# Start all
docker compose up -d
```

**Container Configuration:**
- **Auto-restart policy**: `unless-stopped` (restart on failure, but not if manually stopped)
- **Network mode**: `host` (all containers use host networking)
- **Resource limits**: None by default (can be configured in docker-compose.yml)
- **Logs**: Managed by Docker (use `docker logs` to view)

---

## Performance

### Resource Usage

| Component | CPU | Memory | Disk I/O | Network |
|-----------|-----|--------|----------|---------|
| XRPL Monitor (systemd) | 0.1% | 30 MB (RSS) | minimal | 10 KB/s |
| Prometheus (Docker) | 0.3-0.5% | 150-200 MB | 10-20 KB/s | 5 KB/s |
| Grafana (Docker) | 0.2-0.4% | 100-150 MB | minimal | 5 KB/s |
| Node Exporter (Docker) | 0.1% | 10-20 MB | minimal | 2 KB/s |
| **Total** | **~0.7-1.1%** | **~290-400 MB** | **~10-20 KB/s** | **~22 KB/s** |

**Validator impact:** Effectively zero - all monitoring is read-only

### Data Growth

- **Prometheus TSDB:** ~500 MB - 2 GB for 15 days retention (depends on metrics cardinality)
- **Grafana:** ~50-100 MB (dashboard configs and user data)
- **Docker logs:** Managed by Docker log rotation (default: 10 MB max per container)

---

## Configuration

### config.yml

Generated by the installer (`./install.sh`):

```yaml
rippled:
  mode: docker                  # or 'native'
  container_name: rippled       # Docker mode only
  host: 127.0.0.1              # Native mode only
  port: 5005                    # Native mode only

monitoring:
  poll_interval: 5              # Seconds between polls

prometheus:
  enabled: true
  port: 9094                    # Metrics export port
  host: 0.0.0.0                 # Bind to all interfaces

logging:
  level: INFO
```

### Environment Variable Overrides

Configuration can be overridden using environment variables:

```bash
# Override rippled connection
XRPL_RIPPLED_MODE=native
XRPL_RIPPLED_HOST=127.0.0.1
XRPL_RIPPLED_PORT=5005

# Override Prometheus port
XRPL_PROMETHEUS_PORT=9095

# Set log level
XRPL_LOGGING_LEVEL=DEBUG
```

Format: `XRPL_<SECTION>_<KEY>=<value>`

---

## Error Handling

**rippled Unreachable:**
- Monitor continues running
- Retries connection every 5 seconds
- Metrics show last known state
- Auto-recovers when rippled returns

**Docker Container Crash:**
- Docker auto-restarts containers (policy: `unless-stopped`)
- Prometheus data preserved in Docker volume
- Monitor rebuilds metrics on startup
- No data loss for historical metrics in Prometheus TSDB

**Network Issues:**
- Host networking bypasses Docker bridge (fewer failure points)
- Monitor uses localhost for all connections (no external network needed)
- Graceful degradation (continues monitoring even if some endpoints fail)

**Configuration Errors:**
- Monitor logs errors clearly with troubleshooting hints
- Environment variable validation on startup
- Fallback to defaults when possible

---

## Summary

The XRPL Validator Dashboard is a **containerized monitoring solution** that:

1. **Polls** rippled every 5 seconds (Docker exec or HTTP JSON-RPC)
2. **Updates** Prometheus metrics in real-time
3. **Stores** 15 days of time-series data in Prometheus TSDB
4. **Visualizes** via Grafana dashboards with auto-refresh

**Key Benefits:**
- **Flexible**: Supports both Docker and Native rippled installations
- **Containerized**: All components in Docker, easy deployment
- **Auto-configured**: Installer detects ports and rippled setup
- **Zero impact**: Read-only monitoring, no validator changes
- **Industry standard**: Uses Prometheus and Grafana ecosystem
- **Host networking**: Avoids firewall issues (especially on OCI)

**Components:**
- XRPL Monitor (custom Python exporter)
- Prometheus (time-series database)
- Grafana (visualization dashboards)
- Node Exporter (system metrics)

**Latency:** <10 seconds typical from rippled state change to dashboard update

For more details, see:
- [README.md](../README.md) - Quick start and overview
- [INSTALL.md](INSTALL.md) - Detailed installation guide
- [GRAFANA_DASHBOARD.md](GRAFANA_DASHBOARD.md) - Dashboard panel reference
