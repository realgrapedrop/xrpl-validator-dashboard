# XRPL Monitor - Python Source Code

Technical documentation for the Python monitoring service that powers XRPL validator metrics collection and export.

## Overview

This is a custom Python-based monitoring service that:
- Polls rippled validator every 3 seconds via RPC API
- Tracks state transitions and validation performance
- Stores historical data in SQLite database
- Exports metrics to Prometheus on port 9091
- Runs as a systemd service for reliability

**Deployment:** Automatically installed by `install.sh` script - no manual setup required.

## Architecture

### Component Flow

```
┌────────────────────────────────────────────────────────────┐
│                    XRPL Monitor Service                    │
│                  (fast_poller.py - main loop)              │
│                                                            │
│  ┌──────────────┐    ┌──────────────┐    ┌─────────────┐   │
│  │ RippledAPI   │───→│   Database   │───→│  Prometheus │   │
│  │ (Docker/Native)   │   (SQLite)   │    │  Exporter   │   │
│  └──────────────┘    └──────────────┘    └─────────────┘   │
│         ↓                    ↓                    ↓        │
│  ┌──────────────┐    ┌──────────────┐    ┌─────────────┐   │
│  │ Validation   │    │   Alerter    │    │  HTTP :9091 │   │
│  │   Tracker    │    │              │    │             │   │
│  └──────────────┘    └──────────────┘    └─────────────┘   │
└────────────────────────────────────────────────────────────┘
                                 │
                                 ↓
                        ┌────────────────┐
                        │   Prometheus   │
                        │  (scrapes 9091)│
                        └────────────────┘
                                 │
                                 ↓
                        ┌────────────────┐
                        │    Grafana     │
                        │   (visualizes) │
                        └────────────────┘
```

## Directory Structure

```
src/
├── __init__.py                    # Package initialization
├── alerts/                        # Alert system
│   ├── __init__.py
│   └── alerter.py                # Alert logic and notifications
├── collectors/                    # Data collection modules
│   ├── __init__.py
│   ├── fast_poller.py            # Main polling loop (entry point)
│   └── validation_tracker.py    # Tracks validation performance
├── exporters/                     # Metrics export
│   ├── __init__.py
│   └── prometheus_exporter.py   # Prometheus HTTP endpoint
├── storage/                       # Data persistence
│   ├── __init__.py
│   └── database.py               # SQLite database wrapper
├── utils/                         # Utility modules
│   ├── __init__.py
│   ├── config.py                 # Configuration management
│   └── rippled_api.py            # rippled RPC API client
├── outputs/                       # Future: Additional output plugins
│   └── __init__.py
└── processors/                    # Future: Data processing pipelines
    └── __init__.py
```

## Key Components

### 1. fast_poller.py - Main Entry Point

**Purpose:** Main monitoring loop that orchestrates all components

**How it works:**
1. Initializes all components (API, database, exporter, alerter)
2. Polls rippled every 3 seconds
3. Extracts metrics from server_info response
4. Updates database with timestamped data
5. Exports to Prometheus
6. Sends alerts on state changes
7. Repeat forever (or until stopped)

**Key methods:**
- `poll()` - Single poll cycle
- `_update_server_info()` - Gets static server info once at startup
- `run()` - Main loop

**Entry point:** `main()` function called by systemd service

**Resource usage:**
- Memory: ~50-100MB
- CPU: <1% (mostly idle, spikes during poll)
- Disk: Database grows ~100MB/year

### 2. rippled_api.py - API Client

**Purpose:** Abstraction layer for communicating with rippled

**Supports both:**
- **Docker deployments**: Uses `docker exec` to run commands
- **Native deployments**: Direct HTTP calls to localhost:5005

**Key methods:**
- `get_server_state()` - Full server info including state, peers, ledger
- `get_validation_info()` - Validation performance metrics
- `get_peers()` - Peer connection details
- `_call(command, params)` - Low-level RPC call wrapper

