# XRPL Monitor - Python Source Code

This directory contains the Python source code for the XRPL Validator Monitor.

## Structure

```
src/
├── alerts/
│   ├── __init__.py
│   └── alerter.py              # Alert system for state changes
├── collectors/
│   ├── __init__.py
│   ├── fast_poller.py          # Main monitoring loop (runs every 3s)
│   └── validation_tracker.py  # Tracks validator performance
├── exporters/
│   ├── __init__.py
│   └── prometheus_exporter.py # Exports metrics to Prometheus
├── storage/
│   ├── __init__.py
│   └── database.py             # SQLite database for historical data
├── utils/
│   ├── __init__.py
│   ├── config.py               # Configuration loader
│   └── rippled_api.py          # Interface to rippled (Docker/native)
├── outputs/
│   └── __init__.py             # Reserved for future output plugins
└── processors/
    └── __init__.py             # Reserved for future data processors
```

## Installation

These files are automatically installed by the main `install.sh` script.

### Manual Installation (for development)

```bash
# Install dependencies
pip3 install -r requirements.txt

# Set installation directory
export INSTALL_DIR=/path/to/install

# Copy source files
cp -r src/ $INSTALL_DIR/

# Create systemd service (see ../systemd/xrpl-monitor.service.template)
sudo cp systemd/xrpl-monitor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable xrpl-monitor
sudo systemctl start xrpl-monitor
```

## Path Templating

All Python files use `${INSTALL_DIR}` variable for paths. The install script replaces this with the actual installation directory during deployment.

## Dependencies

- **Python 3.8+** (uses standard library extensively)
- **prometheus-client** (only external dependency)
- **Docker** (if using Docker rippled)
- **rippled** (Docker or native installation)

## Testing

See `../tests/` directory for test files.

## Configuration

Configuration is loaded from:
1. `${INSTALL_DIR}/config/config.yaml` (primary)
2. Environment variables (override)
3. Default values (fallback)

## Entry Point

The main entry point is `src/collectors/fast_poller.py`, which is executed by the systemd service.
