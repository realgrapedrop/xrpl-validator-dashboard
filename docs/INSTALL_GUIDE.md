# **__INSTALL & OPERATIONS GUIDE__**

*Complete guide to install, operate, and maintain the XRPL Validator Dashboard monitoring system.*

---

# Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Uninstalling](#uninstalling)
- [Updates](#updates)
- [Troubleshooting](#troubleshooting)
- [Getting Help](#getting-help)
- [Related Documentation](#related-documentation)

---

# Prerequisites

### System Requirements

| Requirement | Specification |
|-------------|---------------|
| **Operating System** | Ubuntu 20.04 LTS or later |
| **Docker** | Version 23.0+ |
| **Docker Compose** | Version 2.0+ (auto-installed on Ubuntu) |
| **rippled** | Running on same machine |
| **Disk Space** | ~500 MB for images, ~290 MB for 30-day metrics |
| **Memory** | ~729 MB RAM total |

### rippled Requirements

XRPL Monitor requires rippled with admin API access via WebSocket. The port number (6006 in this example) is configurable—any available port works as long as it's defined in your `rippled.cfg`:

```ini
# Example rippled.cfg
[port_ws_admin_local]
port = 6006              # Can be any available port
ip = 127.0.0.1
admin = 127.0.0.1
protocol = ws
```

**Security Note:** When XRPL Monitor runs on the same machine as your rippled validator (recommended), binding to `127.0.0.1` ensures the admin API is only accessible locally. This is a low-risk configuration—no firewall rules are needed since all traffic stays on localhost and never traverses the network.

See [rippled Configuration Guide](RIPPLED-CONFIG.md) for details.

---

# Installation

### Pre-Installation Checklist

Before starting, verify:

- [ ] Docker installed: `docker --version`
- [ ] rippled running: `rippled server_info` or `curl http://localhost:5005`
- [ ] Admin API enabled on port 6006
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

### Migrating from v2.0

If you're running XRPL Monitor v2.0, uninstall it first:

```bash
cd /path/to/v2.0
./uninstall.sh
```

Then install v3.0 using the steps above. Historical data from v2.0 cannot be migrated due to different database formats.

---

# Uninstalling

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

After installation, updates are applied in two simple steps:

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
- Main and Cyberpunk dashboards get timestamped backup copies
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

See [ALERTS.md](ALERTS.md) for webhook alerts (Discord, Slack, etc.).

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
- **Default Main Dashboard** - The standard XRPL Validator Dashboard
- **Cyberpunk Dashboard** - Vibrant color theme variant
- **Both dashboards** - Restore both at once

You'll be prompted for your Grafana username (default: `admin`) and password. The user account must have **Admin** or **Editor** role in Grafana.

---

# Troubleshooting

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
