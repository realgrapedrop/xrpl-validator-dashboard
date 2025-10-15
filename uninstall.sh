#!/bin/bash
# uninstall.sh
# XRPL Validator Monitor Dashboard - Surgical Uninstallation Script
# Removes all tracked components from installation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Tracker file
TRACKER_FILE=".install-tracker.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Flags
DRY_RUN=false
MONITORING_ONLY=false
RIPPLED_ONLY=false
KEEP_DATA=false

# Usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

XRPL Validator Monitor Dashboard Uninstallation Script

OPTIONS:
    --dry-run           Show what would be removed without actually removing
    --monitoring-only   Remove only monitoring components
    --rippled-only      Remove only rippled components
    --keep-data         Keep data directories (preserve ledger data)
    --help              Show this help message

EXAMPLES:
    # Full uninstall
    sudo $0

    # Preview what will be removed
    sudo $0 --dry-run

    # Remove only monitoring stack
    sudo $0 --monitoring-only

    # Remove everything but keep data
    sudo $0 --keep-data

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --monitoring-only)
            MONITORING_ONLY=true
            shift
            ;;
        --rippled-only)
            RIPPLED_ONLY=true
            shift
            ;;
        --keep-data)
            KEEP_DATA=true
            shift
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

# Check if running as root
if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" == false ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   echo "Please run: sudo $0"
   exit 1
fi

# Check if tracker exists
if [ ! -f "$TRACKER_FILE" ]; then
    echo -e "${YELLOW}Warning: Installation tracker not found${NC}"
    echo "Cannot perform tracked uninstallation."
    echo ""
    read -p "Attempt manual cleanup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    MANUAL_MODE=true
else
    MANUAL_MODE=false
fi

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════╗
║   XRPL Validator Monitor Dashboard - Uninstallation     ║
╚══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
    echo ""
fi

# Load tracker data
load_tracker() {
    if [[ "$MANUAL_MODE" == false ]]; then
        INSTALL_DIR=$(jq -r '.install_dir' "$TRACKER_FILE")
        INSTALL_MODE=$(jq -r '.install_mode' "$TRACKER_FILE")
        
        echo "Installation found:"
        echo "  Mode: $INSTALL_MODE"
        echo "  Directory: $INSTALL_DIR"
        echo "  Date: $(jq -r '.installation_date' "$TRACKER_FILE")"
        echo ""
    fi
}

# Stop Docker containers
stop_containers() {
    echo -e "${BLUE}Stopping Docker containers...${NC}"
    
    if [[ "$MANUAL_MODE" == true ]]; then
        CONTAINERS=("rippledvalidator" "prometheus" "grafana" "node_exporter" "cadvisor")
    else
        mapfile -t CONTAINERS < <(jq -r '.docker_containers[]' "$TRACKER_FILE")
    fi
    
    for container in "${CONTAINERS[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            if [[ "$DRY_RUN" == true ]]; then
                echo "[DRY RUN] Would stop container: $container"
            else
                echo "Stopping container: $container"
                docker stop "$container" 2>/dev/null || true
                docker rm "$container" 2>/dev/null || true
            fi
        fi
    done
    
    echo -e "${GREEN}✓ Containers stopped${NC}"
}

# Remove Docker volumes
remove_volumes() {
    echo -e "${BLUE}Removing Docker volumes...${NC}"
    
    if [[ "$MANUAL_MODE" == true ]]; then
        VOLUMES=$(docker volume ls -q | grep -E "rippled|prometheus|grafana" || true)
    else
        mapfile -t VOLUMES < <(jq -r '.docker_volumes[]' "$TRACKER_FILE" 2>/dev/null || echo "")
    fi
    
    if [ -n "$VOLUMES" ]; then
        for volume in $VOLUMES; do
            if docker volume ls -q | grep -q "^${volume}$"; then
                if [[ "$DRY_RUN" == true ]]; then
                    echo "[DRY RUN] Would remove volume: $volume"
                else
                    echo "Removing volume: $volume"
                    docker volume rm "$volume" 2>/dev/null || true
                fi
            fi
        done
    fi
    
    echo -e "${GREEN}✓ Volumes removed${NC}"
}

