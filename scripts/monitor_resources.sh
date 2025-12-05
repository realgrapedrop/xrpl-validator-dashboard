#!/bin/bash
#
# Resource Monitoring Script for XRPL Monitor v3.0
#
# Collects RAM, CPU, and disk usage metrics for all containers
# Appends timestamped results to logs/resource_monitoring.log
#
# Usage:
#   ./scripts/monitor_resources.sh
#
# To run automatically every hour:
#   crontab -e
#   0 * * * * cd /path/to/xrpl-validator-dashboard && ./scripts/monitor_resources.sh
#

set -e

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/resource_monitoring.log"

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Get timestamp
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Separator for readability
echo "" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"
echo "Resource Monitoring Report" >> "$LOG_FILE"
echo "Timestamp: $TIMESTAMP" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Check if containers are running
if ! docker ps | grep -q xrpl-monitor; then
    echo "WARNING: No XRPL Monitor containers found running" >> "$LOG_FILE"
    echo "Run 'docker compose ps' to check container status" >> "$LOG_FILE"
    exit 1
fi

# Get container stats
echo "=== Container Resource Usage ===" >> "$LOG_FILE"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | grep -E "NAME|xrpl-monitor" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Calculate total RAM usage (only xrpl-monitor containers)
echo "=== Total RAM Usage ===" >> "$LOG_FILE"
docker stats --no-stream --format "{{.Name}} {{.MemUsage}}" | grep xrpl-monitor | awk '{print $2}' > /tmp/ram_usage.txt
TOTAL_RAM=$(awk -F' / ' '{
    mem = $1
    if (mem ~ /GiB/) {
        gsub(/GiB/, "", mem)
        sum += mem * 1024
    } else {
        gsub(/MiB/, "", mem)
        sum += mem
    }
}
END {printf "%.2f", sum}' /tmp/ram_usage.txt)
echo "Total RAM: ${TOTAL_RAM} MiB" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Get disk usage for volumes
echo "=== Volume Disk Usage ===" >> "$LOG_FILE"
docker system df -v | grep -A 10 "Local Volumes" | grep xrpl-monitor >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Calculate total disk usage (only xrpl-monitor volumes)
TOTAL_DISK=$(docker system df -v | grep "xrpl-monitor-" | awk '{
    size = $(NF)
    if (size ~ /MB$/) {
        gsub(/MB/, "", size)
        sum += size
    } else if (size ~ /GB$/) {
        gsub(/GB/, "", size)
        sum += size * 1024
    } else if (size ~ /KB$/) {
        gsub(/KB/, "", size)
        sum += size / 1024
    } else if (size ~ /B$/ && size !~ /[MG]B$/) {
        gsub(/B/, "", size)
        sum += size / 1024 / 1024
    }
}
END {printf "%.2f", sum}')

echo "Total Disk: ${TOTAL_DISK} MB" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Get uptime of containers
echo "=== Container Uptime ===" >> "$LOG_FILE"
docker ps --filter "name=xrpl-monitor" --format "table {{.Names}}\t{{.Status}}" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Summary for quick reference
echo "=== Summary ===" >> "$LOG_FILE"
echo "Total RAM: ${TOTAL_RAM} MiB" >> "$LOG_FILE"
echo "Total Disk: ${TOTAL_DISK} MB" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Also print to stdout for immediate viewing
echo ""
echo "Resource monitoring complete!"
echo "Timestamp: $TIMESTAMP"
echo "Total RAM: ${TOTAL_RAM} MiB"
echo "Total Disk: ${TOTAL_DISK} MB"
echo ""
echo "Full report saved to: $LOG_FILE"
echo ""
