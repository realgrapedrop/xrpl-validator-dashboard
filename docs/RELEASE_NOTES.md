# **__RELEASE NOTES__**

*What's new in XRPL Monitor v3.0 - December 2025.*

---

# Table of Contents

- [Overview](#overview)
- [What's New in v3.0](#whats-new-in-v30)
- [Breaking Changes](#breaking-changes)
- [Performance Improvements](#performance-improvements)
- [Known Issues](#known-issues)
- [Deprecations](#deprecations)
- [Future Roadmap](#future-roadmap)
- [Changelog](#changelog)
- [Support](#support)

---

# Overview

**XRPL Monitor v3.0 is a complete architectural rewrite** that transforms validator monitoring with real-time WebSocket streams, the official xrpl-py library, and VictoriaMetrics for dramatically improved performance and reliability.

---

# What's New in v3.0

### Real-Time WebSocket Architecture

- **0-second latency** for critical events (vs 3-6s in v2.0)
- **92% fewer HTTP requests** (from 42/min to 3.2/min)
- **5 real-time streams**: ledger, server, peer_status, consensus, validations

### Official xrpl-py Integration

- AsyncWebSocketClient for real-time event streams
- AsyncJsonRpcClient for supplementary HTTP API calls
- Type hints throughout for better IDE support
- Maintained by XRPL team

### Single Database: VictoriaMetrics

- Single database for all metrics (replaces SQLite + Prometheus)
- Prometheus-compatible query language (PromQL)
- **97% less disk usage** for 30-day retention (~290 MB vs ~9.5 GB)

### Docker Deployment

- One-command deployment: `sudo ./install.sh`
- Host networking for easy access to local rippled
- 14 auto-provisioned alert rules

### Enhanced Dashboard

- Thousand separators in large numbers
- Panel descriptions explaining metrics
- Real-time state monitoring (1-second refresh)
- Grafana 12.x (grafana:latest) with trendline visualizations on key panels
- **Cyberpunk Dashboard** - Fun alternate theme with vibrant neon colors
- **Editable dashboards** - Dashboards imported via API, not provisioned (you can customize and save)
- **Hidden variables/time picker** - Cleaner UI without clutter
- **Gauge panels** - Peer Disconnects, Ledger DB, Ledger NuDB with visual gauges
- **Percentage-based thresholds** - Ledger DB/NuDB use % of disk space (60%/80%)

### Install & Management Improvements

- `install.sh` imports dashboards via Grafana API instead of provisioning
- Dashboards are fully editable - customize and save your changes
- `manage.sh` → Advanced → Restore default dashboard (choose Main, Cyberpunk, or Both)
- Restore prompts for Grafana username (default: admin) and password
- Handles authentication errors and permission checks gracefully

---

# Breaking Changes

### Cannot Upgrade In-Place

v3.0 cannot upgrade from v2.0. This is a complete rewrite with incompatible data formats.

**Migration**: See [INSTALL_GUIDE.md](INSTALL_GUIDE.md#migrating-from-v20) for migration steps.

### Configuration Changes

**v2.0** used `RIPPLED_HOST` and `RIPPLED_PORT`.
**v3.0** uses full URLs:
```bash
RIPPLED_WS_URL=ws://localhost:6006
RIPPLED_HTTP_URL=http://localhost:5005
VICTORIA_METRICS_URL=http://localhost:8428
```

### Metric Changes

| v2.0 Metric | v3.0 Metric |
|-------------|-------------|
| `xrpl_validation_agreement_pct` | `xrpl_validation_agreement_pct_1h` |
| `xrpl_validation_agreements` | `xrpl_validation_agreements_1h` |
| `xrpl_validation_missed` | `xrpl_validation_missed_1h` |

**New metrics**: 24-hour versions (`_24h`) of all validation metrics.

---

# Performance Improvements

| Metric | v2.0 | v3.0 | Change |
|--------|------|------|--------|
| HTTP Requests/min | 42 | 3.2 | **92%** |
| Event Latency | 3-6s | 0s | Instant |
| Disk (30d) | ~9.5 GB | ~290 MB | **97%** |
| RAM | ~609 MB | ~729 MB | +20% (justified by real-time streams) |

---

# Known Issues

### Docker Socket Permissions

CPU monitoring requires Docker socket access. Set `DOCKER_GID` in `.env`:
```bash
DOCKER_GID=$(getent group docker | cut -d: -f3)
```

### State Display

Dashboard's 1-second refresh captures real state transitions. During consensus, validators flip between state 4 (`full`) and state 6 (`proposing`) - both indicate healthy operation.

---

# Deprecations

**Removed from v2.0**:
- SQLite database (replaced with VictoriaMetrics)
- File-based dashboard provisioning (replaced with API import for editability)

---

# Future Roadmap

### v3.1.0 (Planned)
- Multi-validator support
- Custom alert rules
- Mobile-responsive dashboards
- Prometheus remote write
- REST API

---

# Changelog

### v3.0.0

**Major Changes**:
- Complete WebSocket event-driven architecture
- Official xrpl-py library integration
- VictoriaMetrics replaces SQLite + Prometheus
- Docker Compose deployment
- 14 auto-provisioned alert rules
- 92% reduction in HTTP requests
- 97% reduction in disk usage

**Breaking Changes**:
- Cannot upgrade in-place from v2.0
- Configuration format changed (.env based)
- Some metrics renamed with explicit time windows

---

# Support

- **Documentation**: [docs/](../docs/) folder
- **Issues**: [GitHub Issues](https://github.com/realgrapedrop/xrpl-validator-dashboard/issues)
- **XRPL Discord**: `#validators` channel

---

**Built for the XRPL validator community**
