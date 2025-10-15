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

# Stop systemd services
stop_services() {
    echo -e "${BLUE}Stopping systemd services...${NC}"
    
    if [[ "$MANUAL_MODE" == false ]]; then
        mapfile -t SERVICES < <(jq -r '.systemd_services[]' "$TRACKER_FILE" 2>/dev/null || echo "")
        
        for service in "${SERVICES[@]}"; do
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                if [[ "$DRY_RUN" == true ]]; then
                    echo "[DRY RUN] Would stop service: $service"
                else
                    echo "Stopping service: $service"
                    systemctl stop "$service"
                    systemctl disable "$service"
                    rm -f "/etc/systemd/system/${service}.service"
                fi
            fi
        done
        
        if [[ "$DRY_RUN" == false ]] && [ ${#SERVICES[@]} -gt 0 ]; then
            systemctl daemon-reload
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
            
            echo -e "${GREEN}✓ Backup created: $BACKUP_DIR${NC}"
        fi
        
        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY RUN] Would remove directory: $INSTALL_DIR"
        else
            echo "Removing directory: $INSTALL_DIR"
            rm -rf "$INSTALL_DIR"
        fi
    fi
    
    echo -e "${GREEN}✓ Directories removed${NC}"
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
        echo "  • Docker containers"
        echo "  • Docker volumes"
        
        if [[ "$KEEP_DATA" == false ]]; then
            echo "  • Installation directories"
            if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
                echo ""
                echo -e "${YELLOW}Backup created: $BACKUP_DIR${NC}"
                echo "Contains validator keys and configuration."
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
    fi
}

# Confirmation prompt
confirm_uninstall() {
    echo -e "${YELLOW}WARNING: This will remove all installed components${NC}"
    if [[ "$KEEP_DATA" == false ]]; then
        echo -e "${RED}All data will be deleted (ledger data, configurations, etc.)${NC}"
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
    stop_services
    remove_directories
    
    # Remove tracker last
    if [[ "$DRY_RUN" == false ]]; then
        remove_tracker
    fi
    
    # Display summary
    display_summary
}

# Run main
main
