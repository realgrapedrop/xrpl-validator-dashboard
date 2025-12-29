# **__BACKUP & RESTORE GUIDE__**

*How to backup and restore the Grafana database and configuration.*

---

# Table of Contents

- [Why Backups Are Critical](#why-backups-are-critical)
- [Quick Reference](#quick-reference)
- [Backup Process](#backup-process)
- [Restore Process](#restore-process)
- [Backup Storage](#backup-storage)
- [Manual Backup (Without Script)](#manual-backup-without-script)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [Recovery Scenarios](#recovery-scenarios)
- [Summary](#summary)

---

# Why Backups Are Critical

Grafana stores important data that is NOT in the provisioned files:
- Alert folder UIDs and organization
- Dashboard variable selections
- User preferences and settings
- Dashboard versions and history
- Notification history

**ALWAYS backup before:**
- Clearing Grafana database
- Major configuration changes
- Upgrading Grafana version
- Testing risky operations

# Quick Reference

```bash
# Create a backup (do this NOW before any risky operation)
./scripts/backup-grafana.sh

# List available backups
ls -lh data/grafana-backups/

# Restore a backup (will prompt for confirmation)
./scripts/restore-grafana.sh data/grafana-backups/grafana-backup-TIMESTAMP.tar.gz
```

# Backup Process

**In This Section:**
- [What Gets Backed Up](#what-gets-backed-up)
- [Creating a Backup](#creating-a-backup)
- [Automated Backup Before Risky Operations](#automated-backup-before-risky-operations)

---

### What Gets Backed Up

The backup script creates a complete snapshot including:
1. **Grafana Docker volume** (`/var/lib/grafana`) - SQLite database, plugins, etc.
2. **Provisioning configuration** (`config/grafana/provisioning/`)
3. **Dashboard JSON files** (`dashboards/`)
4. **API exports** (folders, dashboards list, alert rules)

### Creating a Backup

```bash
./scripts/backup-grafana.sh
```

The script will:
- Create timestamped backup in `data/grafana-backups/`
- Export all data via Docker volume copy
- Export current state via Grafana API
- Compress everything into `.tar.gz` archive
- Keep only the last 5 backups (auto-cleanup)

**Backup location:**
```
data/grafana-backups/grafana-backup-YYYYMMDD-HHMMSS.tar.gz
```

**Typical backup size:** ~20 MB

### Automated Backup Before Risky Operations

**Example workflow:**
```bash
# 1. ALWAYS backup first
./scripts/backup-grafana.sh

# 2. Perform risky operation (example: clear database)
docker compose down grafana
docker volume rm xrpl-monitor-grafana-data
docker compose up -d grafana

# 3. If something goes wrong, restore
./scripts/restore-grafana.sh data/grafana-backups/grafana-backup-LATEST.tar.gz
```

# Restore Process

**In This Section:**
- [Before Restoring](#before-restoring)
- [Restoring a Backup](#restoring-a-backup)
- [Verify Restoration](#verify-restoration)

---

### Before Restoring

⚠️ **WARNING:** Restore will:
- Stop Grafana container
- **REPLACE ALL current Grafana data** with backup
- Restart Grafana container

The restore script will:
1. Create a backup of current state (safety measure)
2. Prompt for confirmation
3. Only proceed if you type "yes"

### Restoring a Backup

```bash
# List available backups
ls -lh data/grafana-backups/

# Restore specific backup
./scripts/restore-grafana.sh data/grafana-backups/grafana-backup-20251112-191911.tar.gz
```

**The script will:**
1. Create a safety backup of current state
2. Stop Grafana
3. Extract backup archive
4. Replace Docker volume data
5. Restore provisioning and dashboard files
6. Restart Grafana
7. Wait for Grafana to be ready

**After restore:**
- Grafana UI: http://localhost:3000
- Login: admin / admin1 (or whatever was set in backup)
- All dashboards, alerts, and folders restored

### Verify Restoration

After restore, check:
1. Dashboard loads: http://localhost:3000/d/xrpl-validator-monitor-full
2. Alert folders visible: Dashboards → Folders
3. Alert rules working: Alerting → Alert rules
4. Variables populated: Dashboard Settings → Variables

# Backup Storage

**In This Section:**
- [Local Backups](#local-backups)
- [Off-Site Backups](#off-site-backups)

---

### Local Backups

Backups are stored in `data/grafana-backups/`:
- **Automatic cleanup:** Only last 5 backups kept
- **Not in Git:** Directory is gitignored (backups are large)
- **Manual cleanup:** Delete old backups manually if needed

```bash
# Remove backups older than 7 days
find data/grafana-backups/ -name "*.tar.gz" -mtime +7 -delete
```

### Off-Site Backups

**Important:** Local backups are NOT safe from hardware failure. Copy critical backups off-site:

```bash
# Copy to external drive
cp data/grafana-backups/grafana-backup-TIMESTAMP.tar.gz /mnt/backup-drive/

# Copy to remote server via scp
scp data/grafana-backups/grafana-backup-TIMESTAMP.tar.gz user@backup-server:/backups/

# Copy to cloud storage (example: AWS S3)
aws s3 cp data/grafana-backups/grafana-backup-TIMESTAMP.tar.gz s3://my-backups/grafana/
```

# Manual Backup (Without Script)

If the script isn't available, manual backup:

```bash
# 1. Create backup directory
mkdir -p manual-backup-$(date +%Y%m%d)

# 2. Backup Docker volume
docker cp xrpl-monitor-grafana:/var/lib/grafana manual-backup-$(date +%Y%m%d)/

# 3. Backup provisioning
cp -r config/grafana/provisioning manual-backup-$(date +%Y%m%d)/

# 4. Backup dashboards
cp -r dashboards manual-backup-$(date +%Y%m%d)/

# 5. Compress
tar -czf manual-backup-$(date +%Y%m%d).tar.gz manual-backup-$(date +%Y%m%d)/
```

# Troubleshooting

**In This Section:**
- [Backup Script Fails](#backup-script-fails)
- [Restore Script Fails](#restore-script-fails)

---

### Backup Script Fails

**Error: "Grafana container is not running"**
- Start Grafana: `docker compose up -d grafana`
- Wait for it to be ready (10-15 seconds)
- Retry backup

**Error: "Permission denied"**
- Make script executable: `chmod +x scripts/backup-grafana.sh`
- Retry

**Error: "API exports failed"**
- This is non-critical - volume backup still works
- Check Grafana password in script (default: admin1)

### Restore Script Fails

**Error: "Backup file not found"**
- Check file path is correct
- Use absolute path or relative from project root

**Error: "Grafana won't start after restore"**
- Check Docker logs: `docker compose logs grafana`
- Volume might be corrupted - restore from earlier backup
- Last resort: Clear volume and start fresh

# Best Practices

1. ✅ **Backup before ANY risky operation**
2. ✅ **Test restore process periodically** (verify backups work)
3. ✅ **Keep backups off-site** (external drive, remote server, cloud)
4. ✅ **Document what changed** (commit message, changelog)
5. ✅ **Automate backups** (cron job, CI/CD pipeline)

### Automated Daily Backups (Optional)

Add to crontab for daily backups at 3 AM:

```bash
# Edit crontab
crontab -e

# Add this line (update path to your installation directory):
0 3 * * * cd /home/user/xrpl-validator-dashboard && ./scripts/backup-grafana.sh >> logs/backup.log 2>&1
```

# Recovery Scenarios

**In This Section:**
- [Scenario 1: Accidentally Deleted Folders](#scenario-1-accidentally-deleted-folders)
- [Scenario 2: Dashboard Configuration Lost](#scenario-2-dashboard-configuration-lost)
- [Scenario 3: Database Corrupted](#scenario-3-database-corrupted)

---

### Scenario 1: Accidentally Deleted Folders

**Problem:** Alert folders showing UIDs instead of names

**Solution:**
```bash
# Restore from most recent backup
./scripts/restore-grafana.sh data/grafana-backups/grafana-backup-LATEST.tar.gz
```

### Scenario 2: Dashboard Configuration Lost

**Problem:** Dashboard variables broken or missing

**Solution:**
```bash
# Option 1: Restore from backup
./scripts/restore-grafana.sh data/grafana-backups/grafana-backup-TIMESTAMP.tar.gz

# Option 2: Reprovision from Git
git checkout config/grafana/provisioning/dashboards/xrpl-validator-main.json
docker compose restart grafana
```

### Scenario 3: Database Corrupted

**Problem:** Grafana won't start, SQLite errors in logs

**Solution:**
```bash
# 1. Try restore from backup
./scripts/restore-grafana.sh data/grafana-backups/grafana-backup-LATEST.tar.gz

# 2. If that fails, start fresh
docker compose down grafana
docker volume rm xrpl-monitor-grafana-data
docker compose up -d grafana
./scripts/setup-grafana-folders.sh
```

---

# Summary

**Golden Rule:** ALWAYS backup before destructive operations.

**Quick Commands:**
- Backup: `./scripts/backup-grafana.sh`
- Restore: `./scripts/restore-grafana.sh BACKUP_FILE`
- List: `ls -lh data/grafana-backups/`

**What's Protected:**
- ✅ Grafana database (folders, users, settings)
- ✅ Dashboards
- ✅ Alert rules
- ✅ Provisioning configs

**What's NOT in backup:**
- ❌ VictoriaMetrics data (metrics database)
- ❌ Docker container configs (in docker-compose.yml)
- ❌ Application code (in Git)

---

**Last Updated:** 2025-11-12
