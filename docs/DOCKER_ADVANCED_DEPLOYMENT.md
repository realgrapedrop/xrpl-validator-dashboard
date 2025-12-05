# **__DOCKER DEPLOYMENT GUIDE__**

*Advanced Docker deployment options for fully containerized monitoring.*

---

# Table of Contents

- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Volume Mounts](#volume-mounts)
- [Configuration](#configuration)
- [Deployment Scenarios](#deployment-scenarios)
- [Troubleshooting](#troubleshooting)
- [Metrics Collection](#metrics-collection)
- [Performance](#performance)
- [Security](#security)
- [Updates](#updates)
- [Logs](#logs)
- [Health Checks](#health-checks)
- [Integration with Rippled-In-A-Box](#integration-with-rippled-in-a-box)

---

# Quick Start

1. **Configure environment**:
   ```bash
   cp .env.example .env
   nano .env  # Edit configuration
   ```

2. **Find your Docker group ID** (for socket access):
   ```bash
   getent group docker | cut -d: -f3
   ```
   Add to `.env`:
   ```bash
   DOCKER_GID=999  # Use your actual Docker GID
   ```

3. **Build and start**:
   ```bash
   docker compose up -d collector victoria-metrics grafana
   ```

4. **Check logs**:
   ```bash
   docker compose logs -f collector
   ```

5. **Access dashboard**:
   - Grafana: http://localhost:3000 (admin/admin)
   - VictoriaMetrics: http://localhost:8428

# Architecture

**Default Setup (Host Networking)**
```
┌────────────────────────────────────────────────────┐
│                  Host Network                      │
│  ┌────────────┐  ┌────────────┐  ┌──────────────┐  │
│  │ Collector  │─→│  Victoria  │←─│   Grafana    │  │
│  │ (host net) │  │  Metrics   │  │ (Dashboard)  │  │
│  └────────────┘  └────────────┘  └──────────────┘  │
│       │ ↓                                          │
│       │ ↓    Can access localhost (rippled)        │
└───────│─↓──────────────────────────────────────────┘
        │ ↓
    ┌───┴─↓──────────────┐
    │  Docker Socket    │  (for peer metrics)
    │  rippled Data Dir │  (for NuDB metrics)
    │  rippled on host  │  (native or Docker)
    └──────────────────┘
```

**Rippled-In-A-Box Setup (Bridge Networking)**
```
┌────────────────────────────────────────────────────┐
│              xrpl-monitor-network (bridge)         │
│  ┌────────────┐  ┌────────────┐  ┌──────────────┐  │
│  │ Collector  │─→│  Victoria  │←─│   Grafana    │  │
│  │ (Python)   │  │  Metrics   │  │ (Dashboard)  │  │
│  └────────────┘  └────────────┘  └──────────────┘  │
│       │ ↓              │                           │
│       │ ↓              │                           │
│       │ ↓         ┌────┴──────┐                    │
│       │ ↓         │  rippled  │  (in Docker)       │
│       │ ↓         └───────────┘                    │
└───────│─↓──────────────────────────────────────────┘
        │ ↓
    ┌───┴─↓────────────┐
    │  Docker Socket   │  (for peer metrics)
    │  rippled Volume  │  (for NuDB metrics)
    └──────────────────┘
```

# Volume Mounts

The collector container requires two key mounts:

### 1. Docker Socket (Peer Metrics)
```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
```
**Purpose**: Enables `docker exec` fallback for peer metrics when rippled API is restricted.

### 2. rippled Data Directory (NuDB Metrics)
```yaml
volumes:
  - ${RIPPLED_DATA_PATH:-/var/lib/rippled}:/rippled-data:ro
```

**Configuration options**:
- **Native rippled**: Use `/var/lib/rippled` (default)
- **Docker rippled**: Use host mount path (e.g., `/home/user/rippled/data`)
- Set in `.env`:
  ```bash
  RIPPLED_DATA_PATH=/home/username/rippled/data
  ```

# Configuration

### Network Configuration

**For Docker rippled** (rippled in a container):
```bash
# .env
RIPPLED_WS_URL=ws://rippledvalidator:6006
RIPPLED_HTTP_URL=http://rippledvalidator:5005
RIPPLED_DOCKER_CONTAINER=rippledvalidator
```

**For Native rippled** (rippled on host):
```bash
# .env
RIPPLED_WS_URL=ws://localhost:6006
RIPPLED_HTTP_URL=http://localhost:5005
# Leave RIPPLED_DOCKER_CONTAINER commented out
```

### Required Environment Variables

```bash
# Validator tracking (required for validation metrics)
VALIDATOR_PUBLIC_KEY=nHB6bPcp9jk8QbUZiGXoonERK9rcDvjZUJAoFsGVCs2ZgUdCtnSV

# Docker socket access (required for peer metrics fallback)
DOCKER_GID=999  # Find with: getent group docker | cut -d: -f3

# rippled data path (required for NuDB metrics)
RIPPLED_DATA_PATH=/home/username/rippled/data
```

### Optional Environment Variables

```bash
# Docker container name (if rippled runs in Docker)
RIPPLED_DOCKER_CONTAINER=rippledvalidator

# Logging level
LOG_LEVEL=INFO  # DEBUG, INFO, WARNING, ERROR, CRITICAL
```

# Deployment Scenarios

### Scenario 1: Default Setup (Host Networking)

**Works with both native rippled and Docker rippled**. The monitor uses host networking to access localhost directly.

This is the **default configuration** and works out-of-the-box.

**Configuration (.env)**:
```bash
# Works for both native rippled and Docker rippled on localhost
RIPPLED_WS_URL=ws://localhost:6006
RIPPLED_HTTP_URL=http://localhost:5005
VICTORIA_METRICS_URL=http://localhost:8428

VALIDATOR_PUBLIC_KEY=nHB6bPcp9jk8QbUZiGXoonERK9rcDvjZUJAoFsGVCs2ZgUdCtnSV
DOCKER_GID=999  # Run: getent group docker | cut -d: -f3
RIPPLED_DATA_PATH=/var/lib/rippled  # or /home/user/rippled/data for Docker rippled
RIPPLED_DOCKER_CONTAINER=rippledvalidator  # If rippled runs in Docker
```

**Start the stack**:
```bash
cp .env.example .env
nano .env  # Configure your settings
docker compose up -d
```

**Benefits**:
- Simple configuration (uses localhost)
- Works with native rippled
- Works with Docker rippled bound to localhost
- No network complexity

### Scenario 2: Rippled-In-A-Box (All-in-One Container Stack)

**For turnkey deployments** where everything (rippled + monitoring) runs in Docker with container-to-container networking.

This setup requires modifying docker-compose.yml to use bridge networking instead of host networking.

**1. Modify docker-compose.yml**:
```yaml
services:
  # Add rippled service
  rippled:
    image: xrpllabsofficial/xrpld:latest
    container_name: rippledvalidator
    volumes:
      - rippled_data:/var/lib/rippled
      - ./rippled.cfg:/etc/rippled/rippled.cfg:ro
    networks:
      - xrpl-monitor-network
    # ... other rippled config

  # Modify collector service
  collector:
    # ... keep existing build, volumes, etc ...
    environment:
      # Connect via container name instead of localhost
      - RIPPLED_WS_URL=ws://rippledvalidator:6006
      - RIPPLED_HTTP_URL=http://rippledvalidator:5005
      - VICTORIA_METRICS_URL=http://victoria-metrics:8428
      - RIPPLED_DOCKER_CONTAINER=rippledvalidator
      - RIPPLED_DATA_PATH=/rippled-data
      - VALIDATOR_PUBLIC_KEY=${VALIDATOR_PUBLIC_KEY}
      - LOG_LEVEL=${LOG_LEVEL:-INFO}
      - DOCKER_GID=${DOCKER_GID:-999}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - rippled_data:/rippled-data:ro  # Mount rippled's volume
      - ./logs:/app/logs
    # CHANGE: Use bridge network instead of host
    networks:
      - xrpl-monitor-network
    # REMOVE: network_mode: "host" line
    depends_on:
      - victoria-metrics
      - rippled
    group_add:
      - ${DOCKER_GID:-999}

  victoria-metrics:
    # ... existing config

  grafana:
    # ... existing config

volumes:
  rippled_data:  # Shared between rippled and monitor
  # ... other volumes

networks:
  xrpl-monitor-network:
```

**2. Configure .env**:
```bash
VALIDATOR_PUBLIC_KEY=nHB6bPcp9jk8QbUZiGXoonERK9rcDvjZUJAoFsGVCs2ZgUdCtnSV
DOCKER_GID=999
LOG_LEVEL=INFO
# No need to set URLs - they're in docker-compose.yml
```

**3. Start the all-in-one stack**:
```bash
docker compose up -d
```

**Benefits**:
- Turnkey deployment
- Everything in containers
- Portable across systems
- Perfect for Rippled-In-A-Box project

### Scenario 3: Native Python Deployment

Run monitor directly with Python (no Docker).

```bash
# .env
RIPPLED_WS_URL=ws://localhost:6006
RIPPLED_HTTP_URL=http://localhost:5005
VICTORIA_METRICS_URL=http://localhost:8428
RIPPLED_DATA_PATH=/var/lib/rippled
RIPPLED_DOCKER_CONTAINER=rippledvalidator  # If rippled is in Docker

# Run collector
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python -m src.monitor.main
```

# Troubleshooting

### Docker Socket Permission Denied

**Error**: `permission denied while connecting to the Docker daemon socket`

**Solution**: Check Docker GID and add to `.env`:
```bash
getent group docker | cut -d: -f3
# Add result to .env as DOCKER_GID=999
```

### NuDB Path Not Found

**Error**: `Could not auto-discover NuDB path`

**Solution**: Set explicit path in `.env`:
```bash
# For Docker rippled (host mount):
RIPPLED_DATA_PATH=/home/username/rippled/data

# For native rippled:
RIPPLED_DATA_PATH=/var/lib/rippled
```

### Connection Refused to rippled

**Error**: `Failed to connect to rippled`

**For Docker rippled**: Use service name or container IP
```bash
RIPPLED_WS_URL=ws://rippledvalidator:6006
```

**For native rippled**: Use localhost (works on all platforms)
```bash
# Recommended (works everywhere):
RIPPLED_WS_URL=ws://localhost:6006

# Alternative for Linux if localhost doesn't work:
RIPPLED_WS_URL=ws://172.17.0.1:6006

# Alternative for macOS/Windows with Docker Desktop:
RIPPLED_WS_URL=ws://host.docker.internal:6006
```

### Validation Metrics Not Appearing

**Cause**: Validator key not configured

**Solution**: Set in `.env`:
```bash
VALIDATOR_PUBLIC_KEY=nHB6bPcp9jk8QbUZiGXoonERK9rcDvjZUJAoFsGVCs2ZgUdCtnSV
```

# Metrics Collection

The Dockerized collector collects all metrics:

| Metric Category | Method | Requirement |
|----------------|--------|-------------|
| **Ledger Stream** | WebSocket | Always works |
| **Server State** | HTTP API | Always works |
| **Validation Events** | WebSocket | Requires `VALIDATOR_PUBLIC_KEY` |
| **Peer Metrics** | HTTP API or `docker exec` | Docker socket or API access |
| **NuDB Size** | Filesystem | Data directory mount |
| **CPU Usage** | psutil in container | Always works |

# Performance

Docker adds minimal overhead:
- **CPU**: <1% additional overhead
- **Memory**: Total system ~729 MB (VictoriaMetrics ~400 MB, Monitor ~200 MB, Grafana ~130 MB)
- **Network**: Minimal (local bridge)
- **Storage**: Images ~300 MB, 30-day metrics ~70 MB

# Security

The collector container requires elevated privileges for two features:

1. **Docker socket access** (peer metrics fallback)
   - Read-only mount minimizes risk
   - Alternative: Enable rippled peers API

2. **rippled data directory** (NuDB metrics)
   - Read-only mount prevents modification
   - Alternative: Monitor without NuDB metrics

Both are optional but recommended for full metrics coverage.

# Updates

Pull latest changes and rebuild:
```bash
git pull
docker compose build collector
docker compose up -d collector
```

# Logs

View collector logs:
```bash
# Live tail
docker compose logs -f collector

# Last 100 lines
docker compose logs --tail=100 collector

# Write to file
docker compose logs collector > collector.log
```

# Health Checks

Check collector is running:
```bash
docker compose ps collector
docker compose exec collector ps aux
```

Check metrics are flowing:
```bash
curl http://localhost:8428/api/v1/query?query=xrpl_ledger_sequence
```

# Integration with Rippled-In-A-Box

For the Rippled-In-A-Box project, this collector fits perfectly:

1. **Turnkey**: Single `docker compose up` command
2. **Portable**: Works on any Docker-capable system
3. **Isolated**: No Python/system dependencies
4. **Observable**: All metrics in one stack
5. **Configurable**: Environment-based configuration

Add this to your Rippled-In-A-Box repository as a submodule or direct integration.
