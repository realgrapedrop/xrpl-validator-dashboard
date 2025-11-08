#!/bin/bash
#
# XRPL Validator Dashboard - Service Installation Script
# This script installs and starts the monitor as a systemd service
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
echo -e "${BLUE}XRPL Validator Dashboard - Service Installation${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "${PROJECT_DIR}/src/collectors/fast_poller.py" ]; then
    echo -e "${RED}Error: Cannot find fast_poller.py in ${PROJECT_DIR}${NC}"
    exit 1
fi

# Check if Docker services are running
echo -e "${BLUE}Step 1: Checking Docker services...${NC}"
cd "${PROJECT_DIR}"
if ! docker compose ps | grep -q "xrpl-dashboard-grafana"; then
    echo -e "${YELLOW}Starting Docker services...${NC}"
    docker compose up -d
    echo -e "${GREEN}✓ Docker services started${NC}"
else
    echo -e "${GREEN}✓ Docker services already running${NC}"
fi
echo ""

# Create systemd service file
echo -e "${BLUE}Step 2: Creating systemd service...${NC}"
sudo tee "${SERVICE_FILE}" > /dev/null << 'EOF'
[Unit]
Description=XRPL Validator Dashboard Monitor
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=grapedrop
Group=grapedrop
WorkingDirectory=/home/grapedrop/projects/xrpl-validator-dashboard
ExecStart=/usr/bin/python3 -u /home/grapedrop/projects/xrpl-validator-dashboard/src/collectors/fast_poller.py
Restart=always
RestartSec=10
StandardOutput=append:/home/grapedrop/projects/xrpl-validator-dashboard/logs/monitor.log
StandardError=append:/home/grapedrop/projects/xrpl-validator-dashboard/logs/error.log
NoNewPrivileges=true
MemoryMax=512M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}✓ Service file created: ${SERVICE_FILE}${NC}"
echo ""

# Reload systemd
echo -e "${BLUE}Step 3: Reloading systemd...${NC}"
sudo systemctl daemon-reload
echo -e "${GREEN}✓ Systemd reloaded${NC}"
echo ""

# Enable service
echo -e "${BLUE}Step 4: Enabling service to start on boot...${NC}"
sudo systemctl enable "${SERVICE_NAME}"
echo -e "${GREEN}✓ Service enabled${NC}"
echo ""

# Start service
echo -e "${BLUE}Step 5: Starting service...${NC}"
sudo systemctl start "${SERVICE_NAME}"
sleep 2
echo -e "${GREEN}✓ Service started${NC}"
echo ""

# Show status
echo -e "${BLUE}Step 6: Checking service status...${NC}"
sudo systemctl status "${SERVICE_NAME}" --no-pager -l
echo ""

echo -e "${GREEN}================================================================================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}================================================================================================${NC}"
echo ""
echo -e "The monitor is now running as a background service."
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo -e "  View live logs:        ${YELLOW}sudo journalctl -u ${SERVICE_NAME} -f${NC}"
echo -e "  View status:           ${YELLOW}sudo systemctl status ${SERVICE_NAME}${NC}"
echo -e "  Stop service:          ${YELLOW}sudo systemctl stop ${SERVICE_NAME}${NC}"
echo -e "  Start service:         ${YELLOW}sudo systemctl start ${SERVICE_NAME}${NC}"
echo -e "  Restart service:       ${YELLOW}sudo systemctl restart ${SERVICE_NAME}${NC}"
echo -e "  View application log:  ${YELLOW}tail -f logs/monitor.log${NC}"
echo ""
echo -e "${BLUE}Access Your Dashboards:${NC}"
echo -e "  Grafana:    ${YELLOW}http://localhost:3003${NC} (admin/admin)"
echo -e "  Prometheus: ${YELLOW}http://localhost:9092${NC}"
echo -e "  Metrics:    ${YELLOW}http://localhost:9094/metrics${NC}"
echo ""
