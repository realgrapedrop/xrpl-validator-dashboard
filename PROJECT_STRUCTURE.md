# Project Structure

Quick reference for navigating the codebase.

## Root Directory

```
xrpl-validator-monitor-dashboard/
├── install.sh                         # Main installer - handles everything
├── uninstall.sh                       # Clean removal - reads install tracker
├── requirements.txt                   # Just prometheus-client for now
├── README.md                          # Start here
├── LICENSE                            # MIT
```

## Python Source (src/)

The monitoring service that does all the work.

```
src/
├── collectors/
│   ├── fast_poller.py                # Entry point - runs every 3 sec
│   └── validation_tracker.py        # Tracks validation performance
├── exporters/
│   └── prometheus_exporter.py       # Serves metrics on :9091
├── storage/
│   └── database.py                  # SQLite wrapper
├── utils/
│   ├── rippled_api.py               # Talks to rippled (Docker or native)
│   └── config.py                    # Config loader
└── alerts/
    └── alerter.py                   # Alert logic
```

**Note:** Each directory needs `__init__.py` or Python imports break.

## Configuration Templates

```
config/
├── rippled.cfg.template             # Main rippled config
├── validators.txt.template          # UNL list
└── prometheus.yml.template          # Prometheus scrape config
```

## Docker Compose Files

```
docker-compose-full.yml              # Everything (rippled + monitoring)
docker-compose-monitoring.yml        # Just monitoring stack
docker-compose-rippled-template.yml  # Reference only
```

## Monitoring Stack

```
monitoring/
└── grafana/
    └── dashboards/
        └── Rippled-Dashboard.json   # Pre-built dashboard
```

## Systemd Service

```
systemd/
└── xrpl-monitor.service.template    # Service file (install.sh processes this)
```

Variables like `${INSTALL_DIR}` and `${USER}` get replaced during installation.

## Documentation

```
docs/
├── PREREQUISITES.md                 # What you need before installing
├── TROUBLESHOOTING.md               # Common issues
├── TIPS.md                          # Performance tips
├── SECURITY.md                      # Security best practices
└── DEVELOPMENT.md                   # For contributors
```

## Scripts

```
scripts/
├── backup.sh                        # Backup utility
└── restore.sh                       # Restore utility
```

## Images

```
images/
├── dashboard-screenshot.png         # README screenshot
└── dashboard-demo.gif               # Animated demo
```

## Installation Artifacts

These get created during installation (not in repo):

```
${INSTALL_DIR}/                      # User-specified, default ~/xrpl-validator
├── src/                             # Python source (copied from repo)
├── data/
│   └── monitor.db                   # SQLite database
├── logs/
│   ├── monitor.log                  # Application logs
│   └── error.log                    # Error logs
├── rippled/                         # If using --full mode
│   ├── config/
│   └── data/
└── monitoring/                      # Prometheus/Grafana data
    ├── prometheus/
    └── grafana/
```

## System Files Created

```
/etc/systemd/system/xrpl-monitor.service  # Created from template
.install-tracker.json                      # Tracks everything for uninstall
```

## What Gets Tracked for Uninstall

The `.install-tracker.json` file records:
- All files copied
- Directories created
- Docker containers started
- Systemd services installed
- Config files generated

This lets `uninstall.sh` remove everything cleanly.

## Import Paths

Python imports work like this:

```python
from src.utils.rippled_api import RippledAPI
from src.storage.database import Database
from src.exporters.prometheus_exporter import PrometheusExporter
```

That's why every directory needs `__init__.py`.

## Key Entry Points

- **Installation**: `install.sh`
- **Service execution**: `src/collectors/fast_poller.py`
- **Metrics endpoint**: http://localhost:9091/metrics
- **Database**: `${INSTALL_DIR}/data/monitor.db`
- **Logs**: `${INSTALL_DIR}/logs/monitor.log`

## File Count

As of last check:
- 15 Python source files
- 14 `__init__.py` files (package markers)
- 3 shell scripts (install, uninstall, helpers)
- 3 Docker compose files
- 1 Grafana dashboard
- Multiple docs and templates

## Notes

- Don't delete `__init__.py` files - they're required for Python imports
- The `src/` directory structure mirrors how the code is organized logically
- Database schema auto-creates on first run
- Service logs go to systemd journal AND log files
- Prometheus scrapes the exporter, it doesn't push
