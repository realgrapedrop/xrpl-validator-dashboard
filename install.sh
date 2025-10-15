#!/bin/bash
# install.sh
# XRPL Validator Monitor Dashboard - Installation Script
# Tracks all installed components for clean uninstallation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Installation tracker file
TRACKER_FILE=".install-tracker.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
INSTALL_DIR="${HOME}/xrpl-validator"
INSTALL_MODE=""
RIPPLED_TYPE="docker"

# Usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

XRPL Validator Monitor Dashboard Installation Script

OPTIONS:
    --full                  Install complete stack (rippled + monitoring)
    --monitoring            Install monitoring stack only
    --dashboard-only        Import Grafana dashboard only
    --rippled-type TYPE     Rippled deployment type: docker|native (default: docker)
    --install-dir PATH      Installation directory (default: \$HOME/xrpl-validator)
    --help                  Show this help message

EXAMPLES:
    # Full installation
    sudo $0 --full

    # Monitoring only for existing Docker rippled
    sudo $0 --monitoring --rippled-type docker

    # Monitoring only for native rippled
    sudo $0 --monitoring --rippled-type native

    # Custom installation directory
    sudo $0 --full --install-dir /opt/xrpl-validator

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            INSTALL_MODE="full"
            shift
            ;;
        --monitoring)
            INSTALL_MODE="monitoring"
            shift
            ;;
        --dashboard-only)
            INSTALL_MODE="dashboard"
            shift
            ;;
        --rippled-type)
            RIPPLED_TYPE="$2"
            shift 2
            ;;
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Validate install mode
if [[ -z "$INSTALL_MODE" ]]; then
    echo -e "${RED}Error: Installation mode required${NC}"
    usage
fi

# Validate rippled type
if [[ "$RIPPLED_TYPE" != "docker" && "$RIPPLED_TYPE" != "native" ]]; then
    echo -e "${RED}Error: --rippled-type must be 'docker' or 'native'${NC}"
    exit 1
fi

# Check if running as root for full/monitoring installs
if [[ "$INSTALL_MODE" != "dashboard" && $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root for full/monitoring installation${NC}"
   echo "Please run: sudo $0 $@"
   exit 1
fi

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════╗
║   XRPL Validator Monitor Dashboard - Installation       ║
╚══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Initialize tracker
init_tracker() {
    cat > "$TRACKER_FILE" << EOF
{
  "installation_date": "$(date -Iseconds)",
  "install_mode": "$INSTALL_MODE",
  "install_dir": "$INSTALL_DIR",
  "rippled_type": "$RIPPLED_TYPE",
  "components": [],
  "docker_containers": [],
  "docker_volumes": [],
  "systemd_services": [],
  "config_files": [],
  "directories": []
}
EOF
    echo -e "${GREEN}✓ Installation tracker initialized${NC}"
}

# Add to tracker
track_component() {
    local component_type="$1"
    local component_value="$2"
    
    # Create temp file with updated JSON
    jq ".${component_type} += [\"${component_value}\"]" "$TRACKER_FILE" > "${TRACKER_FILE}.tmp"
    mv "${TRACKER_FILE}.tmp" "$TRACKER_FILE"
}

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}Checking prerequisites...${NC}"
    
    local missing_deps=()
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    else
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
        echo -e "${GREEN}✓ Docker found: ${DOCKER_VERSION}${NC}"
    fi
    
    # Check Docker Compose
    if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
        missing_deps+=("docker-compose")
    else
        COMPOSE_VERSION=$(docker compose version | awk '{print $4}')
        echo -e "${GREEN}✓ Docker Compose found: ${COMPOSE_VERSION}${NC}"
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}! jq not found, installing...${NC}"
        apt-get update && apt-get install -y jq
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}"
        echo ""
        echo "Please install:"
        echo "  Docker: https://docs.docker.com/engine/install/ubuntu/"
        echo "  Docker Compose: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    echo -e "${GREEN}✓ All prerequisites met${NC}"
}

# Create directories
create_directories() {
    echo -e "${BLUE}Creating directory structure...${NC}"
    
    mkdir -p "$INSTALL_DIR"/{rippled/{config,data},monitoring/{grafana/{dashboards,data},prometheus/{data,config}}}
    
    track_component "directories" "$INSTALL_DIR"
    track_component "directories" "$INSTALL_DIR/rippled"
    track_component "directories" "$INSTALL_DIR/monitoring"
    
    echo -e "${GREEN}✓ Directories created${NC}"
}

# Install rippled (full mode only)
install_rippled() {
    echo -e "${BLUE}Installing rippled validator...${NC}"
    
    # Copy docker-compose file
    cp "$SCRIPT_DIR/docker-compose-full.yml" "$INSTALL_DIR/docker-compose.yml"
    
    # Substitute variables
    sed -i "s|\${INSTALL_DIR}|$INSTALL_DIR|g" "$INSTALL_DIR/docker-compose.yml"
    
    # Copy config templates
    if [ ! -f "$INSTALL_DIR/rippled/config/rippled.cfg" ]; then
        cp "$SCRIPT_DIR/config/rippled.cfg.template" "$INSTALL_DIR/rippled/config/rippled.cfg"
        track_component "config_files" "$INSTALL_DIR/rippled/config/rippled.cfg"
    fi
    
    if [ ! -f "$INSTALL_DIR/rippled/config/validators.txt" ]; then
        cp "$SCRIPT_DIR/config/validators.txt.template" "$INSTALL_DIR/rippled/config/validators.txt"
        track_component "config_files" "$INSTALL_DIR/rippled/config/validators.txt"
    fi
    
    # Start services
    cd "$INSTALL_DIR"
    docker compose up -d
    
    track_component "docker_containers" "rippledvalidator"
    track_component "docker_containers" "prometheus"
    track_component "docker_containers" "grafana"
    track_component "docker_containers" "node_exporter"
    
    echo -e "${GREEN}✓ Rippled validator installed${NC}"
}

