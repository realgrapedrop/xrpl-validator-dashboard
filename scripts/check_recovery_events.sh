#!/bin/bash
#
# Check for Recovery and Instability Events
# Analyzes logs and metrics to detect websocket reconnections, HTTP failures, and recovery attempts
#
# Usage: ./check_recovery_events.sh [container_name] [hours_back]
# Example: ./check_recovery_events.sh xrpl-monitor-collector 24

set -e

CONTAINER=${1:-xrpl-monitor-collector}
HOURS=${2:-24}
VICTORIA_URL="http://localhost:8428"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo "════════════════════════════════════════════════════════════"
echo "  Recovery & Instability Event Analysis"
echo "  Container: ${CONTAINER}"
echo "  Time Period: Last ${HOURS} hours"
echo "════════════════════════════════════════════════════════════"
echo ""

# Calculate time range
SINCE="${HOURS}h"

# Check if container exists
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo -e "${RED}✗ Container ${CONTAINER} not found${NC}"
    exit 1
fi

echo -e "${CYAN}━━━ Container Status ━━━${NC}"
echo ""
CONTAINER_STATUS=$(docker ps --filter "name=${CONTAINER}" --format "{{.Status}}")
CONTAINER_HEALTH=$(docker inspect ${CONTAINER} --format='{{.State.Health.Status}}' 2>/dev/null || echo "N/A")
echo "Status: ${CONTAINER_STATUS}"
echo "Health: ${CONTAINER_HEALTH}"
echo ""

# 1. WebSocket Reconnection Events
echo -e "${CYAN}━━━ WebSocket Reconnection Events ━━━${NC}"
echo ""

RECONNECT_LOGS=$(docker logs ${CONTAINER} --since ${SINCE} 2>&1 | grep -i "reconnect\|disconnected" || echo "")
if [ -n "$RECONNECT_LOGS" ]; then
    RECONNECT_COUNT=$(echo "$RECONNECT_LOGS" | grep -c "Reconnection attempt" || echo "0")
else
    RECONNECT_COUNT=0
fi

