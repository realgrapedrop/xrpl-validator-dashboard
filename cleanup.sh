#!/bin/bash
#
# XRPL Validator Dashboard - Cleanup Script
# This script removes the service and Docker containers for a clean reinstall
#

set -e

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

PROJECT_DIR="/home/grapedrop/projects/xrpl-validator-dashboard"
SERVICE_NAME="xrpl-validator-dashboard"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${BLUE}XRPL Validator Dashboard - Cleanup${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo ""

# Stop service if running
echo -e "${BLUE}Step 1: Stopping and removing systemd service...${NC}"
if systemctl is-active --quiet "${SERVICE_NAME}"; then
    echo -e "${YELLOW}Stopping service...${NC}"
    sudo systemctl stop "${SERVICE_NAME}"
    echo -e "${GREEN}✓ Service stopped${NC}"
    # Wait for port to be fully released from TIME_WAIT
    echo -e "${YELLOW}Waiting 5 seconds for ports to release...${NC}"
    sleep 5
else
    echo -e "${GREEN}✓ Service is not running${NC}"
fi

if systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null; then
    echo -e "${YELLOW}Disabling service...${NC}"
    sudo systemctl disable "${SERVICE_NAME}"
    echo -e "${GREEN}✓ Service disabled${NC}"
else
    echo -e "${GREEN}✓ Service is not enabled${NC}"
fi

if [ -f "${SERVICE_FILE}" ]; then
    echo -e "${YELLOW}Removing service file...${NC}"
    sudo rm "${SERVICE_FILE}"
    sudo systemctl daemon-reload
    echo -e "${GREEN}✓ Service file removed${NC}"
else
    echo -e "${GREEN}✓ Service file does not exist${NC}"
fi
echo ""

# Stop and remove Docker containers
echo -e "${BLUE}Step 2: Stopping and removing Docker containers...${NC}"
cd "${PROJECT_DIR}"
if docker compose ps 2>/dev/null | grep -q "xrpl-dashboard"; then
    echo -e "${YELLOW}Stopping containers...${NC}"
    docker compose down
    echo -e "${GREEN}✓ Containers stopped and removed${NC}"
    # Wait for ports to be fully released from TIME_WAIT
    echo -e "${YELLOW}Waiting 5 seconds for ports to release...${NC}"
    sleep 5
else
    echo -e "${GREEN}✓ No containers running${NC}"
fi
echo ""

# Optional: Remove volumes (data)
echo -e "${BLUE}Step 3: Docker volumes...${NC}"
read -p "Remove Docker volumes (Prometheus & Grafana data)? [Y/n]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}✓ Volumes preserved${NC}"
else
    docker compose down -v 2>/dev/null || true
    echo -e "${GREEN}✓ Volumes removed${NC}"
fi
echo ""

# Optional: Remove database and logs
echo -e "${BLUE}Step 4: Local data files...${NC}"
read -p "Remove database and logs (data/*.db, logs/*.log)? [Y/n]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}✓ Database and logs preserved${NC}"
else
    rm -f data/*.db data/*.db-* logs/*.log 2>/dev/null || true
    echo -e "${GREEN}✓ Database and logs removed${NC}"
fi
echo ""

echo -e "${GREEN}================================================================================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}================================================================================================${NC}"
echo ""
echo -e "${YELLOW}Waiting 5 more seconds to ensure all ports are fully released...${NC}"
sleep 5
echo ""
echo -e "You can now run the setup wizard again:"
echo -e "  ${YELLOW}python3 setup.py${NC}"
echo ""