# Install monitoring stack
install_monitoring() {
    echo -e "${BLUE}Installing monitoring stack...${NC}"
    
    # Copy appropriate docker-compose
    cp "$SCRIPT_DIR/docker-compose-monitoring.yml" "$INSTALL_DIR/docker-compose.yml"
    
    # Substitute variables
    sed -i "s|\${INSTALL_DIR}|$INSTALL_DIR|g" "$INSTALL_DIR/docker-compose.yml"
    
    # Copy Prometheus config
    cp "$SCRIPT_DIR/config/prometheus.yml.template" "$INSTALL_DIR/monitoring/prometheus/prometheus.yml"
    
    # Configure for rippled type
    if [[ "$RIPPLED_TYPE" == "native" ]]; then
        # Update scrape config for native rippled
        sed -i "s|rippledvalidator:5005|localhost:5005|g" "$INSTALL_DIR/monitoring/prometheus/prometheus.yml"
    fi
    
    track_component "config_files" "$INSTALL_DIR/monitoring/prometheus/prometheus.yml"
    
    # Start monitoring services
    cd "$INSTALL_DIR"
    docker compose up -d
    
    track_component "docker_containers" "prometheus"
    track_component "docker_containers" "grafana"
    track_component "docker_containers" "node_exporter"
    
    echo -e "${GREEN}✓ Monitoring stack installed${NC}"
}

# Import Grafana dashboard
import_dashboard() {
    echo -e "${BLUE}Importing Grafana dashboard...${NC}"
    
    # Wait for Grafana to be ready
    echo "Waiting for Grafana to start..."
    sleep 10
    
    # Check if dashboard file exists
    if [ ! -f "$SCRIPT_DIR/monitoring/grafana/dashboards/Rippled-Dashboard.json" ]; then
        echo -e "${YELLOW}! Dashboard file not found${NC}"
        echo "Please manually import: monitoring/grafana/dashboards/Rippled-Dashboard.json"
        return
    fi
    
    # Import dashboard via API (requires Grafana to be running)
    # This is a placeholder - actual implementation would use Grafana API
    echo -e "${YELLOW}! Automatic dashboard import not yet implemented${NC}"
    echo "Please manually import dashboard:"
    echo "  1. Open http://localhost:3000"
    echo "  2. Login (admin/admin)"
    echo "  3. Go to Dashboards → Import"
    echo "  4. Upload: $SCRIPT_DIR/monitoring/grafana/dashboards/Rippled-Dashboard.json"
}

# Dashboard-only install
install_dashboard_only() {
    echo -e "${BLUE}Dashboard-only installation...${NC}"
    
    echo "To import the dashboard into your existing Grafana:"
    echo "  1. Open your Grafana instance"
    echo "  2. Navigate to Dashboards → Import"
    echo "  3. Upload: $SCRIPT_DIR/monitoring/grafana/dashboards/Rippled-Dashboard.json"
    echo "  4. Select your Prometheus datasource"
    echo "  5. Click Import"
    
    echo -e "${GREEN}✓ Dashboard file location provided${NC}"
}

# Display summary
display_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          Installation Complete!                          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ "$INSTALL_MODE" == "dashboard" ]]; then
        echo "Dashboard file: $SCRIPT_DIR/monitoring/grafana/dashboards/Rippled-Dashboard.json"
    else
        echo "Installation directory: $INSTALL_DIR"
        echo ""
        echo "Services:"
        if [[ "$INSTALL_MODE" == "full" ]]; then
            echo "  • Rippled Validator: docker ps | grep rippledvalidator"
        fi
        echo "  • Grafana: http://localhost:3000 (admin/admin)"
        echo "  • Prometheus: http://localhost:9090"
        echo ""
        echo "Commands:"
        echo "  • Check status: cd $INSTALL_DIR && docker compose ps"
        echo "  • View logs: docker logs -f <container_name>"
        if [[ "$INSTALL_MODE" == "full" ]]; then
            echo "  • Rippled info: docker exec rippledvalidator rippled server_info"
        fi
        echo ""
        echo "Uninstall:"
        echo "  sudo $SCRIPT_DIR/uninstall.sh"
    fi
    
    echo ""
    echo -e "${YELLOW}Note: Installation tracked in $TRACKER_FILE${NC}"
}

# Main installation flow
main() {
    echo "Installation Mode: $INSTALL_MODE"
    echo "Installation Directory: $INSTALL_DIR"
    if [[ "$INSTALL_MODE" != "dashboard" ]]; then
        echo "Rippled Type: $RIPPLED_TYPE"
    fi
    echo ""
    
    read -p "Continue with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    
    # Initialize tracker
    init_tracker
    
    # Check prerequisites
    check_prerequisites
    
    # Install based on mode
    case $INSTALL_MODE in
        full)
            create_directories
            install_rippled
            import_dashboard
            ;;
        monitoring)
            create_directories
            install_monitoring
            import_dashboard
            ;;
        dashboard)
            install_dashboard_only
            ;;
    esac
    
    # Display summary
    display_summary
}

# Run main
main
