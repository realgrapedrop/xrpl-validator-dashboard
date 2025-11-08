#!/bin/bash
#
# XRPL Validator Dashboard - Prerequisites Installation Script
# For Ubuntu 20.04/22.04/24.04
#
# Installs:
# - Python 3 and pip3
# - Docker Engine
# - Docker Compose V2
#

set -e  # Exit on error

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${BLUE}XRPL Validator Dashboard - Prerequisites Installation${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo ""

# Get current user
CURRENT_USER=$(whoami)
echo -e "${BLUE}Installing prerequisites for user: ${YELLOW}${CURRENT_USER}${NC}"
echo ""

# Step 1: Update system
echo -e "${BLUE}Step 1: Updating system packages...${NC}"
sudo apt update
echo -e "${GREEN}✓ Package list updated${NC}"
echo ""

# Step 2: Install Python and pip3
echo -e "${BLUE}Step 2: Installing Python 3 and pip3...${NC}"
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    echo -e "${GREEN}✓ Python already installed: ${PYTHON_VERSION}${NC}"
else
    sudo apt install -y python3
    echo -e "${GREEN}✓ Python 3 installed${NC}"
fi

if command -v pip3 &> /dev/null; then
    PIP_VERSION=$(pip3 --version)
    echo -e "${GREEN}✓ pip3 already installed: ${PIP_VERSION}${NC}"
else
    sudo apt install -y python3-pip
    echo -e "${GREEN}✓ pip3 installed${NC}"
fi
echo ""

# Step 3: Install Docker prerequisites
echo -e "${BLUE}Step 3: Installing Docker prerequisites...${NC}"
sudo apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
echo -e "${GREEN}✓ Prerequisites installed${NC}"
echo ""

# Step 4: Add Docker's official GPG key
echo -e "${BLUE}Step 4: Adding Docker GPG key...${NC}"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo -e "${GREEN}✓ Docker GPG key added${NC}"
echo ""

# Step 5: Add Docker repository
echo -e "${BLUE}Step 5: Adding Docker repository...${NC}"
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
echo -e "${GREEN}✓ Docker repository added${NC}"
echo ""

# Step 6: Install Docker Engine
echo -e "${BLUE}Step 6: Installing Docker Engine...${NC}"
sudo apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
echo -e "${GREEN}✓ Docker Engine installed${NC}"
echo ""

# Step 7: Start and enable Docker
echo -e "${BLUE}Step 7: Starting Docker service...${NC}"
sudo systemctl enable docker
sudo systemctl start docker
echo -e "${GREEN}✓ Docker service started${NC}"
echo ""

# Step 8: Add user to docker group
echo -e "${BLUE}Step 8: Adding user '${CURRENT_USER}' to docker group...${NC}"
sudo usermod -aG docker ${CURRENT_USER}
echo -e "${GREEN}✓ User added to docker group${NC}"
echo ""

# Step 9: Verify installations
echo -e "${BLUE}Step 9: Verifying installations...${NC}"
echo ""

# Check Python
PYTHON_VERSION=$(python3 --version 2>&1)
echo -e "${GREEN}✓ Python: ${PYTHON_VERSION}${NC}"

# Check pip3
PIP_VERSION=$(pip3 --version 2>&1 | head -1)
echo -e "${GREEN}✓ pip3: ${PIP_VERSION}${NC}"

# Check Docker
DOCKER_VERSION=$(docker --version 2>&1)
echo -e "${GREEN}✓ Docker: ${DOCKER_VERSION}${NC}"

# Check Docker Compose
COMPOSE_VERSION=$(docker compose version 2>&1)
echo -e "${GREEN}✓ Docker Compose: ${COMPOSE_VERSION}${NC}"

# Check Docker service
if sudo systemctl is-active --quiet docker; then
    echo -e "${GREEN}✓ Docker service is running${NC}"
else
    echo -e "${RED}✗ Docker service is not running${NC}"
fi

echo ""
echo -e "${GREEN}================================================================================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}================================================================================================${NC}"
echo ""

echo -e "${YELLOW}⚠️  IMPORTANT: Docker group changes require logout/login${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo -e "1. ${YELLOW}Log out and log back in${NC} for Docker group permissions to take effect:"
echo -e "   ${YELLOW}exit${NC}"
echo -e "   ${YELLOW}ssh <your-connection-command>${NC}"
echo ""
echo -e "2. Verify Docker works without sudo:"
echo -e "   ${YELLOW}docker ps${NC}"
echo ""
echo -e "3. Run the dashboard setup wizard:"
echo -e "   ${YELLOW}cd ~/xrpl-validator-dashboard${NC}"
echo -e "   ${YELLOW}python3 setup.py${NC}"
echo ""
echo -e "${BLUE}Configuration for native rippled:${NC}"
echo -e "  - rippled_mode: ${YELLOW}native${NC}"
echo -e "  - rippled_host: ${YELLOW}localhost${NC}"
echo -e "  - rippled_port: ${YELLOW}5015${NC} (or your custom port)"
echo ""
