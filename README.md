# XRPL Validator Monitor Dashboard

A comprehensive monitoring solution for XRPL (Ripple) validator nodes. Provides real-time metrics, performance tracking, and alerting through Grafana and Prometheus.

**Created by:** [Grapedrop](https://xrp-validator.grapedrop.xyz) | [@realGrapedrop](https://x.com/realGrapedrop)

## Features

- 📊 **Real-time Monitoring** - Track validator performance, consensus state, and network metrics
- 🐳 **Docker-based** - Easy deployment with Docker Compose
- 🔧 **Modular Installation** - Choose what you need (full stack, monitoring only, or just the dashboard)
- 📈 **Pre-built Dashboard** - Grafana dashboard with key XRPL validator metrics
- 🔐 **Security Hardened** - Best practices for production validator security
- 🗑️ **Clean Uninstall** - Surgical removal script that tracks and removes everything

## Table of Contents

- [Prerequisites](#prerequisites)
- [Use Cases](#use-cases)
- [Quick Start](#quick-start)
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
- **RAM**: 4GB minimum
- **Storage**: 50GB for metrics retention

### Network Requirements
- Peer port: 51235 (TCP/UDP) - Must be publicly accessible
- Admin ports: 5005, 5006, 6006 (bound to localhost only)

## Use Cases

This project supports multiple deployment scenarios:

### Use Case 1: Full Stack with Docker Rippled
Complete setup including rippled validator and monitoring stack.
```bash
./install.sh --full
```

### Use Case 2: Monitoring Only (Docker Rippled)
Add monitoring to existing rippled Docker container.
```bash
./install.sh --monitoring --rippled-type docker
```

### Use Case 3: Monitoring Only (Native Rippled)
Add monitoring to rippled running as systemd service or binary.
```bash
./install.sh --monitoring --rippled-type native
```

### Use Case 4: Dashboard Only
Import dashboard into existing Grafana instance.
```bash
./install.sh --dashboard-only
```

## Quick Start

**Full installation with rippled validator:**

```bash
# Clone repository
git clone https://github.com/realGrapedrop/xrpl-validator-monitor-dashboard.git
cd xrpl-validator-monitor-dashboard

# Run installation
sudo ./install.sh --full

# Follow the prompts to configure
```

**Monitoring only (existing rippled):**

```bash
# Clone repository
git clone https://github.com/realGrapedrop/xrpl-validator-monitor-dashboard.git
cd xrpl-validator-monitor-dashboard

# Install monitoring stack
sudo ./install.sh --monitoring --rippled-type docker

# Access Grafana at http://localhost:3000
# Default credentials: admin/admin (change on first login)
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
- `--full` - Complete stack (rippled + monitoring)
- `--monitoring` - Monitoring stack only
- `--dashboard-only` - Import dashboard only
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

### Step 4: Verify Installation

```bash
# Check rippled status (if installed)
docker ps | grep rippledvalidator
docker exec rippledvalidator rippled server_info

# Check monitoring stack
docker ps | grep -E "prometheus|grafana|node"

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

### Prometheus Configuration

Prometheus config is at `${INSTALL_DIR}/monitoring/prometheus/prometheus.yml`

Default scrape targets:
- rippled metrics: `localhost:5005`
- node_exporter: `localhost:9100`
- cadvisor: `localhost:8080`

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
cd ${INSTALL_DIR}
docker compose -f docker-compose-full.yml up -d
```

**Monitoring only:**
```bash
cd ${INSTALL_DIR}
docker compose -f docker-compose-monitoring.yml up -d
```

### Stopping Services

```bash
cd ${INSTALL_DIR}
docker compose down
```

### Viewing Logs

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

**Check resource usage:**
```bash
docker stats
```

**Access Grafana:**
- URL: http://localhost:3000
- Default credentials: admin/admin

**Access Prometheus:**
- URL: http://localhost:9090

## Uninstallation

The uninstall script performs surgical removal of all installed components based on the installation tracker.

```bash
# Full uninstall (removes everything)
sudo ./uninstall.sh

# Preview what will be removed (dry-run)
sudo ./uninstall.sh --dry-run

# Remove specific components
sudo ./uninstall.sh --monitoring-only
sudo ./uninstall.sh --rippled-only
```

**What gets removed:**
- Docker containers and volumes
- Configuration files
- Installation directories
- System services (if any)
- Installation tracker

**What is preserved:**
- Docker images (use `docker image prune` manually if needed)
- Backup files (stored in `${INSTALL_DIR}/backups/`)

## Troubleshooting

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
   - Try query: `rippled_server_info`

### High Memory Usage

1. Check rippled memory:
```bash
docker stats rippledvalidator
```

2. Adjust memory limits in docker-compose.yml:
```yaml
mem_limit: "64g"  # Adjust based on available RAM
```

3. Consider reducing `node_size` in rippled.cfg (not recommended for validators)

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
sudo netstat -tulpn | grep -E "51235|5005|3000|9090"
```

For more troubleshooting, see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

## Project Structure

```
xrpl-validator-monitor-dashboard/
├── README.md                          # This file
├── LICENSE                            # MIT License
├── install.sh                         # Installation script
├── uninstall.sh                       # Uninstallation script
├── docker-compose-full.yml            # Full stack (rippled + monitoring)
├── docker-compose-monitoring.yml      # Monitoring only
├── docker-compose-rippled-template.yml # Rippled reference config
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
    └── SECURITY.md                    # Security best practices
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## Acknowledgments

- [Ripple](https://ripple.com) - For the XRPL protocol
- [XRPL Labs](https://xrpl-labs.com) - For the rippled Docker image
- [Prometheus](https://prometheus.io) - Monitoring and alerting
- [Grafana](https://grafana.com) - Visualization and dashboards

## Support

- **Documentation**: [docs/](docs/)
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
