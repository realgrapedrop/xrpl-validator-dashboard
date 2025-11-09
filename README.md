# XRPL Validator Dashboard

A comprehensive, self-contained monitoring dashboard for XRP Ledger (XRPL) validator nodes with automated setup wizard. Designed for Mainnet validators, also works for non-validator nodes (with limited validation metrics).

**Created by:** [Grapedrop](https://xrp-validator.grapedrop.xyz) | [@realGrapedrop](https://x.com/realGrapedrop)

## Dashboard Preview

![XRPL Validator Dashboard](images/xrpl-validator-monitor-dashboard-inaction.gif)

*Real-time monitoring of XRPL validator performance, consensus state, and network metrics*

## Why Use This Dashboard?

Running an XRPL validator is critical infrastructure - but manually checking health metrics is tedious and error-prone. This dashboard provides:

**Continuous Monitoring:**
- Catches state transitions instantly (proposing → tracking → syncing)
- Detects validation misses and network issues in real-time
- Tracks 24-hour validation agreement rates automatically

**Historical Analysis:**
- 30-day metric retention for troubleshooting
- Validation history stored in SQLite database
- State transition tracking with duration accounting

**Proactive Alerts:**
- Automatic alerts for state changes and validation issues
- Logged to file (`data/alerts.log`) and displayed in service logs
- Severity levels: INFO, WARNING, CRITICAL

**Minimal Overhead:**
Running the entire dashboard adds negligible load to your system:
- **CPU:** ~1% (barely noticeable)
- **Memory:** ~280 MB (out of typical 16-32GB servers)
- **Disk I/O:** ~20 KB/s (minimal)
- **Storage:** ~50-100 MB/month

**Compare this to:**
- Manual checking: Time-consuming, error-prone, no history
- SSH + rippled commands: No visualization, no historical trends
- Custom scripts: Requires maintenance, no standardized dashboard

## Features

- 🎯 **One-Command Setup** - Interactive wizard handles everything automatically
- 📊 **Real-time Monitoring** - 3-second polling captures rapid state transitions
- 🐳 **Self-Contained** - Grafana, Prometheus, and metrics exporter in one package
- 🔧 **Smart Configuration** - Auto-detects validator, checks ports, configures services
- 📈 **Pre-built Dashboard** - Production-ready Grafana dashboard with 40+ metrics
- 🚀 **Systemd Integration** - Run as background service with automatic startup
- 🧹 **Easy Cleanup** - One-command removal of all services and data
- ⚡ **Fast Deployment** - From zero to dashboard in under 5 minutes

## What You Get

The setup wizard (`setup.py`) automatically creates and configures:

**Docker Containers:**
- **Grafana** (port 3003) - Dashboard UI with beautiful visualizations
- **Prometheus** (port 9092) - Time-series database with 30-day retention
- **Node Exporter** (port 9102) - System metrics (CPU, RAM, Disk, Network)

**Systemd Service:**
- **XRPL Monitor** (fast_poller.py) - Polls rippled every 3 seconds, exports metrics on port 9094

**Local Storage:**
- **SQLite Database** (`data/monitor.db`) - Historical data and validation tracking
- **Alert Logs** (`data/alerts.log`) - State changes and validation issues

### Why Dedicated Services?

**This dashboard uses its own Prometheus and Grafana instances** rather than sharing with existing monitoring infrastructure. Here's why:

✅ **Simplicity** - No configuration conflicts with existing monitoring
✅ **Isolation** - Dashboard issues won't affect other services
✅ **Clean Uninstall** - One command removes everything, no orphaned data
✅ **Port Flexibility** - Setup wizard detects conflicts and suggests alternatives
✅ **Minimal Overhead** - Dedicated instances add only ~280 MB RAM and ~1% CPU

**Resource footprint per container:**
- Grafana: ~100 MB RAM, 0.2% CPU, 1GB limit
- Prometheus: ~100 MB RAM, 0.3% CPU, 2GB limit
- Node Exporter: ~30 MB RAM, <0.1% CPU, 128MB limit

If you already run Prometheus elsewhere, the ~280 MB overhead is negligible on validator servers (typically 16-32GB RAM). The benefit of simplified management far outweighs the small resource cost.

## Prerequisites

### Required Software

- **Docker** (v20.10+) - Container runtime
- **Docker Compose** (v2.0+) - Container orchestration
- **Python 3.6+** - For setup wizard and monitor service
- **pip3** - Python package manager

### Required Services

- **XRPL Validator (rippled)** running in Docker container

### Quick Check

```bash
# Check software versions
python3 --version  # Should be 3.6+
docker --version   # Should be 20.10+
docker compose version  # Should be v2.0+

# Verify rippled is running
docker ps | grep rippled
```

### Installing Docker (If Needed)

**New to Docker?** We've got you covered!

- **Ubuntu/Debian:** See our step-by-step guide: [DOCKER_INSTALL.md](DOCKER_INSTALL.md)
- **Other systems:** Official Docker documentation: https://docs.docker.com/engine/install/

**Note:** Python is typically pre-installed on Ubuntu/Debian. If not: `sudo apt install python3 python3-pip`

## Dashboard Compatibility

### Designed For: Mainnet Validators

This dashboard is **primarily designed for XRPL validator nodes on Mainnet** that actively participate in consensus and validation.

### What Works on Different Node Types

| Metric Category | Validator | Non-Validator | Testnet/Devnet |
|----------------|-----------|---------------|----------------|
| **Server Metrics** (CPU, RAM, Disk, Network) | ✅ Full | ✅ Full | ✅ Full |
| **Node State & Uptime** | ✅ Full | ✅ Full | ✅ Full |
| **Ledger Tracking** (Current Ledger, Age) | ✅ Full | ✅ Full | ✅ Full |
| **Network Metrics** (Peers, Latency, Traffic) | ✅ Full | ✅ Full | ✅ Full |
| **Validation Metrics** (Rate, Agreements) | ✅ Full | ⚠️ Always 0% | ✅ Full |
| **Validator Pubkey** | ✅ Shows key | ⚠️ Shows "none" | ✅ Shows key |
| **Consensus Metrics** (Proposers, Quorum) | ✅ Full | ✅ Full | ✅ Full |

### Expected Behavior for Non-Validators

If you run this dashboard on a **standalone/stock rippled node** (non-validator), the following panels will show **zero or "none"** - this is normal:

**Always Zero/Empty:**
- **Pubkey**: Shows "none"
- **Validation Rate**: 0%
- **Agreements % (1h & 24h)**: 0%
- **Agreements (1h & 24h)**: 0
- **Missed (1h & 24h)**: 0
- **Validations Checked**: 0.0

**Will Still Work:**
- ✅ All server metrics (CPU, RAM, Disk, Network)
- ✅ Server State (connected → syncing → tracking → full)
- ✅ Ledger tracking (Current Ledger, Age, Ledgers/min)
- ✅ Network metrics (Peers, Latency, Consensus time)
- ✅ Network consensus view (Proposers, Quorum)
- ✅ System performance metrics

**Bottom Line:** The dashboard works on non-validators but validation-specific panels will be empty. This is expected and not an error.

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/realgrapedrop/xrpl-validator-dashboard.git
cd xrpl-validator-dashboard
```

### 2. Run Setup Wizard

```bash
python3 setup.py
```

The wizard will guide you through:
- ✓ Prerequisite checks (Docker, Python, pip)
- ✓ Rippled container detection and connectivity test
- ✓ Port availability and conflict resolution
- ✓ Python dependency installation
- ✓ Configuration file generation
- ✓ Pre-flight validation
- ✓ Optional automatic service deployment

### 3. Choose Deployment

The wizard will ask: **"Automatically start services and import dashboard?"**

**Option A: Automatic (Recommended)**
- ✓ Starts Docker services (Grafana + Prometheus)
- ✓ Installs and starts systemd service
- ✓ Imports dashboard automatically
- ✓ Sets dashboard as home page

**Option B: Manual**
- Shows clear step-by-step commands to run
- Useful for custom deployments or troubleshooting

### 4. Access Dashboard

After automatic setup completes, the wizard shows:

```
================================================================================================
All Done! Everything is Running
================================================================================================

Services running:
  Grafana:    http://localhost:3003
  Prometheus: http://localhost:9092
  Metrics:    http://localhost:9094/metrics

You are ready to view your dashboard:
  1. Go to http://localhost:3003
  2. Login with username: admin / password: admin
  3. You will be prompted to change the password
  4. Dashboard opens automatically with all metrics ready!

⏳ Note: 24-hour metrics panels (Agreements %, Agreements, Missed) will
        populate after 5-10 minutes as historical data is collected.
```

## Architecture

```
┌──────────────────────────────────────────────────┐
│     XRPL Validator (rippled) - Docker            │
│     Listens on: localhost:5005 (admin API)       │
└──────────────────────────────────────────────────┘
                      │
                      │ Docker exec commands
                      ▼
┌──────────────────────────────────────────────────┐
│     XRPL Monitor Service (fast_poller.py)        │
│     - Polls every 3 seconds                      │
│     - Tracks validator state transitions         │
│     - Monitors validation performance            │
│     - Exports Prometheus metrics (port 9094)     │
│     - Stores data in SQLite                      │
└──────────────────────────────────────────────────┘
                      │
                      │ HTTP scrape (every 5s)
                      ▼
┌──────────────────────────────────────────────────┐
│     Prometheus (port 9092)                       │
│     - Time-series database                       │
│     - 30-day retention                           │
│     - Scrapes node-exporter for system metrics   │
└──────────────────────────────────────────────────┘
                      │
                      │ PromQL queries
                      ▼
┌──────────────────────────────────────────────────┐
│     Grafana (port 3003)                          │
│     - Pre-configured dashboard                   │
│     - Auto-imports on setup                      │
│     - Real-time visualization                    │
└──────────────────────────────────────────────────┘
```

## Port Configuration

The dashboard uses non-conflicting ports:

| Service | Port | Purpose | Access |
|---------|------|---------|--------|
| Grafana | 3003 | Dashboard UI | http://localhost:3003 |
| Prometheus | 9092 | Metrics storage | http://localhost:9092 |
| Node Exporter | 9102 | System metrics | http://localhost:9102/metrics |
| XRPL Monitor | 9094 | Validator metrics | http://localhost:9094/metrics |

**Smart Port Detection:**
- Wizard checks if ports are in use
- Shows existing containers using those ports
- Suggests next available port automatically
- Updates all configs consistently

## Dashboard Metrics

### Validator State Tracking
- Current state (proposing, full, tracking, syncing, etc.)
- Time in current state
- State transition history
- State duration accounting

### Validation Performance
- Validation agreement rate (24-hour and 1-hour)
- Total agreements and misses
- Validation participation percentage
- Proposer count and quorum size

### Network & Connectivity
- Peer connections (total, inbound, outbound)
- Peer latency (P90)
- Network stability
- Connection quality

### Ledger Metrics
- Current validated ledger sequence
- Ledger age and close times
- Consensus convergence time
- Transaction throughput

### System Performance
- CPU usage (server and validator process)
- Memory usage (RAM and SWAP)
- Disk I/O and usage
- Network I/O
- Load factor

## Configuration

### Main Config: `config.yaml`

Generated automatically by setup wizard:

```yaml
monitoring:
  poll_interval: 3              # Seconds between polls
  container_name: rippledvalidator  # Your rippled container

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

### Docker Compose Config

Automatically configured for your environment:
- `docker-compose.yml` - Main service definitions
- `compose/prometheus/prometheus.yml` - Prometheus scrape config
- `compose/grafana/provisioning/` - Grafana data sources

## Service Management

The monitor runs as a systemd service for reliability and automatic startup.

### Check Status

```bash
sudo systemctl status xrpl-validator-dashboard
```

### View Logs

```bash
# Real-time logs
sudo journalctl -u xrpl-validator-dashboard -f

# Application log
tail -f logs/monitor.log
```

### Control Service

```bash
# Start
sudo systemctl start xrpl-validator-dashboard

# Stop
sudo systemctl stop xrpl-validator-dashboard

# Restart
sudo systemctl restart xrpl-validator-dashboard
```

### Check Metrics Endpoint

```bash
curl http://localhost:9094/metrics | grep xrpl
```

## Cleanup & Removal

The cleanup script removes all services and data:

```bash
./cleanup.sh
```

**What it does:**
1. Stops and removes systemd service
2. Stops and removes Docker containers
3. Optionally removes Docker volumes (Prometheus & Grafana data)
4. Optionally removes database and logs
5. Waits for ports to fully release (15 seconds total)

**Safe defaults:**
- Prompts before removing volumes
- Prompts before removing database/logs
- Press Enter to remove, or 'n' to keep

After cleanup, you can run `python3 setup.py` again for a fresh installation.

## Directory Structure

```
xrpl-validator-dashboard/
├── setup.py                    # Interactive setup wizard
├── cleanup.sh                  # Cleanup script
├── install-service.sh          # Systemd service installer
├── config.yaml                 # Main configuration (generated)
├── docker-compose.yml          # Container orchestration
├── src/                        # Python source code
│   ├── collectors/             # Data collection
│   │   └── fast_poller.py      # Main monitoring loop
│   ├── exporters/              # Prometheus exporter
│   ├── storage/                # Database layer
│   ├── utils/                  # API clients & config
│   └── alerts/                 # Alert handlers
├── compose/                    # Docker service configs
│   ├── grafana/                # Grafana settings & dashboard
│   └── prometheus/             # Prometheus configuration
├── data/                       # Runtime data (SQLite)
├── logs/                       # Application logs
└── dashboards/                 # Dashboard JSON templates
```

## Advanced Usage

### Manual Service Installation

If you skipped automatic setup:

```bash
# Start Docker services
docker compose up -d

# Install systemd service
./install-service.sh

# Verify everything is running
docker compose ps
sudo systemctl status xrpl-validator-dashboard
curl http://localhost:9094/metrics
```

### Re-running Setup

Safe to run multiple times:
```bash
python3 setup.py
```

The wizard will:
- Detect existing configuration
- Offer to reconfigure if needed
- Update ports if conflicts detected
- Preserve existing data

### Custom Port Configuration

If you need different ports, edit before setup:
1. Edit `docker-compose.yml` - External port mappings
2. Edit `config.yaml` - Metrics exporter port
3. Run setup wizard to validate

### Database Queries

Access historical data:

```bash
# View record count
sqlite3 data/monitor.db "SELECT COUNT(*) FROM validator_metrics;"

# Recent validator states
sqlite3 data/monitor.db "SELECT datetime(timestamp, 'unixepoch'), server_state, ledger_seq FROM validator_metrics ORDER BY timestamp DESC LIMIT 10;"

# Validation statistics
sqlite3 data/monitor.db "SELECT * FROM validation_stats ORDER BY timestamp DESC LIMIT 5;"
```

## Troubleshooting

### Setup Wizard Issues

**Python not found:**
```bash
sudo apt update
sudo apt install python3 python3-pip
```

**Docker not found:**
```bash
# See: https://docs.docker.com/engine/install/
```

**Rippled container not detected:**
```bash
# Verify container is running
docker ps | grep rippled

# Test connectivity
docker exec <container_name> rippled server_info
```

### Port Conflicts

The wizard detects port conflicts automatically. If manual resolution needed:

```bash
# Find what's using a port
sudo lsof -i :3003
sudo netstat -tulpn | grep 3003

# Kill process or change port in config
```

### Service Won't Start

```bash
# Check service status
sudo systemctl status xrpl-validator-dashboard

# View detailed logs
sudo journalctl -u xrpl-validator-dashboard -n 50

# Check Python dependencies
pip3 list | grep prometheus
```

### No Metrics in Dashboard

1. **Check monitor is running:**
   ```bash
   sudo systemctl status xrpl-validator-dashboard
   curl http://localhost:9094/metrics
   ```

2. **Check Prometheus is scraping:**
   - Visit http://localhost:9092/targets
   - Look for `xrpl-monitor` job
   - Should show "UP" status

3. **Check Grafana datasource:**
   - Grafana → Settings → Data Sources → Prometheus
   - Test connection
   - Verify URL: `http://prometheus:9090`

### Dashboard Variables Not Working

The setup wizard automatically configures dashboard variables. If manually importing:

1. Ensure nodename matches your container
2. Check instance port matches Node Exporter port (9102)
3. Refresh dashboard variables (Dashboard settings → Variables)

## Development

### Project Structure

See [HOW_IT_WORKS.md](HOW_IT_WORKS.md) for detailed architecture documentation.

### Running Tests

```bash
# Test rippled API connectivity
python3 tests/manual/test_api.py

# Test database operations
python3 tests/manual/test_database.py

# 5-minute integration test
python3 tests/manual/test_poller_5min.py
```

### Customizing the Dashboard

1. Access Grafana at http://localhost:3003
2. Navigate to dashboard
3. Click panel title → Edit
4. Modify queries, visualizations, thresholds
5. Save dashboard
6. Export JSON to `dashboards/` directory

## Tips & Best Practices

### Optimal Refresh Rate

For real-time monitoring:
1. Set Grafana auto-refresh to **5 seconds** (top-right dropdown)
2. Enable "Refresh live dashboards" in dashboard settings
3. Matches Prometheus scrape interval for immediate updates

### Alert Configuration

**Built-in Alerts (Automatic):**

The monitor service automatically detects and logs alerts for:

**State Changes:**
- 🚨 CRITICAL: Validator enters `disconnected` or `syncing` state
- ⚠️  WARNING: Validator drops to `tracking` state
- ℹ️  INFO: Validator returns to `proposing` state
- Includes duration in previous state and current ledger

**Validation Issues:**
- 🚨 CRITICAL: Validation disagreement (voted against network consensus)
- ⚠️  WARNING: Missed validation opportunity

**Alert Storage:**
- Written to `data/alerts.log` with timestamps
- Displayed in service logs: `sudo journalctl -u xrpl-validator-dashboard -f`
- Color-coded output with emojis for easy identification

**View Recent Alerts:**
```bash
# Last 20 alerts
tail -20 data/alerts.log

# Watch alerts in real-time
tail -f data/alerts.log

# Service logs (includes alerts + metrics)
sudo journalctl -u xrpl-validator-dashboard -f
```

**Optional: Grafana Alerts**

You can also configure Grafana's alerting system for additional notifications:
- Validator state != proposing for >5 minutes
- Validation agreement rate <95%
- Peer count <10
- High CPU/memory usage

Configure in Grafana: Settings → Alerting → Contact Points (supports email, Slack, Discord, PagerDuty, etc.)

### Performance Tuning

**Reduce Prometheus retention for lower disk usage:**
Edit `docker-compose.yml`:
```yaml
--storage.tsdb.retention.time=7d  # Instead of 30d
```

**Adjust polling interval:**
Edit `config.yaml`:
```yaml
monitoring:
  poll_interval: 5  # Increase if needed
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

### Areas for Contribution
- Additional metrics and panels
- Dashboard improvements
- Setup wizard enhancements
- Documentation updates
- Bug fixes and optimizations

## Support

- **Documentation**: See [HOW_IT_WORKS.md](HOW_IT_WORKS.md) for architecture details
- **Dashboard Details**: See [GRAFANA_DASHBOARD.md](GRAFANA_DASHBOARD.md) for panel reference
- **Issues**: https://github.com/realgrapedrop/xrpl-validator-dashboard/issues
- **XRPL Documentation**: https://xrpl.org/docs.html
- **Author**: [Grapedrop](https://xrp-validator.grapedrop.xyz) | [@realGrapedrop](https://x.com/realGrapedrop)

## Author

**Grapedrop**
- Website: https://xrp-validator.grapedrop.xyz
- X/Twitter: [@realGrapedrop](https://x.com/realGrapedrop)
- Running XRPL validator since 2025

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Ripple](https://ripple.com) - For the XRPL protocol
- [Prometheus](https://prometheus.io) - Monitoring and time-series database
- [Grafana](https://grafana.com) - Visualization and dashboards
- XRPL Community - For validator tools and documentation

## Disclaimer

This software is provided "as is" without warranty. Running an XRPL validator requires technical expertise and understanding of the risks involved. Always test in a non-production environment first.
