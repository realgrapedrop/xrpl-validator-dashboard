#!/bin/bash
#
# XRPL Validator Dashboard v3.0 - Uninstall Script
# Interactive uninstaller with component scanning and selection
#
# Version: 3.0.0
# Last Updated: 2025-11-18
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Clear screen helper
clear_screen() {
    clear
    echo -e "${BLUE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║           XRPL Monitor v3.0 - Uninstall Wizard                ║
║          Remove monitoring stack components safely            ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Print functions
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}━━━ $1 ━━━${NC}"
    echo ""
}

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "" 1>&2
    echo "Error: This script must be run with root privileges." 1>&2
    echo "" 1>&2
    echo "Please run the uninstaller with sudo:" 1>&2
    echo "  sudo ./uninstall.sh" 1>&2
    echo "" 1>&2
    exit 1
fi

# Component tracking arrays
FOUND_CONTAINERS=()
FOUND_VOLUMES=()
FOUND_NETWORKS=()
FOUND_FILES=()
DOCKER_INSTALLED=false
DOCKER_COMPOSE_INSTALLED=false

# Removal selection (all true by default)
REMOVE_CONTAINERS=true
REMOVE_VOLUMES=true
REMOVE_NETWORKS=true
REMOVE_FILES=true
REMOVE_DOCKER=false

