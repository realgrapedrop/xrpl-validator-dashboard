#!/bin/bash
#
# Dashboard Performance Monitoring Script
# Monitors Grafana and metrics collection for 8 hours with 15-minute reports
#
# Usage: ./monitor_dashboard_performance.sh [duration_hours] [interval_minutes]
# Example: ./monitor_dashboard_performance.sh 8 15

set -e

# Configuration
DURATION_HOURS=${1:-8}
INTERVAL_MINUTES=${2:-15}
GRAFANA_URL="http://localhost:3003"
VICTORIA_URL="http://localhost:8428"
REPORT_DIR="./monitoring-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="${REPORT_DIR}/dashboard-performance-${TIMESTAMP}.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Create report directory
mkdir -p "$REPORT_DIR"

# Print header
echo "════════════════════════════════════════════════════════════"
echo "  Dashboard Performance Monitoring"
echo "  Duration: ${DURATION_HOURS} hours | Interval: ${INTERVAL_MINUTES} minutes"
echo "  Started: $(date)"
echo "  Report: ${REPORT_FILE}"
echo "════════════════════════════════════════════════════════════"
echo ""

# Initialize report file
cat > "$REPORT_FILE" << EOF
Dashboard Performance Monitoring Report
Started: $(date)
Duration: ${DURATION_HOURS} hours
Interval: ${INTERVAL_MINUTES} minutes

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

# Calculate end time
END_TIME=$(($(date +%s) + DURATION_HOURS * 3600))
INTERVAL_SECONDS=$((INTERVAL_MINUTES * 60))
ITERATION=0

# Monitoring loop
while [ $(date +%s) -lt $END_TIME ]; do
    ITERATION=$((ITERATION + 1))
    CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S")

    echo -e "${BLUE}[$(date +%H:%M:%S)] Report #${ITERATION}${NC}"

    # Start report section
    cat >> "$REPORT_FILE" << EOF

━━━ Report #${ITERATION} - ${CURRENT_TIME} ━━━

EOF

    # 1. Container Health
    echo -n "  Checking containers... "
    CONTAINER_STATUS=$(docker ps --filter name=xrpl-monitor --format "{{.Names}}|{{.Status}}" 2>/dev/null || echo "ERROR")
    if [ "$CONTAINER_STATUS" != "ERROR" ]; then
        CONTAINER_COUNT=$(echo "$CONTAINER_STATUS" | wc -l)
        UNHEALTHY=$(echo "$CONTAINER_STATUS" | grep -c "unhealthy" || true)
        echo -e "${GREEN}✓${NC} ${CONTAINER_COUNT} running"

        cat >> "$REPORT_FILE" << EOF
Containers:
$(echo "$CONTAINER_STATUS" | sed 's/^/  /')

EOF

        if [ $UNHEALTHY -gt 0 ]; then
            echo -e "  ${RED}⚠ ${UNHEALTHY} unhealthy containers${NC}"
        fi
    else
        echo -e "${RED}✗${NC} Failed"
    fi

    # 2. Grafana Health
    echo -n "  Checking Grafana... "
    GRAFANA_HEALTH=$(curl -s "${GRAFANA_URL}/api/health" 2>/dev/null || echo '{"status":"error"}')
    GRAFANA_STATUS=$(echo "$GRAFANA_HEALTH" | jq -r '.database' 2>/dev/null || echo "error")
    if [ "$GRAFANA_STATUS" = "ok" ]; then
        echo -e "${GREEN}✓${NC} Healthy"
        cat >> "$REPORT_FILE" << EOF
Grafana:
  Status: Healthy
  Database: OK

EOF
    else
        echo -e "${RED}✗${NC} Unhealthy"
        cat >> "$REPORT_FILE" << EOF
Grafana:
  Status: Unhealthy
  Response: ${GRAFANA_HEALTH}

EOF
    fi

    # 3. VictoriaMetrics Health
    echo -n "  Checking VictoriaMetrics... "
    VM_HEALTH=$(curl -s "${VICTORIA_URL}/health" 2>/dev/null || echo "error")
    if [ "$VM_HEALTH" = "OK" ]; then
        echo -e "${GREEN}✓${NC} Healthy"

        # Get metrics stats
        TOTAL_SERIES=$(curl -s "${VICTORIA_URL}/api/v1/status/tsdb" 2>/dev/null | jq -r '.data.totalSeries' 2>/dev/null || echo "N/A")

        cat >> "$REPORT_FILE" << EOF
