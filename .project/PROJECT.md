# XRPL Validator Dashboard - Project Context

## Project Overview

A comprehensive, self-contained monitoring dashboard for XRP Ledger (XRPL) validator nodes with automated setup wizard. This project provides real-time monitoring, historical analysis, and proactive alerting for XRPL validators with minimal overhead (~1% CPU, ~280 MB RAM).

**Purpose**: Enable XRPL validator operators to continuously monitor validator health, catch state transitions instantly, detect validation issues in real-time, and maintain 30-day metric history for troubleshooting.

**Key Features**:
- One-command setup via interactive wizard
- Real-time monitoring with 3-second polling
- Self-contained deployment (Grafana, Prometheus, metrics exporter)
- Pre-built Grafana dashboard with 40+ metrics
- Systemd integration for reliability
- Automatic state change and validation alerts

## Technology Stack

### Core Languages
- **Python 3.6+**: Main monitoring service and setup wizard
  - Standard library only (subprocess, sqlite3, json, datetime, logging)
  - Single external dependency: `prometheus-client>=0.19.0`

### Infrastructure
- **Docker & Docker Compose v2.0+**: Container orchestration
  - Grafana 11.2.0
  - Prometheus v2.54.1
  - Node Exporter v1.8.2
- **Systemd**: Service management for monitoring daemon

### Data Storage
- **SQLite**: Persistent local storage
  - Validation history tracking
  - State transition records
  - Historical metrics (30-day default)
  - Database location: `data/monitor.db`

- **Prometheus**: Time-series metrics database
  - 30-day retention period
  - 5-second scrape interval
  - In-memory + disk persistence
  - Volume: `prometheus_data`

### Monitoring & Visualization
- **Prometheus Client (Python)**: Metrics export library
  - Gauges for current values
  - Counters for cumulative totals
  - Info metrics for metadata
  - HTTP endpoint on port 9094 (default)

- **Grafana**: Dashboard and visualization
  - Pre-configured data source
  - Auto-imported dashboard
  - Port 3003 (default)
  - Volume: `grafana_data`

- **Node Exporter**: System metrics collector
  - CPU, memory, disk, network
  - Port 9102 (default)

### External Dependencies
- **rippled**: XRP Ledger validator (Docker or native)
  - Accessed via Docker exec commands (Docker mode)
  - Accessed via HTTP API at localhost:5005 (native mode)
  - Read-only operations only

## Architecture

### System Components

```
┌──────────────────────────────────────┐
│   XRPL Validator (rippled)           │
│   - Docker container OR native       │
│   - Admin API: localhost:5005        │
└──────────────────────────────────────┘
              │
              │ Docker exec OR HTTP API
              ▼
┌──────────────────────────────────────┐
│   Monitor Service (fast_poller.py)   │
│   - Systemd service                  │
│   - Polls every 3 seconds            │
│   - Dual storage: SQLite + Prom      │
│   - Port 9094: Metrics endpoint      │
└──────────────────────────────────────┘
              │
              │ HTTP scrape every 5s
              ▼
┌──────────────────────────────────────┐
│   Prometheus Container               │
│   - Port 9092: Query interface       │
│   - 30-day retention                 │
│   - Scrapes monitor + node-exporter  │
└──────────────────────────────────────┘
              │
              │ PromQL queries
              ▼
┌──────────────────────────────────────┐
│   Grafana Container                  │
│   - Port 3003: Web UI                │
│   - Pre-built dashboard              │
│   - Auto-provisioned datasource      │
└──────────────────────────────────────┘
```

### Data Flow

1. **Collection** (every 3 seconds):
   - `fast_poller.py` polls rippled API
   - Extracts 40+ metrics from server_info, peers, ledger data
   - Detects state transitions and validation events

2. **Storage** (dual-write):
   - **SQLite**: Persistent records for historical analysis
     - `validator_metrics`: Basic metrics (state, ledger, peers)
     - `state_transitions`: State change events with duration
     - `ledger_validations`: Per-ledger validation tracking
   - **Prometheus**: In-memory gauges/counters for real-time display
     - Updated via prometheus_client library
     - Exposed on HTTP /metrics endpoint