# ============================================================================
# PHASE 1: Scan system for installed components
# ============================================================================
scan_system() {
    print_header "Scanning System"

    # Check for Docker
    if command -v docker &> /dev/null; then
        DOCKER_INSTALLED=true
        print_success "Docker is installed ($(docker --version | cut -d' ' -f3 | tr -d ','))"
    else
        print_info "Docker is not installed"
    fi

    # Check for Docker Compose
    if command -v docker compose &> /dev/null || command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_INSTALLED=true
        COMPOSE_VERSION=$(docker compose version 2>/dev/null | cut -d' ' -f4 || docker-compose --version | cut -d' ' -f3 | tr -d ',')
        print_success "Docker Compose is installed ($COMPOSE_VERSION)"
    else
        print_info "Docker Compose is not installed"
    fi

    if ! $DOCKER_INSTALLED; then
        echo ""
        print_warning "Docker is not installed. Nothing to uninstall."
        return 1
    fi

    echo ""
    print_info "Scanning for dashboard components..."
    echo ""

    # Scan containers dynamically (find all containers with xrpl-monitor prefix)
    while IFS= read -r container; do
        if [ -n "$container" ]; then
            STATUS=$(docker ps -a --filter "name=${container}" --format "{{.Status}}")
            FOUND_CONTAINERS+=("$container|$STATUS")
        fi
    done < <(docker ps -a --format '{{.Names}}' 2>/dev/null | grep "^xrpl-monitor-" || true)

    if [ ${#FOUND_CONTAINERS[@]} -gt 0 ]; then
        print_success "Found ${#FOUND_CONTAINERS[@]} container(s)"
    else
        print_info "No containers found"
    fi

    # Scan volumes dynamically (find all volumes with xrpl-monitor prefix)
    while IFS= read -r volume; do
        if [ -n "$volume" ]; then
            SIZE=$(docker volume inspect "$volume" --format '{{.Mountpoint}}' 2>/dev/null | xargs du -sh 2>/dev/null | cut -f1 || echo "unknown")
            FOUND_VOLUMES+=("$volume|$SIZE")
        fi
    done < <(docker volume ls --format '{{.Name}}' 2>/dev/null | grep "^xrpl-monitor-" || true)

    if [ ${#FOUND_VOLUMES[@]} -gt 0 ]; then
        print_success "Found ${#FOUND_VOLUMES[@]} volume(s)"
    else
        print_info "No volumes found"
    fi

    # Scan network
    if docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "^xrpl-monitor-network$"; then
        FOUND_NETWORKS+=("xrpl-monitor-network")
        print_success "Found network: xrpl-monitor-network"
    else
        print_info "No network found"
    fi

    # Scan files
    if [ -f ".env" ]; then
        FOUND_FILES+=(".env file")
    fi

    if [ -d "logs" ] && [ "$(ls -A logs 2>/dev/null)" ]; then
        LOG_SIZE=$(du -sh logs 2>/dev/null | cut -f1 || echo "unknown")
        FOUND_FILES+=("logs directory ($LOG_SIZE)")
    fi

    if ls /tmp/xrpl-monitor-install-*.log 1> /dev/null 2>&1; then
        LOG_COUNT=$(ls /tmp/xrpl-monitor-install-*.log 2>/dev/null | wc -l)
        FOUND_FILES+=("$LOG_COUNT installation log(s)")
    fi

    if [ -f "config/grafana/provisioning/dashboards/xrpl-validator-main.json" ]; then
        FOUND_FILES+=("generated dashboard (xrpl-validator-main.json)")
    fi

    # Check if config files have been modified from defaults (ports changed)
    if [ -f "docker-compose.yml" ]; then
        # Check if any non-default ports are configured
        if grep -q "GF_SERVER_HTTP_PORT=" docker-compose.yml && ! grep -q "GF_SERVER_HTTP_PORT=3000" docker-compose.yml; then
            FOUND_FILES+=("modified port configs (will reset to defaults)")
        fi
    fi

    if [ ${#FOUND_FILES[@]} -gt 0 ]; then
        print_success "Found ${#FOUND_FILES[@]} file/directory item(s)"
    else
        print_info "No files to clean up"
    fi

    return 0
}

# ============================================================================
# PHASE 2: Show what will be removed and get confirmation
# ============================================================================
review_and_confirm() {
    clear_screen
    print_header "Review Components"

    # Check if anything was found
    TOTAL_ITEMS=$((${#FOUND_CONTAINERS[@]} + ${#FOUND_VOLUMES[@]} + ${#FOUND_NETWORKS[@]} + ${#FOUND_FILES[@]}))

    if [ $TOTAL_ITEMS -eq 0 ]; then
        print_info "No dashboard components found on this system."
        echo ""
        echo "The monitoring stack appears to be already uninstalled."
        echo ""

        # Show what IS installed (Docker/Compose) and offer to remove
        if $DOCKER_INSTALLED || $DOCKER_COMPOSE_INSTALLED; then
            echo -e "${CYAN}What is still installed:${NC}"
            if $DOCKER_INSTALLED; then
                echo "  • Docker $(docker --version | cut -d' ' -f3 | tr -d ',')"
            fi
            if $DOCKER_COMPOSE_INSTALLED; then
                COMPOSE_VERSION=$(docker compose version 2>/dev/null | cut -d' ' -f4 || docker-compose --version | cut -d' ' -f3 | tr -d ',')
                echo "  • Docker Compose $COMPOSE_VERSION"
            fi
            echo ""
            echo -e "${YELLOW}Note:${NC} Docker and Docker Compose may be used by other applications."
            echo ""
            echo "Options:"
            echo "  [Enter] Exit without removing Docker"
            echo "  [r]     Remove Docker and Docker Compose"
            echo "  [q]     Quit"
            echo ""
            read -p "Choose: " docker_choice </dev/tty || docker_choice=""
            echo

            case "$docker_choice" in
                r|R)
                    # Set flag and call remove_components which handles Docker removal
                    REMOVE_DOCKER=true
                    remove_components

                    # Verify Docker was removed
                    echo ""
                    print_header "Verification"
                    if command -v docker &> /dev/null; then
                        print_warning "Docker command still found in PATH"
                        echo "  You may need to log out and back in, or run: hash -r"
                    else
                        print_success "Docker and Docker Compose successfully removed"
                    fi
                    echo ""
                    read -p "Press Enter to exit..." </dev/tty
                    exit 0
                    ;;
                q|Q)
                    print_info "Uninstall cancelled"
                    exit 0
                    ;;
                *)
                    print_info "Docker and Docker Compose kept installed"
                    exit 0
                    ;;
            esac
        else
            # Nothing installed at all
            read -p "Press Enter to exit..." </dev/tty
            exit 0
        fi
    fi

    echo "The following components will be removed:"
    echo ""

    # Show containers
    if [ ${#FOUND_CONTAINERS[@]} -gt 0 ]; then
        echo -e "${YELLOW}Docker Containers (${#FOUND_CONTAINERS[@]}):${NC}"
        for item in "${FOUND_CONTAINERS[@]}"; do
            name=$(echo "$item" | cut -d'|' -f1)
            status=$(echo "$item" | cut -d'|' -f2)
            echo "  • $name ($status)"
        done
        echo ""
    fi

    # Show volumes
    if [ ${#FOUND_VOLUMES[@]} -gt 0 ]; then
        echo -e "${YELLOW}Docker Volumes (${#FOUND_VOLUMES[@]}) - ALL DATA WILL BE LOST:${NC}"
        for item in "${FOUND_VOLUMES[@]}"; do
            name=$(echo "$item" | cut -d'|' -f1)
            size=$(echo "$item" | cut -d'|' -f2)
            echo "  • $name ($size)"
        done
        echo ""
    fi

    # Show network
    if [ ${#FOUND_NETWORKS[@]} -gt 0 ]; then
        echo -e "${YELLOW}Docker Networks:${NC}"
        for network in "${FOUND_NETWORKS[@]}"; do
            echo "  • $network"
        done
        echo ""
    fi

    # Show files
    if [ ${#FOUND_FILES[@]} -gt 0 ]; then
        echo -e "${YELLOW}Files & Directories:${NC}"
        for file in "${FOUND_FILES[@]}"; do
            echo "  • $file"
        done
        echo ""
    fi

    # Show Docker/Compose status
    if $DOCKER_INSTALLED || $DOCKER_COMPOSE_INSTALLED; then
        echo -e "${YELLOW}Optional - Can Also Be Removed:${NC}"
        if $DOCKER_INSTALLED; then
            echo "  • Docker ($(docker --version | cut -d' ' -f3 | tr -d ','))"
        fi
        if $DOCKER_COMPOSE_INSTALLED; then
            COMPOSE_VERSION=$(docker compose version 2>/dev/null | cut -d' ' -f4 || docker-compose --version | cut -d' ' -f3 | tr -d ',')
            echo "  • Docker Compose ($COMPOSE_VERSION)"
        fi
        echo ""
    fi

    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}What will NOT be removed:${NC}"
    echo "  • This project directory (${PWD})"
    echo "  • rippled installation (not managed by installer)"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Options:"
    echo "  [Enter] Continue to select components"
    echo "  [a]     Remove ALL components (quick uninstall)"
    echo "  [q]     Cancel and exit"
    echo ""
    read -p "Choose: " choice </dev/tty || choice=""
    echo

    case $choice in
        q|Q)
            print_info "Uninstall cancelled"
            exit 0
            ;;
        a|A)
            # Confirm complete removal
            while true; do
                echo ""
                echo -e "${YELLOW}⚠️  WARNING: This will remove ALL components including data!${NC}"
                echo ""
                echo "This action will:"
                echo "  • Stop and remove all ${#FOUND_CONTAINERS[@]} containers"
                echo "  • Delete all ${#FOUND_VOLUMES[@]} volumes (dashboards, metrics, state)"
                echo "  • Remove network and configuration files"
                echo "  • Clean up all installation logs"
                echo ""
                echo -e "${RED}ALL MONITORING DATA WILL BE PERMANENTLY LOST${NC}"
                echo ""
                echo "Options:"
                echo "  Type 'yes' to confirm complete removal"
                echo "  Type 'b' to go back"
                echo "  Type 'q' to quit"
                echo ""
                read -p "Choose: " confirm </dev/tty
                echo

                case "$confirm" in
                    yes)
                        # Select all components for removal
                        CONTAINERS_TO_REMOVE=("${FOUND_CONTAINERS[@]%%|*}")
                        VOLUMES_TO_REMOVE=("${FOUND_VOLUMES[@]%%|*}")
                        REMOVE_NETWORKS=true
                        REMOVE_FILES=true

                        # Populate FILES_TO_REMOVE with actual file paths
                        FILES_TO_REMOVE=()
                        [ -f ".env" ] && FILES_TO_REMOVE+=(".env")
                        [ -d "logs" ] && FILES_TO_REMOVE+=("logs")
                        if ls /tmp/xrpl-monitor-install-*.log 1> /dev/null 2>&1; then
                            FILES_TO_REMOVE+=(/tmp/xrpl-monitor-install-*.log)
                        fi
                        [ -f "config/grafana/provisioning/dashboards/xrpl-validator-main.json" ] && FILES_TO_REMOVE+=("config/grafana/provisioning/dashboards/xrpl-validator-main.json")

                        # Ask about Docker/Compose if installed
                        REMOVE_DOCKER=false
                        if $DOCKER_INSTALLED || $DOCKER_COMPOSE_INSTALLED; then
                            echo ""
                            echo -e "${CYAN}Docker & Docker Compose:${NC}"
                            if $DOCKER_INSTALLED; then
                                DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
                                echo "  • Docker $DOCKER_VERSION (installed)"
                            fi
                            if $DOCKER_COMPOSE_INSTALLED; then
                                echo "  • Docker Compose $COMPOSE_VERSION (installed)"
                            fi
                            echo ""
                            echo -e "${YELLOW}Note: These may be used by other applications${NC}"
                            echo ""
                            read -p "Also remove Docker & Docker Compose? (yes/no): " docker_confirm </dev/tty
                            echo

                            if [ "$docker_confirm" = "yes" ]; then
                                REMOVE_DOCKER=true
                                print_info "Docker & Docker Compose will be removed"
                            else
                                print_info "Docker & Docker Compose will be kept"
                            fi
                        fi

                        print_info "Proceeding with complete removal..."
                        remove_components
                        verify_removal
                        show_completion
                        exit 0
                        ;;
                    b|B)
                        print_info "Returning to component review..."
                        review_and_confirm
                        return
                        ;;
                    q|Q)
                        print_info "Uninstall cancelled"
                        exit 0
                        ;;
                    *)
                        echo -e "${YELLOW}Invalid input: '$confirm'${NC}"
                        echo "You must type exactly 'yes' to confirm, 'b' to go back, or 'q' to quit."
                        echo ""
                        read -p "Press Enter to try again..." </dev/tty
                        ;;
                esac
            done
            ;;
        *)
            # Enter customize mode
            customize_removal
            ;;
    esac
}

# Helper function to check for quit
check_quit() {
    local response="$1"
    # Convert to lowercase for case-insensitive comparison
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)
    if [ "$response" = "quit" ] || [ "$response" = "q" ]; then
        echo ""
        print_info "Uninstall cancelled by user"
        exit 0
    fi
}

# Helper function to get valid yes/no/quit response (default: yes)
# Returns: "yes", "no", or "quit"
get_yes_no_quit() {
    local prompt="$1"
    local response
    while true; do
        read -p "$prompt" response </dev/tty
        # Trim whitespace and convert to lowercase for comparison
        response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)

        # Empty input defaults to "yes"
        if [ -z "$response" ]; then
            response="yes"
        fi

        # Check for quit - return "quit" so caller can handle it
        if [ "$response" = "quit" ] || [ "$response" = "q" ]; then
            echo "quit"
            return 0
        fi

        # Check for valid yes/no
        if [ "$response" = "yes" ] || [ "$response" = "y" ]; then
            echo "yes"
            return 0
        elif [ "$response" = "no" ] || [ "$response" = "n" ]; then
            echo "no"
            return 0
        else
            echo -e "    ${RED}Invalid input. Please type 'yes', 'no', or 'quit' (default: yes)${NC}" >/dev/tty
        fi
    done
}

# Helper function to handle quit from get_yes_no_quit
handle_quit_choice() {
    local choice="$1"
    if [ "$choice" = "quit" ]; then
        echo "" >/dev/tty
        print_info "Uninstall cancelled by user"
        exit 0
    fi
}

# ============================================================================
# CUSTOMIZE MODE: Step-by-step selection
# ============================================================================
customize_removal() {
    clear_screen
    print_header "Customize Removal"

    echo "Select which components to remove:"
    echo -e "${YELLOW}Tip: Type 'quit' or 'q' at any prompt to exit${NC}"
    echo ""

    # Track which specific items to remove
    CONTAINERS_TO_REMOVE=()
    VOLUMES_TO_REMOVE=()
    FILES_TO_REMOVE=()

    # Individual Containers
    if [ ${#FOUND_CONTAINERS[@]} -gt 0 ]; then
        echo -e "${CYAN}Docker Containers:${NC}"
        for item in "${FOUND_CONTAINERS[@]}"; do
            name=$(echo "$item" | cut -d'|' -f1)
            status=$(echo "$item" | cut -d'|' -f2)
            choice=$(get_yes_no_quit "  Remove $name ($status)? (YES/no/quit): ")
            handle_quit_choice "$choice"
            if [ "$choice" = "yes" ]; then
                CONTAINERS_TO_REMOVE+=("$name")
                echo -e "    ${GREEN}✓${NC} Will remove" >/dev/tty
            else
                echo -e "    ${BLUE}ℹ${NC} Will keep" >/dev/tty
            fi
        done
        echo ""
    fi

    # Individual Volumes
    if [ ${#FOUND_VOLUMES[@]} -gt 0 ]; then
        echo -e "${CYAN}Docker Volumes:${NC}"
        echo -e "${RED}Warning: Removing volumes will delete all data!${NC}"
        for item in "${FOUND_VOLUMES[@]}"; do
            name=$(echo "$item" | cut -d'|' -f1)
            size=$(echo "$item" | cut -d'|' -f2)
            choice=$(get_yes_no_quit "  Remove $name ($size)? (YES/no/quit): ")
            handle_quit_choice "$choice"
            if [ "$choice" = "yes" ]; then
                VOLUMES_TO_REMOVE+=("$name")
                echo -e "    ${GREEN}✓${NC} Will remove" >/dev/tty
            else
                echo -e "    ${BLUE}ℹ${NC} Will keep" >/dev/tty
            fi
        done
        echo ""
    fi

    # Network
    if [ ${#FOUND_NETWORKS[@]} -gt 0 ]; then
        echo -e "${CYAN}Docker Network:${NC}"
        choice=$(get_yes_no_quit "  Remove xrpl-monitor-network? (YES/no/quit): ")
        handle_quit_choice "$choice"
        if [ "$choice" = "yes" ]; then
            REMOVE_NETWORKS=true
            echo -e "    ${GREEN}✓${NC} Will remove" >/dev/tty
        else
            REMOVE_NETWORKS=false
            echo -e "    ${BLUE}ℹ${NC} Will keep" >/dev/tty
        fi
        echo ""
    fi

    # Files
    if [ ${#FOUND_FILES[@]} -gt 0 ]; then
        echo -e "${CYAN}Configuration Files:${NC}"
        for file in "${FOUND_FILES[@]}"; do
            choice=$(get_yes_no_quit "  Remove $file? (YES/no/quit): ")
            handle_quit_choice "$choice"
            if [ "$choice" = "yes" ]; then
                FILES_TO_REMOVE+=("$file")
                echo -e "    ${GREEN}✓${NC} Will remove" >/dev/tty
            else
                echo -e "    ${BLUE}ℹ${NC} Will keep" >/dev/tty
            fi
        done
        echo ""
    fi

    # Docker itself (last option)
    if $DOCKER_INSTALLED || $DOCKER_COMPOSE_INSTALLED; then
        echo -e "${CYAN}${BOLD}Optional: Docker Software${NC}"
        echo "Docker is used to run containers. Only remove if you don't need it."
        if $DOCKER_INSTALLED; then
            choice=$(get_yes_no_quit "  Remove Docker? (YES/no/quit): ")
            handle_quit_choice "$choice"
            if [ "$choice" = "yes" ]; then
                REMOVE_DOCKER=true
                echo -e "    ${YELLOW}⚠${NC} Will remove Docker" >/dev/tty
            else
                echo -e "    ${BLUE}ℹ${NC} Will keep Docker" >/dev/tty
            fi
        fi
        if $DOCKER_COMPOSE_INSTALLED; then
            choice=$(get_yes_no_quit "  Remove Docker Compose? (YES/no/quit): ")
            handle_quit_choice "$choice"
            if [ "$choice" = "yes" ]; then
                REMOVE_DOCKER=true
                echo -e "    ${YELLOW}⚠${NC} Will remove Docker Compose" >/dev/tty
            else
                echo -e "    ${BLUE}ℹ${NC} Will keep Docker Compose" >/dev/tty
            fi
        fi
        echo ""
    fi

    # Update global flags based on selections
    if [ ${#CONTAINERS_TO_REMOVE[@]} -gt 0 ]; then
        REMOVE_CONTAINERS=true
    else
        REMOVE_CONTAINERS=false
    fi

    if [ ${#VOLUMES_TO_REMOVE[@]} -gt 0 ]; then
        REMOVE_VOLUMES=true
    else
        REMOVE_VOLUMES=false
    fi

    if [ ${#FILES_TO_REMOVE[@]} -gt 0 ]; then
        REMOVE_FILES=true
    else
        REMOVE_FILES=false
    fi

    # Summary
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Summary of what will be removed:"
    echo ""

    if [ ${#CONTAINERS_TO_REMOVE[@]} -gt 0 ]; then
        echo "  Containers:"
        for container in "${CONTAINERS_TO_REMOVE[@]}"; do
            echo "    • $container"
        done
    fi

    if [ ${#VOLUMES_TO_REMOVE[@]} -gt 0 ]; then
        echo "  Volumes:"
        for item in "${VOLUMES_TO_REMOVE[@]}"; do
            echo "    • $item"
        done
    fi

    $REMOVE_NETWORKS && echo "  Network: xrpl-monitor-network"

    if [ ${#FILES_TO_REMOVE[@]} -gt 0 ]; then
        echo "  Files:"
        for file in "${FILES_TO_REMOVE[@]}"; do
            echo "    • $file"
        done
    fi

    $REMOVE_DOCKER && echo "  Docker & Docker Compose"
    echo ""

    if ! $REMOVE_CONTAINERS && ! $REMOVE_VOLUMES && ! $REMOVE_NETWORKS && ! $REMOVE_FILES && ! $REMOVE_DOCKER; then
        print_info "Nothing selected for removal."
        echo ""
        read -p "Press Enter to exit..." </dev/tty
        exit 0
    fi

    read -p "Proceed with removal? Type 'yes' to confirm (or 'quit' to cancel): " confirm </dev/tty
    check_quit "$confirm"
    if [ "$confirm" != "yes" ]; then
        print_info "Uninstall cancelled"
        exit 0
    fi
}

# ============================================================================
# Reset config files to defaults for clean reinstall
# ============================================================================
reset_config_files_to_defaults() {
    print_info "Resetting configuration files to defaults..."
    echo ""

    # Remove .env file (will be regenerated on install)
    if [ -f ".env" ]; then
        rm -f .env
        echo -e "  ${GREEN}✓${NC} Removed .env file"
    fi

    # Reset docker-compose.yml ports to defaults using git
    if [ -f "docker-compose.yml" ]; then
        if command -v git &> /dev/null && [ -d ".git" ]; then
            # Use git to restore docker-compose.yml to its committed state
            git checkout -- docker-compose.yml 2>/dev/null && \
                echo -e "  ${GREEN}✓${NC} Reset docker-compose.yml to defaults" || \
                echo -e "  ${YELLOW}⚠${NC} Could not reset docker-compose.yml (may not be in git)"
        else
            # Manual reset of key port settings to defaults (when git not available)
            # Default ports:
            # Grafana=3000, VictoriaMetrics=8428, vmagent=8427, NodeExporter=9100, UptimeExporter=9101, StateExporter=9102
            sed -i "s/GF_SERVER_HTTP_PORT=[0-9]*/GF_SERVER_HTTP_PORT=3000/" docker-compose.yml
            sed -i 's/- "[0-9]*:[0-9]*"/- "8428:8428"/' docker-compose.yml
            sed -i "s/--httpListenAddr=:[0-9]*/--httpListenAddr=:8428/" docker-compose.yml
            sed -i "s/--web.listen-address=:[0-9]*/--web.listen-address=:9100/" docker-compose.yml
            # Reset uptime-exporter port
            sed -i "/uptime-exporter/,/state-exporter/{s/EXPORTER_PORT=[0-9]*/EXPORTER_PORT=9101/}" docker-compose.yml
            # Reset state-exporter port
            sed -i "/state-exporter/,/vmagent:/{s/EXPORTER_PORT=[0-9]*/EXPORTER_PORT=9102/}" docker-compose.yml
            # Reset healthcheck URLs
            sed -i "/node-exporter/,/uptime-exporter/{s|http://localhost:[0-9]*/metrics|http://localhost:9100/metrics|}" docker-compose.yml
            sed -i "/uptime-exporter/,/state-exporter/{s|http://localhost:[0-9]*/metrics|http://localhost:9101/metrics|}" docker-compose.yml
            sed -i "/state-exporter/,/vmagent:/{s|http://localhost:[0-9]*/metrics|http://localhost:9102/metrics|}" docker-compose.yml
            # Reset vmagent remoteWrite URL and httpListenAddr
            sed -i "s|-remoteWrite.url=http://localhost:[0-9]*/api/v1/write|-remoteWrite.url=http://localhost:8428/api/v1/write|" docker-compose.yml
            sed -i "/vmagent:/,/autoheal:/{s/-httpListenAddr=:[0-9]*/-httpListenAddr=:8427/}" docker-compose.yml
            echo -e "  ${GREEN}✓${NC} Reset docker-compose.yml ports to defaults"
        fi
    fi

    # Reset scrape.yml to defaults
    if [ -f "config/vmagent/scrape.yml" ]; then
        if command -v git &> /dev/null && [ -d ".git" ]; then
            git checkout -- config/vmagent/scrape.yml 2>/dev/null && \
                echo -e "  ${GREEN}✓${NC} Reset scrape.yml to defaults" || \
                echo -e "  ${YELLOW}⚠${NC} Could not reset scrape.yml (may not be in git)"
        else
            # Manual reset using job_name context
            sed -i "/job_name: 'node-exporter'/,/job_name:/{s|targets: \['localhost:[0-9]*'\]|targets: ['localhost:9100']|}" config/vmagent/scrape.yml
            sed -i "/job_name: 'uptime-exporter'/,/job_name:/{s|targets: \['localhost:[0-9]*'\]|targets: ['localhost:9101']|}" config/vmagent/scrape.yml
            sed -i "/job_name: 'state-exporter'/,\$s|targets: \['localhost:[0-9]*'\]|targets: ['localhost:9102']|" config/vmagent/scrape.yml
            echo -e "  ${GREEN}✓${NC} Reset scrape.yml ports to defaults"
        fi
    fi

    # Reset datasource.yml to defaults
    if [ -f "config/grafana/provisioning/datasources/datasource.yml" ]; then
        if command -v git &> /dev/null && [ -d ".git" ]; then
            git checkout -- config/grafana/provisioning/datasources/datasource.yml 2>/dev/null && \
                echo -e "  ${GREEN}✓${NC} Reset datasource.yml to defaults" || \
                echo -e "  ${YELLOW}⚠${NC} Could not reset datasource.yml (may not be in git)"
        else
            # Manual reset using name context
            sed -i "/name: VictoriaMetrics/,/name:/{s|url: http://localhost:[0-9]*|url: http://localhost:8428|}" config/grafana/provisioning/datasources/datasource.yml
            sed -i "/name: StateExporter/,/editable:/{s|url: http://localhost:[0-9]*|url: http://localhost:9102|}" config/grafana/provisioning/datasources/datasource.yml
            echo -e "  ${GREEN}✓${NC} Reset datasource.yml ports to defaults"
        fi
    fi

    # Remove generated dashboard (will be regenerated from template)
    if [ -f "config/grafana/provisioning/dashboards/xrpl-validator-main.json" ]; then
        rm -f config/grafana/provisioning/dashboards/xrpl-validator-main.json
        echo -e "  ${GREEN}✓${NC} Removed generated dashboard (will regenerate from template)"
    fi

    # Remove docker-compose.yml.backup if it exists
    if [ -f "docker-compose.yml.backup" ]; then
        rm -f docker-compose.yml.backup
        echo -e "  ${GREEN}✓${NC} Removed docker-compose.yml.backup"
    fi

    echo ""
    print_success "Configuration files reset to defaults"
}

# ============================================================================
# PHASE 3: Remove selected components
# ============================================================================
remove_components() {
    clear_screen
    print_header "Removing Components"

    # Remove containers
    if [ ${#CONTAINERS_TO_REMOVE[@]} -gt 0 ]; then
        print_info "Stopping and removing containers..."
        echo ""

        # Try docker compose down first if removing all containers
        if [ ${#CONTAINERS_TO_REMOVE[@]} -eq ${#FOUND_CONTAINERS[@]} ] && [ -f "docker-compose.yml" ]; then
            docker compose down 2>/dev/null || true
        fi

        # Remove selected containers
        for container in "${CONTAINERS_TO_REMOVE[@]}"; do
            echo -n "  Removing $container... "
            if docker rm -f "$container" 2>/dev/null; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${YELLOW}skipped${NC}"
            fi
        done

        echo ""
        print_success "Containers removed"
    fi

    # Remove volumes
    if [ ${#VOLUMES_TO_REMOVE[@]} -gt 0 ]; then
        print_info "Removing volumes (this may take a moment)..."
        echo ""

        for volume in "${VOLUMES_TO_REMOVE[@]}"; do
            echo -n "  Removing $volume... "
            if docker volume rm "$volume" 2>/dev/null; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${YELLOW}skipped${NC}"
            fi
        done

        echo ""
        print_success "Volumes removed"
    fi

    # Remove network
    if $REMOVE_NETWORKS && [ ${#FOUND_NETWORKS[@]} -gt 0 ]; then
        print_info "Removing network..."

        if docker network rm xrpl-monitor-network 2>/dev/null; then
            print_success "Network removed"
        else
            print_warning "Network removal skipped (may be in use)"
        fi
        echo ""
    fi

    # Remove files
    if [ ${#FILES_TO_REMOVE[@]} -gt 0 ]; then
        print_info "Cleaning up files..."
        echo ""

        for file in "${FILES_TO_REMOVE[@]}"; do
            echo -n "  Removing $file... "
            if rm -rf "$file" 2>/dev/null; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${YELLOW}skipped${NC}"
            fi
        done

        echo ""
        print_success "File cleanup complete"
    fi

    # Always reset config files to defaults for clean reinstall
    reset_config_files_to_defaults

    # Remove Docker (last step)
    if $REMOVE_DOCKER; then
        echo ""
        print_info "Removing Docker and Docker Compose..."
        echo ""

        # Final confirmation loop
        while true; do
            # Final warning
            echo -e "${RED}${BOLD}FINAL WARNING:${NC} This will remove Docker from your system."
            echo "Any other Docker containers and images will also be affected!"
            echo ""
            echo "Options:"
            echo "  Type 'REMOVE DOCKER' to confirm and proceed"
            echo "  Type 'skip' to keep Docker installed"
            echo "  Type 'q' to quit"
            echo ""
            read -p "Choose: " final_confirm </dev/tty
            echo

            case "$final_confirm" in
                "REMOVE DOCKER")
            echo ""
            print_info "Uninstalling Docker..."
            echo ""

            # Purge Docker packages
            print_info "Removing Docker packages..."
            if apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin 2>&1 | tee /tmp/docker-uninstall.log | grep -E "Removing|Purging"; then
                print_success "Docker packages removed"
            else
                print_warning "No Docker packages found or removal incomplete"
                echo "  (Check /tmp/docker-uninstall.log for details)"
            fi

            # Remove Docker directories
            echo ""
            print_info "Removing Docker data directories..."
            rm -rf /var/lib/docker /var/lib/containerd 2>/dev/null || true
            print_success "Docker data directories removed"

            # Autoremove
            echo ""
            print_info "Cleaning up dependencies..."
            apt-get autoremove -y >/dev/null 2>&1 || true
            print_success "Cleanup complete"

            echo ""
            print_success "Docker and Docker Compose removed"

                    # Verify removal
                    if command -v docker &> /dev/null; then
                        print_warning "Warning: docker command still found in PATH"
                        echo "  You may need to log out and back in, or run: hash -r"
                    fi
                    break
                    ;;
                skip|SKIP)
                    print_info "Docker removal skipped - keeping Docker installed"
                    break
                    ;;
                q|Q)
                    print_info "Uninstall cancelled"
                    exit 0
                    ;;
                *)
                    echo -e "${YELLOW}Invalid input: '$final_confirm'${NC}"
                    echo "You must type exactly 'REMOVE DOCKER' to confirm, 'skip' to keep Docker, or 'q' to quit."
                    echo ""
                    read -p "Press Enter to try again..." </dev/tty
                    echo ""
                    ;;
            esac
        done
    fi
}

# ============================================================================
# Verification and completion
# ============================================================================
verify_removal() {
    echo ""
    print_header "Verification"

    if ! $DOCKER_INSTALLED; then
        print_success "Uninstall complete (Docker not present)"
        return
    fi

    # Check if anything remains
    remaining_containers=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -c "^xrpl-monitor-" || true)
    remaining_volumes=$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -c "^xrpl-monitor-" || true)
    remaining_networks=$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -c "^xrpl-monitor-" || true)

    if [ "$remaining_containers" -eq 0 ] && [ "$remaining_volumes" -eq 0 ] && [ "$remaining_networks" -eq 0 ]; then
        print_success "All monitoring stack components removed successfully"
    else
        print_warning "Some components may still exist:"
        [ "$remaining_containers" -gt 0 ] && echo "  • Containers: $remaining_containers"
        [ "$remaining_volumes" -gt 0 ] && echo "  • Volumes: $remaining_volumes"
        [ "$remaining_networks" -gt 0 ] && echo "  • Networks: $remaining_networks"
        echo ""
        echo "You may need to remove these manually with:"
        echo "  docker ps -a | grep xrpl-monitor"
        echo "  docker volume ls | grep xrpl-monitor"
    fi
}

show_completion() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}${BOLD}Uninstall Complete!${NC}"
    echo ""
    print_info "What was cleaned up:"
    echo "  • All xrpl-monitor containers and volumes"
    echo "  • .env configuration file"
    echo "  • Config files reset to default ports"
    echo ""
    print_info "What remains on your system:"
    echo "  • Docker & Docker Compose (not removed)"
    echo "  • This project directory: ${PWD}"
    echo "  • rippled installation (not managed by installer)"
    echo ""
    print_info "Ready for clean reinstall:"
    echo "  sudo ./install.sh"
    echo ""
    print_info "To completely remove this project directory:"
    echo "  cd .. && rm -rf $(basename ${PWD})"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ============================================================================
# Main execution flow
# ============================================================================
main() {
    clear_screen

    print_info "This wizard will help you safely remove the XRPL monitoring stack."
    echo ""
    read -p "Press Enter to scan for installed components..." </dev/tty

    # Phase 1: Scan
    if ! scan_system; then
        exit 0
    fi

    # Phase 2: Review and confirm
    review_and_confirm

    # Phase 3: Remove
    remove_components

    # Verify and show completion
    verify_removal
    show_completion
}

# Run main
main
