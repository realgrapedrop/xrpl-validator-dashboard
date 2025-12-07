# **__RELEASE NOTES__**

*Release history and changelog for the XRPL Validator Dashboard.*

---

# Table of Contents

- [Overview](#overview)
- [New Features](#new-features)
- [Enhancements and Improvements](#enhancements-and-improvements)
- [Bug Fixes](#bug-fixes)
- [Deprecations and Removals](#deprecations-and-removals)
- [Known Issues](#known-issues)
- [System Requirements and Compatibility](#system-requirements-and-compatibility)
- [Installation and Upgrade Instructions](#installation-and-upgrade-instructions)
- [Additional Resources](#additional-resources)

---

**XRPL Validator Dashboard**
**Version 3.0.0**
**Release Date: December 6, 2025**

---

# Overview

XRPL Validator Dashboard v3.0 is a **complete architectural rewrite** that transforms validator monitoring with real-time WebSocket streams, the official xrpl-py library, and VictoriaMetrics for dramatically improved performance and reliability.

This release delivers **instant event latency** (vs 3-6 seconds in v2.0), **92% fewer HTTP requests**, and **97% less disk usage** while adding new features like the Cyberpunk dashboard theme, editable dashboards via API import, and improved management tools.

---

# New Features

- **Real-Time WebSocket Architecture**
  0-second latency for critical events with 5 real-time streams: ledger, server, peer_status, consensus, and validations.

- **Official xrpl-py Integration**
  AsyncWebSocketClient for real-time event streams and AsyncJsonRpcClient for supplementary HTTP API calls, with type hints throughout.

- **VictoriaMetrics Database**
  Single database for all metrics (replaces SQLite + Prometheus) with Prometheus-compatible query language (PromQL).

- **Docker Deployment**
  One-command deployment with `sudo ./install.sh`, host networking for easy access to local rippled, and 14 auto-provisioned alert rules.

- **Cyberpunk Dashboard**
  Fun alternate theme with vibrant neon colors for those late-night monitoring sessions.

- **Editable Dashboards**
  Dashboards imported via Grafana API instead of file provisioning—customize and save your changes.

- **Dashboard Restore Menu**
  Restore default dashboards from `manage.sh` → Advanced → Restore. Choose Main, Cyberpunk, or Both.

---

# Enhancements and Improvements

- **Gauge Panels for Database Metrics**
  Peer Disconnects, Ledger DB, and Ledger NuDB now display as visual gauges instead of stat panels.

- **Percentage-Based Disk Thresholds**
  Ledger DB and NuDB panels use percentage of disk space (60%/80% thresholds) instead of fixed byte values—works universally regardless of disk size or retention settings.

- **Cleaner Dashboard UI**
  Hidden variables row and time picker for a streamlined interface.

- **Improved Dashboard Restore Flow**
  Prompts for Grafana username (default: admin) before password, with clear notes about required Admin or Editor role.

- **Better Authentication Error Handling**
  Dashboard restore now handles wrong password (401) vs insufficient permissions (403) separately with clear error messages.

- **Grafana 12.x Support**
  Uses `grafana:latest` with trendline visualizations on key panels.

- **Panel Descriptions**
  Metrics include descriptions explaining what each panel measures.

- **Thousand Separators**
  Large numbers display with thousand separators for readability.

---

# Bug Fixes

- **WebSocket Admin Port Detection**
  Fixed detection logic for rippled WebSocket admin port configuration.

- **Port Conflict Loop**
  Resolved issue where port detection could enter an infinite loop on certain configurations.

- **Development Tool References**
  Removed development tool references from ignore files.

---

# Deprecations and Removals

- **SQLite Database**
  Removed in favor of VictoriaMetrics for all metric storage.

- **File-Based Dashboard Provisioning**
  Replaced with API import to enable dashboard editing and customization.

- **v2.0 Configuration Format**
  `RIPPLED_HOST` and `RIPPLED_PORT` replaced with full URLs (`RIPPLED_WS_URL`, `RIPPLED_HTTP_URL`).

- **Legacy Metric Names**
  Validation metrics renamed with explicit time windows (e.g., `xrpl_validation_agreement_pct` → `xrpl_validation_agreement_pct_1h`).

---

# Known Issues

- **Docker Socket Permissions**
  CPU monitoring requires Docker socket access. Set `DOCKER_GID` in `.env`:
  ```bash
  DOCKER_GID=$(getent group docker | cut -d: -f3)
  ```

- **State Display Flicker**
  Dashboard's 1-second refresh captures real state transitions. During consensus, validators flip between state 4 (`full`) and state 6 (`proposing`)—both indicate healthy operation.

---

# System Requirements and Compatibility

| Requirement | Specification |
|-------------|---------------|
| **Operating System** | Ubuntu 20.04 LTS or later |
| **Docker** | Version 23.0+ |
| **Docker Compose** | Version 2.0+ |
| **rippled** | Running on same machine with admin WebSocket access |
| **Disk Space** | ~500 MB for images, ~290 MB for 30-day metrics |
| **Memory** | ~729 MB RAM total |

### Breaking Changes from v2.0

- Cannot upgrade in-place from v2.0—this is a complete rewrite with incompatible data formats
- Configuration format changed to `.env` based with full URLs
- Some metrics renamed with explicit time windows (`_1h`, `_24h` suffixes)

---

# Installation and Upgrade Instructions

### New Installation

```bash
git clone https://github.com/realgrapedrop/xrpl-validator-dashboard.git
cd xrpl-validator-dashboard
sudo ./install.sh
```

### Upgrading from v2.0

v3.0 cannot upgrade in-place from v2.0. See [INSTALL_GUIDE.md](INSTALL_GUIDE.md#migrating-from-v20) for migration steps.

### Updating v3.x

```bash
cd xrpl-validator-dashboard
git pull
sudo ./install.sh
```

---

# Additional Resources

- **Installation Guide**: [INSTALL_GUIDE.md](INSTALL_GUIDE.md)
- **Architecture**: [ARCHITECTURE.md](ARCHITECTURE.md)
- **Metrics Reference**: [METRICS.md](METRICS.md)
- **Alert Rules**: [ALERTS.md](ALERTS.md)
- **GitHub Issues**: [Report a bug or request a feature](https://github.com/realgrapedrop/xrpl-validator-dashboard/issues)
- **XRPL Discord**: `#validators` channel

---

**Thank you for using XRPL Validator Dashboard. We appreciate your continued support.**
