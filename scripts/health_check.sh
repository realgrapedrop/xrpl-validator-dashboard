#!/bin/bash
#
# XRPL Validator Dashboard - Health Check Script
# Checks if rippled is running and responding
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "XRPL Validator Dashboard - Health Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if rippled is running (container or native)
echo -e "${BLUE}Checking rippled...${NC}"

# First check for containerized rippled
if docker ps --filter "name=rippledvalidator" --format "{{.Names}}" 2>/dev/null | grep -q "rippledvalidator"; then
    STATUS=$(docker ps --filter "name=rippledvalidator" --format "{{.Status}}")
    echo -e "${GREEN}✓${NC} rippled container is running"
    echo "  Status: $STATUS"
# Then check for native rippled process
elif pgrep -x rippled > /dev/null; then
    echo -e "${GREEN}✓${NC} rippled is running (native)"
    UPTIME=$(ps -p $(pgrep -x rippled) -o etime= | xargs)
    echo "  Uptime: $UPTIME"
else
    echo -e "${RED}✗${NC} rippled is not running"
    echo ""
    echo "To start rippled:"
    echo "  Container: docker start rippledvalidator"
    echo "  Native:    sudo systemctl start rippled"
    exit 1
fi

echo ""

# Check WebSocket connectivity
echo -e "${BLUE}Checking WebSocket (ws://localhost:6006)...${NC}"
if timeout 5 curl -s --include \
     --no-buffer \
     --header "Connection: Upgrade" \
     --header "Upgrade: websocket" \
     --header "Sec-WebSocket-Version: 13" \
     --header "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" \
     http://localhost:6006/ 2>&1 | grep -q "101 Switching Protocols"; then
    echo -e "${GREEN}✓${NC} WebSocket is responding"
else
    echo -e "${RED}✗${NC} WebSocket is not responding"
fi

echo ""

# Check HTTP/RPC connectivity
echo -e "${BLUE}Checking HTTP/RPC (http://localhost:5005)...${NC}"
if timeout 5 curl -s -X POST http://localhost:5005/ \
     -H "Content-Type: application/json" \
     -d '{"method":"server_info","params":[{}]}' | grep -q "result"; then
    echo -e "${GREEN}✓${NC} HTTP/RPC is responding"

    # Get server state
    SERVER_STATE=$(curl -s -X POST http://localhost:5005/ \
         -H "Content-Type: application/json" \
         -d '{"method":"server_info","params":[{}]}' | \
         jq -r '.result.info.server_state' 2>/dev/null || echo "unknown")

    echo "  Server state: $SERVER_STATE"

    # Get network
    NETWORK=$(curl -s -X POST http://localhost:5005/ \
         -H "Content-Type: application/json" \
         -d '{"method":"server_info","params":[{}]}' | \
         jq -r '.result.info.network_id' 2>/dev/null || echo "unknown")

    echo "  Network ID: $NETWORK"
else
    echo -e "${RED}✗${NC} HTTP/RPC is not responding"
fi

echo ""

# Check dashboard containers
echo -e "${BLUE}Checking dashboard containers...${NC}"
for container in xrpl-monitor-collector xrpl-monitor-victoria xrpl-monitor-grafana; do
    if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
        HEALTH=$(docker inspect --format='{{.State.Health.Status}}' $container 2>/dev/null || echo "no healthcheck")
        if [ "$HEALTH" = "healthy" ] || [ "$HEALTH" = "no healthcheck" ]; then
            echo -e "${GREEN}✓${NC} $container"
        else
            echo -e "${YELLOW}⚠${NC} $container (health: $HEALTH)"
        fi
    else
        echo -e "${RED}✗${NC} $container (not running)"
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Health check complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
