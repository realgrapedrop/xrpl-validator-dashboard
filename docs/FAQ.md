# **__FREQUENTLY ASKED QUESTIONS__**

*Common questions and answers about XRPL Monitor v3.0.*

---

# Table of Contents

### [Installation & Setup](#installation--setup)
- [What are the system requirements?](#what-are-the-system-requirements)
- [Why must XRPL Monitor run on the same machine as rippled?](#why-must-xrpl-monitor-run-on-the-same-machine-as-rippled)
- [How do I install Docker if it's not already installed?](#how-do-i-install-docker-if-its-not-already-installed)
- [What Docker installation mode does the installer use? Can I use rootless mode?](#what-docker-installation-mode-does-the-installer-use-can-i-use-rootless-mode)
- [What does the installer do?](#what-does-the-installer-do)
- [What if port 3000 is already in use?](#what-if-port-3000-is-already-in-use)
- [Can I run v2.0 and v3.0 side by side?](#can-i-run-v20-and-v30-side-by-side)
- [How do I upgrade from v2.0 to v3.0?](#how-do-i-upgrade-from-v20-to-v30)

### [Metrics & Accuracy](#metrics--accuracy)
- [What are the rippled server states?](#what-are-the-rippled-server-states)
- [Why don't Agreements/Missed counts match xrpscan.com exactly?](#why-dont-agreementsmissed-counts-match-xrpscancom-exactly)
- [How does the Collector calculate validation metrics?](#how-does-the-collector-calculate-validation-metrics)
- [What's the difference between real-time WebSocket metrics vs polling?](#whats-the-difference-between-real-time-websocket-metrics-vs-polling)
- [How accurate are the metrics?](#how-accurate-are-the-metrics)

### [Architecture & Technology](#architecture--technology)
- [Why use Grafana for dashboards?](#why-use-grafana-for-dashboards)
- [Why use the official xrpl-py Python library?](#why-use-the-official-xrpl-py-python-library)
- [Why use VictoriaMetrics database?](#why-use-victoriametrics-database)
- [How does the Collector work?](#how-does-the-collector-work)
- [What are vmagent and Node Exporter?](#what-are-vmagent-and-node-exporter)
- [Why is the entire stack running in Docker?](#why-is-the-entire-stack-running-in-docker)
- [Are all system components open source and license-free?](#are-all-system-components-open-source-and-license-free)
- [What does this dashboard solve?](#what-does-this-dashboard-solve)
- [Can I customize the Grafana dashboards?](#can-i-customize-the-grafana-dashboards)

### [Configuration & Operations](#configuration--operations)
- [How do I configure email/webhook alerts?](#how-do-i-configure-emailwebhook-alerts)
- [How do I change my Grafana password?](#how-do-i-change-my-grafana-password)
- [How do I display the dashboard in full-screen kiosk mode?](#how-do-i-display-the-dashboard-in-full-screen-kiosk-mode)
- [What happens if I don't enable HTTP API?](#what-happens-if-i-dont-enable-http-api)
- [Can I monitor multiple validators?](#can-i-monitor-multiple-validators)
- [How long is historical data retained?](#how-long-is-historical-data-retained)
- [What happens if my rippled node goes down?](#what-happens-if-my-rippled-node-goes-down)
- [What ports need to be accessible?](#what-ports-need-to-be-accessible)

### [Troubleshooting](#troubleshooting)
- [Grafana shows "No Data"](#grafana-shows-no-data)
- ["Port already in use" error during installation](#port-already-in-use-error-during-installation)
- [Validation counts seem wrong](#validation-counts-seem-wrong)
- [Docker Compose won't start](#docker-compose-wont-start)

---

# Installation & Setup

### What are the system requirements?

**Operating System:**
- Ubuntu 20.04 LTS or later (required)
- Other Linux distributions may work but are not officially supported

**Software:**
- Docker (must be installed manually - installer only checks for presence)
- Docker Compose (auto-installed on Ubuntu if missing)
- rippled validator node running locally

**Hardware:**
- Minimum 2GB RAM (4GB+ recommended)
- Minimum 10GB disk space for 30 days of metrics
- Network connectivity to your rippled node

**rippled Requirements:**
- WebSocket admin API enabled (commonly port 6006, but configurable)
- (Optional) HTTP admin API enabled on port 5005
- Admin access configured (`admin = 127.0.0.1` in rippled.cfg)

**IMPORTANT:** The dashboard must be installed on the **same machine** as your rippled validator. The collector requires filesystem access to `/var/lib/rippled` for database size metrics.

### Why must XRPL Monitor run on the same machine as rippled?

XRPL Monitor requires **filesystem access** to your rippled validator's data directory for database size monitoring.

**Technical Requirements:**

The Collector needs to read:
- `/var/lib/rippled/db/` - RocksDB database size
- `/var/lib/rippled/nudb/` - NuDB database size

These metrics are collected every 5 minutes via direct filesystem access, which is not available through rippled's WebSocket or HTTP RPC APIs.

**Remote Deployment Challenges:**

Running XRPL Monitor remotely would require:

1. **Network Configuration:**
   - Opening firewall rules for rippled's admin API ports (6006 WebSocket, 5005 HTTP)
   - Configuring rippled to accept remote admin connections
   - Implementing secure transport (VPN, SSH tunnels, or TLS)

2. **Security Considerations:**
   - Exposing admin APIs to network increases attack surface
   - Admin APIs have full node control (stop, reload config, etc.)
   - Requires advanced security expertise to implement safely

3. **Database Monitoring:**
   - Filesystem metrics would not be available remotely
   - Dashboard would lose db/nudb size tracking capabilities

**Future Enhancement:**

A future version (v3.1+) may add an optional configuration to:
- Skip database size monitoring (disable filesystem access requirement)
- Allow remote deployment for WebSocket/HTTP metrics only
- Trade complete metric coverage for deployment flexibility

For now, **same-host deployment** is recommended for complete monitoring coverage with minimal security risk.

### How do I install Docker if it's not already installed?

The installer checks for Docker but does not auto-install it. You must install Docker manually before running the installer.

**Quick Check:**
```bash
docker --version
```

If Docker is not installed, see the Docker installation section in **[INSTALL_GUIDE.md](INSTALL_GUIDE.md#installing-docker)**

The guide includes:
- Official Docker installation steps for Ubuntu 20.04+
- Common installation issues and fixes (package conflicts, GPG errors, firewall issues)
- Pre-installation conflict detection script
- Post-installation verification steps

**Note:** Docker Compose IS auto-installed by the XRPL Monitor installer on Ubuntu systems.

### What Docker installation mode does the installer use? Can I use rootless mode?

When the XRPL Monitor `install.sh` script installs Docker (if not already present), it uses **Standard Mode** - Docker's official recommended setup where the Docker daemon runs with root privileges, but regular users can access it by being added to the `docker` group.

**What Mode the Installer Uses:**

The installer runs Docker's official installation script (`curl -fsSL https://get.docker.com | sh`), which sets up:
- Docker daemon running as root
- Your user added to the `docker` group
- Ability to run Docker commands without `sudo`

**Security Warning You'll See:**

After Docker installation, you'll see this message:

```
================================================================================

To run Docker as a non-privileged user, consider setting up the
Docker daemon in rootless mode for your user:

    dockerd-rootless-setuptool.sh install

Visit https://docs.docker.com/go/rootless/ to learn about rootless mode.


To run the Docker daemon as a fully privileged service, but granting non-root
users access, refer to https://docs.docker.com/go/daemon-access/

WARNING: Access to the remote API on a privileged Docker daemon is equivalent
         to root access on the host. Refer to the 'Docker daemon attack surface'
         documentation for details: https://docs.docker.com/go/attack-surface/

================================================================================
```

**Understanding Your Options:**

| Mode | Security | Complexity | Dashboard Compatibility | Recommended For |
|------|----------|------------|------------------------|-----------------|
| **Standard** (what installer uses) | Anyone with Docker access has root | Simple | ✅ Fully supported | Single-user validators, production use |
| **Rootless** | Docker runs without root | Complex | ⚠️ May have issues | High-security environments, multi-user systems |
| **Locked Down** | Only root can run Docker | Restrictive | ❌ Not practical | Highly restricted environments |

**Why Standard Mode is Recommended:**

For validator monitoring, Standard Mode is the right choice because:
1. You're the only user on your validator machine
2. You already have sudo access
3. All dashboard components work reliably
4. Rootless mode can cause compatibility issues with:
   - Docker socket access (needed for CPU monitoring of Docker-based rippled)
   - Volume mounts to `/var/lib/rippled` (database size metrics)
   - Network access patterns

**If You Want Rootless Mode Anyway:**

If you require rootless Docker for security compliance:

1. **Uninstall current installation:**
   ```bash
   cd /path/to/xrpl-validator-dashboard
   sudo ./uninstall.sh
   ```

2. **Remove Docker (installed by installer):**
   ```bash
   sudo apt-get remove docker-ce docker-ce-cli containerd.io docker-compose-plugin
   ```

3. **Install Docker in rootless mode manually:**
   ```bash
   # Follow official rootless installation
   curl -fsSL https://get.docker.com/rootless | sh

   # Verify rootless mode
   docker context use rootless
   docker info | grep -i "rootless"
   ```

4. **Reconfigure dashboard for rootless:**
   ```bash
   # May need to modify docker-compose.yml:
   # - Remove Docker socket mounts
   # - Adjust filesystem permissions
   # - Change network modes
   ```

5. **Run installer:**
   ```bash
   sudo ./install.sh
   ```

**Access Requirements for Dashboard:**

XRPL Monitor requires these Docker capabilities to function properly:

| Capability | Why Required | Affected Metrics |
|------------|--------------|------------------|
| **Docker socket access** | CPU monitoring of Docker-based rippled | `xrpl_rippled_cpu_percent`, `xrpl_rippled_cpu_cores` |
| **Filesystem read access** | Database size tracking | `xrpl_db_size_bytes`, `xrpl_nudb_size_bytes` |
| **Network access** | Connect to rippled APIs | All WebSocket and HTTP metrics |
| **User in docker group** | Run containers without sudo | All functionality |

**Security Best Practices:**

Whether using Standard or Rootless mode:
- Don't give Docker access to untrusted users
- Keep Docker and containers updated
- Use firewall rules to restrict port access
- Monitor Docker logs for suspicious activity
- Never expose Docker socket over network

**Bottom Line:**

The installer uses Standard Mode because it's the most reliable, well-tested configuration for single-user validator operations. The security warning is primarily for shared servers with multiple users - for a single-operator validator, this mode is appropriate and recommended.

### What does the installer do?

The XRPL Monitor installer is a fully automated script that sets up the complete monitoring stack in 2-5 minutes. It handles everything from pre-flight checks to dashboard provisioning.

**Quick Summary:**

The installer performs five main phases:

1. **Pre-Installation Checks** - Verifies Docker is installed, checks port availability, installs Docker Compose if needed
2. **Configuration** - Prompts for Grafana port and optional email alerts
3. **Service Deployment** - Pulls container images from Docker Hub, creates volumes, starts all services
4. **Auto-Provisioning** - Configures datasource, imports dashboard, provisions 14 alert rules
5. **Verification** - Reports access URL, credentials, and service status

**What you need before installing:**
- Ubuntu 20.04 LTS or later
- Docker installed (see [How do I install Docker?](#how-do-i-install-docker-if-its-not-already-installed))
- rippled running locally with admin API enabled
- Sudo access

**What the installer does NOT do:**
- Does not install Docker (must be pre-installed)
- Does not modify rippled configuration
- Does not require root access to rippled (filesystem read-only)
- Does not interfere with existing v2.0 installations

**Installation time:** 2-5 minutes (depending on download speed)

**For complete step-by-step instructions, installation flow diagram, and troubleshooting, see:**

📖 **[Install & Operations Guide](INSTALL_GUIDE.md)**

The full guide includes:
- Detailed prerequisite checklist
- Visual installation flow diagram with GitHub clone step
- Phase-by-phase breakdown of what happens
- Troubleshooting for common issues
- Post-installation verification steps
- Component upgrade instructions

### What if port 3000 is already in use?

The installer includes smart port conflict detection:

1. During installation, the installer checks if port 3000 (Grafana default) is available
2. If occupied, it automatically finds the next available port (3001, 3002, etc.)
3. You'll be prompted: `Grafana port [3001]:`
4. Press Enter to accept the suggested port, or enter a custom port
5. If your custom port is also occupied, the installer will suggest an alternative

The same logic applies to VictoriaMetrics (8428) and Node Exporter (9100).

**Note:** The installer auto-updates `docker-compose.yml` with your selected ports, so no manual configuration is needed.

### Can I run v2.0 and v3.0 side by side?

Yes! This is fully supported and recommended for migration testing:

- v2.0 uses port 3000 by default
- v3.0 detects this and automatically suggests port 3001+
- Both can monitor the same rippled node simultaneously
- Both collect independent data (no interference)

**Example workflow:**
```bash
# v2.0 running on port 3000
# v3.0 installer detects conflict
Grafana port [3001]: <press Enter>
```

### How do I upgrade from v2.0 to v3.0?

**Important:** v3.0 is a complete architectural rewrite and **cannot upgrade in-place**.

**Recommended Approach - Clean Install:**

1. **Backup v2.0 data** (optional - for historical reference only)
   ```bash
   cd /path/to/v2.0
   # Export Grafana dashboards if customized
   ```

2. **Uninstall v2.0**
   ```bash
   cd /path/to/v2.0
   sudo ./uninstall.sh
   ```

3. **Install v3.0**
   ```bash
   cd /path/to/v3.0
   sudo ./install.sh
   ```

4. **Verify Operation**
   - Access Grafana at the configured port
   - Confirm metrics are flowing (wait 1-2 minutes)
   - Review auto-provisioned alert rules

**Note:** Historical data from v2.0 cannot be imported to v3.0 due to the database change (SQLite + Prometheus → VictoriaMetrics). v3.0 starts with fresh data.

For detailed migration steps, refer to the [Install & Operations Guide](INSTALL_GUIDE.md#updating-xrpl-monitor).

---

# Metrics & Accuracy

### What are the rippled server states?

rippled nodes progress through these states during operation:

| State | Number | Description |
|-------|--------|-------------|
| **disconnected** | 0 | Not connected to the network |
| **connected** | 1 | Connected to network, starting sync |
| **syncing** | 2 | Downloading ledger history |
| **tracking** | 3 | Following the network, not fully synced |
| **full** | 4 | Fully synced, participating in consensus |
| **validating** | 5 | (Legacy) Publishing validations (deprecated) |
| **proposing** | 6 | UNL member with active proposal rights |

**Note:** During active consensus, validators rapidly flip between state 4 (`full`) and state 6 (`proposing`). With v3.0's real-time monitoring (1-second refresh), the dashboard accurately captures these transitions and displays the actual current state. See [README: Server State Display](../README.md#⚠️-important-note-server-state-display) for details.

For complete technical details, see the [official XRPL documentation](https://xrpl.org/docs/references).

### Why don't Agreements/Missed counts match xrpscan.com exactly?

This is expected and occurs for several technical reasons:

**1. Different Data Sources**
- **XRPL Monitor:** Collects validations directly from YOUR validator's WebSocket stream
- **XRPScan:** Aggregates validations from multiple network observers

**2. Timing Windows**
- **XRPL Monitor:** Uses sliding 1-hour and 24-hour windows from collection start time
- **XRPScan:** May use fixed UTC hour boundaries or different time windows

**3. Network Propagation**
- **XRPL Monitor:** Records what your node sees/sends in real-time
- **XRPScan:** Records what the broader network observes (may miss some validations due to network conditions)

**4. Restart Effects (Validator Restarts)**
- **XRPL Monitor:** When rippled restarts, its internal counters reset to zero. The dashboard can only report what rippled knows, so 24h metrics will only reflect data since the restart.
- **XRPScan:** Observes validations from the network's perspective, so it counts ALL ledgers your validator missed during the restart window (while rippled was down and reconnecting).

**Example:** If your validator was down for 90 seconds during a restart (~23 ledgers at 4s/ledger):
- XRPScan 24h missed: 41 (includes 23 missed during restart + 18 missed after)
- Dashboard 24h missed: 18 (only counts misses since rippled came back online)
- The difference (23) represents ledgers that closed while your validator was restarting

**Which is more accurate for YOUR validator?**
- **XRPL Monitor** gives you the ground truth of what your validator is actually producing - real-time local metrics straight from your validator's WebSocket stream
- **XRPScan** shows what the network is receiving from your validator - aggregated from multiple network observers with potential propagation delays

**Normal Behavior - Sliding Window Oscillation:**

Because XRPL Monitor uses a continuously sliding time window (not fixed hourly boundaries), you'll see the 1h agreement count naturally oscillate by ±2-3 agreements as the window moves forward. For example: 927 → 928 → 929 → 928 → 927. This is **expected and indicates healthy operation**.

**Why oscillation occurs:**
- New validations enter the window (~15.5/min = one every ~4 seconds)
- Old validations from exactly 60 minutes ago drop off
- Ledger close timing has natural variance (~3.5-4.5 seconds)
- The sliding window captures this real-time ebb and flow

**What's normal:** ±2-3 oscillation around your average (~928 for a healthy validator)
**What's concerning:** Large swings (>10), steady decline, or values consistently below 900/hour

**Accuracy advantage:** XRPL Monitor is more real-time and accurate than XRPScan because it reads directly from your local validator with zero network propagation delay.

### How does the Collector calculate validation metrics?

The Collector uses two methods depending on the metric:

**Real-Time Stream Tracking (Agreements/Missed):**

1. **WebSocket Subscription:** Listens to `validations` stream from rippled
2. **Agreement Detection:** When validation message includes `"full": true`, it's an agreement
3. **Time-Window Counting:**
   - Maintains sliding 1-hour window (last 3600 seconds)
   - Maintains sliding 24-hour window (last 86400 seconds)
   - Increments counters in real-time
   - Expires old validations as they fall outside window

**Example:**
```
12:00:00 - Validation received → agreements_1h = 1
12:01:00 - Validation received → agreements_1h = 2
...
13:00:01 - First validation expires → agreements_1h = X (older ones dropped)
```

**HTTP Polling (Server State Metrics):**

- `server_info` endpoint polled every 5 seconds
- Extracts current values (no calculation needed)
- Examples: ledger sequence, peer count, load factor

**Accuracy:** Real-time WebSocket provides <100ms latency. HTTP polling has up to 5-second lag.

### What's the difference between real-time WebSocket metrics vs polling?

| Aspect | WebSocket (Real-time) | HTTP Polling |
|--------|----------------------|--------------|
| **Latency** | <100ms (instant) | 5-60 seconds |
| **Data Source** | Event-driven streams | Periodic snapshots |
| **Accuracy** | Every event captured | Misses events between polls |
| **Resource Usage** | Lower (push model) | Higher (pull model) |
| **Network Load** | Minimal | 3.2 requests/min |

**WebSocket Metrics (v3.0):**
- Ledger closes (instant notification)
- Validation messages (real-time)
- Peer status changes (immediate)
- Server state changes (3-10 second events)
- Consensus performance (real-time)

**HTTP Polling Metrics (v3.0):**
- Server info (every 5 seconds)
- Peer details (every 60 seconds)
- Database state (every 5 minutes)
- Filesystem size (every 5 minutes)

**Key Improvement in v3.0:** 51-63% of metrics now use WebSocket streams vs 0% in v2.0.

### How accurate are the metrics?

**Accuracy by Category:**

| Metric Type | Accuracy | Notes |
|-------------|----------|-------|
| **Ledger Sequence** | 100% | Direct from rippled WebSocket |
| **Validation Counts** | 99%+ | May differ slightly from network view |
| **Peer Count** | 100% | Direct from rippled HTTP API |
| **Server State** | 100% | Real-time WebSocket notifications |
| **Consensus Metrics** | 100% | Direct observation of consensus events |
| **Database Size** | 100% | Filesystem measurement every 5 minutes |
| **Timestamps** | ±1 second | Collector processing time |

**Data Integrity:**
- All metrics written to VictoriaMetrics with millisecond timestamps
- No data loss during collector restart (VictoriaMetrics retains history)
- 30-day retention by default (configurable)

**Known Limitations:**
- Brief data collection gap during collector restart (~2-5 seconds)
- Filesystem metrics lag by up to 5 minutes (polling interval)
- Validation counters and sliding windows are recovered from VictoriaMetrics on monitor restart
- Validations Sent counter resets to 0 if rippled restarted (tracks validations since rippled restart)

---

# Architecture & Technology

### Why use Grafana for dashboards?

Grafana is the industry-standard open-source visualization platform, and I chose it for several compelling reasons:

**1. Battle-Tested & Stable**
- Over 1 million active installations worldwide
- 10+ years of active development
- Used by Fortune 500 companies for mission-critical monitoring
- Proven reliability for 24/7 operations

**2. User Customization Freedom**
- Full control over dashboard layout and appearance
- Create custom panels with your preferred metrics
- Add your own queries and visualizations
- Share dashboards with your team
- Export/import dashboard JSON for version control

**3. Rich Ecosystem**
- Extensive plugin library (100+ visualization types)
- Native support for PromQL (VictoriaMetrics query language)
- Built-in alerting with 15+ notification channels
- Mobile app for on-the-go monitoring

**4. No Vendor Lock-In**
- Open source (AGPLv3) - no licensing fees
- Run anywhere Docker is supported
- Export your data anytime
- Switch to other tools if needed

**5. Professional Features**
- Role-based access control (RBAC)
- Dashboard versioning and history
- Annotations for marking events
- Variable templating for dynamic dashboards
- Playlist mode for cycling through dashboards

**Alternatives I Considered:**
- **Custom web UI:** Would require significant development/maintenance effort
- **Prometheus UI:** Limited visualization capabilities
- **VictoriaMetrics UI:** Basic, not suitable for complex dashboards
- **Chronograf:** Less mature, smaller community

**Bottom Line:** Why reinvent the wheel? Grafana gives validator operators enterprise-grade monitoring out of the box, with the flexibility to customize exactly how they want.

### Why use the official xrpl-py Python library?

I chose the official `xrpl-py` library maintained by the XRPL Foundation for critical technical and operational reasons:

**1. Dual Protocol Support**
- **WebSocket Client:** Real-time event streams for instant notifications
- **HTTP JSON-RPC Client:** Reliable request/response for state queries
- Both protocols fully implemented with async/await support

**2. Officially Maintained by XRPL Team**
- Direct support from the team that builds rippled
- Guaranteed compatibility with rippled protocol changes
- First to receive updates for new XRPL features
- Follows official XRPL specifications exactly

**3. Type Safety & Modern Python**
- Full type hints for IDE autocomplete and type checking
- Python dataclasses for structured responses
- Reduces bugs from manual JSON parsing
- Better developer experience

**4. Production-Ready Features**
- Automatic WebSocket reconnection logic
- Connection pooling for HTTP requests
- Proper error handling and exceptions
- Rate limiting protection
- Comprehensive test coverage

**5. Active Development & Community**
- 500+ GitHub stars
- Regular updates and security patches
- Large community of developers
- Extensive documentation and examples

**What I Get vs Manual Implementation:**

| Feature | xrpl-py | Manual JSON |
|---------|---------|-------------|
| **Code Lines** | ~50 lines | ~200+ lines |
| **WebSocket Reconnect** | Built-in | Must implement |
| **Type Safety** | Full types | None |
| **Protocol Updates** | Auto-updated | Manual tracking |
| **Testing** | Extensively tested | Self-tested |
| **Maintenance** | XRPL team | Me |

**Real Example from My Code:**
```python
# With xrpl-py (clean & type-safe)
async with AsyncWebsocketClient(url) as client:
    await client.send(Subscribe(streams=["ledger"]))
    async for message in client:
        if isinstance(message, LedgerStreamResponse):
            process_ledger(message.ledger_index)

# Without xrpl-py (manual & error-prone)
ws = await websockets.connect(url)
await ws.send(json.dumps({"command": "subscribe", "streams": ["ledger"]}))
while True:
    raw = await ws.recv()
    data = json.loads(raw)  # No type checking!
    if data.get("type") == "ledgerClosed":  # String matching prone to typos
        process_ledger(data["ledger_index"])  # KeyError if field missing!
```

**Bottom Line:** Using the official library means less code to maintain, fewer bugs, automatic compatibility with rippled updates, and more time focusing on monitoring features instead of reimplementing WebSocket protocols.

### Why use VictoriaMetrics database?

VictoriaMetrics is a high-performance time-series database that replaced my dual-database approach (SQLite + Prometheus) from v2.0:

**1. Purpose-Built for Metrics**
- Optimized for time-series data (timestamps + values)
- Handles high cardinality (many unique metric labels)
- Efficient compression algorithms
- Fast range queries for dashboard graphs

**2. Dramatic Resource Savings**

| Aspect | v2.0 (SQLite + Prometheus) | v3.0 (VictoriaMetrics) | Improvement |
|--------|---------------------------|------------------------|-------------|
| **Disk (30d)** | 9.5 GB | 70 MB | **99% reduction** |
| **RAM** | ~450 MB | ~500 MB | Similar |
| **Query Speed** | Slow (SQLite) | Fast (optimized) | 10-100x faster |
| **Databases** | 2 separate | 1 unified | Simpler |

**3. Prometheus-Compatible**
- Uses PromQL query language (industry standard)
- Native Grafana datasource support
- Compatible with Prometheus exporters
- Easy migration path if needed

**4. Operational Simplicity**
- Single binary, no dependencies
- No complex configuration required
- Automatic data compaction
- Built-in data retention management
- No separate backup strategy needed

**5. Performance at Scale**
- Handles millions of data points per second
- Sub-millisecond query response times
- Efficiently stores sparse data
- Low CPU usage during queries

**6. Production-Grade Features**
- Crash recovery and data consistency
- Native HTTP API for querying
- Built-in deduplication
- Downsampling for long-term storage

**Why Not Prometheus Directly?**
- VictoriaMetrics uses **10x less RAM** than Prometheus
- **7x less disk space** for same data
- Faster query performance for range queries
- Drop-in replacement (same query language)

**Why Not InfluxDB/TimescaleDB?**
- More complex setup (separate database server)
- Higher resource requirements
- Additional query language to learn
- Overkill for single-validator monitoring

**Real-World Impact:**
```
v2.0: Two databases to maintain, 9.5 GB for 30 days, slow queries
v3.0: One database, 70 MB for 30 days, instant queries
Result: 99% less disk, simpler operations, better performance
```

**Bottom Line:** VictoriaMetrics gives me enterprise-grade time-series storage with consumer-grade resource usage. It's the sweet spot between performance, simplicity, and operational efficiency.

### How does the Collector work?

The Collector is the heart of XRPL Monitor - a Python application that gathers metrics from your rippled validator and stores them in VictoriaMetrics.

**Architecture Overview:**

```
┌──────────────────────────────────────────┐
│  Collector (Python asyncio)              │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │  WebSocket Manager                 │  │
│  │  • Maintains connection to rippled │  │
│  │  • Auto-reconnects on disconnect   │  │
│  │  • Subscribes to 5 streams:        │  │
│  │    - ledger (instant notifications)│  │
│  │    - server (state changes)        │  │
│  │    - peer_status (peer events)     │  │
│  │    - validations (real-time)       │  │
│  │    - consensus (performance)       │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │  HTTP Poller                       │  │
│  │  • server_info (every 5s)          │  │
│  │  • peers (every 60s)               │  │
│  │  • server_state (every 5min)       │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │  Filesystem Monitor                │  │
│  │  • Reads /var/lib/rippled/db size  │  │
│  │  • Reads /var/lib/rippled/nudb size│  │
│  │  • Updates every 5 minutes         │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │  Metrics Processor                 │  │
│  │  • Calculates validation windows   │  │
│  │  • Tracks sliding counters         │  │
│  │  • Formats data for VictoriaMetrics│  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │  VictoriaMetrics Writer            │  │
│  │  • Batches metrics for efficiency  │  │
│  │  • Writes to VM HTTP API           │  │
│  │  • Handles write failures          │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
                      │
                      ▼
              ┌─────────────────┐
              │ VictoriaMetrics │
              │   (Storage)     │
              └─────────────────┘
```

**Event Flow Example:**

1. **Ledger Close Event (WebSocket):**
   ```
   rippled closes ledger → WebSocket message received
   → Extract ledger_index, txn_count, close_time
   → Calculate ledger_age (now - close_time)
   → Write 4 metrics to VictoriaMetrics
   → Update Grafana dashboard (< 100ms total)
   ```

2. **Validation Event (WebSocket):**
   ```
   rippled sends validation → WebSocket message received
   → Check if validation has "full": true (agreement)
   → Increment 1h and 24h sliding windows
   → Write agreement counter to VictoriaMetrics
   → Update dashboard panel instantly
   ```

3. **Server Info Poll (HTTP):**
   ```
   Every 5 seconds → HTTP request to rippled:5005
   → Parse server_info response
   → Extract 15 metrics (load factor, peers, uptime, etc.)
   → Batch write all metrics to VictoriaMetrics
   → Dashboard reflects new values within 5s
   ```

**Key Design Decisions:**

**1. Event-Driven Architecture:**
- WebSocket streams push events to me (vs polling)
- Immediate notification of critical changes
- Lower CPU usage (no constant polling)
- <100ms latency for real-time metrics

**2. Async/Await Python:**
- Single-threaded concurrency (more efficient than threading)
- Non-blocking I/O for all operations
- Handles 5 WebSocket streams + 3 HTTP pollers + filesystem checks simultaneously
- Lower memory footprint than multi-threaded approach

**3. Graceful Error Handling:**
- WebSocket disconnect → Auto-reconnect with exponential backoff
- HTTP request fails → Retry up to 3 times
- VictoriaMetrics write fails → Buffer and retry
- rippled down → Log error, keep retrying connections

**4. Counter Persistence:**
- On startup: Query VictoriaMetrics for last known counters
- Recover validation counts (1h and 24h windows)
- Continue counting from last known values
- No reset to zero on Collector restart

**Resource Usage:**
- CPU: ~2-5% during normal operation
- RAM: ~200 MB (including Python runtime)
- Network: ~3.2 HTTP requests/minute + 5 WebSocket streams
- Disk: None (writes to VictoriaMetrics only)

**Code Structure:**
```
src/monitor/
├── main.py              # Entry point, orchestration
├── websocket_client.py  # WebSocket connection management
├── http_client.py       # HTTP polling
├── metrics.py           # Metric calculations & formatting
├── filesystem.py        # Database size monitoring
└── victoriametrics.py   # VictoriaMetrics writer
```

**Monitoring the Collector:**
```bash
# View real-time logs
docker compose logs -f collector

# Check if connected to rippled
docker compose logs collector | grep "Connected to"

# See metric write activity
docker compose logs collector | grep "Wrote.*metrics"
```

**Bottom Line:** The Collector is a lightweight, event-driven monitoring agent that efficiently bridges rippled's APIs with VictoriaMetrics' storage, providing real-time visibility into your validator's health with minimal resource overhead.

### What are vmagent and Node Exporter?

These are two infrastructure components that provide **system-level monitoring** (CPU, RAM, disk, network) alongside the Collector's **validator-specific monitoring** (ledgers, validations, consensus).

**Node Exporter** - System Metrics Exporter

**What it does:**
- Collects host system metrics from the underlying Linux OS
- Exposes metrics on port 9100 in Prometheus format
- Metrics include: CPU usage, RAM usage, SWAP usage, disk space, disk I/O, network traffic, system load, uptime

**Why I need it:**
- The Collector focuses on validator metrics (ledgers, validations, consensus)
- Node Exporter provides OS-level context: "Is high load factor caused by CPU saturation?"
- Enables correlation: validator performance vs system resource usage

**What it doesn't do:**
- Does not access rippled (no WebSocket/HTTP connections)
- Does not write to VictoriaMetrics (read-only exporter)
- Does not modify system configuration

**vmagent** - Metrics Collection Agent

**What it does:**
- Scrapes all exporters (Node Exporter :9100, Uptime Exporter :9101, State Exporter :9102)
- Transforms Prometheus metrics to VictoriaMetrics format
- Writes metrics to VictoriaMetrics database
- Exposes its own metrics on port 8427

**Why I need it:**
- VictoriaMetrics doesn't have built-in scraping (unlike Prometheus)
- Acts as a lightweight scraper specifically designed for VictoriaMetrics
- Handles the "pull model" for system metrics (vs Collector's "push model" for validator metrics)

**Architecture Diagram:**

See the complete system architecture diagram in the [System Architecture section](#how-does-the-collector-work) above.

**Key Points:**
```
Node Exporter (exports) → vmagent (scrapes) → VictoriaMetrics (stores) → Grafana (visualizes)
     ↓                                               ↑
System metrics                          Collector writes validator metrics
```

**Docker Configuration:**

Both components are auto-deployed during installation:
- No manual configuration required
- Pre-configured ports and scrape intervals
- Automatically connected to VictoriaMetrics
- Included in `docker compose ps` status check

**Resource Usage:**
- Node Exporter: ~10 MB RAM
- vmagent: ~50 MB RAM
- Combined CPU: <1%
- Network: ~0.5 KB/s (local scraping)

**Monitoring These Components:**
```bash
# Check status
docker compose ps

# View vmagent logs
docker compose logs vmagent

# View Node Exporter logs
docker compose logs node-exporter

# Verify scraping is working
curl http://localhost:9100/metrics | head -20  # Node Exporter
curl http://localhost:9101/metrics | head -20  # Uptime Exporter
curl http://localhost:9102/metrics | head -20  # State Exporter
```

**Common Questions:**

**Q: Can I disable system monitoring and only monitor validator metrics?**
A: No, the system metrics provide critical context for validator performance troubleshooting.

**Q: Why not use Prometheus instead of vmagent?**
A: vmagent is lightweight (~50 MB) compared to Prometheus (~200 MB) and designed specifically for VictoriaMetrics.

**Q: Do these components require configuration?**
A: No, they're auto-configured during installation with optimal settings.

### Why is the entire stack running in Docker?

Docker provides critical advantages for validator monitoring:

**1. Isolated Environment**
- No conflicts with validator's Python version
- Isolated dependencies
- No system package pollution

**2. Consistent Deployment**
- Same environment across all systems
- Tested Ubuntu 20.04+ compatibility
- Reproducible builds

**3. Easy Upgrades & Rollbacks**
```bash
# Upgrade
docker compose down
git pull
docker compose up -d

# Rollback
git checkout v3.0.0
docker compose up -d
```

**4. Resource Limits** (Future)
```yaml
mem_limit: "512m"
cpus: "0.5"
```

**5. Security**
- Containers run as non-root
- Limited host filesystem access
- Network isolation (except necessary ports)

**6. Portability**
- Move to new server: copy directory + `docker compose up`
- No system reconfiguration needed
- Works on any Docker-capable system

**What if I don't want Docker?**
- v2.0 supports filesystem installation (no Docker)
- v3.0 is Docker-only by design for operational simplicity
- You can extract the Python code and run manually, but it's not supported

### Are all system components open source and license-free?

Yes! All components are 100% open source with permissive licenses:

| Component | License | Cost | Commercial Use |
|-----------|---------|------|----------------|
| **XRPL Monitor** | MIT | Free | ✅ Allowed |
| **xrpl-py** | ISC | Free | ✅ Allowed |
| **VictoriaMetrics** | Apache 2.0 | Free | ✅ Allowed |
| **Grafana** | AGPLv3 | Free | ✅ Allowed* |
| **Docker** | Apache 2.0 | Free | ✅ Allowed |
| **Python** | PSF | Free | ✅ Allowed |

**Grafana Licensing Note:**
- AGPL allows commercial use
- If you modify Grafana's source code and distribute it, you must share changes
- **This dashboard DOES NOT modify Grafana** - we only use it via Docker and configuration files
- Therefore, no AGPL obligations apply to you

**Can I use this commercially?**
- Yes, for monitoring your own validators
- Yes, for running a validator business
- Yes, for providing monitoring as a service to clients
- **No restrictions** - MIT license is fully permissive

**Attribution:**
- Not legally required (MIT license)
- Appreciated if you find it useful!

### What does this dashboard solve?

XRPL Monitor v3.0 solves several critical problems for validator operators:

**1. Visibility Gaps**
- **Problem:** rippled logs are verbose and hard to parse
- **Solution:** Real-time visual dashboards with clear metrics

**2. Delayed Notifications**
- **Problem:** v2.0 had 3-6 second lag on state changes
- **Solution:** <100ms WebSocket notifications of critical events

**3. Alert Fatigue**
- **Problem:** Manual log monitoring is exhausting
- **Solution:** 10 auto-configured alert rules with multi-channel notifications (Email, Discord, Slack, Teams, Telegram, PagerDuty)

**4. Operational Complexity**
- **Problem:** v2.0 required filesystem services + Docker + SQLite management
- **Solution:** 100% containerized `docker compose up` deployment

**5. Historical Analysis**
- **Problem:** Logs rotate/delete, making trends hard to spot
- **Solution:** 30 days of metrics history (99% less disk than v2.0)

**6. Performance Blind Spots**
- **Problem:** Can't see consensus participation, peer health, database growth
- **Solution:** Comprehensive metrics across all validator subsystems

**7. Network Health**
- **Problem:** Don't know if your validator is well-connected or isolated
- **Solution:** Peer tracking, UNL health, network validation metrics

**Who benefits most?**
- Validator operators who need 24/7 uptime awareness
- Teams running multiple validators
- Operators transitioning from manual monitoring
- Anyone who values their time (automated alerts >> constant checking)

### Can I customize the Grafana dashboards?

Yes, with some important considerations:

**Customizing Existing Dashboards:**

1. **Via Grafana UI:**
   - Edit panels, change colors, rearrange layout
   - **Warning:** Changes are lost on collector container restart
   - **Why?** Dashboards are provisioned from JSON files

2. **Via JSON Files (Persistent):**
   ```bash
   # Edit the source
   nano config/grafana/provisioning/dashboards/xrpl-validator-main.json

   # Restart Grafana
   docker compose restart grafana
   ```
   - Changes persist across restarts
   - Version controlled in git
   - Can be shared with community

**Creating New Dashboards:**

1. Create in Grafana UI
2. Export JSON
3. Save to `config/grafana/provisioning/dashboards/`
4. Add to `dashboard.yaml`:
   ```yaml
   - name: 'my-dashboard'
     type: file
     options:
       path: /etc/grafana/provisioning/dashboards/my-dashboard.json
   ```
5. Restart Grafana

**Best Practices:**
- Always export custom dashboards as JSON backups
- Document custom panels in comments
- Consider contributing useful dashboards back to the project!

**Available Metrics:**
- See [METRICS.md](../METRICS.md) for full list of available metrics
- All 40 XRPL validator metrics are exposed in VictoriaMetrics
- Query language: PromQL

---

# Configuration & Operations

### How do I configure email/webhook alerts?

Alerts are auto-configured! You just need to add your notification channel:

**Email Alerts (SMTP):**

1. Edit `docker-compose.yml` (Grafana section):
   ```yaml
   environment:
     - GF_SMTP_ENABLED=true
     - GF_SMTP_HOST=smtp.gmail.com:587
     - GF_SMTP_USER=your-email@gmail.com
     - GF_SMTP_PASSWORD=your-app-password
     - GF_SMTP_FROM_ADDRESS=your-email@gmail.com
   ```

2. Edit `config/grafana/provisioning/alerting/contact-points.yaml`:
   ```yaml
   - orgId: 1
     name: grafana-default-email
     receivers:
       - uid: default-email
         type: email
         settings:
           addresses: your-email@gmail.com  # ← Change this
   ```

3. Restart Grafana:
   ```bash
   docker compose restart grafana
   ```

**Discord Webhook:**

1. Get webhook URL from Discord Server Settings → Integrations → Webhooks
2. Edit `contact-points.yaml` and uncomment Discord section:
   ```yaml
   - orgId: 1
     name: discord-alerts
     receivers:
       - uid: discord-receiver
         type: discord
         settings:
           url: https://discord.com/api/webhooks/YOUR_WEBHOOK_URL
   ```

3. Restart: `docker compose restart grafana`

**Other Channels:**
- Slack: Uncomment Slack section in `contact-points.yaml`
- Teams: Uncomment Teams section
- Telegram: Uncomment and configure bot token
- PagerDuty: Uncomment and add integration key
- Custom Webhook: Uncomment generic webhook section

**What alerts are configured?**
14 alert rules across 3 categories:
- 5 Critical Monitoring: Validator not proposing, Agreement < 90%, Unhealthy state, WebSocket/HTTP down
- 3 Network Monitoring: Low peer count, high disconnections, connectivity issues
- 6 Performance Monitoring: High load factor, I/O latency, peer latency, memory usage, disk space, validator CPU

See `config/grafana/provisioning/alerting/rules.yaml` for full details.

### How do I change my Grafana password?

You can change your Grafana admin password using either the Web UI or the command line.

**Method 1: Web UI (Recommended)**

1. Log in to Grafana: `http://localhost:3000` (or your custom port)
2. Click on your profile icon in the bottom left
3. Select **"Profile"**
4. Click **"Change Password"**
5. Enter your current password and new password
6. Click **"Change Password"**

**Method 2: Command Line**

Reset the admin password directly via Docker:

```bash
# Set a new password
docker exec grafana grafana-cli admin reset-admin-password YOUR_NEW_PASSWORD

# Restart Grafana to apply changes
docker compose restart grafana
```

**Method 3: Environment Variable (Fresh Install)**

Before first login, you can set a custom admin password in `docker-compose.yml`:

```yaml
services:
  grafana:
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=your-secure-password
```

Then restart:
```bash
docker compose down
docker compose up -d
```

**Note:** Grafana will prompt you to change the default password (`admin`/`admin`) on first login.

**Forgot your password?**

Use Method 2 (Command Line) to reset without needing the old password.

**Security Best Practices:**
- Change default password immediately after installation
- Use a strong password (12+ characters, mixed case, numbers, symbols)
- Consider enabling two-factor authentication (2FA) in Grafana settings
- Restrict Grafana port access via firewall if not accessed remotely

### How do I display the dashboard in full-screen kiosk mode?

Grafana kiosk mode hides the top menu bar and sidebar for a clean, distraction-free display on TVs or dedicated monitoring screens.

**Method 1: URL Parameter (Recommended)**

Add `&kiosk` to the end of your dashboard URL:

```
http://localhost:3000/d/xrpl-validator/xrpl-validator-main?kiosk
```

To exit kiosk mode, press `Esc` on your keyboard.

**Method 2: Keyboard Shortcut**

While viewing the dashboard:
1. Press `v` to toggle the View menu
2. Select **"Kiosk mode"** or press `k`

Or simply press `d` + `k` in quick succession.

**Common Use Cases:**

- **TV Display:** Mount a monitor on the wall showing your validator status 24/7
- **Dedicated Monitoring Station:** Set up a Raspberry Pi or spare computer for continuous dashboard display
- **Wall-mounted Tablet:** Use a tablet in kiosk mode for at-a-glance monitoring

**Tips:**

- Use browser full-screen mode (F11) in addition to kiosk mode for maximum screen space
- Consider using a browser extension for auto-refresh if you need to keep the display updated
- For permanently dedicated displays, set the kiosk URL as your browser's homepage with auto-start on boot

**Note:** Grafana kiosk mode will still respect your session timeout settings. You may need to log in again periodically unless you adjust Grafana's session configuration.

### What happens if I don't enable HTTP API?

XRPL Monitor v3.0 can run in **WebSocket-only mode**, but you'll lose ~5-10% of metrics that are only available via HTTP polling.

**What Still Works (WebSocket Streams):**

✅ **Real-time metrics (95% coverage):**
- Ledger closes (instant notifications)
- Server state changes (full, proposing, syncing)
- Peer connections/disconnections
- Validation tracking (agreements, missed)
- Consensus performance

✅ **All critical monitoring:**
- Your validator's state (proposing, full, syncing)
- Ledger synchronization status
- Validation participation rate
- Network consensus health

**What You'll Lose (HTTP Polling Metrics):**

❌ **server_info (5s polling) - 4 metrics:**
- Load factor
- Server uptime
- Validation quorum
- UNL expiry days

❌ **peers (60s polling) - 3 metrics:**
- Peer latency averages
- Peer sanity status
- Detailed peer connection info

❌ **server_state (5min polling) - 2 metrics:**
- State accounting data
- Internal state transitions

**Impact Assessment:**

| Severity | Impact | Affected Metrics |
|----------|--------|------------------|
| **Low** | Most dashboards work | 9 of 40 metrics missing |
| **Medium** | Missing performance context | No load factor, peer latency |
| **High** | Database monitoring still works | Filesystem access unaffected |

**Dashboard Behavior:**

Panels showing HTTP-only metrics will display "No Data":
- Load Factor gauge (Performance row)
- UNL Expiry gauge (Validator row)
- Peer Latency stat panel (Peers row)

**Why You Might Run WebSocket-Only:**

1. **Security Hardening:** HTTP admin API disabled by design
2. **Network Restrictions:** Only WebSocket port exposed
3. **Minimal Attack Surface:** Fewer open ports

**Recommendation:**

Enable both WebSocket (6006) and HTTP (5005) APIs for complete metric coverage. If you must choose one, **WebSocket is more important** - it provides real-time critical metrics.

**Configuration:**

See [rippled Configuration Guide](RIPPLED-CONFIG.md) for details on enabling both APIs.

### Can I monitor multiple validators?

Not in v3.0 (single validator only). Multi-validator support is planned for v3.1:

**Current Limitation:**
- One dashboard per validator node
- One collector instance per validator
- One set of containers per validator

**Workaround for Multiple Validators (v3.0):**

Deploy separate instances with different ports:

```bash
# Validator 1
cd /home/user/xrpl-monitor-validator1
./install.sh
# Configure: Grafana 3000, VictoriaMetrics 8428, rippled :6006

# Validator 2
cd /home/user/xrpl-monitor-validator2
./install.sh
# Configure: Grafana 3001, VictoriaMetrics 8429, rippled :6007
```

Each instance is completely independent.

**v3.1 Planned Features:**
- Single Grafana instance with multi-validator dropdowns
- Centralized VictoriaMetrics
- Validator comparison dashboards
- Aggregate fleet health metrics

### How long is historical data retained?

**Default:** 30 days

**Configurable** via `docker-compose.yml`:

```yaml
victoria-metrics:
  command:
    - '--retentionPeriod=30d'  # ← Change this
```

**Options:**
- `--retentionPeriod=7d` - 7 days
- `--retentionPeriod=90d` - 90 days
- `--retentionPeriod=1y` - 1 year

**Disk Usage Estimates (v3.0):**
- 30 days: ~290 MB
- 90 days: ~870 MB
- 1 year: ~3.5 GB

**After changing retention:**
```bash
docker compose down
docker compose up -d
```

**Note:** Increasing retention does NOT recover deleted data. It only affects future data.

### What happens if my rippled node goes down?

**Immediate Effects:**

1. **WebSocket Disconnection:**
   - Collector logs: `WebSocket connection lost. Reconnecting...`
   - Automatic reconnection attempts every 5 seconds
   - Grafana dashboards show last known values (flatline)

2. **Alert Firing:**
   - "Validator Server Down" alert fires within 30 seconds
   - Notifications sent to all configured channels

3. **Metric Gaps:**
   - No new data written to VictoriaMetrics
   - Historical data preserved
   - Gap visible as flatline or "no data" in panels

**When rippled Returns:**

1. **Automatic Reconnection:**
   - Collector detects rippled is back
   - Re-establishes WebSocket streams
   - Resumes HTTP polling

2. **Metrics Resume:**
   - New data starts flowing immediately
   - Gap remains in historical data (cannot be backfilled)
   - Sliding window counters (agreements/missed) may be affected

3. **Alert Resolution:**
   - "Validator Server Down" alert auto-resolves
   - Resolution notification sent

**Best Practices:**
- Monitor rippled's systemd service: `systemctl status rippled`
- Set up redundant alert channels (email + Discord)
- Document your rippled restart procedures

### What ports need to be accessible?

**Ports Used by XRPL Monitor:**

| Port | Service | Accessible From | Required |
|------|---------|-----------------|----------|
| 3000 | Grafana Dashboard | Your browser | Yes (users) |
| 8428 | VictoriaMetrics API | Collector, vmagent | Yes (internal) |
| 8427 | vmagent | VictoriaMetrics | Yes (internal) |
| 9100 | Node Exporter | vmagent | Yes (internal) |
| 9101 | Uptime Exporter | vmagent | Yes (internal) |
| 9102 | State Exporter | Grafana, vmagent | Yes (internal) |

**Ports Accessed on rippled:**

| Port | Service | Protocol | Required |
|------|---------|----------|----------|
| 6006 | rippled WebSocket Admin | WebSocket | Yes |
| 5005 | rippled HTTP Admin | HTTP | Optional* |

*Optional if using `docker exec` fallback for peer metrics

**Firewall Configuration:**

```bash
# Allow Grafana access (from your IP only)
sudo ufw allow from YOUR_IP to any port 3000

# Block public access to other ports
sudo ufw deny 8428  # VictoriaMetrics
sudo ufw deny 9100  # Node Exporter
sudo ufw deny 9101  # Uptime Exporter
sudo ufw deny 9102  # State Exporter
sudo ufw deny 5005  # rippled admin (if exposed)
sudo ufw deny 6006  # rippled WebSocket admin (if exposed)
```

**SSH Tunnel (Recommended for Remote Access):**

```bash
# From your local machine
ssh -L 3000:localhost:3000 user@validator-server

# Access: http://localhost:3000
```

**Docker Network:**
- All containers communicate via `xrpl-monitor-network` (internal)
- Only Grafana exposes a public port (configurable during install)

---

# Troubleshooting

### Grafana shows "No Data"

**1. Check collector is running:**
```bash
docker compose ps
# Should show: xrpl-monitor-collector (Up)
```

**2. Check collector logs:**
```bash
docker compose logs collector | tail -50
```

Look for:
- ✅ `Connected to rippled WebSocket`
- ✅ `Subscribed to streams: ledger, server, validations...`
- ❌ `Connection refused` → rippled not accessible
- ❌ `Authentication failed` → admin access not configured

**3. Verify rippled accessibility:**
```bash
# WebSocket
curl -i http://localhost:6006

# HTTP
curl -i http://localhost:5005
```

**4. Check VictoriaMetrics has data:**
```bash
# Query metric count
curl 'http://localhost:8428/api/v1/query?query=xrpl_ledger_sequence' | jq
```

If empty: Collector isn't writing data (check rippled connection)

**5. Verify Grafana datasource:**
- Grafana → Configuration → Data Sources → VictoriaMetrics
- Click "Test" button
- Should show: ✅ "Data source is working"

### "Port already in use" error during installation

**Cause:** Another service is using the default port (3000, 8428, or 9100)

**Solution 1:** Use the installer's auto-detection (recommended)
- The installer automatically detects conflicts
- It will prompt you with the next available port
- Press Enter to accept, or enter custom port

**Solution 2:** Manually configure ports before installation

Edit `docker-compose.yml`:
```yaml
grafana:
  ports:
    - "3001:3000"  # Changed from 3000:3000

victoria-metrics:
  ports:
    - "8429:8428"  # Changed from 8428:8428
```

**Solution 3:** Stop conflicting service

```bash
# Find what's using port 3000
sudo lsof -i :3000

# Stop the service (example)
sudo systemctl stop grafana  # If v2.0 Grafana
```

### Validation counts seem wrong

**Expected Variance:**
- ±1-5% difference from XRPScan is normal
- Caused by timing windows and network propagation

**Troubleshooting Larger Discrepancies:**

**1. Check validation stream is active:**
```bash
docker compose logs collector | grep "validations stream"
```

Should see periodic validation messages.

**2. Verify your validator is proposing:**
```bash
curl -s http://localhost:5005 -d '{
  "method": "server_info"
}' | jq '.result.info.server_state'
```

Should show: `"proposing"` or `"full"` (both are normal)

**3. Check for stream reconnections:**
```bash
docker compose logs collector | grep -i "reconnect"
```

Frequent reconnects can cause missed validations.

**4. Compare with rippled logs:**
```bash
# Your validator's validation messages
sudo journalctl -u rippled | grep "We validated"
```

Count should roughly match dashboard over same time period.

**When to worry:**
- Consistently 0 validations → Check rippled is validating
- Sudden drop to 0 → Check collector/rippled connection
- Consistently >20% variance → Check clock sync on server (NTP)

### Docker Compose won't start

**Error: "command not found: docker compose"**

**Cause:** Docker Compose plugin not installed

**Solution (Ubuntu):**
```bash
sudo apt-get update
sudo apt-get install docker-compose-plugin

# Verify
docker compose version
```

**Error: "permission denied"**

**Cause:** User not in docker group

**Solution:**
```bash
sudo usermod -aG docker $USER

# Log out and back in, then verify:
docker ps
```

**Error: "network xrpl-monitor-network already exists"**

**Cause:** Previous installation not fully removed

**Solution:**
```bash
docker compose down --volumes --remove-orphans
docker network rm xrpl-monitor-network
docker compose up -d
```

---

# Still Have Questions?

- **Documentation:** [README.md](../README.md), [METRICS.md](../METRICS.md), [INSTALLATION.md](../INSTALLATION.md)
- **Issues:** [GitHub Issues](https://github.com/realgrapedrop/xrpl-validator-dashboard/issues)
- **Discussions:** [GitHub Discussions](https://github.com/realgrapedrop/xrpl-validator-dashboard/discussions)
- **XRPL Community:** Discord `#validators` channel

---

**Last Updated:** 2025-11-12
**Version:** 3.0.0
