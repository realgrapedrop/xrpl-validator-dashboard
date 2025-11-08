#!/bin/bash
#
# XRPL Validator Dashboard - Comprehensive Uninstall Script
# For Ubuntu 20.04/22.04/24.04
#
# Can remove:
# - Systemd service
# - Docker containers (dashboard components)
# - Docker volumes (Grafana/Prometheus data)
# - Local data files (logs, database)
# - Docker Engine
# - pip3
#

set -e  # Exit on error

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get current user and project directory
CURRENT_USER=$(whoami)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="xrpl-validator-dashboard"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${BLUE}XRPL Validator Dashboard - Uninstall${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo ""

# Ask if user wants to remove everything
echo -e "${YELLOW}⚠️  WARNING: This script can remove dashboard components and/or Docker itself${NC}"
echo ""
read -p "Remove EVERYTHING (service, containers, volumes, logs, Docker)? [y/N]: " -n 1 -r
echo
echo ""

REMOVE_ALL=false
if [[ $REPLY =~ ^[Yy]$ ]]; then
    REMOVE_ALL=true
    REMOVE_SERVICE=true
    REMOVE_CONTAINERS=true
    REMOVE_VOLUMES=true
    REMOVE_DATA=true
    REMOVE_DOCKER=true
    REMOVE_PIP=false  # Still ask about pip since it affects other apps

    echo -e "${RED}Will remove: service, containers, volumes, data, and Docker Engine${NC}"
    echo ""
    read -p "Are you absolutely sure? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Uninstall cancelled.${NC}"
        exit 0
    fi
    echo ""
else
    # Ask individually
    echo -e "${BLUE}Select components to remove:${NC}"
    echo ""

    # Systemd service
    read -p "Remove systemd service? [y/N]: " -n 1 -r
    echo
    REMOVE_SERVICE=false
    [[ $REPLY =~ ^[Yy]$ ]] && REMOVE_SERVICE=true

    # Docker containers
    read -p "Remove Docker containers (Grafana, Prometheus, Node Exporter)? [y/N]: " -n 1 -r
    echo
    REMOVE_CONTAINERS=false
    [[ $REPLY =~ ^[Yy]$ ]] && REMOVE_CONTAINERS=true

    # Docker volumes
    if [ "$REMOVE_CONTAINERS" = true ]; then
        read -p "Remove Docker volumes (Grafana/Prometheus data)? [y/N]: " -n 1 -r
        echo
        REMOVE_VOLUMES=false
        [[ $REPLY =~ ^[Yy]$ ]] && REMOVE_VOLUMES=true
    else
        REMOVE_VOLUMES=false
    fi

    # Local data files
    read -p "Remove local data files (logs, database)? [y/N]: " -n 1 -r
    echo
    REMOVE_DATA=false
    [[ $REPLY =~ ^[Yy]$ ]] && REMOVE_DATA=true

    # Docker Engine
    read -p "Remove Docker Engine entirely? [y/N]: " -n 1 -r
    echo
    REMOVE_DOCKER=false
    [[ $REPLY =~ ^[Yy]$ ]] && REMOVE_DOCKER=true

    REMOVE_PIP=false

    echo ""
fi

# =============================================================================
# Step 1: Stop and remove systemd service
# =============================================================================
if [ "$REMOVE_SERVICE" = true ]; then
    echo -e "${BLUE}Step 1: Stopping and removing systemd service...${NC}"

    if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
        echo -e "${YELLOW}Stopping service...${NC}"
        sudo systemctl stop "${SERVICE_NAME}"
        echo -e "${GREEN}✓ Service stopped${NC}"
        sleep 2
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
else
    echo -e "${BLUE}Step 1: Skipping systemd service removal${NC}"
    echo ""
fi

# =============================================================================
# Step 2: Stop and remove Docker containers
# =============================================================================
if [ "$REMOVE_CONTAINERS" = true ]; then
    echo -e "${BLUE}Step 2: Stopping and removing Docker containers...${NC}"

    if command -v docker &> /dev/null; then
        cd "${PROJECT_DIR}"

        # Check for dashboard containers
        if docker ps -a --filter "name=xrpl-dashboard" --format "{{.Names}}" | grep -q "xrpl-dashboard"; then
            echo -e "${YELLOW}Stopping containers...${NC}"

            # Try docker compose down
            if [ "$REMOVE_VOLUMES" = true ]; then
                docker compose down -v 2>/dev/null || true
            else
                docker compose down 2>/dev/null || true
            fi

            # Ensure all dashboard containers are stopped
            docker stop xrpl-dashboard-grafana xrpl-dashboard-prometheus xrpl-dashboard-node-exporter 2>/dev/null || true
            docker rm xrpl-dashboard-grafana xrpl-dashboard-prometheus xrpl-dashboard-node-exporter 2>/dev/null || true

            echo -e "${GREEN}✓ Containers stopped and removed${NC}"
            sleep 2
        else
            echo -e "${GREEN}✓ No dashboard containers found${NC}"
        fi
    else
        echo -e "${GREEN}✓ Docker not installed${NC}"
    fi
    echo ""
else
    echo -e "${BLUE}Step 2: Skipping Docker containers removal${NC}"
    echo ""
fi

# =============================================================================
# Step 3: Remove local data files
# =============================================================================
if [ "$REMOVE_DATA" = true ]; then
    echo -e "${BLUE}Step 3: Removing local data files...${NC}"
    cd "${PROJECT_DIR}"

    rm -f data/*.db data/*.db-* logs/*.log config.yaml config.yaml.backup 2>/dev/null || true
    echo -e "${GREEN}✓ Local data files removed${NC}"
    echo ""
else
    echo -e "${BLUE}Step 3: Skipping local data files removal${NC}"
    echo ""
fi

# =============================================================================
# Step 4-9: Remove Docker Engine (if requested)
# =============================================================================
if [ "$REMOVE_DOCKER" = true ]; then
    echo -e "${BLUE}Step 4: Stopping and removing ALL Docker containers...${NC}"
    if command -v docker &> /dev/null; then
        # Stop all running containers
        CONTAINERS=$(sudo docker ps -q)
        if [ -n "$CONTAINERS" ]; then
            echo -e "${YELLOW}Stopping running containers...${NC}"
            sudo docker stop $(sudo docker ps -q) 2>/dev/null || true
            echo -e "${GREEN}✓ Containers stopped${NC}"
        else
            echo -e "${GREEN}✓ No running containers${NC}"
        fi

        # Remove all containers
        ALL_CONTAINERS=$(sudo docker ps -a -q)
        if [ -n "$ALL_CONTAINERS" ]; then
            echo -e "${YELLOW}Removing all containers...${NC}"
            sudo docker rm $(sudo docker ps -a -q) 2>/dev/null || true
            echo -e "${GREEN}✓ Containers removed${NC}"
        else
            echo -e "${GREEN}✓ No containers to remove${NC}"
        fi
    else
        echo -e "${GREEN}✓ Docker not installed${NC}"
    fi
    echo ""

    echo -e "${BLUE}Step 5: Removing Docker images...${NC}"
    if command -v docker &> /dev/null; then
        IMAGES=$(sudo docker images -q)
        if [ -n "$IMAGES" ]; then
            echo -e "${YELLOW}Removing images...${NC}"
            sudo docker rmi $(sudo docker images -q) 2>/dev/null || true
            echo -e "${GREEN}✓ Images removed${NC}"
        else
            echo -e "${GREEN}✓ No images to remove${NC}"
        fi
    else
        echo -e "${GREEN}✓ Docker not installed${NC}"
    fi
    echo ""

    echo -e "${BLUE}Step 6: Removing Docker volumes...${NC}"
    if command -v docker &> /dev/null; then
        VOLUMES=$(sudo docker volume ls -q)
        if [ -n "$VOLUMES" ]; then
            echo -e "${YELLOW}Removing volumes...${NC}"
            sudo docker volume rm $(sudo docker volume ls -q) 2>/dev/null || true
            echo -e "${GREEN}✓ Volumes removed${NC}"
        else
            echo -e "${GREEN}✓ No volumes to remove${NC}"
        fi
    else
        echo -e "${GREEN}✓ Docker not installed${NC}"
    fi
    echo ""

    echo -e "${BLUE}Step 7: Stopping Docker service...${NC}"
    if systemctl is-active --quiet docker 2>/dev/null; then
        sudo systemctl stop docker
        sudo systemctl disable docker
        echo -e "${GREEN}✓ Docker service stopped and disabled${NC}"
    else
        echo -e "${GREEN}✓ Docker service not running${NC}"
    fi
    echo ""

    echo -e "${BLUE}Step 8: Removing Docker packages...${NC}"
    sudo apt remove -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin 2>/dev/null || true
    sudo apt autoremove -y
    echo -e "${GREEN}✓ Docker packages removed${NC}"
    echo ""

    echo -e "${BLUE}Step 9: Removing Docker data directories...${NC}"
    sudo rm -rf /var/lib/docker
    sudo rm -rf /var/lib/containerd
    echo -e "${GREEN}✓ Docker data directories removed${NC}"
    echo ""

    echo -e "${BLUE}Step 10: Removing Docker repository...${NC}"
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/keyrings/docker.gpg
    sudo apt update
    echo -e "${GREEN}✓ Docker repository removed${NC}"
    echo ""

    echo -e "${BLUE}Step 11: Removing user from docker group...${NC}"
    if groups ${CURRENT_USER} | grep -q docker; then
        sudo deluser ${CURRENT_USER} docker 2>/dev/null || true
        echo -e "${GREEN}✓ User removed from docker group${NC}"
    else
        echo -e "${GREEN}✓ User not in docker group${NC}"
    fi
    echo ""
else
    echo -e "${BLUE}Steps 4-11: Skipping Docker Engine removal${NC}"
    echo ""
fi

# =============================================================================
# Step 12: Remove pip3 (always ask)
# =============================================================================
echo -e "${BLUE}Step 12: pip3 removal (optional)...${NC}"
read -p "Remove pip3? This may break other Python applications. [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo apt remove -y python3-pip
    sudo apt autoremove -y
    echo -e "${GREEN}✓ pip3 removed${NC}"
else
    echo -e "${YELLOW}✓ pip3 preserved${NC}"
fi
echo ""

# =============================================================================
# Verification
# =============================================================================
echo -e "${BLUE}Verification:${NC}"
echo ""

# Check systemd service
if [ "$REMOVE_SERVICE" = true ]; then
    if [ -f "${SERVICE_FILE}" ]; then
        echo -e "${RED}✗ Service file still exists${NC}"
    else
        echo -e "${GREEN}✓ Service removed${NC}"
    fi
fi

# Check Docker containers
if [ "$REMOVE_CONTAINERS" = true ]; then
    if command -v docker &> /dev/null; then
        if docker ps -a --filter "name=xrpl-dashboard" --format "{{.Names}}" | grep -q "xrpl-dashboard"; then
            echo -e "${RED}✗ Dashboard containers still exist${NC}"
        else
            echo -e "${GREEN}✓ Dashboard containers removed${NC}"
        fi
    fi
fi

# Check Docker
if [ "$REMOVE_DOCKER" = true ]; then
    if command -v docker &> /dev/null; then
        echo -e "${RED}✗ Docker still installed${NC}"
    else
        echo -e "${GREEN}✓ Docker removed${NC}"
    fi

    if groups ${CURRENT_USER} | grep -q docker; then
        echo -e "${YELLOW}⚠ User still in docker group (requires logout/login)${NC}"
    else
        echo -e "${GREEN}✓ User removed from docker group${NC}"
    fi
fi

# Check pip3
if command -v pip3 &> /dev/null; then
    echo -e "${YELLOW}✓ pip3 still installed${NC}"
else
    echo -e "${GREEN}✓ pip3 removed${NC}"
fi

echo ""
echo -e "${GREEN}================================================================================================${NC}"
echo -e "${GREEN}Uninstall Complete!${NC}"
echo -e "${GREEN}================================================================================================${NC}"
echo ""

# Show next steps based on what was removed
if [ "$REMOVE_DOCKER" = true ] || [ "$REMOVE_SERVICE" = true ]; then
    echo -e "${BLUE}Next Steps:${NC}"
    echo ""

    if [ "$REMOVE_DOCKER" = true ]; then
        echo -e "1. ${YELLOW}Log out and log back in${NC} for group changes to take effect:"
        echo -e "   ${YELLOW}exit${NC}"
        echo ""
        echo -e "2. To reinstall:"
        echo -e "   ${YELLOW}./install-prerequisites.sh${NC}"
        echo -e "   ${YELLOW}python3 setup.py${NC}"
    else
        echo -e "To restart the dashboard:"
        echo -e "   ${YELLOW}python3 setup.py${NC}"
    fi
    echo ""
fi