3. **Aggregation**:
   - Prometheus scrapes monitor endpoint (5s interval)
   - Prometheus scrapes node-exporter (system metrics)
   - 30-day time-series retention with compression

4. **Visualization**:
   - Grafana queries Prometheus via PromQL
   - Real-time dashboard updates (5s refresh)
   - Historical trend analysis (30-day range)

### Alert Flow

1. **Detection** (fast_poller.py):
   - State change detection (proposing → tracking)
   - Validation disagreement detection
   - Missed validation detection
   - API connectivity issues

2. **Alerting** (alerter.py):
   - Severity levels: INFO, WARNING, CRITICAL
   - Written to `data/alerts.log`
   - Displayed in systemd journal
   - Color-coded console output with emojis

3. **Optional Grafana Alerts**:
   - Configure via Grafana UI
   - Support for email, Slack, Discord, PagerDuty
   - Custom thresholds and conditions

## Key Components

### 1. Fast Poller (`src/collectors/fast_poller.py`)

**Purpose**: Main monitoring loop that polls validator and manages all data collection.

**Responsibilities**:
- Poll rippled API every 3 seconds (configurable)
- Track validator state transitions
- Monitor validation performance per ledger
- Update Prometheus metrics
- Write to SQLite database
- Trigger alerts on state changes
- Calculate derived metrics (TPS, P90 latency, etc.)

**Key Metrics Collected**:
- Validator state (proposing, full, tracking, syncing, etc.)
- Ledger sequence and age
- Peer counts (total, inbound, outbound, insane)
- Validation quorum and proposer count
- Load factor and I/O latency
- Consensus convergence time
- Transaction rate
- Database sizes

**State Tracking**:
- Maintains `last_state` and `state_entered_at` for duration calculation
- Records transitions to `state_transitions` table
- Sends alerts on state changes

### 2. Validation Tracker (`src/collectors/validation_tracker.py`)

**Purpose**: Track ledger-by-ledger validation participation and agreement.

**Responsibilities**:
- Determine if validator should have validated each ledger
- Check if validator actually submitted validation
- Verify validation agreement with network consensus
- Calculate 24-hour agreement rates
- Detect missed validations and disagreements
- Trigger alerts for validation issues

**Algorithm**:
```python
for ledger in new_ledgers:
    should_validate = (state == "proposing")
    did_validate = check_validations_api(ledger)
    agreed = (validation_hash == network_consensus_hash)

    db.write_ledger_validation(...)

    if should_validate and not did_validate:
        alerter.alert("Missed validation")
    if did_validate and not agreed:
        alerter.alert("Validation disagreement")
```

### 3. Prometheus Exporter (`src/exporters/prometheus_exporter.py`)

**Purpose**: Export metrics in Prometheus format via HTTP endpoint.

**Metric Types**:
- **Gauges**: Current values (state, ledger, peers, load)
- **Counters**: Cumulative totals (validations checked, state changes, errors)
- **Info**: Metadata (server version, validator pubkey)

**Endpoint**: `http://localhost:9094/metrics` (default)

**Example Metrics**:
```
xrpl_validator_state_value{} 6.0
xrpl_ledger_sequence{} 87654321
xrpl_peer_count{} 15
xrpl_validation_agreement_pct_24h{} 99.87
xrpl_state_changes_total{} 42
```

### 4. Database Layer (`src/storage/database.py`)

**Purpose**: SQLite persistence layer for historical data.

**Tables**:

1. **validator_metrics**: Basic metrics snapshot
   - Fields: timestamp, server_state, ledger_seq, peers, load_factor
   - Indexes: timestamp, ledger_seq
   - Retention: Indefinite (manual cleanup required)

2. **state_transitions**: State change events
   - Fields: timestamp, old_state, new_state, duration_in_old_state, ledger_seq, peers, load_factor
   - Indexes: timestamp, (old_state, new_state)
   - Use case: Analyze state stability over time

