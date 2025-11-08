#!/bin/bash
#
# XRPL Validator Dashboard - Prerequisites Uninstall Script
# For Ubuntu 20.04/22.04/24.04
#
# Removes:
# - Docker Engine
# - Docker Compose V2
# - Docker data and volumes
# - pip3 (optional)
#

set -e  # Exit on error

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${BLUE}XRPL Validator Dashboard - Prerequisites Uninstall${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo ""

# Get current user
CURRENT_USER=$(whoami)
echo -e "${YELLOW}⚠️  WARNING: This will remove Docker and all containers/volumes!${NC}"
echo ""
read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Uninstall cancelled.${NC}"
    exit 0
fi
echo ""

# Step 1: Stop and remove all Docker containers
echo -e "${BLUE}Step 1: Stopping and removing all Docker containers...${NC}"
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

# Step 2: Remove Docker images
echo -e "${BLUE}Step 2: Removing Docker images...${NC}"
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

# Step 3: Remove Docker volumes
echo -e "${BLUE}Step 3: Removing Docker volumes...${NC}"
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

# Step 4: Stop Docker service
echo -e "${BLUE}Step 4: Stopping Docker service...${NC}"
if systemctl is-active --quiet docker 2>/dev/null; then
    sudo systemctl stop docker
    sudo systemctl disable docker
    echo -e "${GREEN}✓ Docker service stopped and disabled${NC}"
else
    echo -e "${GREEN}✓ Docker service not running${NC}"
fi
echo ""

# Step 5: Remove Docker packages
echo -e "${BLUE}Step 5: Removing Docker packages...${NC}"
sudo apt remove -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin 2>/dev/null || true
sudo apt autoremove -y
echo -e "${GREEN}✓ Docker packages removed${NC}"
echo ""

# Step 6: Remove Docker data directories
echo -e "${BLUE}Step 6: Removing Docker data directories...${NC}"
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
echo -e "${GREEN}✓ Docker data directories removed${NC}"
echo ""

# Step 7: Remove Docker repository and GPG key
echo -e "${BLUE}Step 7: Removing Docker repository...${NC}"
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -f /etc/apt/keyrings/docker.gpg
sudo apt update
echo -e "${GREEN}✓ Docker repository removed${NC}"
echo ""

# Step 8: Remove user from docker group
echo -e "${BLUE}Step 8: Removing user '${CURRENT_USER}' from docker group...${NC}"
if groups ${CURRENT_USER} | grep -q docker; then
    sudo deluser ${CURRENT_USER} docker 2>/dev/null || true
    echo -e "${GREEN}✓ User removed from docker group${NC}"
else
    echo -e "${GREEN}✓ User not in docker group${NC}"
fi
echo ""

# Step 9: Optional - Remove pip3
echo -e "${BLUE}Step 9: pip3 removal (optional)...${NC}"
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

# Step 10: Verify removal
echo -e "${BLUE}Step 10: Verifying removal...${NC}"
echo ""

# Check Docker
if command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker still installed${NC}"
else
    echo -e "${GREEN}✓ Docker removed${NC}"
fi

# Check docker group
if groups ${CURRENT_USER} | grep -q docker; then
    echo -e "${YELLOW}⚠ User still in docker group (requires logout/login)${NC}"
else
    echo -e "${GREEN}✓ User removed from docker group${NC}"
fi

# Check pip3
if command -v pip3 &> /dev/null; then
    echo -e "${YELLOW}✓ pip3 still installed (preserved or not removed)${NC}"
else
    echo -e "${GREEN}✓ pip3 removed${NC}"
fi

echo ""
echo -e "${GREEN}================================================================================================${NC}"
echo -e "${GREEN}Uninstall Complete!${NC}"
echo -e "${GREEN}================================================================================================${NC}"
echo ""

echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo -e "1. ${YELLOW}Log out and log back in${NC} for group changes to take effect:"
echo -e "   ${YELLOW}exit${NC}"
echo ""
echo -e "2. To reinstall prerequisites:"
echo -e "   ${YELLOW}./test/install-prerequisites.sh${NC}"
echo ""
echo -e "3. To verify complete removal:"
echo -e "   ${YELLOW}docker --version${NC} (should show 'command not found')"
echo -e "   ${YELLOW}groups${NC} (should not show 'docker')"
echo ""
