# Migration Guide: Upgrading to Docker-Based Dashboard

This guide is for users upgrading from the **old systemd-based version** to the **new Docker-based GA release**.

## What Changed?

The dashboard has been completely rewritten with a modern architecture:

| Old Version | New GA Version |
|-------------|----------------|
| Systemd service | Docker Compose containers |
| SQLite database | Prometheus time-series DB |
| Manual port configuration | Auto-detection with smart defaults |
| Complex setup | One-command installation |
| Limited monitoring | Full metrics with 30-day retention |

## Migration Steps

### Step 1: Uninstall the Old Version

Navigate to your existing installation directory and run the old uninstall script:

```bash
cd /path/to/old/xrpl-validator-dashboard
./uninstall.sh
```

**If the old `uninstall.sh` doesn't exist or fails**, manually clean up the systemd service:

```bash
# Stop and remove old systemd service
sudo systemctl stop xrpl-validator-dashboard
sudo systemctl disable xrpl-validator-dashboard
sudo rm /etc/systemd/system/xrpl-validator-dashboard.service
sudo systemctl daemon-reload

# Verify service is removed
systemctl status xrpl-validator-dashboard
# Should show "could not be found"
```

### Step 2: Backup Custom Configurations (Optional)

If you customized any settings, save them for reference:

```bash
# Backup config file (if you made custom changes)
cp config.yaml ~/config.yaml.backup 2>/dev/null || true

# Backup any custom alert rules
cp alerts.yaml ~/alerts.yaml.backup 2>/dev/null || true
```

**Note:** The new version has a different configuration structure, so you'll need to manually apply your settings to the new `config.yaml` after installation.

### Step 3: Remove Old Installation Directory

```bash
cd ~
rm -rf xrpl-validator-dashboard
```

**Or if you want to preserve it for reference:**

```bash
cd ~
mv xrpl-validator-dashboard xrpl-validator-dashboard.old
```

### Step 4: Fresh Install of GA Version

```bash
# Clone the new version
git clone https://github.com/realgrapedrop/xrpl-validator-dashboard.git
cd xrpl-validator-dashboard

# Run the automated installer
./install.sh
```

The installer will:
1. **Part 1:** Check for Docker/Python (install if missing)
2. **Part 2:** Auto-detect your rippled installation, configure monitoring, and start services

### Step 5: Verify the New Installation

After installation completes:

1. **Check containers are running:**
   ```bash
   docker ps | grep xrpl-dashboard
   ```

   You should see:
   - `xrpl-dashboard-grafana`
   - `xrpl-dashboard-prometheus`
   - `xrpl-dashboard-node-exporter`
   - `xrpl-dashboard-monitor`

2. **Access Grafana:**
   - URL: `http://localhost:3003` (or your detected port)
   - Username: `admin`
   - Password: `admin`

3. **Verify metrics are flowing:**
   - Check that the dashboard shows current data
   - Verify "State" panel shows your rippled's status

## What You'll Lose

- **Historical metrics** from the old SQLite database (only recent data)
- **Old Grafana customizations** (dashboard is completely new)
- **Alert history** (fresh start with new alerting)

## What's Preserved

✅ **Your rippled installation** - Completely untouched
✅ **rippled configuration** - `/etc/opt/ripple/rippled.cfg` unchanged
✅ **rippled data** - All ledger history preserved
✅ **Validator keys** - No changes to validator setup

## Troubleshooting Migration

### Issue: Old service won't stop

```bash
# Force kill the old process
sudo pkill -f "xrpl.*monitor"
sudo systemctl daemon-reload
```

### Issue: Port conflicts

The new version auto-detects available ports, but if you have conflicts:

```bash
# Check what's using ports
sudo ss -tlnp | grep -E ":(300[0-9]|909[0-9])"

# Edit docker-compose.yml to change ports if needed
nano docker-compose.yml
```

### Issue: Old Docker containers interfering

If you have old dashboard containers from a previous failed attempt:

```bash
# List all dashboard containers
docker ps -a | grep dashboard

# Remove old ones
docker rm -f $(docker ps -a | grep dashboard | awk '{print $1}')
```

### Issue: Want to revert to old version

If you kept the old directory:

```bash
cd ~/xrpl-validator-dashboard.old

# Reinstall old version
python3 -m pip install -r requirements.txt
python3 setup.py

# Uninstall new version
cd ~/xrpl-validator-dashboard
./uninstall.sh
```

## Configuration Differences

### Old `config.yaml` structure:
```yaml
monitoring:
  poll_interval: 5

alerts:
  email_enabled: true
  smtp_server: smtp.gmail.com
```

### New `config.yaml` structure:
```yaml
monitoring:
  poll_interval: 3
  rippled_mode: docker  # or native
  container_name: rippledvalidator  # if docker mode

prometheus:
  enabled: true
  port: 9094

alerts:
  file_enabled: true
  email_enabled: false  # Use Grafana alerts instead
```

**Migration tip:** Email alerts are now handled by Grafana's built-in alerting system. Configure them in Grafana UI: Settings → Alerting → Contact Points.

## Why Migrate?

### Benefits of the New Version

1. **Better Performance**
   - Prometheus handles metrics 10x faster than SQLite
   - 30-day retention with efficient storage
   - Real-time queries with no database locks

2. **Easier Management**
   - One command to install: `./install.sh`
   - One command to uninstall: `./uninstall.sh`
   - All components isolated in Docker containers

3. **Auto-Detection**
   - Finds rippled automatically (Docker or Native)
   - Detects available ports
   - Smart defaults based on your setup

4. **Industry Standard Stack**
   - Grafana 11.2.0 (latest stable)
   - Prometheus v2.54.1 (production-grade)
   - Docker Compose (standard orchestration)

5. **Better Monitoring**
   - 50+ metrics collected
   - Custom dashboards for validators
   - Built-in alerting and notifications

## Getting Help

If you encounter issues during migration:

1. **Check the installation guide:** [docs/INSTALL.md](docs/INSTALL.md)
2. **Review troubleshooting:** [README.md#troubleshooting](README.md#troubleshooting)
3. **Open an issue:** https://github.com/realgrapedrop/xrpl-validator-dashboard/issues

Include in your issue:
- Operating system version (`lsb_release -a`)
- Docker version (`docker --version`)
- Error messages or logs
- Steps you've already tried

## Summary

The migration is straightforward:
1. ✅ Uninstall old version
2. ✅ Remove old directory
3. ✅ Clone new version
4. ✅ Run `./install.sh`
5. ✅ Access Grafana and verify metrics

Your rippled installation is never touched during this process. The dashboard only monitors - it never modifies your validator.

**Welcome to the GA release!** 🚀
