#!/bin/bash
# Setup Grafana alert folders after fresh installation
# This script creates the alert folders with proper names via Grafana API

set -e

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3003}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin}"

echo "Setting up Grafana alert folders..."
echo "Grafana URL: $GRAFANA_URL"

# Wait for Grafana to be ready
echo "Waiting for Grafana to be ready..."
for i in {1..30}; do
    if curl -s -f "$GRAFANA_URL/api/health" > /dev/null 2>&1; then
        echo "Grafana is ready"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 2
done

# The alert folders are created automatically by provisioning with UIDs
# We just need to rename them via API

# Function to update folder title
update_folder() {
    local uid=$1
    local title=$2

    echo "Updating folder $uid to '$title'..."

    # Get current folder
    folder_json=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
        "$GRAFANA_URL/api/folders/$uid")

    if echo "$folder_json" | jq -e '.uid' > /dev/null 2>&1; then
        # Update the folder title
        curl -s -X PUT -u "$GRAFANA_USER:$GRAFANA_PASS" \
            -H "Content-Type: application/json" \
            -d "{\"title\": \"$title\", \"overwrite\": true}" \
            "$GRAFANA_URL/api/folders/$uid" > /dev/null

        echo "✓ Updated folder '$title'"
    else
        echo "✗ Folder $uid not found (it will be created by alert provisioning)"
    fi
}

# Give alert provisioning time to create folders
echo "Waiting for alert provisioning to create folders..."
sleep 5

# Update the three alert folders (using actual UIDs from fresh install)
update_folder "bf3y2wk5l0h6ob" "Network Monitoring"
update_folder "bf3y2wkmsbawwa" "Critical Monitoring"
update_folder "bf3y2wkp57uo0f" "Performance Monitoring"

echo ""
echo "✓ Grafana alert folders configured successfully"
echo ""
echo "Alert folders should now appear with proper names in:"
echo "  - Dashboards → Folders (for organization)"
echo "  - Alerting → Alert rules (grouped by folder)"