#=============================================================================
# Remove Python Monitor
#=============================================================================
remove_python_monitor() {
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}Removing Python Monitor${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
    
    local service_removed=false
    local service_name="xrpl-monitor.service"
    
    # Check if service exists
    if systemctl list-unit-files 2>/dev/null | grep -q "$service_name"; then
        
        # Stop service if running
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            if [[ "$DRY_RUN" == true ]]; then
                echo "[DRY RUN] Would stop service: $service_name"
            else
                echo -e "${BLUE}[1/4] Stopping service...${NC}"
                systemctl stop "$service_name"
                echo -e "${GREEN}  ✓ Service stopped${NC}"
            fi
        else
            echo -e "${BLUE}[1/4] Service not running${NC}"
        fi
        
        # Disable service if enabled
        if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
            if [[ "$DRY_RUN" == true ]]; then
                echo "[DRY RUN] Would disable service: $service_name"
            else
                echo -e "${BLUE}[2/4] Disabling service...${NC}"
                systemctl disable "$service_name"
                echo -e "${GREEN}  ✓ Service disabled${NC}"
            fi
        else
            echo -e "${BLUE}[2/4] Service not enabled${NC}"
        fi
        
        # Remove service file
        if [[ -f "/etc/systemd/system/$service_name" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                echo "[DRY RUN] Would remove service file: /etc/systemd/system/$service_name"
            else
                echo -e "${BLUE}[3/4] Removing service file...${NC}"
                rm -f "/etc/systemd/system/$service_name"
                systemctl daemon-reload
                systemctl reset-failed 2>/dev/null || true
                echo -e "${GREEN}  ✓ Service file removed${NC}"
                service_removed=true
            fi
        else
            echo -e "${BLUE}[3/4] Service file not found${NC}"
        fi
        
    else
        echo -e "${BLUE}[1-3/4] Service not found, skipping...${NC}"
    fi
    
    # Python source files will be removed by main uninstall loop
    echo -e "${BLUE}[4/4] Python source files...${NC}"
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would remove Python files with installation directory"
    else
        echo -e "${GREEN}  ✓ Will be removed with tracked files${NC}"
    fi
    
    echo ""
    if [[ "$DRY_RUN" == false ]]; then
        if [ "$service_removed" = true ]; then
            echo -e "${GREEN}✓ Python Monitor Service Removed${NC}"
        else
            echo -e "${GREEN}✓ Python Monitor Cleanup Complete${NC}"
        fi
    fi
    echo -e "${BLUE}==========================================${NC}"
    echo ""
}

# Stop systemd services
stop_services() {
    echo -e "${BLUE}Stopping systemd services...${NC}"
    
    # First remove Python monitor service
    remove_python_monitor
    
    # Then handle other tracked services
    if [[ "$MANUAL_MODE" == false ]]; then
        mapfile -t SERVICES < <(jq -r '.systemd_services[]' "$TRACKER_FILE" 2>/dev/null | grep -v "xrpl-monitor.service" || echo "")
        
        if [ ${#SERVICES[@]} -gt 0 ]; then
            for service in "${SERVICES[@]}"; do
                if systemctl is-active --quiet "$service" 2>/dev/null; then
                    if [[ "$DRY_RUN" == true ]]; then
                        echo "[DRY RUN] Would stop service: $service"
                    else
                        echo "Stopping service: $service"
                        systemctl stop "$service"
                        systemctl disable "$service"
                        rm -f "/etc/systemd/system/${service}"
                    fi
                fi
            done
            
            if [[ "$DRY_RUN" == false ]]; then
                systemctl daemon-reload
            fi
        fi
    fi
    
    echo -e "${GREEN}✓ Services stopped${NC}"
}

# Remove directories
remove_directories() {
    echo -e "${BLUE}Removing directories...${NC}"
    
    if [[ "$KEEP_DATA" == true ]]; then
        echo -e "${YELLOW}Keeping data directories (--keep-data flag)${NC}"
        return
    fi
    
    if [[ "$MANUAL_MODE" == true ]]; then
        read -p "Enter installation directory to remove: " INSTALL_DIR
        if [ -z "$INSTALL_DIR" ]; then
            echo "No directory specified, skipping."
            return
        fi
    fi
    
    if [ -d "$INSTALL_DIR" ]; then
        # Create backup before removal
        if [[ "$DRY_RUN" == false ]]; then
            BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
            echo "Creating backup: $BACKUP_DIR"
            
            # Backup important files only
            mkdir -p "$BACKUP_DIR"
            [ -f "$INSTALL_DIR/rippled/config/validator-keys.json" ] && \
                cp "$INSTALL_DIR/rippled/config/validator-keys.json" "$BACKUP_DIR/" 2>/dev/null || true
            [ -f "$INSTALL_DIR/rippled/config/rippled.cfg" ] && \
                cp "$INSTALL_DIR/rippled/config/rippled.cfg" "$BACKUP_DIR/" 2>/dev/null || true
            
            # Backup database if it exists
            [ -f "$INSTALL_DIR/data/monitor.db" ] && \
                cp "$INSTALL_DIR/data/monitor.db" "$BACKUP_DIR/" 2>/dev/null || true
            
            echo -e "${GREEN}✓ Backup created: $BACKUP_DIR${NC}"
        fi
        
        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY RUN] Would remove directory: $INSTALL_DIR"
            echo "[DRY RUN] Would remove Python source: $INSTALL_DIR/src"
            echo "[DRY RUN] Would remove logs: $INSTALL_DIR/logs"
            echo "[DRY RUN] Would remove data: $INSTALL_DIR/data"
        else
            echo "Removing directory: $INSTALL_DIR"
            rm -rf "$INSTALL_DIR"
        fi
    fi
    
    echo -e "${GREEN}✓ Directories removed${NC}"
}

# Remove Python dependencies (optional)
remove_python_dependencies() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Python dependencies would remain installed"
        return
    fi
    
    echo ""
    echo -e "${BLUE}Checking Python dependencies...${NC}"
    
    # Check if prometheus-client is installed
    if pip3 show prometheus-client &>/dev/null; then
        echo -e "${YELLOW}Python package 'prometheus-client' is installed${NC}"
        echo "This package may be used by other applications."
        read -p "Remove prometheus-client? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            pip3 uninstall -y prometheus-client 2>/dev/null || true
            echo -e "${GREEN}  ✓ Python dependencies removed${NC}"
        else
            echo -e "${YELLOW}  ℹ Python dependencies left intact${NC}"
        fi
    else
        echo -e "${GREEN}  ✓ No Python dependencies to remove${NC}"
    fi
}

# Verify removal
verify_removal() {
    if [[ "$DRY_RUN" == true ]]; then
        return
    fi
    
    echo ""
    echo -e "${BLUE}Verifying removal...${NC}"
    
    local all_clean=true
    
    # Check Python monitor service
    if systemctl list-unit-files 2>/dev/null | grep -q "xrpl-monitor.service"; then
        echo -e "${RED}  ✗ xrpl-monitor.service still exists${NC}"
        all_clean=false
    else
        echo -e "${GREEN}  ✓ Python monitor service removed${NC}"
    fi
    
    # Check service file
    if [[ -f "/etc/systemd/system/xrpl-monitor.service" ]]; then
        echo -e "${RED}  ✗ Service file still exists${NC}"
        all_clean=false
    else
        echo -e "${GREEN}  ✓ Service file removed${NC}"
    fi
    
    # Check if service is running
    if systemctl is-active --quiet xrpl-monitor.service 2>/dev/null; then
        echo -e "${RED}  ✗ Service still running${NC}"
        all_clean=false
    else
        echo -e "${GREEN}  ✓ Service not running${NC}"
    fi
    
    # Check installation directory
    if [ -d "$INSTALL_DIR" ] && [[ "$KEEP_DATA" == false ]]; then
        echo -e "${RED}  ✗ Installation directory still exists${NC}"
        all_clean=false
    elif [[ "$KEEP_DATA" == true ]]; then
        echo -e "${YELLOW}  ℹ Installation directory preserved (--keep-data)${NC}"
    else
        echo -e "${GREEN}  ✓ Installation directory removed${NC}"
    fi
    
    # Check Prometheus metrics endpoint
    if curl -s http://localhost:9091/metrics 2>/dev/null | grep -q "xrpl_validator_state"; then
        echo -e "${YELLOW}  ⚠ Metrics endpoint still responding${NC}"
        all_clean=false
    else
        echo -e "${GREEN}  ✓ Metrics endpoint not responding${NC}"
    fi
    
    echo ""
    if [ "$all_clean" = true ]; then
        echo -e "${GREEN}✓ Verification Complete - All Components Removed${NC}"
    else
        echo -e "${YELLOW}⚠ Verification Complete - Some Components May Remain${NC}"
        echo "  Manual cleanup may be required"
    fi
}

# Remove tracker
remove_tracker() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would remove tracker: $TRACKER_FILE"
    else
        if [ -f "$TRACKER_FILE" ]; then
            echo "Removing installation tracker..."
            rm -f "$TRACKER_FILE"
        fi
    fi
}

# Display summary
display_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${GREEN}║          Dry Run Complete - No Changes Made             ║${NC}"
    else
        echo -e "${GREEN}║          Uninstallation Complete!                       ║${NC}"
    fi
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ "$DRY_RUN" == false ]]; then
        echo "Removed components:"
        echo "  • Python monitor service"
        echo "  • Docker containers"
        echo "  • Docker volumes"
        
        if [[ "$KEEP_DATA" == false ]]; then
            echo "  • Installation directories"
            echo "  • Python source code"
            echo "  • Configuration files"
            if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
                echo ""
                echo -e "${YELLOW}Backup created: $BACKUP_DIR${NC}"
                echo "Contains validator keys, configuration, and database."
            fi
        else
            echo ""
            echo -e "${YELLOW}Data preserved: $INSTALL_DIR${NC}"
        fi
        
        echo ""
        echo "Remaining Docker images (if any):"
        echo "  docker images | grep -E 'rippled|prometheus|grafana'"
        echo ""
        echo "To remove images:"
        echo "  docker rmi <image_name>"
        echo ""
        echo "To remove Python dependencies:"
        echo "  pip3 uninstall prometheus-client"
    fi
}

# Confirmation prompt
confirm_uninstall() {
    echo -e "${YELLOW}WARNING: This will remove all installed components${NC}"
    echo "  • Python monitoring service"
    echo "  • Docker containers"
    if [[ "$KEEP_DATA" == false ]]; then
        echo -e "${RED}  • All data (ledger data, configurations, monitoring database, etc.)${NC}"
    fi
    echo ""
    
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Uninstallation cancelled."
        exit 0
    fi
    
    echo ""
}

# Main uninstallation flow
main() {
    # Load tracker
    load_tracker
    
    # Confirmation
    if [[ "$DRY_RUN" == false ]]; then
        confirm_uninstall
    fi
    
    # Execute removal steps
    stop_containers
    remove_volumes
    stop_services  # This now includes Python monitor removal
    remove_directories
    
    # Optional: Remove Python dependencies
    if [[ "$DRY_RUN" == false ]]; then
        remove_python_dependencies
    fi
    
    # Verify removal
    verify_removal
    
    # Remove tracker last
    if [[ "$DRY_RUN" == false ]]; then
        remove_tracker
    fi
    
    # Display summary
    display_summary
}

# Run main
main