3. **ledger_validations**: Per-ledger validation tracking
   - Fields: timestamp, ledger_seq (UNIQUE), server_state, was_proposing, should_validate, did_validate, agreed, peers, load_factor
   - Indexes: timestamp, ledger_seq, (should_validate, did_validate)
   - Use case: Calculate agreement rates, detect missed validations

**Context Manager Pattern**:
```python
with self.get_connection() as conn:
    cursor = conn.cursor()
    cursor.execute(...)
    # Auto-commit on success, rollback on exception
```

### 5. Rippled API Client (`src/utils/rippled_api.py`)

**Purpose**: Interface to rippled validator via Docker exec or HTTP.

**Supported Modes**:
- **Docker mode**: `docker exec <container> rippled <command>`
- **Native mode**: HTTP POST to `http://localhost:5005` (future)

**Key Methods**:
- `get_server_state()`: Comprehensive server info (server_info)
- `get_peers()`: Peer list with latency details
- `get_ledger(seq)`: Ledger data by sequence
- `get_validations(seq)`: Validations for specific ledger
- `get_validator_info()`: Validator keys and configuration
- `get_fee()`: Fee info and current ledger size

**Error Handling**:
- Raises `RippledAPIError` on failures
- 10-second timeout per command
- JSON parsing validation

### 6. Alerter (`src/alerts/alerter.py`)

**Purpose**: Generate and log alerts for important events.

**Alert Types**:
1. **State Changes**:
   - CRITICAL: → disconnected, → syncing
   - WARNING: → tracking
   - INFO: → proposing

2. **Validation Issues**:
   - CRITICAL: Disagreement with network
   - WARNING: Missed validation

3. **Connectivity**:
   - CRITICAL: Validator unreachable

**Output**:
- File: `data/alerts.log`
- Systemd journal: `journalctl -u xrpl-validator-dashboard`
- Console: Color-coded with emojis

### 7. Setup Wizard (`setup.py`)

**Purpose**: Interactive setup wizard for one-command deployment.

**Checks**:
1. Prerequisites: Docker, Python, pip
2. Rippled container detection
3. Port availability (3003, 9092, 9094, 9102)
4. Python dependencies
5. Config file validation

**Actions**:
1. Detect rippled container name
2. Test rippled API connectivity
3. Generate `config.yaml`
4. Update `docker-compose.yml` with detected ports
5. Install Python dependencies
6. Optionally start services
7. Optionally install systemd service
8. Optionally import Grafana dashboard

**Smart Features**:
- Port conflict detection with suggestions
- Rippled mode detection (Docker vs native)
- Idempotent (safe to run multiple times)
- Graceful error handling with helpful messages

### 8. Configuration (`config.yaml`)

**Generated by setup wizard**:

```yaml
monitoring:
  poll_interval: 3                    # Seconds between polls
  rippled_mode: docker                # docker or native
  container_name: rippledvalidator    # Docker mode
  rippled_host: localhost             # Native mode
  rippled_port: 5005                  # Native mode

prometheus:
  enabled: true
  port: 9094
  host: 0.0.0.0

database:
  path: ./data/monitor.db

logging:
  level: INFO
  file: ./logs/monitor.log
```

### 9. Service Installation (`install-service.sh`)

**Purpose**: Install monitoring service as systemd daemon.

**Service Unit**:
- Name: `xrpl-validator-dashboard.service`
- Type: simple
- Restart: always
- Working directory: Project root
- ExecStart: `python3 src/collectors/fast_poller.py`

**Commands**:
```bash
sudo systemctl status xrpl-validator-dashboard
sudo systemctl restart xrpl-validator-dashboard
sudo journalctl -u xrpl-validator-dashboard -f
```

## Directory Structure

