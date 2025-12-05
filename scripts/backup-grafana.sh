#!/bin/bash
# Backup Grafana database and configuration
# Run this before any major changes to Grafana

set -e

BACKUP_DIR="data/grafana-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="grafana-backup-${TIMESTAMP}"

echo "=== Grafana Backup Script ==="
echo "Backup directory: $BACKUP_DIR"
echo "Timestamp: $TIMESTAMP"
echo ""

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Check if Grafana container is running
if ! docker ps | grep -q xrpl-monitor-grafana; then
    echo "ERROR: Grafana container is not running"
    exit 1
fi

echo "Step 1: Creating backup directory..."
mkdir -p "$BACKUP_DIR/$BACKUP_NAME"

echo "Step 2: Backing up Grafana Docker volume..."
# Use docker cp to copy from the running container
docker cp xrpl-monitor-grafana:/var/lib/grafana "$BACKUP_DIR/$BACKUP_NAME/grafana-data"

echo "Step 3: Backing up provisioning configuration..."
cp -r config/grafana/provisioning "$BACKUP_DIR/$BACKUP_NAME/"

echo "Step 4: Backing up dashboard files..."
cp -r dashboards "$BACKUP_DIR/$BACKUP_NAME/"

echo "Step 5: Exporting Grafana folders via API..."
mkdir -p "$BACKUP_DIR/$BACKUP_NAME/api-exports"
curl -s -u admin:admin1 http://localhost:3003/api/folders > "$BACKUP_DIR/$BACKUP_NAME/api-exports/folders.json" 2>/dev/null || echo "Warning: Could not export folders"

echo "Step 6: Exporting Grafana dashboards via API..."
curl -s -u admin:admin1 'http://localhost:3003/api/search?type=dash-db' > "$BACKUP_DIR/$BACKUP_NAME/api-exports/dashboards-list.json" 2>/dev/null || echo "Warning: Could not export dashboards list"

echo "Step 7: Exporting alert rules via API..."
curl -s -u admin:admin1 http://localhost:3003/api/v1/provisioning/alert-rules > "$BACKUP_DIR/$BACKUP_NAME/api-exports/alert-rules.json" 2>/dev/null || echo "Warning: Could not export alert rules"

echo "Step 8: Creating backup metadata..."
cat > "$BACKUP_DIR/$BACKUP_NAME/backup-info.txt" <<EOF
Grafana Backup
==============
Timestamp: $TIMESTAMP
Date: $(date)
Grafana Version: $(docker exec xrpl-monitor-grafana grafana-cli --version 2>/dev/null || echo "unknown")
Backup Contents:
- grafana-data/ (Docker volume copy)
- provisioning/ (provisioning configs)
- dashboards/ (dashboard JSON files)
- api-exports/ (API exports of folders, dashboards, alerts)
EOF

echo "Step 9: Creating compressed archive..."
cd "$BACKUP_DIR"
tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
BACKUP_SIZE=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)
echo "Compressed backup size: $BACKUP_SIZE"

echo "Step 10: Cleaning up temporary directory..."
rm -rf "$BACKUP_NAME"

echo ""
echo "✓ Backup completed successfully!"
echo ""
echo "Backup location: $BACKUP_DIR/${BACKUP_NAME}.tar.gz"
echo "Backup size: $BACKUP_SIZE"
echo ""
echo "To restore this backup:"
echo "  ./scripts/restore-grafana.sh ${BACKUP_NAME}.tar.gz"
echo ""

# Keep only last 5 backups
echo "Cleaning up old backups (keeping last 5)..."
ls -t "$BACKUP_DIR"/grafana-backup-*.tar.gz | tail -n +6 | xargs -r rm -f
echo "Done."
