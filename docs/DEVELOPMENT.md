# Development Guide - XRPL Validator Monitor

This document explains the project architecture, development workflow, and contribution guidelines for developers working on the XRPL Validator Monitor.

---

## Table of Contents

1. [Project Architecture](#project-architecture)
2. [Technology Stack](#technology-stack)
3. [Development Setup](#development-setup)
4. [Code Structure](#code-structure)
5. [Installation System](#installation-system)
6. [Testing](#testing)
7. [Contributing](#contributing)
8. [Deployment](#deployment)

---

## Project Architecture

### High-Level Overview

```
┌─────────────────┐
│  rippled node   │ ←─── Docker or Native
└────────┬────────┘
         │ RPC API (port 5005/51235)
         ↓
┌─────────────────────────────────────┐
│   Python Monitoring System          │
│  (fast_poller.py - runs every 3s)   │
│                                     │
│  ├── RippledAPI (query validator)   │
│  ├── Database (SQLite storage)      │
│  ├── ValidationTracker (metrics)    │
│  └── PrometheusExporter (port 9091) │
└────────┬────────────────────────────┘
         │ Metrics Export
         ↓
┌─────────────────┐      ┌──────────────┐
│   Prometheus    │─────→│   Grafana    │
│  (port 9090)    │      │  (port 3000) │
└─────────────────┘      └──────────────┘
         │                       │
         └───────────────────────┘
                  │
                  ↓
         ┌────────────────┐
         │   Dashboard    │
         │  Visualization │
         └────────────────┘
```

### Component Interaction

1. **Python Monitor** polls rippled every 3 seconds
2. **Stores** metrics in SQLite database
3. **Exports** to Prometheus via HTTP endpoint (port 9091)
4. **Prometheus** scrapes metrics every 15 seconds
5. **Grafana** queries Prometheus for visualization
6. **Alerts** trigger on state changes or anomalies

---

## Technology Stack

### Core Components

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Monitoring** | Python 3.8+ | Core monitoring logic |
| **Metrics Export** | prometheus-client | Metrics exposition |
| **Time-Series DB** | Prometheus | Metrics storage |
| **Visualization** | Grafana | Dashboard and alerts |
| **Local Storage** | SQLite | Historical data |
| **Service Management** | systemd | Process supervision |
| **Container Platform** | Docker | Optional deployment |

### Python Dependencies

```python
# Core - Required
prometheus-client>=0.19.0  # Metrics export

# Standard Library - No install needed
subprocess  # Docker/rippled commands
sqlite3     # Database
json        # API parsing
datetime    # Timestamps
logging     # Debug/alerts
```

---

## Development Setup

### Prerequisites

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y python3 python3-pip git docker.io

# Verify installations
python3 --version  # Should be 3.8+
docker --version
```

### Clone and Setup

```bash
# Clone repository
git clone https://github.com/yourusername/xrpl-validator-monitor.git
cd xrpl-validator-monitor

# Install Python dependencies
pip3 install -r requirements.txt

# Set environment variable for development
export INSTALL_DIR=$(pwd)
```

### Running Locally (Development Mode)

```bash
# Option 1: Direct execution (for testing)
python3 src/collectors/fast_poller.py

# Option 2: Install as systemd service (production-like)
sudo ./install.sh --monitoring --rippled-type docker

# Option 3: Docker compose (full stack)
docker-compose -f docker-compose-full.yml up -d
```

---

## Code Structure

### Directory Layout

```
xrpl-validator-monitor/
├── src/                          # Python source code
│   ├── alerts/                   # Alert system
│   │   ├── __init__.py
│   │   └── alerter.py           # Alert logic and notification
│   ├── collectors/               # Data collection
│   │   ├── __init__.py
│   │   ├── fast_poller.py       # Main polling loop (3s)
│   │   └── validation_tracker.py # Validation metrics
│   ├── exporters/                # Metrics export
│   │   ├── __init__.py
│   │   └── prometheus_exporter.py # Prometheus endpoint
│   ├── storage/                  # Data persistence
│   │   ├── __init__.py
│   │   └── database.py          # SQLite wrapper
│   ├── utils/                    # Utilities
│   │   ├── __init__.py
│   │   ├── config.py            # Configuration loader
│   │   └── rippled_api.py       # rippled API client
│   ├── outputs/                  # Reserved for future
│   └── processors/               # Reserved for future
├── systemd/                      # Service files
│   └── xrpl-monitor.service.template
├── config/                       # Configuration templates
│   └── templates/
├── dashboards/                   # Grafana dashboards
│   └── grafana/
├── docs/                         # Documentation
│   ├── PREREQUISITES.md
│   ├── TROUBLESHOOTING.md
│   └── DEVELOPMENT.md (this file)
├── tests/                        # Test files
│   ├── unit/
│   ├── integration/
│   └── manual/
├── install.sh                    # Installation script
├── uninstall.sh                  # Removal script
├── requirements.txt              # Python dependencies
└── README.md                     # User documentation
```

### Key Files Explained

#### `src/collectors/fast_poller.py`
**Purpose:** Main monitoring loop  
**Runs:** Every 3 seconds via systemd  
**Does:**
- Queries rippled via RippledAPI
- Tracks validator state changes
- Stores metrics in database
- Exports to Prometheus
- Triggers alerts on state changes

**Entry Point:** `main()` function

#### `src/utils/rippled_api.py`
**Purpose:** Interface to rippled validator  
**Supports:**
- Docker containers (`docker exec`)
- Native rippled installations
**Key Methods:**
- `get_server_state()` - Get validator status
- `get_validation_info()` - Get validation metrics
- `get_peers()` - Get peer information

#### `src/exporters/prometheus_exporter.py`
**Purpose:** Export metrics in Prometheus format  
**Exposes:** HTTP endpoint on port 9091  
**Metrics Types:**
- Gauge (current values)
- Counter (cumulative counts)
- Info (metadata labels)

#### `src/storage/database.py`
**Purpose:** SQLite database wrapper  
**Auto-creates:** Schema on first run  
**Stores:** Historical validator metrics  
**Tables:**
- `validator_metrics` - Core metrics with timestamps

---

## Installation System

### How Installation Works

The installation system uses **manifest tracking** to enable clean removal:

```
1. User runs: ./install.sh --monitoring --rippled-type docker
2. Script creates: .install-tracker.json
3. Every file/service created is tracked in manifest
4. User runs: ./uninstall.sh
5. Script reads manifest and removes everything
```

### Manifest Format

`.install-tracker.json`:
```json
{
  "project": "xrpl-monitor",
  "version": "1.0.0",
  "installed_at": "2025-10-15T12:00:00Z",
  "files": [
    "/path/to/install/src/collectors/fast_poller.py",
    "/path/to/install/src/utils/rippled_api.py"
  ],
  "directories": [
    "/path/to/install/src",
    "/path/to/install/logs"
  ],
  "systemd_services": [
    "xrpl-monitor.service"
  ],
  "docker_containers": [],
  "docker_volumes": []
}
```

### Installation Modes

| Mode | Installs | Use Case |
|------|----------|----------|
| `--full` | rippled + monitoring | New validator setup |
| `--monitoring --rippled-type docker` | Monitoring only | Existing Docker rippled |
| `--monitoring --rippled-type native` | Monitoring only | Existing native rippled |
| `--dashboard-only` | Dashboard import | Just Grafana setup |

### Path Templating

Python files use `${INSTALL_DIR}` placeholder:

```python
# In source (GitHub):
db_path = '${INSTALL_DIR}/data/monitor.db'

# After installation:
db_path = '/opt/xrpl-monitor/data/monitor.db'
```

The install script replaces placeholders during deployment.

---

## Testing

### Unit Tests

```bash
# Run unit tests
cd tests/unit
python3 -m pytest test_*.py

# Test specific module
python3 -m pytest test_rippled_api.py -v
```

### Integration Tests

```bash
# Run integration tests (requires rippled running)
cd tests/integration
python3 test_full_stack.py
```

### Manual Testing

```bash
# Test API connectivity
python3 tests/manual/test_rippled_connection.py

# Test Prometheus metrics
curl http://localhost:9091/metrics

# Test database writes
sqlite3 /path/to/install/data/monitor.db "SELECT COUNT(*) FROM validator_metrics;"

# Test service
sudo systemctl status xrpl-monitor
sudo journalctl -u xrpl-monitor -f
```

### Testing Installation

```bash
# Test in isolated directory
sudo ./install.sh --monitoring --rippled-type docker --install-dir /tmp/test-install

# Verify
systemctl status xrpl-monitor
curl http://localhost:9091/metrics

# Test uninstall
sudo ./uninstall.sh

# Verify clean removal
systemctl status xrpl-monitor  # Should not exist
ls /tmp/test-install            # Should be empty
```

---

## Contributing

### Development Workflow

1. **Fork** the repository
2. **Create** feature branch: `git checkout -b feature/my-feature`
3. **Make** changes following code style
4. **Test** thoroughly (unit + integration)
5. **Commit** with clear messages
6. **Push** to your fork
7. **Create** Pull Request

### Code Style

**Python (PEP 8):**
```python
# Use type hints
def get_state() -> Dict[str, Any]:
    pass

# Docstrings for all functions
def process_metrics(data: Dict) -> None:
    """
    Process validator metrics and store in database.
    
    Args:
        data: Raw metrics from rippled API
    """
    pass

# Clear variable names
validation_count = 0  # Good
vc = 0               # Bad
```

**Shell Scripts:**
```bash
# Use shellcheck
shellcheck install.sh

# Clear function names
install_python_monitor() {
    # Function purpose clear from name
}

# Error handling
set -euo pipefail  # Exit on error
```

### Commit Messages

```
Format: <type>: <subject>

Types:
- feat: New feature
- fix: Bug fix
- docs: Documentation
- refactor: Code restructuring
- test: Test additions
- chore: Maintenance

Examples:
feat: Add peer latency P90 tracking
fix: Handle rippled connection timeout
docs: Update installation prerequisites
```

### Pull Request Checklist

- [ ] Code follows project style
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] Changelog entry added
- [ ] No breaking changes (or clearly documented)
- [ ] install.sh/uninstall.sh tested
- [ ] Works with both Docker and native rippled

---

## Deployment

### Production Deployment

```bash
# 1. Download latest release
wget https://github.com/yourusername/xrpl-validator-monitor/archive/v1.0.0.tar.gz
tar -xzf v1.0.0.tar.gz
cd xrpl-validator-monitor-1.0.0

# 2. Review configuration
vi config/config.yaml.template

# 3. Install
sudo ./install.sh --monitoring --rippled-type docker

# 4. Verify
systemctl status xrpl-monitor
curl http://localhost:9091/metrics
```

### Updating Existing Installation

```bash
# 1. Stop service
sudo systemctl stop xrpl-monitor

# 2. Backup
sudo cp -r /opt/xrpl-monitor /opt/xrpl-monitor.backup

# 3. Pull updates
cd xrpl-validator-monitor
git pull

# 4. Reinstall (preserves data)
sudo ./install.sh --monitoring --rippled-type docker

# 5. Restart
sudo systemctl start xrpl-monitor
```

### Rollback

```bash
# If update fails, rollback:
sudo systemctl stop xrpl-monitor
sudo rm -rf /opt/xrpl-monitor
sudo mv /opt/xrpl-monitor.backup /opt/xrpl-monitor
sudo systemctl start xrpl-monitor
```

---

## Common Development Tasks

### Adding a New Metric

1. **Update `prometheus_exporter.py`:**
```python
# Add metric definition
self.new_metric = Gauge('xrpl_new_metric', 'Description')

# Add update method
def update_new_metric(self, value: float):
    self.new_metric.set(value)
```

2. **Update `fast_poller.py`:**
```python
# Extract from API
new_value = state.get('new_field', 0)

# Export to Prometheus
if self.prometheus:
    self.prometheus.update_new_metric(new_value)
```

3. **Test:**
```bash
# Restart service
sudo systemctl restart xrpl-monitor

# Check metric appears
curl http://localhost:9091/metrics | grep xrpl_new_metric
```

### Adding a New Alert

1. **Update `alerter.py`:**
```python
def check_new_condition(self, data: Dict) -> bool:
    """Check if new alert condition is met"""
    if data['metric'] > threshold:
        self.send_alert("New alert triggered")
        return True
    return False
```

2. **Call from `fast_poller.py`:**
```python
if self.alerter.check_new_condition(metrics):
    self.alerts_sent += 1
```

### Adding a New Dashboard Panel

1. **Create PromQL query** in Grafana
2. **Export dashboard JSON**
3. **Save to** `dashboards/grafana/`
4. **Update** documentation

---

## Troubleshooting Development Issues

### Python Import Errors

```bash
# Fix: Add project root to PYTHONPATH
export PYTHONPATH="${PYTHONPATH}:$(pwd)"
python3 src/collectors/fast_poller.py
```

### Service Won't Start

```bash
# Check logs
sudo journalctl -u xrpl-monitor -n 50 --no-pager

# Check Python errors
tail -50 /opt/xrpl-monitor/logs/error.log

# Test script directly
sudo -u grapedrop python3 /opt/xrpl-monitor/src/collectors/fast_poller.py
```

### Metrics Not Appearing

```bash
# Verify Prometheus exporter running
curl http://localhost:9091/metrics

# Check Prometheus scrape config
curl http://localhost:9090/api/v1/targets

# Check Prometheus logs
docker logs prometheus
```

---

## Resources

- **XRPL Docs:** https://xrpl.org/
- **Prometheus Docs:** https://prometheus.io/docs/
- **Grafana Docs:** https://grafana.com/docs/
- **Python prometheus-client:** https://github.com/prometheus/client_python

---

## Getting Help

- **Issues:** https://github.com/yourusername/xrpl-validator-monitor/issues
- **Discussions:** https://github.com/yourusername/xrpl-validator-monitor/discussions
- **XRPL Discord:** Community support

---

## License

MIT License - See LICENSE file for details.

---

**Last Updated:** October 2025  
**Maintainer:** [Email Grapedrop](mailto:captain@grapedrop.xyz)