```
xrpl-validator-dashboard/
├── setup.py                      # Interactive setup wizard
├── cleanup.sh                    # Uninstall script
├── install-service.sh            # Systemd service installer
├── requirements.txt              # Python dependencies
├── config.yaml                   # Main configuration (generated)
├── docker-compose.yml            # Container definitions
│
├── src/                          # Python source code
│   ├── collectors/               # Data collection
│   │   ├── fast_poller.py        # Main monitoring loop (entry point)
│   │   └── validation_tracker.py # Validation tracking logic
│   ├── exporters/                # Metrics exporters
│   │   └── prometheus_exporter.py # Prometheus HTTP endpoint
│   ├── storage/                  # Persistence layer
│   │   └── database.py           # SQLite wrapper
│   ├── utils/                    # Utilities
│   │   ├── config.py             # Config file parser
│   │   └── rippled_api.py        # Rippled API client
│   └── alerts/                   # Alerting
│       └── alerter.py            # Alert handler
│
├── compose/                      # Docker configurations
│   ├── grafana/
│   │   ├── grafana.ini           # Grafana settings
│   │   ├── provisioning/
│   │   │   ├── datasources/      # Prometheus datasource config
│   │   │   └── dashboards/       # Dashboard auto-import config
│   │   └── custom.css            # Custom styling
│   └── prometheus/
│       ├── prometheus.yml        # Scrape configuration
│       ├── alert.rules.yml       # Alert rules
│       ├── recording.rules.yml   # Recording rules
│       └── rules/                # Additional rules
│
├── dashboards/                   # Grafana dashboard JSONs
│   └── generate_all_dashboards.py # Dashboard generator
│
├── data/                         # Runtime data (gitignored)
│   ├── monitor.db                # SQLite database
│   └── alerts.log                # Alert log file
│
├── logs/                         # Application logs (gitignored)
│   └── monitor.log               # Service log
│
└── .project/                     # Project metadata
    └── PROJECT.md                # This file
```

## Deployment Architecture

### Port Allocation (Defaults)

| Service | Internal | External | Purpose |
|---------|----------|----------|---------|
| Grafana | 3000 | 3003 | Dashboard UI |
| Prometheus | 9090 | 9092 | Metrics DB |
| Node Exporter | 9100 | 9102 | System metrics |
| XRPL Monitor | 9094 | 9094 | Validator metrics |

All ports are configurable via setup wizard with automatic conflict detection.

### Resource Limits

**Docker Containers**:
- **Grafana**: 0.5 CPU, 1GB RAM limit
- **Prometheus**: 1.0 CPU, 2GB RAM limit (GOMEMLIMIT)
- **Node Exporter**: 0.2 CPU, 128MB RAM limit

**Monitor Service**: ~0.3-0.5% CPU, ~50 MB RAM

**Total Overhead**: ~1% CPU, ~280 MB RAM, ~20 KB/s disk I/O

### Persistence

**Docker Volumes**:
- `prometheus_data`: Prometheus TSDB (30-day retention)
- `grafana_data`: Grafana dashboards, users, settings

**Local Files**:
- `data/monitor.db`: SQLite database (indefinite retention)
- `data/alerts.log`: Alert history
- `logs/monitor.log`: Service logs

## Development Notes

### Adding New Metrics

1. **Collect** in `fast_poller.py`:
   ```python
   new_metric = state_info.get('new_field', 0)
   ```

2. **Store** in `prometheus_exporter.py`:
   ```python
   self.new_metric = Gauge('xrpl_new_metric', 'Description')
   ```

3. **Update** in polling loop:
   ```python
   if self.prometheus:
       self.prometheus.update_new_metric(new_metric)
   ```

4. **Query** in Grafana:
   ```promql
   xrpl_new_metric{}
   ```

### Testing

**Manual Tests**:
- `tests/manual/test_api.py`: Rippled API connectivity
- `tests/manual/test_database.py`: SQLite operations
- `tests/manual/test_poller_5min.py`: 5-minute integration test

**Validation**:
```bash
# Check metrics endpoint
curl http://localhost:9094/metrics | grep xrpl

# Query database
sqlite3 data/monitor.db "SELECT COUNT(*) FROM validator_metrics;"

# Check service status
sudo systemctl status xrpl-validator-dashboard
```

### Customization Points

