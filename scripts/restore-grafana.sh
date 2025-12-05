#!/bin/bash
# Restore Grafana database and configuration from backup
# ALWAYS make a backup before restoring!

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <backup-file.tar.gz>"
    echo ""
    echo "Available backups:"
    ls -lh data/grafana-backups/*.tar.gz 2>/dev/null || echo "  No backups found"
    exit 1
fi

BACKUP_FILE="$1"
BACKUP_DIR="data/grafana-backups"
TEMP_RESTORE_DIR="/tmp/grafana-restore-$$"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "ERROR: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "=== Grafana Restore Script ==="
echo "Backup file: $BACKUP_FILE"
echo ""
echo "WARNING: This will:"
echo "  1. Stop Grafana container"
echo "  2. Replace ALL Grafana data with backup"
echo "  3. Restart Grafana container"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

echo ""
echo "Step 1: Creating current backup before restore..."
./scripts/backup-grafana.sh

echo ""
echo "Step 2: Stopping Grafana container..."
docker compose stop grafana

echo "Step 3: Extracting backup archive..."
mkdir -p "$TEMP_RESTORE_DIR"
tar -xzf "$BACKUP_FILE" -C "$TEMP_RESTORE_DIR"

# Find the extracted directory
EXTRACTED_DIR=$(find "$TEMP_RESTORE_DIR" -maxdepth 1 -type d -name "grafana-backup-*" | head -1)

if [ -z "$EXTRACTED_DIR" ]; then
    echo "ERROR: Could not find extracted backup directory"
    rm -rf "$TEMP_RESTORE_DIR"
    exit 1
fi

echo "Step 4: Restoring Grafana data to Docker volume..."
# Remove old data and copy backup
docker run --rm -v xrpl-monitor-grafana-data:/data alpine sh -c "rm -rf /data/*"
docker cp "$EXTRACTED_DIR/grafana-data/." xrpl-monitor-grafana:/var/lib/grafana/

echo "Step 5: Restoring provisioning configuration..."
cp -r "$EXTRACTED_DIR/provisioning/"* config/grafana/provisioning/

echo "Step 6: Restoring dashboard files..."
cp -r "$EXTRACTED_DIR/dashboards/"* dashboards/

echo "Step 7: Cleaning up temporary files..."
rm -rf "$TEMP_RESTORE_DIR"

echo "Step 8: Starting Grafana container..."
docker compose start grafana

echo ""
echo "Waiting for Grafana to start..."
sleep 5

for i in {1..30}; do
    if curl -s -f http://localhost:3003/api/health > /dev/null 2>&1; then
        echo "✓ Grafana is ready"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 2
done

echo ""
echo "✓ Restore completed successfully!"
echo ""
echo "Grafana UI: http://localhost:3003"
echo "Login: admin / admin1"
echo ""
