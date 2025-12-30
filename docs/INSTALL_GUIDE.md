# **__INSTALL & OPERATIONS GUIDE__**

*Complete guide to install, operate, and maintain the XRPL Validator Dashboard monitoring system.*

---

# Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Uninstalling](#uninstalling)
- [Updates](#updates)
- [Migrating from v2.0](#migrating-from-v20)
- [Hardened Architecture](#hardened-architecture)
- [Troubleshooting](#troubleshooting)
- [Getting Help](#getting-help)
- [Related Documentation](#related-documentation)

---

# Prerequisites

**In This Section:**
- [System Requirements](#system-requirements)
- [rippled Requirements](#rippled-requirements)

---

### System Requirements

| Requirement | Specification |
|-------------|---------------|
| **Operating System** | Ubuntu 20.04+, Linux Mint 21+, or Debian-based distros |
| **Docker** | Version 23.0+ |
| **Docker Compose** | Version 2.0+ (auto-installed on Ubuntu) |
| **curl** | For API calls (auto-installed if missing) |
| **jq** | For JSON processing (auto-installed if missing) |
| **rippled** | Running on same machine |
| **Disk Space** | ~500 MB for images, ~290 MB for 30-day metrics |
| **Memory** | ~729 MB RAM total |

### rippled Requirements

XRPL Monitor requires rippled with admin API access via both WebSocket and HTTP RPC. The port numbers are configurable—any available ports work as long as they're defined in your `rippled.cfg`:

```ini
# Example rippled.cfg

[port_rpc_admin_local]
port = 5005              # HTTP RPC admin port (any available port)
ip = 127.0.0.1
admin = 127.0.0.1
protocol = http

[port_ws_admin_local]
port = 6006              # WebSocket admin port (any available port)
ip = 127.0.0.1
admin = 127.0.0.1
protocol = ws
```

**Security Note:** When XRPL Monitor runs on the same machine as your rippled validator (recommended), binding to `127.0.0.1` ensures the admin API is only accessible locally. This is a low-risk configuration—no firewall rules are needed since all traffic stays on localhost and never traverses the network.

See [rippled Configuration Guide](RIPPLED-CONFIG.md) for details.

---

# Installation

**In This Section:**
- [Pre-Installation Checklist](#pre-installation-checklist)
- [Step 1: Install Docker](#step-1-install-docker-if-needed)
- [Step 2: Clone Repository](#step-2-clone-repository)
- [Step 3: Run Installer](#step-3-run-installer)
- [Step 4: Verify Installation](#step-4-verify-installation)
- [Step 5: Access Dashboard](#step-5-access-dashboard)

---

### Pre-Installation Checklist

Before starting, verify:

- [ ] Docker installed: `docker --version`
- [ ] curl installed: `curl --version` (auto-installed if missing)
- [ ] jq installed: `jq --version` (auto-installed if missing)
- [ ] rippled running: `rippled server_info` or `curl http://localhost:5005`
- [ ] WebSocket admin API enabled (default port 6006)
- [ ] HTTP RPC admin API enabled (default port 5005)
- [ ] Ports available: 3000, 8428, 9100-9102

### Step 1: Install Docker (if needed)

> **Note:** The installer will offer to install Docker automatically if it's not already installed. You can skip this step and let the installer handle it.

<details>
<summary><strong>Click to expand Docker installation instructions</strong></summary>

#### Quick Docker Installation (Ubuntu)

```bash
# Remove old packages
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    sudo apt-get remove $pkg 2>/dev/null
done

# Set up repository
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$UBUNTU_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify installation
docker --version
sudo docker run hello-world

# Allow running without sudo (optional, requires logout/login)
sudo usermod -aG docker $USER
```

</details>

### Step 2: Clone Repository

```bash
cd /home/user/projects    # Navigate to your preferred install location
git clone https://github.com/realgrapedrop/xrpl-validator-dashboard.git
cd xrpl-validator-dashboard
```

### Step 3: Run Installer

```bash
sudo ./install.sh
```

The installer will:
1. Check for Docker (fails if not present)
2. Install Docker Compose if missing (Ubuntu only)
3. Detect port conflicts and suggest alternatives
4. Auto-detect rippled endpoints
5. Pull container images
6. Start all services
7. Provision Grafana datasource, dashboard, and 14 alert rules

**Installation time:** < 5 minutes

### Step 4: Verify Installation

```bash
docker ps --format "table {{.Names}}\t{{.Status}}" | grep xrpl-monitor
```

Expected output shows 6-8 containers with "Up" status.

To verify metrics are flowing:

```bash
docker compose logs -f collector    # Press Ctrl+C to exit
```

Look for: `INFO Connected to rippled WebSocket` and `INFO Metrics written to VictoriaMetrics`

> **Note:** If you just installed rippled, some panels show "No data" initially. This is normal—panels like Ledgers Per Minute require 1-6 hours of sync time.

### Step 5: Access Dashboard

Open your browser to: `http://localhost:3000`

**Default credentials:**
- Username: `admin`
- Password: `admin`

Change the password on first login.

---

# Uninstalling

**In This Section:**
- [Clean Uninstall](#clean-uninstall)
- [Manual Uninstall](#manual-uninstall)

---

### Clean Uninstall

```bash
sudo ./uninstall.sh
```

This removes:
- All Docker containers
- All data volumes (metrics, dashboards)
- Docker network
- Log files

**Note:** The uninstaller prompts to fully remove Docker and Docker Compose, or keep them installed.

### Manual Uninstall

```bash
docker compose down -v
docker rm -f $(docker ps -a --format '{{.Names}}' | grep xrpl-monitor)
docker volume rm $(docker volume ls --format '{{.Name}}' | grep xrpl-monitor)
docker network rm xrpl-monitor-network 2>/dev/null || true
```

---

# Updates

After installation, updates are applied in two simple steps.

**In This Section:**
- [Step 1: Pull Latest Code](#step-1-pull-latest-code)
- [Step 2: Apply Updates](#step-2-apply-updates)
- [Check for Available Updates](#check-for-available-updates)
- [Dashboard Preservation](#dashboard-preservation)
- [Using manage.sh](#using-managesh)

---

### Step 1: Pull Latest Code

```bash
cd /path/to/xrpl-validator-dashboard
git pull
```

This downloads the latest changes including:
- Bug fixes and improvements
- New dashboard panels and features
- Updated alert rules
- Exporter and collector enhancements

### Step 2: Apply Updates

```bash
./manage.sh    # Select option 10 "Apply Updates"
```

Option 10 automatically:
- Regenerates config files from your `.env` settings
- Rebuilds containers with code changes
- Restarts all services
- Backs up and preserves your dashboards

### Check for Available Updates

To see what updates are available before pulling:

```bash
git fetch origin
git log HEAD..origin/main --oneline
```

### Dashboard Preservation

Your dashboards are automatically protected during updates:
- Main, Cyberpunk, and Light Mode dashboards get timestamped backup copies
- Custom dashboards you created are preserved with timestamps
- Previous backup copies accumulate (not overwritten)
- JSON backups saved to `data/dashboard-backups/` for manual recovery

---

## Using manage.sh

The `manage.sh` script is your primary tool for managing XRPL Monitor—including applying updates. Run `./manage.sh` for an interactive menu or use command-line mode:

```bash
./manage.sh                      # Interactive menu
./manage.sh status               # Check all services
./manage.sh start                # Start all services
./manage.sh stop                 # Stop all services
./manage.sh restart [service]    # Restart all or specific service
./manage.sh logs [service]       # View logs (default: collector)
./manage.sh rebuild [service]    # Rebuild and restart a service
./manage.sh --help               # Show all options
```

**Menu Options:**

| Option | Name | Description |
|--------|------|-------------|
| 1 | Start the stack | Start all monitoring services |
| 2 | Stop the stack | Stop all monitoring services |
| 3 | Restart the stack | Restart all or specific service |
| 4 | Manage a single service | Start/stop/restart individual services |
| 5 | View logs (all) | Follow logs from all containers |
| 6 | View logs (specific) | Follow logs from one service |
| 7 | Check service status | Display status of all services |
| 8 | Rebuild service | Rebuild and restart a container |
| 9 | Backup & Restore | Backup/restore Grafana dashboards |
| 10 | Apply Updates | Apply updates after git pull |
| 11 | Setup Gmail Alerts | Configure email notifications |
| 12 | Advanced settings | Retention period, restore defaults |
| 13 | Exit | Exit the management console |

### Customizing Ports

Edit `.env` to change ports:

```bash
GRAFANA_PORT=3003
NODE_EXPORTER_PORT=9104
STATE_EXPORTER_PORT=9103
VICTORIA_METRICS_PORT=8428
```

Apply changes with `./manage.sh` → option 10 "Apply Updates".

### Upgrading Components

XRPL Monitor uses these tested component versions:

| Component | Tested Version | Purpose |
|-----------|---------------|---------|
| Grafana | v12.1.1 | Dashboard platform |
| VictoriaMetrics | v1.129.1 | Time-series database |
| vmagent | v1.129.1 | Metrics agent |
| Node Exporter | v1.10.2 | System metrics |

To pull latest images:

```bash
docker compose pull
docker compose up -d
```

For production stability, pin versions in `docker-compose.yml`.

### Configuring Email Alerts

Use `./manage.sh` → option 11 for guided Gmail setup, or edit `.env` manually:

```bash
GF_SMTP_ENABLED=true
GF_SMTP_HOST=smtp.gmail.com:587
GF_SMTP_USER=your-email@gmail.com
GF_SMTP_PASSWORD="your-app-password"    # Quote if contains spaces!
GF_SMTP_FROM_ADDRESS=your-email@gmail.com
```

Then restart: `docker compose restart grafana`

See [ALERTS.md](ALERTS.md) for webhook alerts (Discord, Slack, etc.) and [SMS alerts using TextBee](ALERTS.md#sms-alerts-textbee---free-option) (free option).

### Rollback

To rollback code changes:

```bash
git tag -l | grep stable                    # List stable tags
git checkout v3.0-stable-20251130 -- .      # Restore to tag
./manage.sh                                  # Option 10 "Apply Updates"
```

To rollback component versions, edit `docker-compose.yml` to use previous image versions, then:

```bash
docker compose down && docker compose up -d
```

### Restoring Dashboards

If you accidentally break a dashboard, you can restore it to the default:

```bash
./manage.sh    # Select option 12 (Advanced settings)
               # Select option 2 (Restore default dashboard)
```

You can restore:
- **Default Main Dashboard** - The standard XRPL Validator Dashboard (dark theme)
- **Cyberpunk Dashboard** - Vibrant neon color theme variant
- **Light Mode Dashboard** - Blue color scheme optimized for Grafana's light theme
- **All dashboards** - Restore all three at once

You'll be prompted for your Grafana username (default: `admin`) and password. The user account must have **Admin** or **Editor** role in Grafana.

---

# Migrating from v2.0

If you're running XRPL Monitor v2.0, simply uninstall it and install v3.0 fresh.

**In This Section:**
- [Why a Clean Install?](#why-a-clean-install)
- [Migration Steps](#migration-steps)

---

### Why a Clean Install?

v3.0 is a complete rewrite with a different architecture:

- **Different database** - v3.0 uses VictoriaMetrics instead of Prometheus
- **Different metrics** - New metric names and collection methods
- **Different containers** - All containers are renamed with `xrpl-monitor-` prefix
- **No conflicts** - v2.0 and v3.0 use different container names, networks, and volumes

Historical data from v2.0 cannot be migrated, but this has minimal impact—most dashboard panels show real-time or rolling 24-hour data that rebuilds quickly after installation.

### Migration Steps

```bash
# Step 1: Uninstall v2.0
cd /path/to/v2.0
./uninstall.sh

# Step 2: Install v3.0 (in a new directory)
cd /home/user/projects
git clone https://github.com/realgrapedrop/xrpl-validator-dashboard.git
cd xrpl-validator-dashboard
sudo ./install.sh
```

Your validator continues running normally throughout this process—the monitoring dashboard is independent of rippled.

---

# Hardened Architecture

For security-conscious operators, we recommend separating the validator and monitoring stack onto different hosts. This eliminates Docker from the validator host, reducing attack surface.

**Benefits:**
- No Docker daemon running on validator (eliminates container escape risk)
- Dedicated validator resources (no resource contention)
- Network isolation between validator and monitoring
- Follows XRPL Foundation security recommendations

**Architecture:**
- **Host 1 (Validator):** rippled only, no Docker, minimal software
- **Host 2 (Monitor):** Docker stack with Grafana, VictoriaMetrics, collectors

The monitor connects to the validator's admin API ports (5005, 6006) over a private network, with firewall rules restricting access.

**For complete setup instructions, see [Hardened Architecture Guide](HARDENED_ARCHITECTURE.md)**

---

# Troubleshooting

**In This Section:**
- [Docker Not Found](#docker-not-found)
- [Port Already in Use](#port-already-in-use)
- [Collector Can't Connect to rippled](#collector-cant-connect-to-rippled)
- [Dashboard Shows No Data](#dashboard-shows-no-data)
- [Permission Denied: /var/lib/rippled](#permission-denied-varlibrippled)
- [.env Error: "command not found"](#env-error-command-not-found)
- [Merge Conflicts on git pull](#merge-conflicts-on-git-pull)
- [Services Unhealthy After Update](#services-unhealthy-after-update)
- [Quick Health Check](#quick-health-check)
- [Firewall Issues (Linux Mint / UFW)](#firewall-issues-linux-mint--ufw)

---

### Docker Not Found

Install Docker using the instructions in Prerequisites above.

### Port Already in Use

Edit `.env` to change ports, then run `./manage.sh` → option 10 "Apply Updates".

### Collector Can't Connect to rippled

```bash
rippled server_info          # Check rippled is running
cat .env | grep RIPPLED      # Check configuration
```

### Dashboard Shows No Data

1. Wait 60 seconds for initial metrics
2. Check collector: `docker compose logs collector | grep "Metrics written"`
3. Test VictoriaMetrics: `curl http://localhost:8428/api/v1/labels`
4. Restart collector: `docker compose restart collector`

### Permission Denied: /var/lib/rippled

```bash
sudo chmod -R o+rx /var/lib/rippled
docker compose restart collector
```

### .env Error: "command not found"

Values with spaces must be quoted:

```bash
# BAD
GF_SMTP_PASSWORD=uhoc qzyl yonu xcwk

# GOOD
GF_SMTP_PASSWORD="uhoc qzyl yonu xcwk"
```

### Merge Conflicts on git pull

```bash
git stash && git pull && ./manage.sh   # Option 10 "Apply Updates"
git stash pop
```

### Services Unhealthy After Update

```bash
docker compose logs -f collector
./manage.sh rebuild collector
```

### Quick Health Check

```bash
curl -s "http://localhost:8428/api/v1/query?query=up" | jq '.data.result | length'
```

### Firewall Issues (Linux Mint / UFW)

If the collector can't connect to rippled or you can't access Grafana from another machine:

```bash
# Check if UFW is active
sudo ufw status

# Allow Grafana access from your local network
sudo ufw allow from 192.168.1.0/24 to any port 3000

# Or allow from a specific IP
sudo ufw allow from 192.168.1.100 to any port 3000

# If rippled runs in Docker, allow Docker networks
sudo ufw allow from 172.16.0.0/12 to any
```

**Note:** If running XRPL Monitor on the same machine as rippled (recommended), firewall rules typically aren't needed for localhost connections.

---

# Getting Help

1. **Check FAQ:** [FAQ.md](FAQ.md)
2. **Review logs:** `docker compose logs -f`
3. **GitHub Issues:** [Report bugs](https://github.com/realgrapedrop/xrpl-validator-dashboard/issues)
4. **XRPL Discord:** `#validators` channel

---

# Related Documentation

- **[Alerts](ALERTS.md)** - Configure email and webhook notifications
- **[Tuning](TUNING.md)** - Optimize performance
- **[Metrics](METRICS.md)** - Understand dashboard panels
- **[Architecture](ARCHITECTURE.md)** - System design
- **[Release Notes](RELEASE_NOTES.md)** - Version history