1. **Poll Interval**: `config.yaml → monitoring.poll_interval`
2. **Retention Period**: `docker-compose.yml → --storage.tsdb.retention.time`
3. **Alert Thresholds**: `src/alerts/alerter.py`
4. **Dashboard Panels**: Grafana UI → Export to `dashboards/`
5. **Scrape Interval**: `compose/prometheus/prometheus.yml`

## Git Commit Guidelines

### Commit Message Format

Use conventional commits for clear, semantic version history:

- `feat:` New features or functionality
- `fix:` Bug fixes
- `docs:` Documentation changes
- `refactor:` Code refactoring without behavior changes
- `test:` Adding or updating tests
- `chore:` Maintenance, dependencies, configuration
- `perf:` Performance improvements

**Examples**:
```
feat: add validation disagreement detection
fix: correct peer count calculation in fast_poller
docs: update installation instructions in README
refactor: extract database operations into separate module
chore: update prometheus-client to 0.20.0
```

### AI Attribution Policy

**CRITICAL - NO AI ATTRIBUTION IN COMMITS**

To maintain clean git history and proper project ownership:

- ❌ **DO NOT** include `Co-Authored-By: Claude <noreply@anthropic.com>`
- ❌ **DO NOT** add "🤖 Generated with Claude Code" or similar AI attribution
- ❌ **DO NOT** reference AI tools in commit message bodies
- ✅ **DO** attribute all commits solely to the project owner (Grapedrop)

**Why this matters**:
- Maintains professional git history
- Ensures clear project ownership
- Prevents GitHub contributor graph pollution
- Protects privacy and security
- GitHub caches contributor data aggressively (can take days/weeks to fix)

**AI tools like Claude Code are development aids** - use them freely for coding, debugging, and problem-solving. This `.project/PROJECT.md` file helps AI understand project context. Just don't add AI attribution to commits pushed to GitHub.

### Code Style

- Follow PEP 8 for Python code
- Use type hints where beneficial
- Write clear, self-documenting code with descriptive variable names
- Add comments for complex logic or non-obvious decisions
- Keep functions focused and single-purpose

### Testing Before Commits

- Test new features locally before committing
- Run manual tests in `tests/manual/` for affected components
- Verify metrics endpoint: `curl http://localhost:9094/metrics`
- Check systemd service status if modifying collector code
- Validate configuration changes don't break setup wizard

## Performance Characteristics

### Polling Overhead

- **3-second interval**: Captures state changes within 3-6 seconds
- **API call latency**: ~50-200ms per poll (Docker exec overhead)
- **Database writes**: ~10-20 KB/s sustained
- **Memory growth**: ~1-2 MB/day (SQLite)

### Scalability Limits

- **SQLite**: Millions of records supported, no cleanup implemented
- **Prometheus**: 30-day retention at 5s scrape = ~500k samples/metric
- **Dashboard**: 40+ panels, 5s refresh = manageable load

### Bottlenecks

1. **Docker exec latency**: Native HTTP mode would be 10x faster
2. **SQLite write contention**: Not an issue at 3s interval
3. **Prometheus scrape interval**: 5s minimum for dashboard responsiveness

## Security Considerations

### Access Control

- **Grafana**: Default admin/admin (prompt to change on first login)
- **Prometheus**: No authentication, localhost binding only
- **Monitor**: No authentication, 0.0.0.0 binding for container access

### Network Exposure

- All services bind to localhost by default
- Reverse proxy required for remote access
- No TLS/SSL configured

### Rippled Access

- **Docker mode**: Requires Docker socket access (sudo/docker group)
- **Native mode**: Requires rippled admin API access (localhost:5005)
- **Read-only**: No write operations to validator

### Data Privacy

- No external network calls
- All data stored locally
- Validator pubkey visible in metrics

## Operational Characteristics

### Startup Sequence

1. Docker Compose starts Prometheus, Grafana, Node Exporter
2. Grafana auto-provisions Prometheus datasource
3. Systemd starts `xrpl-validator-dashboard.service`
4. Monitor service polls rippled and begins metric export
5. Prometheus scrapes monitor endpoint
6. Dashboard displays data (24h panels populate after 5-10 min)

