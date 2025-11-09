# XRPL Validator Dashboard v2.0

A comprehensive, self-contained monitoring dashboard for XRP Ledger (XRPL) validator nodes with automated setup wizard. Designed for Mainnet validators, also works for non-validator nodes (with limited validation metrics).

**Created by:** [Grapedrop](https://xrp-validator.grapedrop.xyz) | [@realGrapedrop](https://x.com/realGrapedrop)

## Dashboard Preview

![XRPL Validator Dashboard](images/xrpl-validator-monitor-dashboard-inaction.gif)

*Real-time monitoring of XRPL validator performance, consensus state, and network metrics*

---

**⚠️ Upgrading from an older version?** This is a complete rewrite with a modern Docker-based architecture. See **[MIGRATION.md](docs/MIGRATION.md)** for upgrade instructions.

---

## Why Use This Dashboard?

Running an XRPL validator is critical infrastructure - but manually checking health metrics is tedious and error-prone. This dashboard provides:

For a full list of metrics, see [METRICS.md](docs/METRICS.md).

**Continuous Monitoring:**
- Catches state transitions across 6 states (unreachable → connected → syncing → tracking → full → proposing)
- Detects validation misses and network issues in real-time
- Tracks 24-hour validation agreement rates automatically
- Monitors server metrics (CPU load, I/O latency, job queue depth)

**Historical Analysis:**
- 30-day metric retention for troubleshooting
- Validation history stored in SQLite database
- State transition tracking with duration accounting

**Proactive Alerts:**
- Automatic alerts for state changes and validation issues
- Insane peers detection (peers on different ledger chain)
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

**For detailed information about all 40+ metrics, thresholds, and troubleshooting guidance, see the [METRICS.md](docs/METRICS.md) guide.**

## Features

- 🎯 **One-Command Setup** - Automated installation with `./install.sh`
- 📊 **Real-time Monitoring** - 3-second polling captures rapid state transitions
- 🐳 **Self-Contained** - Grafana, Prometheus, and metrics exporter in one package
- 🔧 **Smart Configuration** - Auto-detects rippled (Docker or native), checks ports, configures services
- 📈 **Pre-built Dashboard** - Production-ready Grafana dashboard with 40+ metrics
- 🔄 **Automatic Updates** - Containerized monitor with host networking
- 🧹 **Easy Cleanup** - One-command removal with `./uninstall.sh`
- ⚡ **Fast Deployment** - From zero to dashboard in under 5 minutes

## What You Get

The installation automatically creates and configures:

**Docker Containers:**
- **Grafana** - Dashboard UI with beautiful visualizations
- **Prometheus** - Time-series database with 30-day retention
- **Node Exporter** - System metrics (CPU, RAM, Disk, Network)
- **XRPL Monitor** - Polls rippled every 3 seconds, exports metrics

**Local Storage:**
- **SQLite Database** (`data/monitor.db`) - Historical data and validation tracking
- **Alert Logs** (`data/alerts.log`) - State changes and validation issues

**Note:** All services run in Docker containers using host networking mode to avoid firewall issues (especially on OCI).

### Why Dedicated Services?

**This dashboard uses its own Prometheus and Grafana instances** rather than sharing with existing monitoring infrastructure. Here's why:

- ✅ **Simplicity** - No configuration conflicts with existing monitoring
- ✅ **Isolation** - Dashboard issues won't affect other services
- ✅ **Clean Uninstall** - One command removes everything, no orphaned data
- ✅ **Port Flexibility** - Setup wizard detects conflicts and suggests alternatives
- ✅ **Minimal Overhead** - Dedicated instances add only ~280 MB RAM and ~1% CPU

**Resource footprint per container:**
- Grafana: ~100 MB RAM, 0.2% CPU, 1GB limit
- Prometheus: ~100 MB RAM, 0.3% CPU, 2GB limit
- Node Exporter: ~30 MB RAM, <0.1% CPU, 128MB limit
- XRPL Monitor: ~50 MB RAM, <0.1% CPU, 256MB limit

If you already run Prometheus elsewhere, the ~280 MB overhead is negligible on validator servers (typically 16-32GB RAM). The benefit of simplified management far outweighs the small resource cost.

## Prerequisites

### Required Software

- **Docker** (v20.10+) - Container runtime
- **Docker Compose** (v2.0+) - Container orchestration
- **Python 3.6+** - For setup wizard
- **pip3** - Python package manager

### Required Services

- **XRPL Node (rippled)** - Running in Docker container OR as native installation

### Quick Check

**Note:** If Docker or Python are missing, `./install.sh` (Part 1) will install them automatically. This check is optional.

```bash
# Check software versions (optional - installer will install if missing)
python3 --version  # Should be 3.6+
docker --version   # Should be 20.10+
docker compose version  # Should be v2.0+
```

**Note:** You don't need to have your XRPL node running to start the installation. The installer will detect it automatically during Part 2, whether it's Docker or Native, local or remote.

### Installing Prerequisites

**New to Docker?** See our installation guide:

- **Ubuntu/Debian:** [Installation Guide - Part 1](docs/INSTALL.md#part-1-prerequisites)
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

See detailed installation guides:
- **[Installation Guide](docs/INSTALL.md)** - Complete step-by-step instructions for Docker and Native rippled

### Summary

```bash
# 1. Clone repository
git clone https://github.com/realgrapedrop/xrpl-validator-dashboard.git
cd xrpl-validator-dashboard

# 2. Run installation (handles prerequisites and dashboard setup)
./install.sh

# 3. Access dashboard
# Open browser to http://localhost:<port shown in setup>
# Login: admin / admin
```

**That's it!** The installer handles everything automatically.

## Architecture

The dashboard supports both Docker and Native rippled installations:

### Docker Mode Architecture

```
┌──────────────────────────────────────────────────┐
│   XRPL Validator (rippled) - Docker Container    │
│   Exposes: Admin RPC via docker exec             │
└──────────────────────────────────────────────────┘
                      │
                      │ docker exec rippled server_info
                      ▼
┌──────────────────────────────────────────────────┐
│   XRPL Monitor (Containerized - Host Network)    │
│   - Polls every 3 seconds via docker exec        │
│   - Tracks validator state transitions           │
│   - Exports Prometheus metrics (port 9094)       │
│   - Stores data in SQLite                        │
└──────────────────────────────────────────────────┘
                      │
                      │ HTTP scrape (every 5s)
                      ▼
┌──────────────────────────────────────────────────┐
│   Prometheus (Containerized - Host Network)      │
│   - Time-series database (port 9092)             │
│   - 30-day retention                             │
│   - Scrapes monitor + node-exporter              │
└──────────────────────────────────────────────────┘
                      │
                      │ PromQL queries
                      ▼
┌──────────────────────────────────────────────────┐
│   Grafana (Containerized - Host Network)         │
│   - Pre-configured dashboard (port 3003)         │
│   - Auto-imports on setup                        │
│   - Real-time visualization                      │
└──────────────────────────────────────────────────┘
```

### Native Mode Architecture

```
┌──────────────────────────────────────────────────┐
│   XRPL Validator (rippled) - Native Install      │
│   Listens on: localhost:5015 (HTTP RPC)          │
└──────────────────────────────────────────────────┘
                      │
                      │ HTTP JSON-RPC (POST localhost:5015)
                      ▼
┌──────────────────────────────────────────────────┐
│   XRPL Monitor (Containerized - Host Network)    │
│   - Polls every 3 seconds via HTTP API           │
│   - Tracks validator state transitions           │
│   - Exports Prometheus metrics (port 9094)       │
│   - Stores data in SQLite                        │
└──────────────────────────────────────────────────┘
                      │
                      │ (Same as Docker mode from here)
                      ▼
              Prometheus → Grafana
```

**Key Difference:** Docker mode uses `docker exec` commands, Native mode uses HTTP JSON-RPC API.

**Why Host Networking?** All containers use `network_mode: "host"` to bypass Docker bridge networking and avoid firewall issues (especially critical on Oracle Cloud Infrastructure).

## Port Configuration

The dashboard uses the following default ports (auto-detected and configurable):

| Service | Default Port | Purpose | Access |
|---------|-------------|---------|--------|
| Grafana | 3001-3003 | Dashboard UI | http://localhost:PORT |
| Prometheus | 9090-9092 | Metrics storage | http://localhost:PORT |
| Node Exporter | 9100-9102 | System metrics | http://localhost:PORT/metrics |
| XRPL Monitor | 9094 | Validator metrics | http://localhost:PORT/metrics |

**Note:** The installer detects available ports automatically. Your actual ports may differ if defaults are in use.

**Smart Port Detection:**
- Installer checks if ports are in use
- Shows existing services using those ports
- Suggests next available port automatically
- Updates all configs consistently

## Configuration

### Main Config: `config.yaml`

Generated automatically by installer. Example for **Native Mode**:

```yaml
monitoring:
  poll_interval: 3
  mode: native
  rippled:
    host: localhost
    port: 5015

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

Example for **Docker Mode**:

```yaml
monitoring:
  poll_interval: 3
  mode: docker
  rippled:
    container_name: rippledvalidator

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

### Environment Variable Overrides

You can override any config value with environment variables:

```bash
# Format: XRPL_<section>_<key> (uppercase, underscores)
export XRPL_MONITORING_RIPPLED_HOST=192.168.1.100
export XRPL_MONITORING_RIPPLED_PORT=5005
export XRPL_PROMETHEUS_PORT=9095
```

Useful for containerized deployments where you can't easily edit config.yaml.

### Docker Compose Config

Automatically configured for your environment:
- `docker-compose.yml` - Main service definitions
- `compose/prometheus/prometheus.yml` - Prometheus scrape config
- `compose/grafana/provisioning/` - Grafana data sources

## Service Management

All services run as Docker containers. No systemd service needed!

### Check Status

```bash
# View all dashboard containers
docker ps --filter name=xrpl-dashboard

# Check specific container
docker logs xrpl-dashboard-monitor
docker logs xrpl-dashboard-grafana
docker logs xrpl-dashboard-prometheus
```

### Control Services

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# Restart specific service
docker restart xrpl-dashboard-monitor

# View logs
docker logs -f xrpl-dashboard-monitor
```

### Check Metrics Endpoint

```bash
curl http://localhost:9094/metrics | grep xrpl
```

## Cleanup & Removal

The uninstall script removes all services and data:

```bash
./uninstall.sh
```

**What it does:**
1. Stops and removes Docker containers
2. Optionally removes Docker volumes (Prometheus & Grafana data)
3. Optionally removes database and logs
4. Optionally removes Docker Engine entirely

**Safe defaults:**
- Prompts before removing volumes
- Prompts before removing database/logs
- Press Enter for defaults, or choose custom options

After cleanup, you can run `./install.sh` again for a fresh installation.

## Directory Structure

```
xrpl-validator-dashboard/
├── install.sh                  # Automated installer (Part 1 & 2)
├── uninstall.sh                # Cleanup script
├── config.yaml                 # Main configuration (generated)
├── docker-compose.yml          # Container orchestration
├── Dockerfile                  # Monitor container build
├── requirements.txt            # Python dependencies
├── src/                        # Python source code
│   ├── collectors/             # Data collection
│   │   └── fast_poller.py      # Main monitoring loop
│   ├── exporters/              # Prometheus exporter
│   ├── storage/                # Database layer
│   ├── utils/                  # API clients & config
│   └── alerts/                 # Alert handlers
├── scripts/                    # Helper scripts
│   ├── setup.py                # Interactive setup wizard (called by install.sh)
│   └── import-dashboard.sh     # Manual dashboard import
├── compose/                    # Docker service configs
│   ├── grafana/                # Grafana settings & dashboard
│   └── prometheus/             # Prometheus configuration
├── data/                       # Runtime data (SQLite, created on install)
├── logs/                       # Application logs (created on install)
├── dashboards/                 # Dashboard JSON templates
└── docs/                       # Documentation
    └── INSTALL.md              # Detailed installation guide
```

## Advanced Usage

### Manual Dashboard Import

If the automatic import failed during setup:

```bash
./scripts/import-dashboard.sh
```

### Re-running Setup

Safe to run multiple times:
```bash
./install.sh
```

The installer will:
- Detect existing Docker installation
- Detect existing rippled
- Offer to reconfigure if needed
- Update ports if conflicts detected
- Preserve existing data

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

### Common Issues

**1. Dashboard shows "No data"**
- Wait 30-60 seconds for initial data collection
- Check monitor is running: `docker logs xrpl-dashboard-monitor`
- Check Prometheus targets: http://localhost:9092/targets (should show "UP")

**2. Can't connect to rippled**
- **Native mode:** Rippled HTTP RPC may have stuck connections. Restart: `sudo systemctl restart rippled`
- **Docker mode:** Check container name is correct: `docker ps | grep rippled`

**3. Port conflicts**
- The installer detects these automatically
- To manually check: `ss -tlnp | grep -E ':(3000|9090|9100|9094)'`

**4. Dashboard import failed**
- Run manually: `./scripts/import-dashboard.sh`
- Ensure Grafana is running: `docker ps | grep grafana`

**5. Validation metrics showing zero**
- This is normal for non-validator nodes
- See [Dashboard Compatibility](#dashboard-compatibility) section

For more troubleshooting, see: [docs/INSTALL.md](docs/INSTALL.md)

## Dashboard Metrics

### Validator State Tracking
- Current state (proposing, full, tracking, syncing, connected, disconnected)
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
- Displayed in container logs: `docker logs xrpl-dashboard-monitor`
- Color-coded output with emojis for easy identification

**View Recent Alerts:**
```bash
# Last 20 alerts
tail -20 data/alerts.log

# Watch alerts in real-time
tail -f data/alerts.log

# Container logs (includes alerts + metrics)
docker logs -f xrpl-dashboard-monitor
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
- Installation wizard enhancements
- Documentation updates
- Bug fixes and optimizations

## Support

- **Installation Guide**: See [docs/INSTALL.md](docs/INSTALL.md) for step-by-step instructions
- **Architecture Details**: See [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md)
- **Dashboard Reference**: See [docs/GRAFANA_DASHBOARD.md](docs/GRAFANA_DASHBOARD.md)
- **Issues**: https://github.com/realgrapedrop/xrpl-validator-dashboard/issues
- **XRPL Documentation**: https://xrpl.org/docs.html
- **Author**: [Grapedrop](https://xrp-validator.grapedrop.xyz) | [@realGrapedrop](https://x.com/realGrapedrop)

## Author

**Grapedrop**
- Website: https://xrp-validator.grapedrop.xyz
- X/Twitter: [@realGrapedrop](https://x.com/realGrapedrop)
- Running XRPL validator since 2025

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.

## Acknowledgments

- [Ripple](https://ripple.com) - For the XRPL protocol
- [Prometheus](https://prometheus.io) - Monitoring and time-series database
- [Grafana](https://grafana.com) - Visualization and dashboards
- XRPL Community - For validator tools and documentation

## Disclaimer

This software is provided "as is" without warranty. Running an XRPL validator requires technical expertise and understanding of the risks involved. Always test in a non-production environment first.