if [ "$RECONNECT_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Found ${RECONNECT_COUNT} reconnection attempts${NC}"
    echo ""
    echo "Recent reconnection events:"
    echo "$RECONNECT_LOGS" | tail -10 | sed 's/^/  /'
    echo ""
else
    echo -e "${GREEN}✓ No reconnection attempts detected${NC}"
    echo ""
fi

# Check current reconnect attempts metric
RECONNECT_METRIC=$(curl -s "${VICTORIA_URL}/api/v1/query?query=xrpl_websocket_reconnect_attempts" 2>/dev/null | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
echo "Current reconnect attempts counter: ${RECONNECT_METRIC}"
echo ""

# 2. Heartbeat Failures
echo -e "${CYAN}━━━ Heartbeat Failures ━━━${NC}"
echo ""

HEARTBEAT_LOGS=$(docker logs ${CONTAINER} --since ${SINCE} 2>&1 | grep -i "heartbeat.*fail\|heartbeat timeout" || echo "")
if [ -n "$HEARTBEAT_LOGS" ]; then
    HEARTBEAT_COUNT=$(echo "$HEARTBEAT_LOGS" | wc -l)
else
    HEARTBEAT_COUNT=0
fi

if [ "$HEARTBEAT_COUNT" -gt 0 ] && [ -n "$HEARTBEAT_LOGS" ]; then
    echo -e "${YELLOW}⚠ Found ${HEARTBEAT_COUNT} heartbeat failure events${NC}"
    echo ""
    echo "Recent heartbeat failures:"
    echo "$HEARTBEAT_LOGS" | tail -5 | sed 's/^/  /'
    echo ""
else
    echo -e "${GREEN}✓ No heartbeat failures detected${NC}"
    echo ""
fi

# Check heartbeat failures metric
HEARTBEAT_METRIC=$(curl -s "${VICTORIA_URL}/api/v1/query?query=xrpl_websocket_heartbeat_failures" 2>/dev/null | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
echo "Current heartbeat failures: ${HEARTBEAT_METRIC}"
echo ""

# 3. HTTP Polling Failures
echo -e "${CYAN}━━━ HTTP Polling Failures ━━━${NC}"
echo ""

HTTP_ERROR_LOGS=$(docker logs ${CONTAINER} --since ${SINCE} 2>&1 | grep -E "HTTP.*error|HTTP.*fail|HTTP.*timeout|ConnectionError|TimeoutError" || echo "")
if [ -n "$HTTP_ERROR_LOGS" ]; then
    HTTP_ERROR_COUNT=$(echo "$HTTP_ERROR_LOGS" | wc -l)
else
    HTTP_ERROR_COUNT=0
fi

if [ "$HTTP_ERROR_COUNT" -gt 0 ] && [ -n "$HTTP_ERROR_LOGS" ]; then
    echo -e "${YELLOW}⚠ Found ${HTTP_ERROR_COUNT} HTTP error events${NC}"
    echo ""
    echo "Recent HTTP errors:"
    echo "$HTTP_ERROR_LOGS" | tail -10 | sed 's/^/  /'
    echo ""
else
    echo -e "${GREEN}✓ No HTTP errors detected${NC}"
    echo ""
fi

# 4. Validation Recovery Events
echo -e "${CYAN}━━━ Validation Counter Recovery ━━━${NC}"
echo ""

RECOVERY_LOGS=$(docker logs ${CONTAINER} --since ${SINCE} 2>&1 | grep -i "recover.*victoria\|recovery.*baseline\|recovery complete" || echo "")
if [ -n "$RECOVERY_LOGS" ]; then
    RECOVERY_COUNT=$(echo "$RECOVERY_LOGS" | wc -l)
else
    RECOVERY_COUNT=0
fi

if [ "$RECOVERY_COUNT" -gt 0 ] && [ -n "$RECOVERY_LOGS" ]; then
    echo -e "${YELLOW}⚠ Found ${RECOVERY_COUNT} recovery attempts${NC}"
    echo ""
    echo "Recovery events:"
    echo "$RECOVERY_LOGS" | sed 's/^/  /'
    echo ""
else
    echo -e "${GREEN}✓ No recovery operations detected${NC}"
    echo ""
fi

# 5. WebSocket Health Status
echo -e "${CYAN}━━━ WebSocket Health Metrics ━━━${NC}"
echo ""

WS_HEALTHY=$(curl -s "${VICTORIA_URL}/api/v1/query?query=xrpl_websocket_healthy" 2>/dev/null | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
WS_CONNECTED=$(curl -s "${VICTORIA_URL}/api/v1/query?query=xrpl_websocket_connected" 2>/dev/null | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
WS_LAST_MSG_AGE=$(curl -s "${VICTORIA_URL}/api/v1/query?query=xrpl_websocket_last_message_age_seconds" 2>/dev/null | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A")

echo "Connected: ${WS_CONNECTED} (1=yes, 0=no)"
echo "Healthy: ${WS_HEALTHY} (1=yes, 0=no)"
echo "Last message age: ${WS_LAST_MSG_AGE} seconds"
echo ""

if [ "$WS_HEALTHY" = "1" ] && [ "$WS_CONNECTED" = "1" ]; then
    echo -e "${GREEN}✓ WebSocket currently healthy and connected${NC}"
else
    echo -e "${RED}✗ WebSocket currently unhealthy or disconnected${NC}"
fi
echo ""

# 6. Error Summary
echo -e "${CYAN}━━━ Error Summary (Last ${HOURS} hours) ━━━${NC}"
echo ""

ALL_ERRORS=$(docker logs ${CONTAINER} --since ${SINCE} 2>&1 | grep -i "error\|exception\|failed\|critical" || echo "")
ERROR_TYPES=$(echo "$ALL_ERRORS" | grep -oE "error|ERROR|Error|Exception|CRITICAL" | sort | uniq -c | sort -rn || echo "")

if [ -n "$ERROR_TYPES" ]; then
    echo "Error type breakdown:"
    echo "$ERROR_TYPES" | sed 's/^/  /'
    echo ""

    TOTAL_ERRORS=$(echo "$ALL_ERRORS" | wc -l)
    echo "Total error messages: ${TOTAL_ERRORS}"
    echo ""

    if [ $TOTAL_ERRORS -gt 0 ]; then
        echo "Most recent errors (last 5):"
        echo "$ALL_ERRORS" | tail -5 | sed 's/^/  /'
    fi
else
    echo -e "${GREEN}✓ No errors found in logs${NC}"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${BOLD}Summary:${NC}"
echo "  Reconnections: ${RECONNECT_COUNT}"
echo "  Heartbeat Failures: ${HEARTBEAT_COUNT}"
echo "  HTTP Errors: ${HTTP_ERROR_COUNT}"
echo "  Recovery Attempts: ${RECOVERY_COUNT}"
echo ""

if [ "$RECONNECT_COUNT" -eq 0 ] && [ "$HEARTBEAT_COUNT" -eq 0 ] && [ "$HTTP_ERROR_COUNT" -eq 0 ] && [ "$RECOVERY_COUNT" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ System has been stable - no recovery events detected!${NC}"
else
    echo -e "${YELLOW}${BOLD}⚠ Some instability detected - review events above${NC}"
fi

echo "════════════════════════════════════════════════════════════"