### Failure Modes

1. **Rippled unreachable**:
   - Alert: "Validator Unreachable" (after 2 failed attempts)
   - State: Changed to "unreachable"
   - Recovery: Automatic on rippled restart

2. **Database write failure**:
   - Error logged, polling continues
   - Prometheus metrics unaffected

3. **Prometheus down**:
   - Monitor continues collecting to SQLite
   - Metrics lost during downtime (no backfill)

4. **Grafana down**:
   - No impact on monitoring
   - Dashboard inaccessible

### Maintenance

**Regular**:
- Monitor systemd service status
- Check disk space for SQLite growth
- Review alerts.log for issues

**Periodic**:
- Update Docker images (docker compose pull)
- Backup SQLite database
- Clean old alert logs

**Optional**:
- Implement SQLite retention policy
- Export Grafana dashboards as backup
- Configure remote alerting (email, Slack)

## Future Enhancements

### Planned
- WebSocket ledger stream integration (hybrid approach for instant ledger notifications + reduced polling frequency)
- Native rippled HTTP API support (eliminate Docker exec overhead)
- Configurable SQLite retention policy
- Additional Grafana dashboards (network-wide view)
- Webhook alerting integration

### Considered
- Multi-validator monitoring
- Network consensus tracking
- UNL validator health monitoring
- Amendment voting tracker
- Performance benchmarking tools

## Dependencies

### Runtime
- Python 3.6+ with standard library
- prometheus-client>=0.19.0
- Docker 20.10+
- Docker Compose v2.0+
- rippled (Docker container or native)
- systemd (for service management)

### Development
- bash (for setup scripts)
- SQLite3 CLI (for manual queries)
- curl (for endpoint testing)

## Compatibility

### Rippled Versions

**Tested and supported:**
- rippled 2.0.0+
- rippled 2.6.1 (current stable)

**API compatibility:**
- Requires `server_info`, `peers`, `ledger`, `validations` API methods
- Uses standard rippled admin API (no custom extensions)
- Should work with all rippled versions 2.0+

**Breaking changes to watch for:**
- Changes to server_state enum values
- Changes to validation tracking API
- Changes to peer latency metrics

### Operating Systems

**Officially supported:**
- Ubuntu 20.04 LTS
- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS

**Should work on:**
- Debian 11 (Bullseye)
- Debian 12 (Bookworm)
- Linux Mint 20+

**Partially tested:**
- CentOS 8+ (requires Docker Compose v2 manual install)
- Rocky Linux 8+
- Fedora 35+

**Requirements:**
- systemd-based init system
- Docker 20.10+
- Docker Compose v2.0+ (plugin-based, not standalone)
- Python 3.6+ (pre-installed on most distributions)

**Known OS-specific issues:**
- **CentOS/RHEL**: `docker compose` plugin may need manual installation
- **Older Ubuntu (<20.04)**: May have Python 3.6 incompatibility
- **Non-systemd systems**: Service installation will fail (can run manually)

### Architecture

**Supported:**
- x86_64 (amd64) - Primary platform
- aarch64 (arm64) - Docker images support ARM

**Not tested:**
- armv7 (32-bit ARM)
- Other architectures

## Known Limitations

### Docker Mode Limitations

1. **Docker exec overhead**: ~50-200ms latency per API call
   - Native HTTP mode would reduce this to ~5-10ms
   - Impact: Slight delay in state change detection

2. **Docker socket access required**: User must be in `docker` group or use sudo
   - Security consideration: Docker group = root equivalent
   - Alternative: Native mode (when implemented)

3. **Container restart detection**: Monitor service doesn't detect rippled container restarts
   - Workaround: Systemd restarts monitor automatically if it crashes

### Monitoring Limitations

1. **No historical backfill**: If monitor is stopped, metrics during downtime are lost
   - SQLite data is preserved
   - Prometheus metrics for downtime period are not recoverable

2. **3-second polling interval**: Not configurable below 1 second
   - Risk: May miss very brief state transitions (<3s)
   - Mitigation: 3s is sufficient for most validator operations