VictoriaMetrics:
  Status: Healthy
  Total Series: ${TOTAL_SERIES}

EOF
    else
        echo -e "${RED}✗${NC} Unhealthy"
        cat >> "$REPORT_FILE" << EOF
VictoriaMetrics:
  Status: Unhealthy

EOF
    fi

    # 4. Key Metrics Check
    echo -n "  Checking metrics... "

    # Check if key metrics exist
    METRICS_TO_CHECK=(
        "up"
        "xrpl_websocket_healthy"
        "xrpl_ledger_age_seconds"
        "xrpl_peer_count"
        "node_cpu_seconds_total"
    )

    METRICS_OK=0
    METRICS_MISSING=0

    cat >> "$REPORT_FILE" << EOF
Key Metrics:
EOF

    for metric in "${METRICS_TO_CHECK[@]}"; do
        RESULT=$(curl -s "${VICTORIA_URL}/api/v1/query?query=${metric}" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")
        if [ "$RESULT" -gt 0 ]; then
            METRICS_OK=$((METRICS_OK + 1))
            VALUE=$(curl -s "${VICTORIA_URL}/api/v1/query?query=${metric}" 2>/dev/null | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A")
            echo "  ✓ ${metric}: ${VALUE}" >> "$REPORT_FILE"
        else
            METRICS_MISSING=$((METRICS_MISSING + 1))
            echo "  ✗ ${metric}: MISSING" >> "$REPORT_FILE"
        fi
    done

    echo >> "$REPORT_FILE"

    if [ $METRICS_MISSING -eq 0 ]; then
        echo -e "${GREEN}✓${NC} All ${METRICS_OK} metrics present"
    else
        echo -e "${YELLOW}⚠${NC} ${METRICS_MISSING} missing"
    fi

    # 5. Data Collection Rate
    echo -n "  Checking collection rate... "

    # Get collector logs to check collection frequency
    COLLECTOR_LOG=$(docker logs xrpl-monitor-collector --tail 10 2>&1 | grep "HTTP/1.1" | tail -3 || echo "")
    if [ -n "$COLLECTOR_LOG" ]; then
        RECENT_COLLECTIONS=$(echo "$COLLECTOR_LOG" | wc -l)
        echo -e "${GREEN}✓${NC} ${RECENT_COLLECTIONS} recent collections"

        cat >> "$REPORT_FILE" << EOF
Collector Activity:
$(echo "$COLLECTOR_LOG" | sed 's/^/  /')

EOF
    else
        echo -e "${YELLOW}⚠${NC} No recent activity"
    fi

    # 6. Resource Usage
    echo -n "  Checking resources... "

    CONTAINER_STATS=$(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | grep xrpl-monitor || echo "")
    if [ -n "$CONTAINER_STATS" ]; then
        echo -e "${GREEN}✓${NC} Captured"

        cat >> "$REPORT_FILE" << EOF
Resource Usage:
$(echo "$CONTAINER_STATS" | sed 's/^/  /')

EOF
    else
        echo -e "${YELLOW}⚠${NC} Not available"
    fi

    # Summary
    echo ""
    echo -e "${BLUE}  Next check in ${INTERVAL_MINUTES} minutes...${NC}"
    echo ""

    cat >> "$REPORT_FILE" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

    # Wait for next interval (unless this is the last iteration)
    REMAINING_TIME=$((END_TIME - $(date +%s)))
    if [ $REMAINING_TIME -gt $INTERVAL_SECONDS ]; then
        sleep $INTERVAL_SECONDS
    elif [ $REMAINING_TIME -gt 0 ]; then
        sleep $REMAINING_TIME
    else
        break
    fi
done

# Final summary
echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}Monitoring Complete!${NC}"
echo "  Total Reports: ${ITERATION}"
echo "  Duration: ${DURATION_HOURS} hours"
echo "  Report File: ${REPORT_FILE}"
echo "════════════════════════════════════════════════════════════"
echo ""

cat >> "$REPORT_FILE" << EOF

════════════════════════════════════════════════════════════

Monitoring Complete
Total Reports: ${ITERATION}
Ended: $(date)

════════════════════════════════════════════════════════════
EOF

echo "View report: cat ${REPORT_FILE}"
echo "Or: tail -f ${REPORT_FILE} (in another terminal during monitoring)"
