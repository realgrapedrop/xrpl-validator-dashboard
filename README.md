# XRPL Validator Monitor Dashboard

A comprehensive monitoring solution for XRPL (Ripple) validator nodes. Provides real-time metrics, performance tracking, and alerting through Grafana and Prometheus with a custom Python monitoring service.

**Created by:** [Grapedrop](https://xrp-validator.grapedrop.xyz) | [@realGrapedrop](https://x.com/realGrapedrop)

## Dashboard Preview

<video src="images/xrpl-validator-monitor-dashboard-inaction.mp4" controls="controls" style="max-width: 730px;">
</video>

*Real-time monitoring of XRPL validator performance, consensus state, and network metrics*

## Features

- 📊 **Real-time Monitoring** - Track validator performance, consensus state, and network metrics
- 🐍 **Python Monitoring Service** - Custom exporter with 3-second polling for fast state transitions
- 🐳 **Docker-based** - Easy deployment with Docker Compose
- 🔧 **Modular Installation** - Choose what you need (full stack, monitoring only, or just the dashboard)
- 📈 **Pre-built Dashboard** - Grafana dashboard with key XRPL validator metrics
- 🔐 **Security Hardened** - Best practices for production validator security
- 🗑️ **Clean Uninstall** - Surgical removal script that tracks and removes everything
- 📦 **Auto-deployment** - Installation script handles Python service setup automatically

## Table of Contents

- [Prerequisites](#prerequisites)
- [Use Cases](#use-cases)
- [Quick Start](#quick-start)
- [Python Monitoring System](#python-monitoring-system)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Uninstallation](#uninstallation)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Prerequisites

### Operating System
- Ubuntu 24.04 LTS (Noble) or later
- Other Linux distributions may work but are not officially supported

### Software Requirements
- **Docker**: 28.3.3 or later
- **Docker Compose**: v2.39.1 or later
- **Python**: 3.8+ (automatically installed if missing)
- **pip3**: Python package manager (automatically installed if missing)
- **Grafana**: 11.2.0 (included in monitoring stack)
- **Prometheus**: 2.54.1 (included in monitoring stack)
- **Node Exporter**: 1.8.2 (included in monitoring stack)

Install Docker and Docker Compose:
- Docker: https://docs.docker.com/engine/install/ubuntu/
- Docker Compose: https://docs.docker.com/compose/install/

### Hardware Requirements

**Minimum for node_size: huge (recommended for validators):**
- **CPU**: 8+ cores (24 cores recommended)
- **RAM**: 64GB minimum
- **Storage**: 1.5TB+ NVMe SSD
- **Network**: Stable internet connection with low latency

**For monitoring-only installations:**
- **CPU**: 2+ cores
- **RAM**: 4GB minimum (Python monitor uses <100MB)
- **Storage**: 50GB for metrics retention

### Network Requirements
- Peer port: 51235 (TCP/UDP) - Must be publicly accessible
- Admin ports: 5005, 5006, 6006 (bound to localhost only)
- Prometheus metrics: 9091 (Python monitor exporter)

## Use Cases

This project supports multiple deployment scenarios:

### Use Case 1: Full Stack with Docker Rippled
Complete setup including rippled validator and monitoring stack with Python service.
```bash
./install.sh --full
```

### Use Case 2: Monitoring Only (Docker Rippled)
Add monitoring to existing rippled Docker container. Includes Python monitoring service.
```bash
./install.sh --monitoring --rippled-type docker
```

### Use Case 3: Monitoring Only (Native Rippled)
Add monitoring to rippled running as systemd service or binary. Includes Python monitoring service.
```bash
./install.sh --monitoring --rippled-type native
```

### Use Case 4: Dashboard Only
Import dashboard into existing Grafana instance.
```bash
./install.sh --dashboard-only
```

## Python Monitoring System

### Overview

The Python monitoring service (`xrpl-monitor`) is the core component that collects validator metrics and exports them to Prometheus. It runs as a systemd service and polls your rippled node every 3 seconds.

**What it does:**
- ✅ Polls rippled API every 3 seconds for real-time state tracking
- ✅ Tracks validator state transitions (disconnected → syncing → full → proposing)
- ✅ Monitors validation performance (agreements, misses, rates)
- ✅ Records peer network metrics (count, latency, health)
- ✅ Stores historical data in SQLite database
- ✅ Exports metrics to Prometheus (port 9091)
- ✅ Sends alerts on state changes

**Why Python?**
- Fast polling interval (3s) catches quick state transitions
- Rich API client for both Docker and native rippled
- SQLite storage for historical analysis
- Reliable systemd service management
- Easy to extend and customize

### Architecture

```
┌─────────────┐
│   rippled   │ ← Docker or Native
└──────┬──────┘
       │ RPC API (port 5005)
       ↓
┌─────────────────────┐
│  xrpl-monitor       │ ← Python Service (systemd)
│  (fast_poller.py)   │    Polls every 3 seconds
│                     │
│  ├─ RippledAPI      │
│  ├─ Database (SQLite)
│  ├─ ValidationTracker
│  └─ PrometheusExporter (port 9091)
└──────┬──────────────┘
       │ HTTP Metrics
       ↓
┌─────────────┐      ┌──────────┐
│ Prometheus  │─────→│ Grafana  │
└─────────────┘      └──────────┘
```

### Automatic Deployment

The `install.sh` script automatically:
1. ✅ Installs Python dependencies (`pip3 install -r requirements.txt`)
2. ✅ Copies `src/` directory to installation location
3. ✅ Creates systemd service from template
4. ✅ Starts and enables `xrpl-monitor.service`
5. ✅ Tracks all files for clean uninstallation

**No manual setup required!**

### Service Management

After installation, manage the service with:

```bash
# Check status
sudo systemctl status xrpl-monitor

# View logs
sudo journalctl -u xrpl-monitor -f

# Restart service
sudo systemctl restart xrpl-monitor

# Stop service
sudo systemctl stop xrpl-monitor

# Start service
sudo systemctl start xrpl-monitor

# Check metrics endpoint
curl http://localhost:9091/metrics
```

### Key Metrics Exported

The Python service exports 40+ metrics including:

**State Metrics:**
- `xrpl_validator_state_value` - Current validator state (0-6)
- `xrpl_time_in_current_state_seconds` - Time in current state
- `xrpl_server_state_duration_seconds` - Uptime in current state

**Validation Metrics:**
- `xrpl_validation_rate` - Validation participation rate
- `xrpl_validations_checked_total` - Total validations checked
- `xrpl_validator_uptime_seconds` - Total validator uptime

**Network Metrics:**
- `xrpl_peer_count` - Connected peer count
- `xrpl_peers_inbound` / `xrpl_peers_outbound` - Peer direction stats
- `xrpl_peer_latency_p90_ms` - 90th percentile peer latency

**Ledger Metrics:**
- `xrpl_ledger_sequence` - Current ledger number
- `xrpl_ledger_age_seconds` - Age since last ledger
- `xrpl_load_factor` - Server load factor

### Database Storage

Historical metrics are stored in SQLite:
- **Location**: `${INSTALL_DIR}/data/monitor.db`
- **Retention**: Indefinite (manual cleanup if needed)
- **Tables**: `validator_metrics` with timestamped data
- **Size**: ~100MB per year of operation

### For Developers

Want to customize the monitoring? See:
- **Technical Details**: [src/README.md](src/README.md)
- **Development Guide**: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- **Source Code**: [src/](src/)

The Python codebase is well-structured and documented:
```
src/
├── collectors/      # Data collection (fast_poller.py)
├── exporters/       # Prometheus exporter
├── storage/         # SQLite database
├── utils/           # rippled API client
└── alerts/          # Alert system
```

## Quick Start

**Full installation with rippled validator:**

```bash
# Clone repository
git clone https://github.com/realGrapedrop/xrpl-validator-monitor-dashboard.git
cd xrpl-validator-monitor-dashboard

# Run installation (includes Python monitoring service)
sudo ./install.sh --full

# Verify Python service is running
sudo systemctl status xrpl-monitor

# Check metrics are available
curl http://localhost:9091/metrics | grep xrpl_validator_state
```

**Monitoring only (existing rippled):**

```bash
# Clone repository
git clone https://github.com/realGrapedrop/xrpl-validator-monitor-dashboard.git
cd xrpl-validator-monitor-dashboard

# Install monitoring stack (includes Python service)
sudo ./install.sh --monitoring --rippled-type docker

# Access Grafana at http://localhost:3000
# Default credentials: admin/admin (change on first login)

# Verify Python monitor
sudo systemctl status xrpl-monitor
```

## Installation

### Step 1: Clone Repository

```bash
git clone https://github.com/realGrapedrop/xrpl-validator-monitor-dashboard.git
cd xrpl-validator-monitor-dashboard
```

### Step 2: Choose Installation Type

The `install.sh` script supports multiple installation modes:

**Options:**
- `--full` - Complete stack (rippled + monitoring + Python service)
- `--monitoring` - Monitoring stack only (includes Python service)
- `--dashboard-only` - Import dashboard only (no Python service)
- `--rippled-type [docker|native]` - Specify rippled deployment type
- `--install-dir <path>` - Custom installation directory (default: $HOME/xrpl-validator)
- `--help` - Show all options

**Examples:**

```bash
# Full installation with custom directory
sudo ./install.sh --full --install-dir /opt/xrpl-validator

# Monitoring only for Docker rippled
sudo ./install.sh --monitoring --rippled-type docker

# Monitoring only for native rippled
sudo ./install.sh --monitoring --rippled-type native

# Dashboard import only
./install.sh --dashboard-only
```

### Step 3: Configuration

The installation script will guide you through configuration. Key items:

1. **Installation directory** - Where to install (default: `$HOME/xrpl-validator`)
2. **Validator keys** - Generate new or import existing
3. **Network ports** - Confirm firewall rules
4. **Resource limits** - Memory and CPU allocation
5. **Python service** - Automatically configured and started

### Step 4: Verify Installation

```bash
# Check rippled status (if installed)
docker ps | grep rippledvalidator
docker exec rippledvalidator rippled server_info

# Check Python monitoring service
sudo systemctl status xrpl-monitor
sudo journalctl -u xrpl-monitor -n 20

# Check monitoring stack
docker ps | grep -E "prometheus|grafana|node"

# Verify metrics are being exported
curl http://localhost:9091/metrics | head -20

# Access Grafana
# URL: http://localhost:3000
# Default login: admin/admin
```

## Configuration

### Rippled Configuration

Configuration files are located in `${INSTALL_DIR}/rippled/config/`:
- `rippled.cfg` - Main rippled configuration
- `validators.txt` - UNL (Unique Node List)
- `validator-keys.json` - Validator keypair (keep secure!)

### Python Monitor Configuration

The Python monitoring service is configured via:
- **Service file**: `/etc/systemd/system/xrpl-monitor.service`
- **Source code**: `${INSTALL_DIR}/src/`
- **Database**: `${INSTALL_DIR}/data/monitor.db`
- **Logs**: `${INSTALL_DIR}/logs/monitor.log` and `error.log`

**Default settings:**
- Poll interval: 3 seconds
- Metrics port: 9091
- Memory limit: 512MB
- CPU limit: 50%

To modify settings, edit the source files in `${INSTALL_DIR}/src/` and restart the service.

### Systemd Service Template

#### Overview

The Python monitoring service runs as a systemd service for reliability and automatic startup. The service is created automatically during installation.

#### Template Location

```
systemd/xrpl-monitor.service.template
```

This template file contains variables that are replaced during installation:
- `${INSTALL_DIR}` - Replaced with actual installation directory
- `${USER}` - Replaced with the user running the installation

#### Template Contents

```ini
[Unit]
Description=XRPL Validator Monitor (State + Validation + Prometheus)
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER}                              # ← Replaced during install
Group=${USER}                             # ← Replaced during install
WorkingDirectory=${INSTALL_DIR}           # ← Replaced during install
Environment="INSTALL_DIR=${INSTALL_DIR}"  # ← Replaced during install
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/src/collectors/fast_poller.py

Restart=always
RestartSec=10
MemoryMax=512M
CPUQuota=50%

StandardOutput=append:${INSTALL_DIR}/logs/monitor.log
StandardError=append:${INSTALL_DIR}/logs/error.log

[Install]
WantedBy=multi-user.target
```

#### Automatic Installation

**The install.sh script handles everything:**

1. ✅ Reads the template from `systemd/xrpl-monitor.service.template`
2. ✅ Replaces `${INSTALL_DIR}` with actual path (e.g., `/opt/xrpl-validator`)
3. ✅ Replaces `${USER}` with actual username (e.g., `grapedrop`)
4. ✅ Creates `/etc/systemd/system/xrpl-monitor.service`
5. ✅ Reloads systemd daemon
6. ✅ Enables service for auto-start on boot
7. ✅ Starts the service immediately

**Result:** After installation, the service runs automatically with the correct paths for your system.

#### Manual Template Usage (Advanced)

If you need to manually create the service (development/testing):

```bash
# Set your paths
INSTALL_DIR="/path/to/installation"
USER="your-username"

# Process template
sed -e "s|\${INSTALL_DIR}|$INSTALL_DIR|g" \
    -e "s|\${USER}|$USER|g" \
    systemd/xrpl-monitor.service.template \
    > /tmp/xrpl-monitor.service

# Install service
sudo cp /tmp/xrpl-monitor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable xrpl-monitor
sudo systemctl start xrpl-monitor
```

#### Verifying Service Installation

After `install.sh` completes, verify the service was created correctly:

```bash
# Check service file exists and has correct paths
cat /etc/systemd/system/xrpl-monitor.service

# Verify no template variables remain
grep '\${' /etc/systemd/system/xrpl-monitor.service  # Should return nothing

# Check service is running
systemctl status xrpl-monitor

# View service configuration
systemctl cat xrpl-monitor
```

#### Customizing the Service

To modify service parameters (memory limits, restart policy, etc.):

**Option 1: Edit template before installation**
```bash
# Edit systemd/xrpl-monitor.service.template
# Change MemoryMax, CPUQuota, etc.
# Then run install.sh
```

**Option 2: Override after installation**
```bash
# Create override file
sudo systemctl edit xrpl-monitor

# Add your changes:
[Service]
MemoryMax=1G
CPUQuota=100%

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart xrpl-monitor
```

#### Troubleshooting Service Creation

**If service fails to start after installation:**

1. **Check template file exists:**
   ```bash
   ls -la systemd/xrpl-monitor.service.template
   ```

2. **Verify service file was created:**
   ```bash
   ls -la /etc/systemd/system/xrpl-monitor.service
   ```

3. **Check for template variables:**
   ```bash
   grep '\${' /etc/systemd/system/xrpl-monitor.service
   # If this returns anything, variables weren't replaced
   ```

4. **View installation logs:**
   ```bash
   # install.sh outputs service creation status
   # Look for: "[5/6] Creating systemd service..."
   ```

5. **Check systemd errors:**
   ```bash
   sudo journalctl -u xrpl-monitor -n 50
   systemctl status xrpl-monitor
   ```

#### Related Files

- **Template**: `systemd/xrpl-monitor.service.template`
- **Installed service**: `/etc/systemd/system/xrpl-monitor.service`
- **Installation script**: `install.sh` (handles template processing)
- **Uninstall script**: `uninstall.sh` (removes service cleanly)

### Prometheus Configuration

Prometheus config is at `${INSTALL_DIR}/monitoring/prometheus/prometheus.yml`

**Default scrape targets:**
- xrpl-monitor: `localhost:9091` (Python monitoring service) - **Primary metrics source**
- node_exporter: `localhost:9100` (Host system metrics)
- cadvisor: `localhost:8080` (Docker container metrics)

**Scrape interval recommendations:**
```yaml
scrape_configs:
  - job_name: 'xrpl-monitor'
    scrape_interval: 5s      # Match Python poller (3s) for real-time updates
    scrape_timeout: 4s
    static_configs:
      - targets: ['localhost:9091']
```

### Grafana Dashboard

The dashboard is automatically imported during installation. To manually import:

1. Log into Grafana (http://localhost:3000)
2. Navigate to Dashboards → Import
3. Upload `monitoring/grafana/dashboards/Rippled-Dashboard.json`
4. Select Prometheus datasource
5. Click Import

## Usage

### Starting Services

**Full stack:**
```bash
# Start Docker services
cd ${INSTALL_DIR}
docker compose -f docker-compose-full.yml up -d

# Python monitor starts automatically via systemd
sudo systemctl status xrpl-monitor
```

**Monitoring only:**
```bash
# Start Docker monitoring services
cd ${INSTALL_DIR}
docker compose -f docker-compose-monitoring.yml up -d

# Python monitor starts automatically via systemd
sudo systemctl status xrpl-monitor
```

### Stopping Services

```bash
# Stop Docker services
cd ${INSTALL_DIR}
docker compose down

# Stop Python monitor
sudo systemctl stop xrpl-monitor
```

### Viewing Logs

**Python monitor logs:**
```bash
# Real-time logs
sudo journalctl -u xrpl-monitor -f

# Last 50 lines
sudo journalctl -u xrpl-monitor -n 50

# Application logs
tail -f ${INSTALL_DIR}/logs/monitor.log
tail -f ${INSTALL_DIR}/logs/error.log
```

**Rippled logs:**
```bash
docker logs -f rippledvalidator
```

**Prometheus logs:**
```bash
docker logs -f prometheus
```

**Grafana logs:**
```bash
docker logs -f grafana
```

### Monitoring Commands

**Check validator status:**
```bash
docker exec rippledvalidator rippled server_info
```

**Check Python monitor metrics:**
```bash
# Quick health check
curl http://localhost:9091/metrics | grep xrpl_validator_state

# All metrics
curl http://localhost:9091/metrics

# Specific metric
curl http://localhost:9091/metrics | grep xrpl_validation_rate
```

**Check database:**
```bash
# View record count
sqlite3 ${INSTALL_DIR}/data/monitor.db "SELECT COUNT(*) FROM validator_metrics;"

# View recent records
sqlite3 ${INSTALL_DIR}/data/monitor.db "SELECT datetime(timestamp, 'unixepoch'), server_state, ledger_seq FROM validator_metrics ORDER BY timestamp DESC LIMIT 10;"
```

**Check resource usage:**
```bash
# Docker containers
docker stats

# Python service
systemctl status xrpl-monitor | grep Memory
```

**Access Grafana:**
- URL: http://localhost:3000
- Default credentials: admin/admin

**Access Prometheus:**
- URL: http://localhost:9090

## Tips & Best Practices

### Optimize Grafana Dashboard Performance

**Enable Fast Refresh for Real-Time Monitoring:**

1. **Open your Grafana dashboard**

2. **Set Auto-Refresh Interval:**
   - Look at the top-right corner of the dashboard
   - Click the refresh dropdown (🔄 icon)
   - Select **5s** for real-time updates
   - This queries Prometheus every 5 seconds

3. **Enable Live Dashboard (Recommended):**
   - Click the dashboard settings icon (⚙️) at the top
   - Navigate to **Settings** → **General**
   - Under **Time options**, enable **"Refresh live dashboards"**
   - Click **Save dashboard**

4. **Match Prometheus Scrape Interval:**
   - Set Prometheus scrape interval to 5s (in prometheus.yml)
   - Set Grafana refresh to 5s (as above)
   - This ensures you see fresh data immediately

**Why This Matters:**
- **Catch fast state transitions** - Validator can sync in <10 seconds
- **Real-time alerting** - See issues as they happen
- **Better troubleshooting** - Precise timing of events

### Prometheus Scrape Interval for State Monitoring

For the `xrpl-monitor` job in prometheus.yml:

```yaml
- job_name: 'xrpl-monitor'
  scrape_interval: 5s      # Recommended for state monitoring
  scrape_timeout: 4s
  static_configs:
    - targets: ['localhost:9091']
```

**Why 5 seconds?**
- Python service polls every 3 seconds
- Validator state transitions can happen quickly (syncing in 5-10s)
- 5s provides good balance between data granularity and system load
- Default 15s interval may miss intermediate states

**After changing prometheus.yml:**
```bash
docker restart prometheus
```

### Dashboard Tips

**State Timeline Panel:**
- Use `xrpl_validator_state_value` for numeric state (0-6)
- Map values to labels: 0=disconnected, 1=connected, 2=syncing, 3=tracking, 4=full, 6=proposing
- Color code: red (disconnected), yellow (connected), orange (syncing), blue (full), green (proposing)

**Historical State Tracking:**
- Use `xrpl_state_accounting_duration_seconds` to see cumulative time in each state
- Use `xrpl_state_accounting_transitions` to count how many times each state was entered

**Alert Thresholds:**
- Alert if state != proposing for >5 minutes
- Alert if validation agreement drops below 95%
- Alert if peer count <10

## Uninstallation

The uninstall script performs surgical removal of all installed components based on the installation tracker.

```bash
# Full uninstall (removes everything including Python service)
sudo ./uninstall.sh

# Preview what will be removed (dry-run)
sudo ./uninstall.sh --dry-run

# Remove specific components
sudo ./uninstall.sh --monitoring-only
sudo ./uninstall.sh --rippled-only
```

**What gets removed:**
- ✅ Python monitoring service (xrpl-monitor.service)
- ✅ Python source code (src/ directory)
- ✅ Database and logs
- ✅ Docker containers and volumes
- ✅ Configuration files
- ✅ Installation directories
- ✅ System services
- ✅ Installation tracker

**What is preserved:**
- Docker images (use `docker image prune` manually if needed)
- Backup files (stored in `${INSTALL_DIR}_backup_<timestamp>/`)
- Python dependencies (use `pip3 uninstall prometheus-client` if desired)

**Verification:**

After uninstall, the script verifies complete removal:
```bash
# Service removed
systemctl status xrpl-monitor  # Should not exist

# Metrics endpoint gone
curl http://localhost:9091/metrics  # Should fail

# Directory removed
ls ${INSTALL_DIR}  # Should not exist
```

## Troubleshooting

### Python Monitor Not Starting

1. Check service status:
```bash
sudo systemctl status xrpl-monitor
sudo journalctl -u xrpl-monitor -n 50
```

2. Common issues:
   - **Permission denied**: Check file ownership in `${INSTALL_DIR}/src`
   - **Module not found**: Reinstall Python dependencies: `pip3 install -r requirements.txt`
   - **Connection refused**: Verify rippled is running and accessible on port 5005

3. Test manually:
```bash
# Run Python monitor directly to see errors
sudo -u $USER python3 ${INSTALL_DIR}/src/collectors/fast_poller.py
```

### Metrics Not Appearing in Grafana

1. Check Python metrics endpoint:
```bash
curl http://localhost:9091/metrics
```

2. Check Prometheus targets:
   - Visit http://localhost:9090/targets
   - Look for `xrpl-monitor` job
   - Should show "UP" status

3. Verify Prometheus scrape config:
```bash
cat ${INSTALL_DIR}/monitoring/prometheus/prometheus.yml | grep -A 5 xrpl-monitor
```

### Database Errors

1. Check database file:
```bash
ls -la ${INSTALL_DIR}/data/monitor.db
```

2. Check permissions:
```bash
sudo chown $USER:$USER ${INSTALL_DIR}/data/monitor.db
```

3. Verify database integrity:
```bash
sqlite3 ${INSTALL_DIR}/data/monitor.db "PRAGMA integrity_check;"
```

### Rippled Not Syncing

1. Check peer connections:
```bash
docker exec rippledvalidator rippled peers
```

2. Verify port 51235 is accessible:
```bash
sudo netstat -tulpn | grep 51235
```

3. Check firewall rules

### Grafana Dashboard Not Loading

1. Verify Prometheus datasource:
   - Grafana → Configuration → Data Sources
   - Check Prometheus URL: http://prometheus:9090

2. Test Prometheus query:
   - Visit http://localhost:9090
   - Try query: `xrpl_validator_state_value`

### High Memory Usage

1. Check rippled memory:
```bash
docker stats rippledvalidator
```

2. Check Python monitor memory:
```bash
systemctl status xrpl-monitor | grep Memory
```

3. Adjust memory limits in docker-compose.yml:
```yaml
mem_limit: "64g"  # Adjust based on available RAM
```

4. Consider reducing `node_size` in rippled.cfg (not recommended for validators)

### Container Won't Start

1. Check logs:
```bash
docker logs rippledvalidator
```

2. Verify volumes exist:
```bash
ls -la ${INSTALL_DIR}/rippled/{config,data}
```

3. Check port conflicts:
```bash
sudo netstat -tulpn | grep -E "51235|5005|3000|9090|9091"
```

For more troubleshooting, see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

**For optimization tips and best practices, see [docs/TIPS.md](docs/TIPS.md)**

## Project Structure

```
xrpl-validator-monitor-dashboard/
├── README.md                          # This file
├── LICENSE                            # MIT License
├── install.sh                         # Installation script (deploys Python service)
├── uninstall.sh                       # Uninstallation script (removes Python service)
├── requirements.txt                   # Python dependencies
├── docker-compose-full.yml            # Full stack (rippled + monitoring)
├── docker-compose-monitoring.yml      # Monitoring only
├── docker-compose-rippled-template.yml # Rippled reference config
├── src/                               # Python monitoring service source code
│   ├── README.md                      # Technical documentation for developers
│   ├── alerts/
│   │   └── alerter.py                 # Alert system for state changes
│   ├── collectors/
│   │   ├── fast_poller.py             # Main monitoring loop (3s polling)
│   │   └── validation_tracker.py     # Validation performance tracking
│   ├── exporters/
│   │   └── prometheus_exporter.py    # Prometheus metrics exporter (port 9091)
│   ├── storage/
│   │   └── database.py                # SQLite database for historical data
│   ├── utils/
│   │   ├── rippled_api.py             # rippled API client (Docker/native)
│   │   └── config.py                  # Configuration loader
│   ├── outputs/                       # Reserved for future output plugins
│   └── processors/                    # Reserved for future data processors
├── systemd/
│   └── xrpl-monitor.service.template  # Systemd service template for Python monitor
├── config/
│   ├── rippled.cfg.template           # Rippled configuration template
│   ├── validators.txt.template        # UNL template
│   └── prometheus.yml.template        # Prometheus configuration template
├── monitoring/
│   ├── grafana/
│   │   └── dashboards/
│   │       └── Rippled-Dashboard.json # Pre-built Grafana dashboard
│   └── prometheus/
│       └── prometheus.yml             # Prometheus config
├── scripts/
│   ├── backup.sh                      # Backup script
│   └── restore.sh                     # Restore script
└── docs/
    ├── PREREQUISITES.md               # Detailed prerequisites
    ├── INSTALLATION.md                # Detailed installation guide
    ├── TROUBLESHOOTING.md             # Troubleshooting guide
    ├── TIPS.md                        # Tips & best practices
    ├── SECURITY.md                    # Security best practices
    └── DEVELOPMENT.md                 # Developer guide for Python codebase
```

### Key Files Explained

**install.sh & uninstall.sh**
- These scripts handle **everything**, including Python service deployment
- install.sh: Installs dependencies, copies src/, creates systemd service, starts monitoring
- uninstall.sh: Stops service, removes files, cleans up completely
- Both track all changes for surgical removal

**src/ directory**
- Complete Python monitoring system
- Automatically deployed by install.sh
- Runs as systemd service (xrpl-monitor.service)
- See [src/README.md](src/README.md) for technical details

**systemd/ directory**
- Service templates for xrpl-monitor
- install.sh replaces variables with actual paths
- Creates `/etc/systemd/system/xrpl-monitor.service`

**requirements.txt**
- Python dependencies (mainly prometheus-client)
- Automatically installed by install.sh

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### For Code Contributions

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Make your changes
4. Test thoroughly (especially if modifying Python monitoring service)
5. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
6. Push to the branch (`git push origin feature/AmazingFeature`)
7. Open a Pull Request

### Development Setup

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for:
- Project architecture
- Code structure
- Testing procedures
- Contributing guidelines

### Areas for Contribution

- Additional metrics in Python monitor
- Dashboard panel improvements
- Alert rule templates
- Documentation enhancements
- Bug fixes and performance improvements

## Acknowledgments

- [Ripple](https://ripple.com) - For the XRPL protocol
- [XRPL Labs](https://xrpl-labs.com) - For the rippled Docker image
- [Prometheus](https://prometheus.io) - Monitoring and alerting
- [Grafana](https://grafana.com) - Visualization and dashboards
- Python community for excellent monitoring libraries

## Support

- **Documentation**: [docs/](docs/)
- **Python Monitor Docs**: [src/README.md](src/README.md)
- **Developer Guide**: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- **Issues**: https://github.com/realGrapedrop/xrpl-validator-monitor-dashboard/issues
- **XRPL Documentation**: https://xrpl.org/docs.html
- **Author**: [Grapedrop](https://xrp-validator.grapedrop.xyz) | [@realGrapedrop](https://x.com/realGrapedrop)

## Author

**Grapedrop**
- Website: https://xrp-validator.grapedrop.xyz
- X/Twitter: [@realGrapedrop](https://x.com/realGrapedrop)
- Running XRPL validator since 2023

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This software is provided "as is" without warranty. Running an XRPL validator requires technical expertise and understanding of the risks involved. Always test in a non-production environment first.

**Note:** This project does NOT include Cloudflare Tunnel setup for exposing the validator. Users must configure their own secure access methods.