3. **24-hour metrics delayed**: Agreement rate panels require 5-10 minutes of data collection
   - First-time setup: Panels show "No data" initially
   - Recovery from long downtime: Same delay applies

### Database Limitations

1. **No automatic retention policy**: SQLite database grows indefinitely
   - Growth rate: ~50-100 MB/month
   - Mitigation: Manual cleanup or custom retention script

2. **No replication**: Single SQLite file, no built-in backup/HA
   - Risk: Disk failure = data loss
   - Mitigation: Regular backups (see Backup/Restore section)

3. **Write contention**: Single writer (fast_poller.py)
   - Not an issue at 3s interval
   - Concurrent reads supported via WAL mode

### Network Limitations

1. **Single validator only**: Does not support monitoring multiple validators
   - Each validator needs separate dashboard instance
   - No network-wide consensus view

2. **No remote access by default**: All services bind to localhost
   - Remote access requires reverse proxy setup
   - No TLS/SSL configuration included

3. **UNL validator tracking**: Does not track other UNL validator status
   - Only monitors peer connectivity, not validator-specific health

### Alert Limitations

1. **File-based only**: Alerts written to `data/alerts.log` and systemd journal
   - No email/Slack/Discord integration (yet)
   - Grafana alerting available but requires manual setup

2. **No alert aggregation**: Each state change triggers separate alert
   - Flapping states = alert spam
   - No deduplication or rate limiting

3. **Limited validation disagreement detection**: Detects disagreements after the fact
   - Cannot predict or prevent disagreements
   - Requires post-mortem analysis

## Backup and Restore Procedures

### What to Backup

**Critical data:**
- `data/monitor.db` - SQLite database (validation history, state transitions)
- `data/alerts.log` - Alert history

**Optional:**
- `config.yaml` - Configuration (easily regenerated)
- Docker volumes: `prometheus_data`, `grafana_data`

### Backup SQLite Database

**Simple backup (service running):**
```bash
# SQLite is in WAL mode, safe to copy while running
cp data/monitor.db data/monitor.db.backup
```

**Proper backup with integrity check:**
```bash
sqlite3 data/monitor.db ".backup data/monitor.db.backup"
```

**Automated daily backup:**
```bash
#!/bin/bash
# /usr/local/bin/backup-xrpl-dashboard.sh
DATE=$(date +%Y%m%d)
BACKUP_DIR="/var/backups/xrpl-dashboard"
mkdir -p "$BACKUP_DIR"

sqlite3 /home/grapedrop/projects/xrpl-validator-dashboard/data/monitor.db \
  ".backup $BACKUP_DIR/monitor-$DATE.db"

# Keep last 30 days
find "$BACKUP_DIR" -name "monitor-*.db" -mtime +30 -delete
```

**Add to crontab:**
```bash
0 2 * * * /usr/local/bin/backup-xrpl-dashboard.sh
```

### Backup Docker Volumes

**Backup Prometheus data (30-day metrics):**
```bash
docker run --rm \
  -v xrpl-validator-dashboard_prometheus_data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/prometheus-data-$(date +%Y%m%d).tar.gz /data
```

**Backup Grafana data (dashboards, users):**
```bash
docker run --rm \
  -v xrpl-validator-dashboard_grafana_data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/grafana-data-$(date +%Y%m%d).tar.gz /data
```

### Restore SQLite Database

**Stop service before restore:**
```bash
sudo systemctl stop xrpl-validator-dashboard
```

**Restore from backup:**
```bash
cp data/monitor.db.backup data/monitor.db
# or
cp /var/backups/xrpl-dashboard/monitor-20251108.db data/monitor.db
```

**Restart service:**
```bash
sudo systemctl start xrpl-validator-dashboard
```

### Restore Docker Volumes

**Restore Prometheus data:**
```bash
docker compose down
docker run --rm \
  -v xrpl-validator-dashboard_prometheus_data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar xzf /backup/prometheus-data-20251108.tar.gz -C /
docker compose up -d
```