**Error handling:**
- Timeout after 10 seconds
- Retries with exponential backoff
- Returns None on failure (logged but doesn't crash)

**Example usage:**
```python
api = RippledAPI(container_name='rippledvalidator')
state = api.get_server_state()
if state:
    print(f"Current state: {state['server_state']}")
```

### 3. prometheus_exporter.py - Metrics Export

**Purpose:** Exposes metrics via HTTP endpoint for Prometheus scraping

**Metrics types used:**
- **Gauge**: Current values (state, peer count, ledger sequence)
- **Counter**: Cumulative counts (validations checked, state changes)
- **Info**: String metadata (validator pubkey, state labels)

**Key metrics exported:**

| Metric Name | Type | Description |
|------------|------|-------------|
| `xrpl_validator_state_value` | Gauge | Numeric state: 0-6 |
| `xrpl_validator_state` | Info | State as string label |
| `xrpl_time_in_current_state_seconds` | Gauge | Time in current state |
| `xrpl_ledger_sequence` | Gauge | Current ledger number |
| `xrpl_ledger_age_seconds` | Gauge | Age of last ledger |
| `xrpl_peer_count` | Gauge | Total connected peers |
| `xrpl_peers_inbound` | Gauge | Inbound peer connections |
| `xrpl_peers_outbound` | Gauge | Outbound peer connections |
| `xrpl_peer_latency_p90_ms` | Gauge | 90th percentile peer RTT |
| `xrpl_load_factor` | Gauge | Server load factor |
| `xrpl_validation_rate` | Gauge | Validation participation rate |
| `xrpl_validations_checked_total` | Counter | Total validations checked |
| `xrpl_state_changes_total` | Counter | Total state transitions |
| `xrpl_api_errors_total` | Counter | Total API errors |

**HTTP endpoint:** http://localhost:9091/metrics

**Example output:**
```
# HELP xrpl_validator_state_value Validator state as numeric value
# TYPE xrpl_validator_state_value gauge
xrpl_validator_state_value 6.0

# HELP xrpl_peer_count Number of connected peers
# TYPE xrpl_peer_count gauge
xrpl_peer_count 21.0

# HELP xrpl_validation_rate Validation participation rate (%)
# TYPE xrpl_validation_rate gauge
xrpl_validation_rate 98.5
```

### 4. database.py - Historical Storage

**Purpose:** Persists metrics to SQLite for historical analysis

**Database schema:**
```sql
CREATE TABLE validator_metrics (
    timestamp INTEGER PRIMARY KEY,  -- Unix epoch seconds
    server_state TEXT,              -- State string (proposing, full, etc)
    ledger_seq INTEGER,             -- Ledger sequence number
    peers INTEGER,                  -- Peer count
    load_factor REAL,               -- Load factor
    uptime INTEGER,                 -- Validator uptime seconds
    ledger_age REAL                 -- Age of current ledger
);
```

**Key features:**
- Auto-creates table on first run
- Atomic writes (temp file + rename)
- Indexes for fast queries
- No retention limit (manual cleanup if needed)

**Useful queries:**
```bash
# Count total records
sqlite3 monitor.db "SELECT COUNT(*) FROM validator_metrics;"

# Recent state history
sqlite3 monitor.db "SELECT datetime(timestamp, 'unixepoch'), server_state FROM validator_metrics ORDER BY timestamp DESC LIMIT 20;"

# Time spent in each state (last 24h)
sqlite3 monitor.db "SELECT server_state, COUNT(*) * 3 as seconds FROM validator_metrics WHERE timestamp > strftime('%s', 'now', '-1 day') GROUP BY server_state;"
```

### 5. validation_tracker.py - Performance Tracking

**Purpose:** Tracks validator participation in consensus

**What it monitors:**
- Validation agreements (successful proposals)
- Validation misses (missed ledgers)
- Agreement rate percentage
- Validation sequence tracking

**Key metrics:**
- 1-hour agreement rate
- 24-hour agreement rate
- Total agreements/misses
- Current validation streak

### 6. alerter.py - Alert System

**Purpose:** Sends alerts on important events

**Alert triggers:**
- State changes (e.g., proposing → full)
- Extended downtime (state != proposing > 5 min)
- Low validation rate (< 95%)
- Peer count drops (< 10 peers)

**Output:**
- Logs to `${INSTALL_DIR}/logs/monitor.log`
- Can be extended for email/Slack/webhook notifications

**Alert format:**
```
[2025-10-15 12:34:56] ALERT: State changed from 'proposing' to 'full'
[2025-10-15 12:35:23] ALERT: State changed from 'full' to 'proposing'
```

### 7. config.py - Configuration

**Purpose:** Centralized configuration management

**Configuration sources (priority order):**
1. Environment variables
2. config.yaml file (if present)
3. Default values

**Key settings:**
```python
monitoring:
  container_name: 'rippledvalidator'  # Docker container name
  poll_interval: 3                    # Seconds between polls
  
database:
  path: '${INSTALL_DIR}/data/monitor.db'
  
prometheus:
  enabled: true
  port: 9091
  host: '0.0.0.0'
```

## Installation & Deployment

### Automatic Installation (Recommended)

The `install.sh` script in the root directory handles everything:

```bash
sudo ./install.sh --monitoring --rippled-type docker
```

**What install.sh does:**
1. ✅ Checks Python 3.8+ is installed
2. ✅ Installs pip dependencies: `pip3 install -r requirements.txt`
3. ✅ Copies entire `src/` directory to installation location
4. ✅ Replaces `${INSTALL_DIR}` placeholders with actual path
5. ✅ Creates systemd service from template
6. ✅ Starts and enables `xrpl-monitor.service`
7. ✅ Verifies service is running and exporting metrics

### Manual Installation (Development)

For development or custom setups:

```bash
# 1. Install dependencies
pip3 install -r requirements.txt

# 2. Set installation directory
export INSTALL_DIR=/path/to/install

# 3. Copy source code
cp -r src/ $INSTALL_DIR/

# 4. Create directories
mkdir -p $INSTALL_DIR/{logs,data}

# 5. Run manually (testing)
python3 $INSTALL_DIR/src/collectors/fast_poller.py

# 6. Create systemd service (production)
# Use systemd/xrpl-monitor.service.template as reference
```

## Service Management

### Systemd Service

**Service file location:** `/etc/systemd/system/xrpl-monitor.service`

**Key service parameters:**
```ini
[Service]
Type=simple
User=<your-user>
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/src/collectors/fast_poller.py
Restart=always
RestartSec=10
MemoryMax=512M
CPUQuota=50%
```

### Common Commands

```bash
# Start service
sudo systemctl start xrpl-monitor

# Stop service
sudo systemctl stop xrpl-monitor

# Restart service
sudo systemctl restart xrpl-monitor

# Enable auto-start on boot
sudo systemctl enable xrpl-monitor

# Disable auto-start
sudo systemctl disable xrpl-monitor

# Check status
sudo systemctl status xrpl-monitor

# View logs (real-time)
sudo journalctl -u xrpl-monitor -f

# View logs (last 100 lines)
sudo journalctl -u xrpl-monitor -n 100

# Check resource usage
systemctl status xrpl-monitor | grep Memory
```

## Development

### Running Tests

```bash
# Unit tests (when implemented)
cd tests/unit
python3 -m pytest

# Integration tests (requires rippled running)
cd tests/integration
python3 test_full_stack.py

# Manual test
python3 src/collectors/fast_poller.py
```

### Adding New Metrics

1. **Add to prometheus_exporter.py:**
```python
# In __init__:
self.my_new_metric = Gauge('xrpl_my_metric', 'Description')

# Add update method:
def update_my_metric(self, value: float):
    self.my_new_metric.set(value)
```

2. **Extract in fast_poller.py:**
```python
# In poll() method:
my_value = state.get('my_field', 0)

# Export to Prometheus:
if self.prometheus:
    self.prometheus.update_my_metric(my_value)
```

3. **Restart service:**
```bash
sudo systemctl restart xrpl-monitor
```

4. **Verify metric appears:**
```bash
curl http://localhost:9091/metrics | grep my_metric
```

### Code Style

**Python (PEP 8):**
- Type hints for all functions
- Docstrings for classes and methods
- Clear variable names (no single letters except loops)
- Error handling with try/except

**Example:**
```python
def get_server_state(self) -> Optional[Dict[str, Any]]:
    """
    Get comprehensive server state from rippled.
    
    Returns:
        Dictionary with server state or None on error
    """
    try:
        result = self._call('server_info')
        return result.get('info', {})
    except RippledAPIError as e:
        self.logger.error(f"Failed to get server state: {e}")
        return None
```

### Debugging

**Enable debug logging:**
```python
# In fast_poller.py, modify logging level:
logging.basicConfig(level=logging.DEBUG)
```

**Run in foreground:**
```bash
# Stop service
sudo systemctl stop xrpl-monitor

# Run manually to see all output
python3 ${INSTALL_DIR}/src/collectors/fast_poller.py
```

**Check database:**
```bash
# View recent records
sqlite3 ${INSTALL_DIR}/data/monitor.db \
  "SELECT datetime(timestamp, 'unixepoch'), * FROM validator_metrics ORDER BY timestamp DESC LIMIT 5;"
```

**Test API connectivity:**
```bash
# Docker rippled
docker exec rippledvalidator rippled server_info

# Native rippled
curl -X POST http://localhost:5005 \
  -H "Content-Type: application/json" \
  -d '{"method":"server_info","params":[]}'
```

## Troubleshooting

### Service Won't Start

**Check logs:**
```bash
sudo journalctl -u xrpl-monitor -n 50 --no-pager
```

**Common issues:**
1. **ModuleNotFoundError**: `pip3 install -r requirements.txt`
2. **Permission denied**: `sudo chown -R $USER:$USER ${INSTALL_DIR}/src`
3. **Connection refused**: Verify rippled is running
4. **Port in use**: Check nothing else uses port 9091

### Metrics Not Updating

**Verify service is running:**
```bash
systemctl is-active xrpl-monitor  # Should return "active"
```

**Check metrics endpoint:**
```bash
curl http://localhost:9091/metrics | head -20
```

**Check database writes:**
```bash
sqlite3 ${INSTALL_DIR}/data/monitor.db \
  "SELECT MAX(timestamp), datetime(MAX(timestamp), 'unixepoch') FROM validator_metrics;"
```

**Check for errors:**
```bash
tail -50 ${INSTALL_DIR}/logs/error.log
```

### High Memory/CPU Usage

**Check resource usage:**
```bash
systemctl status xrpl-monitor | grep -E "Memory|CPU"
```

**Normal usage:**
- Memory: 50-100MB
- CPU: <1% average, spikes to 5-10% during polls

**If higher:**
1. Check for database lock contention
2. Verify rippled API responding quickly
3. Consider increasing poll interval (not recommended)

## Performance

### Benchmarks

On typical hardware (4-core, 8GB RAM):
- Poll time: 20-50ms per cycle
- Database write: 1-5ms per record
- Memory footprint: 50-100MB
- CPU usage: <1% average
- Metrics export: <1ms per scrape

### Optimization Tips

1. **Database:**
   - Index added on timestamp for fast queries
   - Atomic writes prevent corruption
   - Consider periodic cleanup of old data

2. **Polling:**
   - 3-second interval balances freshness vs load
   - Don't decrease below 1 second (unnecessary load)
   - Increase to 5s if rippled API is slow

3. **Metrics:**
   - Prometheus uses pull model (low overhead)
   - Metrics cached in memory, no disk IO per scrape

## Dependencies

**Python version:** 3.8 or higher

**Required packages (requirements.txt):**
```
prometheus-client>=0.19.0
```

**Standard library (no install needed):**
- subprocess (Docker/rippled commands)
- sqlite3 (database)
- json (API parsing)
- datetime (timestamps)
- logging (alerts and debugging)

## Security Considerations

1. **Service runs as non-root user** (specified in systemd service)
2. **Read-only access to rippled** (uses admin API, no write operations)
3. **Metrics endpoint on localhost only** (change in prometheus_exporter.py if needed)
4. **No sensitive data in metrics** (validator pubkey truncated in logs)
5. **Database stored in protected directory** (chmod 700 on ${INSTALL_DIR})

## Contributing

See [../docs/DEVELOPMENT.md](../docs/DEVELOPMENT.md) for full development guide including:
- Architecture overview
- Testing procedures
- Pull request process
- Code review guidelines

## Support

- **Main README**: [../README.md](../README.md)
- **Developer Guide**: [../docs/DEVELOPMENT.md](../docs/DEVELOPMENT.md)
- **Issues**: https://github.com/realGrapedrop/xrpl-validator-monitor-dashboard/issues

## License

MIT License - See [../LICENSE](../LICENSE) file for details.

---

**Last Updated:** October 2025  
**Maintainer:** [Grapedrop](https://xrp-validator.grapedrop.xyz) | [@realGrapedrop](https://x.com/realGrapedrop)
