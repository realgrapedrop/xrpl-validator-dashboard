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

# Detect actual user (not root)
if [ $SUDO_USER ]; then
    ACTUAL_USER=$SUDO_USER
else
    ACTUAL_USER=$(whoami)
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
  "directories": [],
  "files": []
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
    
    # Check Python3 and pip3
    if ! command -v python3 &> /dev/null; then
        echo -e "${YELLOW}! Python3 not found, installing...${NC}"
        apt-get install -y python3 python3-pip
    else
        PYTHON_VERSION=$(python3 --version | awk '{print $2}')
        echo -e "${GREEN}✓ Python3 found: ${PYTHON_VERSION}${NC}"
    fi
    
    if ! command -v pip3 &> /dev/null; then
        echo -e "${YELLOW}! pip3 not found, installing...${NC}"
        apt-get install -y python3-pip
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
    mkdir -p "$INSTALL_DIR"/{src,logs,data}
    
    track_component "directories" "$INSTALL_DIR"
    track_component "directories" "$INSTALL_DIR/rippled"
    track_component "directories" "$INSTALL_DIR/monitoring"
    track_component "directories" "$INSTALL_DIR/src"
    track_component "directories" "$INSTALL_DIR/logs"
    track_component "directories" "$INSTALL_DIR/data"
    
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

#=============================================================================
# Install Python Monitor
#=============================================================================
install_python_monitor() {
    local install_dir="$1"
    local user="$2"
    
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}Installing Python Monitor${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
    
    # Check if src/ directory exists in repo
    if [[ ! -d "$SCRIPT_DIR/src" ]]; then
        echo -e "${RED}Error: Python source directory '$SCRIPT_DIR/src' not found${NC}"
        echo "Make sure you're running from the repo root with src/ present"
        exit 1
    fi
    
    # Install Python dependencies
    echo -e "${BLUE}[1/6] Installing Python dependencies...${NC}"
    if [[ -f "$SCRIPT_DIR/requirements.txt" ]]; then
        su - "$user" -c "pip3 install -r $SCRIPT_DIR/requirements.txt --user" 2>&1 | grep -v "Requirement already satisfied" || true
        echo -e "${GREEN}  ✓ Python dependencies installed${NC}"
    else
        echo -e "${YELLOW}  ⚠ No requirements.txt found, skipping${NC}"
    fi
    
    # Create src directory in installation
    echo ""
    echo -e "${BLUE}[2/6] Creating Python source directory...${NC}"
    mkdir -p "$install_dir/src"
    echo -e "${GREEN}  ✓ Created $install_dir/src${NC}"
    
    # Copy Python source files
    echo ""
    echo -e "${BLUE}[3/6] Copying Python source files...${NC}"
    
    # Use rsync if available, otherwise cp
    if command -v rsync &> /dev/null; then
        rsync -av --exclude='__pycache__' --exclude='*.pyc' --exclude='*.backup*' \
            "$SCRIPT_DIR/src/" "$install_dir/src/"
    else
        cp -r "$SCRIPT_DIR/src/"* "$install_dir/src/"
        # Remove __pycache__ directories
        find "$install_dir/src" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
        find "$install_dir/src" -type f -name "*.pyc" -delete 2>/dev/null || true
        find "$install_dir/src" -type f -name "*.backup*" -delete 2>/dev/null || true
    fi
    
    # Track each Python file
    find "$install_dir/src" -name "*.py" -type f | while read -r pyfile; do
        track_component "files" "$pyfile"
    done
    
    PYTHON_FILE_COUNT=$(find "$install_dir/src" -name "*.py" -type f | wc -l)
    echo -e "${GREEN}  ✓ Copied $PYTHON_FILE_COUNT Python files${NC}"
    
    # Replace ${INSTALL_DIR} placeholder with actual path
    echo ""
    echo -e "${BLUE}[4/6] Configuring installation paths...${NC}"
    find "$install_dir/src" -name "*.py" -type f -exec \
        sed -i "s|\${INSTALL_DIR}|$install_dir|g" {} \; 2>/dev/null
    echo -e "${GREEN}  ✓ Paths configured for $install_dir${NC}"
    
    # Set ownership
    chown -R "$user:$user" "$install_dir/src"
    chown -R "$user:$user" "$install_dir/logs"
    chown -R "$user:$user" "$install_dir/data"
    echo -e "${GREEN}  ✓ Ownership set to $user${NC}"
    
    # Create systemd service
    echo ""
    echo -e "${BLUE}[5/6] Creating systemd service...${NC}"
    if [[ -f "$SCRIPT_DIR/systemd/xrpl-monitor.service.template" ]]; then
        # Replace template variables
        sed -e "s|\${INSTALL_DIR}|$install_dir|g" \
            -e "s|\${USER}|$user|g" \
            "$SCRIPT_DIR/systemd/xrpl-monitor.service.template" \
            > /tmp/xrpl-monitor.service
        
        # Install service
        cp /tmp/xrpl-monitor.service /etc/systemd/system/
        track_component "systemd_services" "xrpl-monitor.service"
        
        # Reload systemd
        systemctl daemon-reload
        
        echo -e "${GREEN}  ✓ Service created: xrpl-monitor.service${NC}"
    else
        echo -e "${YELLOW}  ⚠ Service template not found at $SCRIPT_DIR/systemd/xrpl-monitor.service.template${NC}"
        echo -e "${YELLOW}  ⚠ Skipping service creation${NC}"
        return
    fi
    
    # Enable and start service
    echo ""
    echo -e "${BLUE}[6/6] Starting monitor service...${NC}"
    
    systemctl enable xrpl-monitor.service
    systemctl start xrpl-monitor.service
    
    # Wait for service to start
    sleep 3
    
    if systemctl is-active --quiet xrpl-monitor.service; then
        echo -e "${GREEN}  ✓ Service started successfully${NC}"
        
        # Show quick status
        echo ""
        echo "Service status:"
        systemctl status xrpl-monitor.service --no-pager -l | head -10
        
        # Check Prometheus metrics
        echo ""
        echo "Checking Prometheus metrics..."
        sleep 2
        if curl -s http://localhost:9091/metrics 2>/dev/null | grep -q "xrpl_validator_state"; then
            echo -e "${GREEN}  ✓ Prometheus metrics available at http://localhost:9091/metrics${NC}"
        else
            echo -e "${YELLOW}  ⚠ Prometheus metrics not yet available (may need more time)${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ Service failed to start${NC}"
        echo ""
        echo "Check logs with:"
        echo "  sudo journalctl -u xrpl-monitor.service -n 50"
        echo "  tail -f $install_dir/logs/error.log"
    fi
    
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${GREEN}Python Monitor Installation Complete${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
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
        echo "  • Python Monitor: systemctl status xrpl-monitor"
        echo "  • Grafana: http://localhost:3000 (admin/admin)"
        echo "  • Prometheus: http://localhost:9090"
        echo "  • Validator Metrics: http://localhost:9091/metrics"
        echo ""
        echo "Commands:"
        echo "  • Check status: cd $INSTALL_DIR && docker compose ps"
        echo "  • Monitor logs: sudo journalctl -u xrpl-monitor -f"
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
    echo "Installing as user: $ACTUAL_USER"
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
            install_python_monitor "$INSTALL_DIR" "$ACTUAL_USER"
            import_dashboard
            ;;
        monitoring)
            create_directories
            install_monitoring
            install_python_monitor "$INSTALL_DIR" "$ACTUAL_USER"
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