**Restore Grafana data:**
```bash
docker compose down
docker run --rm \
  -v xrpl-validator-dashboard_grafana_data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar xzf /backup/grafana-data-20251108.tar.gz -C /
docker compose up -d
```

### Disaster Recovery

**Complete system rebuild:**
1. Install fresh Ubuntu/Debian system
2. Install Docker and Docker Compose
3. Clone repository: `git clone https://github.com/realgrapedrop/xrpl-validator-dashboard.git`
4. Restore `data/monitor.db` from backup
5. Run setup: `python3 setup.py`
6. Optionally restore Docker volumes
7. Verify dashboard displays historical data

**Data loss scenarios:**
- **SQLite lost, volumes intact**: Historical validation data lost, but recent Prometheus data (30 days) available
- **Volumes lost, SQLite intact**: Grafana configuration lost (easily re-imported), Prometheus metrics lost (SQLite has key data)
- **Everything lost**: Start fresh with `python3 setup.py` (historical data unrecoverable)

## Migration and Upgrade Path

### Upgrading Dashboard

**Minor updates (no breaking changes):**
```bash
cd /home/grapedrop/projects/xrpl-validator-dashboard
git pull origin main
sudo systemctl restart xrpl-validator-dashboard
docker compose pull
docker compose up -d
```

**Major updates (potential breaking changes):**
1. **Backup everything** (see Backup section)
2. Review CHANGELOG or commit messages for breaking changes
3. Stop services: `./cleanup.sh` (choose to preserve volumes)
4. Pull updates: `git pull origin main`
5. Re-run setup: `python3 setup.py`
6. Verify dashboard functionality

### Database Schema Migrations

**Currently:** No automated migrations. Schema changes rare.

**If schema changes:**
1. Stop service: `sudo systemctl stop xrpl-validator-dashboard`
2. Backup database: `sqlite3 data/monitor.db ".backup data/monitor.db.pre-migration"`
3. Apply migration script (provided in release notes)
4. Restart service: `sudo systemctl start xrpl-validator-dashboard`

### Config File Changes

**If config.yaml format changes:**
1. Backup existing: `cp config.yaml config.yaml.backup`
2. Re-run setup wizard: `python3 setup.py`
3. Review and merge custom settings from backup

### Dashboard Updates

**Grafana dashboard changes:**
1. Dashboard auto-reimports on setup
2. Manual import: Grafana UI → Dashboards → New → Import → Upload `dashboards/categories/xrpl-monitor-dashboard.json`
3. Customizations: Export your modified dashboard before upgrading

### Preserving Customizations

**Custom dashboard panels:**
- Export dashboard as JSON before upgrading
- After upgrade, manually merge panels from old JSON

**Custom alerts:**
- Grafana alerts stored in `grafana_data` volume (preserved if not removed)
- Export alert rules before major upgrades

**Custom config:**
- `config.yaml` regenerated by setup wizard
- Keep backup of custom settings (poll_interval, log_level, etc.)

### Downgrading

**If upgrade fails:**
```bash
git log --oneline  # Find previous commit
git checkout <commit-hash>
sudo systemctl restart xrpl-validator-dashboard
docker compose pull
docker compose up -d
```

**Restore database if schema changed:**
```bash
sudo systemctl stop xrpl-validator-dashboard
cp data/monitor.db.pre-migration data/monitor.db
sudo systemctl start xrpl-validator-dashboard
```

### Version Compatibility Matrix

| Dashboard Version | Rippled Version | Python | Docker Compose |
|-------------------|-----------------|--------|----------------|
| Current (main)    | 2.0.0+          | 3.6+   | v2.0+          |
| Future (native)   | 2.0.0+          | 3.8+   | v2.0+          |

**Note:** Project does not use semantic versioning. Main branch is always production-ready.

## License

MIT License - See LICENSE.md for details.

## Author

Created by Grapedrop ([@realGrapedrop](https://x.com/realGrapedrop))
Running XRPL validator since 2025
Website: https://xrp-validator.grapedrop.xyz
