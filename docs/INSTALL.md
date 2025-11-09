# XRPL Validator Dashboard - Installation Guide

This guide provides detailed step-by-step instructions for installing the XRPL Validator Dashboard on Ubuntu 20.04/22.04/24.04.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation Overview](#installation-overview)
- [Part 1: Install Prerequisites](#part-1-install-prerequisites)
- [Part 2: Dashboard Setup](#part-2-dashboard-setup)
- [Docker vs Native rippled](#docker-vs-native-rippled)
- [Troubleshooting](#troubleshooting)
- [Next Steps](#next-steps)

---

## Prerequisites

Before starting, ensure you have:

- **Operating System**: Ubuntu 20.04, 22.04, or 24.04 LTS
- **User Access**: Non-root user with sudo privileges
- **rippled Node**: Either Docker or Native installation of rippled (can be on same or different server)
- **SSH Access**: If rippled is on a remote server
- **Network Access**: Ability to connect to rippled's admin endpoint

---

## Installation Overview

The installation process requires running `./install.sh` **TWICE**:

### First Run - Part 1: Install Prerequisites
- Installs Python 3 and pip3
- Installs Docker Engine
- Installs Docker Compose V2
- Adds user to docker group
- **Requires logout/login after completion**

### Second Run - Part 2: Dashboard Setup
- Auto-detects rippled installation (Docker or Native)
- Creates monitoring containers (Grafana, Prometheus, Node Exporter, XRPL Monitor)
- Configures and imports Grafana dashboard
- Sets up automatic startup

---

## Part 1: Install Prerequisites

### Step 1: Download the Project

```bash
cd ~
git clone https://github.com/yourusername/xrpl-validator-dashboard.git
cd xrpl-validator-dashboard
```

### Step 2: Run Part 1 Installation

```bash
./install.sh
```

**What happens during Part 1:**

1. **System Update**
   ```
   Step 1: Updating system packages...
   ✓ Package list updated
   ```

2. **Python Installation**
   ```
   Step 2: Installing Python 3 and pip3...
   ✓ Python already installed: Python 3.10.12
   ✓ pip3 already installed: pip 22.0.2
   ```

3. **Docker Prerequisites**
   ```
   Step 3: Installing Docker prerequisites...
   ✓ Prerequisites installed
   ```

4. **Docker GPG Key**
   ```
   Step 4: Adding Docker GPG key...
   ✓ Docker GPG key added
   ```

5. **Docker Repository**
   ```
   Step 5: Adding Docker repository...
   ✓ Docker repository added
   ```

6. **Docker Engine Installation**
   ```
   Step 6: Installing Docker Engine...
   ✓ Docker Engine installed
   ```

7. **Docker Service Start**
   ```
   Step 7: Starting Docker service...
   ✓ Docker service started
   ```

8. **User Group Addition**
   ```
   Step 8: Adding user 'ubuntu' to docker group...
   ✓ User added to docker group
   ```

9. **Verification**
   ```
   Step 9: Verifying installations...
   ✓ Python: Python 3.10.12
   ✓ pip3: pip 22.0.2 from /usr/lib/python3/dist-packages/pip (python 3.10)
   ✓ Docker: Docker version 24.0.7, build afdd53b
   ✓ Docker Compose: Docker Compose version v2.21.0
   ✓ Docker service is running
   ```

### Step 3: Logout and Login

**IMPORTANT:** You must logout and login for Docker group permissions to take effect.

```bash
exit
```

Then log back in via SSH:

```bash
ssh -i your-key.pem ubuntu@your-server-ip
```

### Step 4: Verify Docker Access

After logging back in, verify you can run Docker without sudo:

```bash
docker ps
```

Expected output:
```
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
```

If you get a permission error, the logout/login didn't take effect. Try:
```bash
newgrp docker
```

---

## Part 2: Dashboard Setup

### Step 1: Navigate to Project Directory

```bash
cd ~/xrpl-validator-dashboard
```

### Step 2: Run Part 2 Installation

```bash
./install.sh
```

Since prerequisites are already installed, the script automatically starts Part 2.

### Step 3: Interactive Setup Wizard

The setup wizard will guide you through configuration:

#### 1. rippled Detection

The wizard automatically detects your rippled installation:

**Docker rippled:**
```
✓ Detected Docker rippled installation
  Container: rippled
  Config: /home/ubuntu/rippled/config/rippled.cfg
  Logs: /home/ubuntu/rippled/log
```

**Native rippled:**
```
✓ Detected native rippled installation
  Config: /etc/opt/ripple/rippled.cfg
  Binary: /opt/ripple/bin/rippled
```

**No rippled detected:**
```
ℹ No rippled installation detected on this server
```

If rippled is on a different server, you'll be prompted for SSH connection details.

#### 2. Connection Configuration

**Local Docker rippled:**
```
Detected local Docker rippled
Using docker exec for commands
```

**Local Native rippled:**
```
Detected local native rippled
Configure HTTP JSON-RPC endpoint:
  Host: 127.0.0.1
  Port: 5005
  Admin endpoint will be used for monitoring
```

**Remote rippled:**
```
Enter SSH connection details:
  Host: validator.example.com
  User: ubuntu
  SSH Key: /home/ubuntu/.ssh/id_rsa

Testing SSH connection...
✓ SSH connection successful
```

#### 3. Port Configuration

The wizard auto-detects available ports:

```
Configuring ports...
✓ Found available port for Grafana: 3001
✓ Found available port for Prometheus: 9090
✓ Found available port for Node Exporter: 9100
```

If default ports are in use:
```
⚠ Port 3000 is in use
✓ Found available port for Grafana: 3002
```

#### 4. Container Deployment

```
Creating monitoring stack...
✓ Created docker-compose.yml
✓ Started Prometheus (port 9090)
✓ Started Node Exporter (port 9100)
✓ Started XRPL Monitor (port 9094)
✓ Started Grafana (port 3001)
```

#### 5. Dashboard Import

```
Importing Grafana dashboard...
✓ Dashboard imported: XRPL Validator Monitor
✓ Configured defaults: Job=xrpl-validator, Instance=127.0.0.1:9100
✓ Dashboard set as home page
```

### Step 4: Access Dashboard

The installation completes with access instructions:

```
================================================================================================
Installation Complete! 🎉
================================================================================================

Your XRPL Validator Dashboard is ready!

Access Dashboard:
  1. Set up SSH tunnel (if remote):
     ssh -i your-key.pem -L 3001:localhost:3001 ubuntu@your-server-ip

  2. Open browser: http://localhost:3001

  3. Login credentials:
     Username: admin
     Password: admin
     (You'll be prompted to change password on first login)

  4. Dashboard opens automatically!

Monitoring Services:
  • Grafana Dashboard: http://localhost:3001
  • Prometheus: http://localhost:9090
  • Node Exporter: http://localhost:9100/metrics
  • XRPL Monitor: http://localhost:9094/metrics

Service Management:
  • View status: docker ps
  • View logs: docker logs xrpl-monitor
  • Restart: docker restart xrpl-monitor
  • Stop all: docker compose down
  • Start all: docker compose up -d

Next Steps:
  1. Change default Grafana password
  2. Explore the dashboard panels
  3. Set up alerts (optional)
  4. Configure backup (optional)
```

---

## Docker vs Native rippled

The dashboard supports both installation types with different communication methods:

### Docker rippled

**How it works:**
- Monitor uses `docker exec` to run commands inside rippled container
- No network configuration needed
- Requires Docker socket access

**Configuration:**
```yaml
rippled:
  mode: docker
  container_name: rippled
```

**Verification:**
```bash
docker exec rippled rippled server_info
```

### Native rippled

**How it works:**
- Monitor uses HTTP JSON-RPC API to communicate with rippled
- Requires rippled admin endpoint enabled
- More secure (can restrict API access)

**Configuration:**
```yaml
rippled:
  mode: native
  host: 127.0.0.1
  port: 5005
```

**rippled.cfg requirements:**
```ini
[port_rpc_admin_local]
port = 5005
ip = 127.0.0.1
admin = 127.0.0.1
protocol = http
```

**Verification:**
```bash
curl -X POST http://127.0.0.1:5005 \
  -H "Content-Type: application/json" \
  -d '{"method":"server_info","params":[{}]}'
```

---

## Troubleshooting

### Part 1 Issues

#### Docker installation fails

**Error:**
```
E: Unable to locate package docker-ce
```

**Solution:**
```bash
# Verify Ubuntu version
lsb_release -a

# Ensure you're using Ubuntu (not Debian or other distro)
# Re-run Docker repository setup:
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release
```

#### User not in docker group

**Error:**
```
permission denied while trying to connect to the Docker daemon socket
```

**Solution:**
```bash
# Verify group membership
groups

# Should show: ubuntu adm ... docker

# If docker is missing:
sudo usermod -aG docker $USER

# Then logout and login again
exit
```

### Part 2 Issues

#### rippled not detected

**Problem:** Setup wizard can't find rippled installation

**Solution for Docker rippled:**
```bash
# Verify container is running
docker ps | grep rippled

# If not running:
cd /path/to/rippled
docker compose up -d

# Verify config file exists
ls -la ~/rippled/config/rippled.cfg
```

**Solution for Native rippled:**
```bash
# Verify rippled is installed
which rippled

# Verify config exists
ls -la /etc/opt/ripple/rippled.cfg

# Verify service is running
sudo systemctl status rippled
```

#### Port conflicts

**Error:**
```
Error starting userland proxy: listen tcp 0.0.0.0:3000: bind: address already in use
```

**Solution:**
The installer should auto-detect this, but if it fails:

```bash
# Find what's using the port
sudo lsof -i :3000

# Kill the process or choose different port
# Edit docker-compose.yml manually if needed
nano docker-compose.yml
```

#### Dashboard import fails

**Error:**
```
HTTP error 401: Unauthorized
```

**Solution:**
```bash
# Verify Grafana is running
docker ps | grep grafana

# Check Grafana logs
docker logs xrpl-dashboard-grafana

# Wait 30 seconds for Grafana to fully start, then retry
./scripts/import-dashboard.sh
```

#### Monitor can't connect to rippled

**For Docker mode:**
```bash
# Verify rippled container name
docker ps | grep rippled

# Test docker exec
docker exec rippled rippled server_info

# Check monitor logs
docker logs xrpl-monitor
```

**For Native mode:**
```bash
# Test JSON-RPC endpoint
curl -X POST http://127.0.0.1:5005 \
  -H "Content-Type: application/json" \
  -d '{"method":"server_info","params":[{}]}'

# Verify rippled.cfg has admin endpoint
grep -A 5 "port_rpc_admin_local" /etc/opt/ripple/rippled.cfg

# Check monitor config
cat config.yml
```

#### Grafana dashboard shows "No Data"

**Possible causes:**

1. **Prometheus not scraping metrics**
   ```bash
   # Check Prometheus targets
   # Open http://localhost:9090/targets
   # All targets should show "UP"
   ```

2. **rippled not connected to network**
   ```bash
   # Check rippled status
   docker exec rippled rippled server_info
   # Look for: "server_state": "full" or "tracking"
   ```

3. **Monitor not running**
   ```bash
   # Check container status
   docker ps | grep xrpl-monitor

   # Check logs
   docker logs xrpl-monitor
   ```

4. **Wrong time range in Grafana**
   - Click time range picker (top right)
   - Select "Last 5 minutes" or "Last 15 minutes"
   - Enable auto-refresh

### Remote rippled Issues

#### SSH connection fails

**Error:**
```
✗ SSH connection failed: Permission denied (publickey)
```

**Solution:**
```bash
# Verify SSH key exists
ls -la ~/.ssh/id_rsa

# Test SSH manually
ssh -i ~/.ssh/id_rsa ubuntu@validator.example.com

# Ensure key has correct permissions
chmod 600 ~/.ssh/id_rsa
```

#### SSH commands timeout

**Problem:** Monitor can connect but commands timeout

**Solution:**
```bash
# Increase timeout in config.yml
nano config.yml

# Add/modify:
rippled:
  ssh_timeout: 30  # Increase from default 10

# Restart monitor
docker restart xrpl-monitor
```

---

## Next Steps

After successful installation:

### 1. Change Default Password

On first login to Grafana (http://localhost:3001):
- Username: `admin`
- Password: `admin`
- You'll be prompted to set a new password

### 2. Explore Dashboard Panels

The dashboard includes:
- **Server State**: Current operational state (disconnected, connected, syncing, tracking, full, validating, proposing)
- **Network Sync Progress**: Ledger synchronization status
- **Validation Metrics**: Proposals, validations (only for validators)
- **System Resources**: CPU, RAM, Disk, Network usage
- **Ledger Statistics**: Transaction rates, fee levels

**Note for Non-Validators:** If your node is not configured as a validator, the validation panels will show zeros (expected behavior).

### 3. Configure Alerts (Optional)

See Grafana documentation for setting up:
- Email notifications
- Slack/Discord webhooks
- Alert rules for critical metrics

### 4. Set Up Backups (Optional)

Backup important configuration:
```bash
# Backup configuration
cp config.yml config.yml.backup

# Backup Grafana data (includes dashboards, settings)
docker exec xrpl-dashboard-grafana grafana-cli admin reset-admin-password newpassword

# Export current dashboard
./scripts/export-dashboard.sh  # (if available)
```

### 5. Review Documentation

- [README.md](../README.md) - Overview and quick reference
- [HOW_IT_WORKS.md](HOW_IT_WORKS.md) - Technical architecture details
- [GRAFANA_DASHBOARD.md](GRAFANA_DASHBOARD.md) - Dashboard customization guide

---

## Support

If you encounter issues not covered in this guide:

1. **Check logs:**
   ```bash
   docker logs xrpl-monitor
   docker logs xrpl-dashboard-grafana
   docker logs xrpl-dashboard-prometheus
   ```

2. **Verify configuration:**
   ```bash
   cat config.yml
   cat docker-compose.yml
   ```

3. **GitHub Issues:** Report bugs or request features at [github.com/yourusername/xrpl-validator-dashboard/issues](https://github.com/yourusername/xrpl-validator-dashboard/issues)

---

## Uninstallation

To completely remove the dashboard:

```bash
cd ~/xrpl-validator-dashboard
./uninstall.sh
```

This will:
- Stop and remove all containers
- Remove Docker volumes
- Clean up configuration files
- Optionally remove Docker itself (if you confirm)

**Note:** Your rippled installation is never affected by uninstallation.
