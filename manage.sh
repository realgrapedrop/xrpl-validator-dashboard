#!/bin/bash
#
# XRPL Monitor v3.0 - Management Script
# Interactive service management with command-line support
#
# Version: 3.0.0
# Last Updated: 2025-11-16
#

# Note: Don't use 'set -e' for interactive menu (allows errors to be handled gracefully)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Service names
SERVICES=("collector" "grafana" "victoria-metrics" "vmagent" "node-exporter" "uptime-exporter" "state-exporter" "autoheal")

# Load ports from .env file (with defaults)
if [ -f .env ]; then
    source .env
fi
GRAFANA_PORT=${GRAFANA_PORT:-3000}
VICTORIA_PORT=${VICTORIA_METRICS_PORT:-8428}
NODE_EXPORTER_PORT=${NODE_EXPORTER_PORT:-9100}
UPTIME_EXPORTER_PORT=${UPTIME_EXPORTER_PORT:-9101}
STATE_EXPORTER_PORT=${STATE_EXPORTER_PORT:-9102}
COLLECTOR_PORT=${COLLECTOR_PORT:-8090}

# Print functions
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Banner
show_banner() {
    echo -e "${BLUE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║            XRPL Monitor v3.0 - Management Console             ║
║               Real-time validator monitoring                  ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Show help
show_help() {
    cat << EOF
XRPL Monitor v3.0 - Management Script

Usage:
  ./manage.sh                    Interactive menu (default)
  ./manage.sh [COMMAND] [SERVICE]

Commands:
  start                 Start all services
  stop                  Stop all services
  restart [SERVICE]     Restart all or specific service
  status                Show service status
  logs [SERVICE]        View logs (default: collector)
  rebuild [SERVICE]     Rebuild and restart service
  --help, -h            Show this help message

Services:
  collector, grafana, victoria-metrics, vmagent, node-exporter,
  uptime-exporter, state-exporter, autoheal

Examples:
  ./manage.sh start                # Start all services
  ./manage.sh restart collector    # Restart only collector
  ./manage.sh logs                 # View collector logs (default)
  ./manage.sh logs grafana         # View grafana logs

Update:
  To update after pulling latest code, run './manage.sh' and select
  option 10 "Update Dashboard (after git pull)"

EOF
}

# Get service status
get_service_status() {
    local service=$1
    local container_name

    # Map service names to container names
    case "$service" in
        "victoria-metrics")
            container_name="xrpl-monitor-victoria"
            ;;
        "node-exporter")
            container_name="xrpl-monitor-node-exporter"
            ;;
        "uptime-exporter")
            container_name="xrpl-monitor-uptime-exporter"
            ;;
        *)
            container_name="xrpl-monitor-${service}"
            ;;
    esac

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
        echo -e "${GREEN}Running${NC}"
        return 0
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
        echo -e "${RED}Stopped${NC}"
        return 1
    else
        echo -e "${YELLOW}Not found${NC}"
        return 2
    fi
}

# Auto-detect rippled ports by scanning
# Checks common rippled ports first, then scans all listening ports
detect_rippled_ports() {
    local detected_http=""
    local detected_ws=""

    # Common rippled ports to check first (native and Docker variants)
    local common_http_ports="5005 5205 5105 5305"
    local common_ws_ports="6006 6206 6106 6306"

    # Try common HTTP RPC ports first
    for port in $common_http_ports; do
        if timeout 1 curl -s "http://localhost:$port" \
            -d '{"method":"server_info"}' \
            -H "Content-Type: application/json" 2>/dev/null | grep -q '"result"'; then
            detected_http="http://localhost:$port"
            break
        fi
    done

    # Try common WebSocket ports first
    for port in $common_ws_ports; do
        # Skip if same as HTTP port we found
        if [ -n "$detected_http" ] && [[ "$detected_http" == *":$port" ]]; then
            continue
        fi
        if timeout 1 curl -s "http://localhost:$port" 2>/dev/null | grep -qi "ripple"; then
            detected_ws="ws://localhost:$port"
            break
        fi
    done

    # If common ports didn't work, scan all listening ports
    if [ -z "$detected_http" ] || [ -z "$detected_ws" ]; then
        local ports=$(ss -tuln 2>/dev/null | grep -E '0\.0\.0\.0:|127\.0\.0\.1:|\*:' | awk '{print $5}' | grep -oE '[0-9]+$' | sort -nu)

        # Scan for HTTP RPC if not found
        if [ -z "$detected_http" ]; then
            for port in $ports; do
                case $port in
                    22|80|443|3000|8080|8428|8427|9090|9100|9101|9102) continue ;;
                esac
                if timeout 1 curl -s "http://localhost:$port" \
                    -d '{"method":"server_info"}' \
                    -H "Content-Type: application/json" 2>/dev/null | grep -q '"result"'; then
                    detected_http="http://localhost:$port"
                    break
                fi
            done
        fi

        # Scan for WebSocket if not found
        if [ -z "$detected_ws" ]; then
            for port in $ports; do
                case $port in
                    22|80|443|3000|8080|8428|8427|9090|9100|9101|9102) continue ;;
                esac
                # Skip HTTP port we found
                if [ -n "$detected_http" ] && [[ "$detected_http" == *":$port" ]]; then
                    continue
                fi
                if timeout 1 curl -s "http://localhost:$port" 2>/dev/null | grep -qi "ripple"; then
                    detected_ws="ws://localhost:$port"
                    break
                fi
            done
        fi
    fi

    echo "$detected_http|$detected_ws"
}

# Show current status
show_status() {
    echo ""
    echo "rippled Connection:"

    # Check HTTP RPC connectivity and get state
    local http_url="${RIPPLED_HTTP_URL:-http://localhost:5005}"
    local ws_url="${RIPPLED_WS_URL:-ws://localhost:6006}"
    local rippled_state

    rippled_state=$(curl -s -m 2 -X POST -H 'Content-Type: application/json' \
        -d '{"method":"server_info"}' "$http_url" 2>/dev/null | \
        grep -o '"server_state":"[^"]*"' | cut -d'"' -f4)

    # If configured URL doesn't work, try auto-detection
    if [ -z "$rippled_state" ]; then
        local detected=$(detect_rippled_ports)
        local detected_http="${detected%|*}"
        local detected_ws="${detected#*|}"

        if [ -n "$detected_http" ]; then
            http_url="$detected_http"
            rippled_state=$(curl -s -m 2 -X POST -H 'Content-Type: application/json' \
                -d '{"method":"server_info"}' "$http_url" 2>/dev/null | \
                grep -o '"server_state":"[^"]*"' | cut -d'"' -f4)
        fi
        if [ -n "$detected_ws" ]; then
            ws_url="$detected_ws"
        fi
    fi

    printf "  %-20s " "HTTP RPC:"
    if [ -n "$rippled_state" ]; then
        # Color based on state
        case "$rippled_state" in
            proposing|full)
                printf "${GREEN}%-12s${NC} (%s)\n" "$rippled_state" "$http_url"
                ;;
            connected|syncing|tracking)
                printf "${YELLOW}%-12s${NC} (%s)\n" "$rippled_state" "$http_url"
                ;;
            *)
                printf "${RED}%-12s${NC} (%s)\n" "$rippled_state" "$http_url"
                ;;
        esac
    else
        printf "${RED}%-12s${NC} (%s)\n" "unreachable" "$http_url"
    fi

    # Check WebSocket connectivity
    local ws_port=$(echo "$ws_url" | grep -oE '[0-9]+$')
    local ws_check
    ws_check=$(curl -s -m 2 "http://localhost:$ws_port" 2>/dev/null)

    printf "  %-20s " "WebSocket:"
    if echo "$ws_check" | grep -qi "ripple"; then
        printf "${GREEN}%-12s${NC} (%s)\n" "healthy" "$ws_url"
    else
        printf "${RED}%-12s${NC} (%s)\n" "unreachable" "$ws_url"
    fi
    echo ""
    echo "Monitor Services:"

    # Services with web interfaces (show URLs)
    # Grafana
    printf "  %-20s " "Grafana:"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^xrpl-monitor-grafana$"; then
        echo -e "${GREEN}Running${NC} (http://localhost:${GRAFANA_PORT})"
    else
        get_service_status "grafana" || true
    fi

    # VictoriaMetrics
    printf "  %-20s " "VictoriaMetrics:"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^xrpl-monitor-victoria$"; then
        echo -e "${GREEN}Running${NC} (http://localhost:${VICTORIA_PORT})"
    else
        get_service_status "victoria-metrics" || true
    fi

    # Collector
    printf "  %-20s " "Collector:"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^xrpl-monitor-collector$"; then
        echo -e "${GREEN}Running${NC} (http://localhost:${COLLECTOR_PORT})"
    else
        get_service_status "collector" || true
    fi

    # State Exporter
    printf "  %-20s " "State Exporter:"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^xrpl-monitor-state-exporter$"; then
        echo -e "${GREEN}Running${NC} (http://localhost:${STATE_EXPORTER_PORT})"
    else
        get_service_status "state-exporter" || true
    fi

    # Uptime Exporter
    printf "  %-20s " "Uptime Exporter:"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^xrpl-monitor-uptime-exporter$"; then
        echo -e "${GREEN}Running${NC} (http://localhost:${UPTIME_EXPORTER_PORT})"
    else
        get_service_status "uptime-exporter" || true
    fi

    # Node Exporter
    printf "  %-20s " "Node Exporter:"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^xrpl-monitor-node-exporter$"; then
        echo -e "${GREEN}Running${NC} (http://localhost:${NODE_EXPORTER_PORT})"
    else
        get_service_status "node-exporter" || true
    fi

    # vmagent (internal, no web UI)
    printf "  %-20s " "vmagent:"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^xrpl-monitor-vmagent$"; then
        echo -e "${GREEN}Running${NC} (Metrics scraper)"
    else
        get_service_status "vmagent" || true
    fi

    # Autoheal (internal, no web UI)
    printf "  %-20s " "Autoheal:"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^xrpl-monitor-autoheal$"; then
        echo -e "${GREEN}Running${NC} (Container recovery)"
    else
        get_service_status "autoheal" || true
    fi

    echo ""
}

# Check if dashboard is installed
is_dashboard_installed() {
    # Check if .env exists and has required settings
    if [ ! -f .env ]; then
        return 1
    fi

    # Check if at least one container exists (even if stopped)
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^xrpl-monitor-"; then
        return 0
    fi

    return 1
}

# Prompt to run installer
prompt_install() {
    echo ""
    print_warning "XRPL Monitor dashboard is not installed."
    echo ""
    echo "Please run the installer first:"
    echo "  sudo ./install.sh"
}

# Start services
start_services() {
    if ! is_dashboard_installed; then
        prompt_install
        return
    fi
    print_info "Starting all services..."
    docker compose up -d
    sleep 3
    print_status "All services started"
    show_status
}

# Stop services
stop_services() {
    if ! is_dashboard_installed; then
        prompt_install
        return
    fi
    print_info "Stopping all services..."
    docker compose stop
    print_status "All services stopped"
}

# Restart services
restart_services() {
    if ! is_dashboard_installed; then
        prompt_install
        return
    fi
    local service=$1

    if [ -z "$service" ]; then
        print_info "Restarting all services..."
        docker compose restart
        sleep 3
        print_status "All services restarted"
    else
        print_info "Restarting ${service}..."
        docker compose restart "$service"
        sleep 2
        print_status "${service} restarted"
    fi
    show_status
}

# View logs
view_logs() {
    if ! is_dashboard_installed; then
        prompt_install
        return
    fi
    local service=${1:-collector}  # Default to collector

    print_info "Viewing logs for ${service}... (Press Ctrl+C to exit)"
    echo ""
    docker compose logs -f --tail=100 "$service"
}

# Rebuild service
rebuild_service() {
    if ! is_dashboard_installed; then
        prompt_install
        return
    fi
    local service=$1

    if [ -z "$service" ]; then
        print_error "Please specify a service to rebuild"
        echo "Available services: ${SERVICES[*]}"
        return 1
    fi

    print_info "Rebuilding ${service}..."
    docker compose stop "$service"
    docker compose build "$service"
    docker compose up -d "$service"
    sleep 3
    print_status "${service} rebuilt and restarted"
    show_status
}

# Service management submenu
manage_single_service() {
    if ! is_dashboard_installed; then
        prompt_install
        return
    fi
    clear
    echo ""
    echo "Manage Single Service"
    echo ""
    echo "Available services:"
    echo "  1) Grafana"
    echo "  2) VictoriaMetrics"
    echo "  3) Collector"
    echo "  4) vmagent"
    echo "  5) Node Exporter"
    echo "  6) Uptime Exporter"
    echo "  7) Back to main menu"
    echo ""

    read -p "Select service [1-7]: " service_choice

    local selected_service
    case $service_choice in
        1) selected_service="grafana" ;;
        2) selected_service="victoria-metrics" ;;
        3) selected_service="collector" ;;
        4) selected_service="vmagent" ;;
        5) selected_service="node-exporter" ;;
        6) selected_service="uptime-exporter" ;;
        7) return ;;
        *)
            print_error "Invalid choice"
            sleep 2
            return
            ;;
    esac

    echo ""
    echo "What would you like to do with ${selected_service}?"
    echo ""
    echo "  1) Start"
    echo "  2) Stop"
    echo "  3) Restart"
    echo "  4) View logs"
    echo "  5) Rebuild"
    echo "  6) Back"
    echo ""

    read -p "Select action [1-6]: " action_choice

    case $action_choice in
        1)
            echo ""
            print_info "Starting ${selected_service}..."
            docker compose start "$selected_service"
            sleep 2
            print_status "${selected_service} started"
            show_status
            ;;
        2)
            echo ""
            print_info "Stopping ${selected_service}..."
            docker compose stop "$selected_service"
            print_status "${selected_service} stopped"
            show_status
            ;;
        3)
            echo ""
            restart_services "$selected_service"
            ;;
        4)
            echo ""
            view_logs "$selected_service"
            ;;
        5)
            echo ""
            rebuild_service "$selected_service"
            ;;
        6)
            return
            ;;
        *)
            print_error "Invalid choice"
            sleep 2
            ;;
    esac
}

# Get current retention from docker-compose.yml
get_current_retention() {
    grep "retentionPeriod" docker-compose.yml | grep -oP '\d+[dmy]' || echo "30d"
}

# Update retention in docker-compose.yml
update_retention() {
    local new_retention=$1

    # Backup docker-compose.yml
    cp docker-compose.yml docker-compose.yml.bak

    # Update retention using sed
    sed -i "s/--retentionPeriod=[0-9]*[dmy]/--retentionPeriod=${new_retention}/" docker-compose.yml

    if [ $? -eq 0 ]; then
        return 0
    else
        # Restore backup on failure
        mv docker-compose.yml.bak docker-compose.yml
        return 1
    fi
}

# Convert retention to days for comparison
retention_to_days() {
    local retention=$1
    local number=${retention//[^0-9]/}
    local unit=${retention//[0-9]/}

    case $unit in
        d) echo $number ;;
        m) echo $((number * 30)) ;;
        y) echo $((number * 365)) ;;
        *) echo 30 ;;
    esac
}

# Adjust data retention
adjust_retention() {
    local current_retention
    current_retention=$(get_current_retention)
    local current_days
    current_days=$(retention_to_days "$current_retention")

    echo ""
    echo "Data Retention Configuration"
    echo ""
    echo "Current retention: ${current_retention}"
    echo ""
    echo "Select retention period:"
    echo ""

    # Mark current selection
    if [ "$current_days" -eq 30 ]; then
        echo "  1) 30 days   (~325 MB)  [CURRENT]"
    else
        echo "  1) 30 days   (~325 MB)"
    fi

    if [ "$current_days" -eq 90 ]; then
        echo "  2) 90 days   (~974 MB)  [CURRENT]"
    else
        echo "  2) 90 days   (~974 MB)"
    fi

    if [ "$current_days" -eq 365 ]; then
        echo "  3) 1 year    (~3.9 GB)  [CURRENT]"
    else
        echo "  3) 1 year    (~3.9 GB)"
    fi

    if [ "$current_days" -eq 730 ]; then
        echo "  4) 2 years   (~7.8 GB)  [CURRENT]"
    else
        echo "  4) 2 years   (~7.8 GB)"
    fi

    echo "  5) Custom (enter days)"
    echo "  6) Back"
    echo ""

    read -p "Select option [1-6]: " retention_choice

    local new_retention=""
    local new_days=0

    case $retention_choice in
        1)
            new_retention="30d"
            new_days=30
            ;;
        2)
            new_retention="90d"
            new_days=90
            ;;
        3)
            new_retention="365d"
            new_days=365
            ;;
        4)
            new_retention="730d"
            new_days=730
            ;;
        5)
            echo ""
            read -p "Enter retention in days [30-730]: " custom_days
            if [[ "$custom_days" =~ ^[0-9]+$ ]] && [ "$custom_days" -ge 30 ] && [ "$custom_days" -le 730 ]; then
                new_retention="${custom_days}d"
                new_days=$custom_days
            else
                print_error "Invalid input. Must be between 30 and 730 days."
                sleep 2
                return
            fi
            ;;
        6)
            return
            ;;
        *)
            print_error "Invalid choice"
            sleep 2
            return
            ;;
    esac

    # Show impact screen
    echo ""
    echo "You selected: ${new_retention}"
    echo "Current setting: ${current_retention}"
    echo ""
    echo "Impact:"

    # Warn about data loss if reducing retention
    if [ "$new_days" -lt "$current_days" ]; then
        echo -e "${YELLOW}⚠ WARNING: Reducing retention from ${current_retention} to ${new_retention}${NC}"
        echo -e "${YELLOW}This will DELETE data older than ${new_retention}!${NC}"
    fi

    echo "- VictoriaMetrics will restart (~2-3 seconds downtime)"
    echo "- Brief gap in metric collection during restart"
    if [ "$new_days" -lt "$current_days" ]; then
        echo "- Data older than ${new_retention} will be permanently deleted"
    else
        echo "- All existing data will be preserved"
    fi
    echo "- Other services will continue running"
    echo ""
    echo "What would you like to do?"
    echo "  1) Continue with change"
    echo "  2) Go back"
    echo ""

    read -p "Enter your choice [1-2]: " confirm_choice

    if [ "$confirm_choice" != "1" ]; then
        print_info "Change cancelled"
        sleep 2
        return
    fi

    # Apply the change
    echo ""
    print_info "Updating retention to ${new_retention}..."

    if update_retention "$new_retention"; then
        print_status "Configuration updated"

        print_info "Restarting VictoriaMetrics..."
        docker compose restart victoria-metrics

        sleep 3

        print_status "Retention period changed to ${new_retention}"

        # Clean up backup
        rm -f docker-compose.yml.bak
    else
        print_error "Failed to update configuration"
    fi

    sleep 2
}

# Import a single dashboard via API (helper function)
# Args: $1=grafana_port, $2=username, $3=password, $4=template_file, $5=dashboard_name
import_dashboard_api() {
    local grafana_port=$1
    local username=$2
    local password=$3
    local template_file=$4
    local dashboard_name=$5

    # Prepare import payload (remove id, set version to 0, wrap for import)
    local import_payload
    import_payload=$(jq 'del(.id) | .version = 0 | {dashboard: ., overwrite: true}' "$template_file" 2>&1)

    if [ $? -ne 0 ]; then
        print_error "Failed to prepare $dashboard_name payload"
        return 1
    fi

    # Import dashboard via Grafana API
    local response
    response=$(echo "$import_payload" | curl -s -w "\n%{http_code}" -X POST "http://localhost:${grafana_port}/api/dashboards/db" \
        -u "${username}:${password}" \
        -H "Content-Type: application/json" \
        -d @- 2>&1)

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)

    if [ "$http_code" = "200" ]; then
        print_status "$dashboard_name restored successfully"
        return 0
    elif [ "$http_code" = "401" ]; then
        return 2  # Auth failed (wrong username/password)
    elif [ "$http_code" = "403" ]; then
        return 3  # Forbidden (insufficient permissions)
    elif [ "$http_code" = "412" ]; then
        print_status "$dashboard_name restored (already up to date)"
        return 0
    else
        print_error "Failed to restore $dashboard_name (HTTP $http_code)"
        return 1
    fi
}

# Restore default dashboard
restore_default_dashboard() {
    local grafana_port=${GRAFANA_PORT:-3003}
    local main_template="config/grafana/provisioning/dashboards/xrpl-validator-main.json.template"
    local cyberpunk_file="config/grafana/provisioning/dashboards/xrpl-validator-cyberpunk.json"
    local max_attempts=3
    local attempt=0

    clear
    echo ""
    echo "Restore Default Dashboard"
    echo ""
    echo "Which dashboard would you like to restore?"
    echo ""
    echo "  1) Default Main Dashboard"
    echo "  2) Cyberpunk Dashboard"
    echo "  3) Both dashboards"
    echo "  4) Cancel"
    echo ""

    read -p "Select option [1-4]: " dashboard_choice

    case $dashboard_choice in
        1)
            local template_file="$main_template"
            local dashboard_name="Main Dashboard"
            local restore_both=false
            ;;
        2)
            local template_file="$cyberpunk_file"
            local dashboard_name="Cyberpunk Dashboard"
            local restore_both=false
            ;;
        3)
            local restore_both=true
            ;;
        4|*)
            print_info "Restore cancelled"
            sleep 2
            return
            ;;
    esac

    echo ""
    if [ "$restore_both" = true ]; then
        echo -e "${YELLOW}⚠ WARNING: This will replace BOTH dashboards with defaults.${NC}"
    else
        echo -e "${YELLOW}⚠ WARNING: This will replace the $dashboard_name with the default.${NC}"
    fi
    echo -e "${YELLOW}All customizations will be LOST.${NC}"
    echo ""

    read -p "Type 'yes' to confirm (or anything else to cancel): " confirm

    if [ "$confirm" != "yes" ]; then
        print_info "Restore cancelled"
        sleep 2
        return
    fi

    # Check if template(s) exist
    if [ "$restore_both" = true ]; then
        if [ ! -f "$main_template" ]; then
            print_error "Main template not found: $main_template"
            sleep 3
            return
        fi
        if [ ! -f "$cyberpunk_file" ]; then
            print_error "Cyberpunk dashboard not found: $cyberpunk_file"
            sleep 3
            return
        fi
    else
        if [ ! -f "$template_file" ]; then
            print_error "Template file not found: $template_file"
            sleep 3
            return
        fi
    fi

    # Check if Grafana is running
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^xrpl-monitor-grafana$"; then
        print_error "Grafana is not running. Please start the stack first."
        sleep 3
        return
    fi

    # Get Grafana credentials
    echo ""
    echo "Enter Grafana credentials (requires Admin or Editor role):"
    echo ""
    read -p "Username [admin]: " grafana_username
    grafana_username=${grafana_username:-admin}

    # Password retry loop
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))

        echo ""
        if [ $attempt -gt 1 ]; then
            echo -e "${YELLOW}⚠ Attempt $attempt of $max_attempts${NC}"
            if [ $attempt -eq $max_attempts ]; then
                echo -e "${YELLOW}WARNING: This is your last attempt. Too many failed attempts may lock your account.${NC}"
            fi
        fi
        read -s -p "Password: " grafana_password
        echo ""

        if [ -z "$grafana_password" ]; then
            print_error "Password cannot be empty"
            continue
        fi

        echo ""

        if [ "$restore_both" = true ]; then
            print_info "Restoring both dashboards..."

            import_dashboard_api "$grafana_port" "$grafana_username" "$grafana_password" "$main_template" "Main Dashboard"
            local main_result=$?

            if [ $main_result -eq 2 ]; then
                print_error "Authentication failed. Incorrect username or password."
                if [ $attempt -lt $max_attempts ]; then
                    echo "Please try again."
                    continue
                else
                    echo ""
                    print_warning "Maximum attempts reached. Returning to menu."
                    break
                fi
            elif [ $main_result -eq 3 ]; then
                print_error "Permission denied. User '$grafana_username' needs Admin or Editor role."
                sleep 3
                return
            fi

            import_dashboard_api "$grafana_port" "$grafana_username" "$grafana_password" "$cyberpunk_file" "Cyberpunk Dashboard"

            echo ""
            print_info "Access your dashboards at: http://localhost:${grafana_port}"
            sleep 3
            return
        else
            print_info "Restoring $dashboard_name..."

            import_dashboard_api "$grafana_port" "$grafana_username" "$grafana_password" "$template_file" "$dashboard_name"
            local result=$?

            if [ $result -eq 2 ]; then
                print_error "Authentication failed. Incorrect username or password."
                if [ $attempt -lt $max_attempts ]; then
                    echo "Please try again."
                    continue
                else
                    echo ""
                    print_warning "Maximum attempts reached. Returning to menu."
                    break
                fi
            elif [ $result -eq 3 ]; then
                print_error "Permission denied. User '$grafana_username' needs Admin or Editor role."
                sleep 3
                return
            fi

            echo ""
            print_info "Access your dashboard at: http://localhost:${grafana_port}"
            sleep 3
            return
        fi
    done

    sleep 2
}

# Backup & Restore menu
backup_restore_menu() {
    if ! is_dashboard_installed; then
        prompt_install
        return
    fi
    clear
    echo ""
    echo "Dashboard Backup & Restore"
    echo ""
    echo -e "  ${YELLOW}Note: This backs up Grafana dashboards, settings, and users.${NC}"
    echo -e "  ${YELLOW}Time-series metrics (VictoriaMetrics) are not included.${NC}"
    echo ""
    echo "  1) Create dashboard backup"
    echo "  2) Restore from backup"
    echo "  3) Back to main menu"
    echo ""

    read -p "Select option [1-3]: " backup_choice

    case $backup_choice in
        1)
            create_dashboard_backup
            ;;
        2)
            restore_dashboard_backup
            ;;
        3)
            return
            ;;
        *)
            print_error "Invalid choice"
            sleep 2
            ;;
    esac
}

# Create dashboard backup
create_dashboard_backup() {
    clear
    echo ""
    echo "Create Dashboard Backup"
    echo ""

    if [ ! -f "scripts/backup-grafana.sh" ]; then
        print_error "Backup script not found: scripts/backup-grafana.sh"
        sleep 2
        return
    fi

    print_info "This will backup:"
    echo "  - Grafana dashboards and customizations"
    echo "  - User settings and preferences"
    echo "  - Alert configurations"
    echo "  - Provisioning configs"
    echo ""
    print_warning "VictoriaMetrics data (time-series metrics) is NOT backed up"
    echo ""

    read -p "Continue with backup? [Y/n]: " confirm
    if [[ $confirm =~ ^[Nn]$ ]]; then
        print_info "Backup cancelled"
        sleep 1
        return
    fi

    echo ""
    bash scripts/backup-grafana.sh

    echo ""
    read -p "Press Enter to continue..."
}

# Restore dashboard backup
restore_dashboard_backup() {
    clear
    echo ""
    echo "Restore Dashboard Backup"
    echo ""

    if [ ! -f "scripts/restore-grafana.sh" ]; then
        print_error "Restore script not found: scripts/restore-grafana.sh"
        sleep 2
        return
    fi

    BACKUP_DIR="data/grafana-backups"

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A $BACKUP_DIR/*.tar.gz 2>/dev/null)" ]; then
        print_warning "No backups found in $BACKUP_DIR"
        echo ""
        read -p "Press Enter to continue..."
        return
    fi

    echo "Available backups (most recent first):"
    echo ""

    # List backups with numbers
    local backups=()
    local count=1
    for backup in $(ls -t "$BACKUP_DIR"/grafana-backup-*.tar.gz 2>/dev/null); do
        local filename=$(basename "$backup")
        local size=$(du -h "$backup" | cut -f1)
        local date=$(echo "$filename" | grep -oP '\d{8}-\d{6}' | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')

        echo "  [$count] $date ($size)"
        backups+=("$backup")
        ((count++))
    done

    echo ""
    echo "  [0] Cancel and return to menu"
    echo ""
    read -p "Select backup number to restore [0-$((count-1))]: " backup_num

    if [ "$backup_num" = "0" ]; then
        print_info "Restore cancelled"
        sleep 1
        return
    fi

    if ! [[ "$backup_num" =~ ^[0-9]+$ ]] || [ "$backup_num" -lt 1 ] || [ "$backup_num" -gt "${#backups[@]}" ]; then
        print_error "Invalid selection"
        sleep 2
        return
    fi

    local selected_backup="${backups[$((backup_num-1))]}"

    echo ""
    print_warning "This will restore Grafana from: $(basename "$selected_backup")"
    print_warning "A backup of current state will be created first"
    echo ""

    bash scripts/restore-grafana.sh "$selected_backup"

    echo ""
    read -p "Press Enter to continue..."
}

# Update Dashboard menu (after user runs git pull)
update_dashboard_menu() {
    if ! is_dashboard_installed; then
        prompt_install
        return
    fi
    clear
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                    Update Dashboard                           ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  WARNING: This update will reset Grafana to apply new features.${NC}"
    echo ""
    echo "This update will:"
    echo "  1. Export your current dashboards"
    echo "  2. Reset Grafana and import the latest dashboards"
    echo "  3. Re-import your old dashboards as 'Dashboard-TIMESTAMP' for comparison"
    echo ""
    echo "What will be preserved:"
    echo "  - All metrics data (agreements, missed, peer counts, etc.)"
    echo "  - Your .env settings (ports, SMTP config)"
    echo "  - Your old dashboards (renamed with timestamp)"
    echo ""
    echo -e "${YELLOW}IMPORTANT: You should run 'git pull' first to get the latest code.${NC}"
    echo ""
    read -p "Do you want to continue? (yes/no) [no]: " confirm </dev/tty

    if [ "$confirm" != "yes" ]; then
        echo ""
        print_info "Update cancelled."
        echo ""
        return
    fi

    # Verify Grafana credentials before proceeding
    # This ensures only authorized users can run the update
    echo ""
    echo "Enter your current Grafana credentials to proceed:"
    read -p "  Username [admin]: " grafana_user </dev/tty
    grafana_user=${grafana_user:-admin}
    read -s -p "  Password: " new_password </dev/tty
    echo ""

    # Verify credentials (use /api/org which requires authentication, not /api/health which doesn't)
    print_info "Verifying credentials..."
    local auth_response
    auth_response=$(curl -s -u "${grafana_user}:${new_password}" "http://localhost:${GRAFANA_PORT:-3000}/api/org" 2>/dev/null)
    if ! echo "$auth_response" | grep -q '"id":1'; then
        echo ""
        print_error "Invalid Grafana credentials. Update cancelled."
        echo ""
        return
    fi
    print_status "Credentials verified"

    # Ask about keeping dashboard copies
    echo ""
    echo "Keep your current dashboards for comparison after update?"
    echo "  - Main & Cyberpunk dashboards will be re-imported with timestamps"
    echo "  - Any custom dashboards will be saved to data/dashboard-backups/"
    echo ""
    read -p "Keep copies? (yes/no) [yes]: " keep_copies </dev/tty
    keep_copies=${keep_copies:-yes}

    # Export current dashboards FIRST (before any changes)
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local saved_main=""
    local saved_cyberpunk=""
    local saved_user_dashboards=0

    if [ "$keep_copies" = "yes" ] || [ "$keep_copies" = "y" ]; then
        print_info "Exporting current dashboards..."
        mkdir -p data/dashboard-backups

        # Export main dashboard
        local main_export=$(curl -s -u "${grafana_user}:${new_password}" "http://localhost:${GRAFANA_PORT:-3000}/api/dashboards/uid/xrpl-validator-monitor-full" 2>/dev/null)
        if echo "$main_export" | jq -e '.dashboard' > /dev/null 2>&1; then
            saved_main="XRPL Validator Dashboard-${timestamp}"
            echo "$main_export" | jq '.dashboard' > "data/dashboard-backups/main-${timestamp}.json"
            print_status "Main dashboard exported"
        fi

        # Export cyberpunk dashboard
        local cyberpunk_export=$(curl -s -u "${grafana_user}:${new_password}" "http://localhost:${GRAFANA_PORT:-3000}/api/dashboards/uid/xrpl-validator-monitor-cyberpunk" 2>/dev/null)
        if echo "$cyberpunk_export" | jq -e '.dashboard' > /dev/null 2>&1; then
            saved_cyberpunk="XRPL Validator Dashboard Cyberpunk-${timestamp}"
            echo "$cyberpunk_export" | jq '.dashboard' > "data/dashboard-backups/cyberpunk-${timestamp}.json"
            print_status "Cyberpunk dashboard exported"
        fi

        # Export ALL other dashboards (user-created ones)
        # Get list of all dashboard UIDs, excluding our known ones and backup copies
        local all_dashboards=$(curl -s -u "${grafana_user}:${new_password}" "http://localhost:${GRAFANA_PORT:-3000}/api/search?type=dash-db" 2>/dev/null)
        if echo "$all_dashboards" | jq -e '.' > /dev/null 2>&1; then
            mkdir -p "data/dashboard-backups/user-dashboards-${timestamp}"

            # Loop through each dashboard
            echo "$all_dashboards" | jq -r '.[] | "\(.uid)|\(.title)"' | while IFS='|' read -r uid title; do
                # Skip only the base provisioned dashboards (we export these separately above)
                case "$uid" in
                    xrpl-validator-monitor-full|xrpl-validator-monitor-cyberpunk)
                        continue
                        ;;
                esac

                # Export this user dashboard
                local dash_export=$(curl -s -u "${grafana_user}:${new_password}" "http://localhost:${GRAFANA_PORT:-3000}/api/dashboards/uid/${uid}" 2>/dev/null)
                if echo "$dash_export" | jq -e '.dashboard' > /dev/null 2>&1; then
                    # Sanitize filename
                    local safe_title=$(echo "$title" | tr -cd '[:alnum:] _-' | tr ' ' '_')
                    echo "$dash_export" | jq '.dashboard' > "data/dashboard-backups/user-dashboards-${timestamp}/${safe_title}.json"
                    echo "    Exported: $title"
                    saved_user_dashboards=$((saved_user_dashboards + 1))
                fi
            done

            # Check if any user dashboards were saved
            local user_dash_count=$(ls -1 "data/dashboard-backups/user-dashboards-${timestamp}/" 2>/dev/null | wc -l)
            if [ "$user_dash_count" -gt 0 ]; then
                print_status "$user_dash_count custom dashboard(s) exported"
            else
                # Remove empty directory
                rmdir "data/dashboard-backups/user-dashboards-${timestamp}" 2>/dev/null
            fi
        fi
    fi

    echo ""
    print_info "Proceeding with update..."
    echo ""

    # Load environment variables with defaults and EXPORT them for envsubst
    if [ -f .env ]; then
        source .env
    fi
    export NODE_EXPORTER_PORT=${NODE_EXPORTER_PORT:-9100}
    export UPTIME_EXPORTER_PORT=${UPTIME_EXPORTER_PORT:-9101}
    export STATE_EXPORTER_PORT=${STATE_EXPORTER_PORT:-9102}
    export VICTORIA_METRICS_PORT=${VICTORIA_METRICS_PORT:-8428}
    export GRAFANA_PORT=${GRAFANA_PORT:-3000}
    export COLLECTOR_PORT=${COLLECTOR_PORT:-8090}
    export VMAGENT_PORT=${VMAGENT_PORT:-8427}

    # Get email from .env for contact point (if configured)
    local contact_email="${GF_SMTP_USER:-example@email.com}"

    # Regenerate scrape.yml from template
    print_info "Regenerating configuration files from templates..."
    if [ -f config/vmagent/scrape.yml.template ]; then
        envsubst < config/vmagent/scrape.yml.template > config/vmagent/scrape.yml
        print_status "scrape.yml regenerated"
    else
        print_warning "scrape.yml.template not found, skipping"
    fi

    # Regenerate datasource.yml from template
    if [ -f config/grafana/provisioning/datasources/datasource.yml.template ]; then
        envsubst < config/grafana/provisioning/datasources/datasource.yml.template > config/grafana/provisioning/datasources/datasource.yml
        print_status "datasource.yml regenerated"
    else
        print_warning "datasource.yml.template not found, skipping"
    fi

    # Rebuild containers with code changes
    print_info "Rebuilding containers..."
    docker compose build collector state-exporter uptime-exporter
    print_status "Containers rebuilt"

    # Stop Grafana, remove container and volume to clear provisioning state
    print_info "Resetting Grafana to apply new features..."
    docker compose stop grafana 2>/dev/null
    docker rm xrpl-monitor-grafana 2>/dev/null || true
    docker volume rm xrpl-monitor-grafana-data 2>/dev/null || true
    print_status "Grafana data reset"

    # Restart all services to pick up changes
    print_info "Restarting services..."
    docker compose up -d --force-recreate
    print_status "Services restarted"

    # Wait for Grafana to be ready (check health endpoint)
    print_info "Waiting for Grafana to start..."
    local max_wait=60
    local wait_count=0
    while [ $wait_count -lt $max_wait ]; do
        if curl -s "http://localhost:${GRAFANA_PORT}/api/health" 2>/dev/null | grep -q "ok"; then
            break
        fi
        sleep 2
        wait_count=$((wait_count + 2))
    done

    if [ $wait_count -ge $max_wait ]; then
        print_warning "Grafana did not start in time"
        print_warning "You may need to manually import dashboards and set password"
        return
    fi

    # Wait a bit more for Grafana to fully initialize, then verify default auth works
    sleep 3
    local auth_check
    auth_check=$(curl -s -u "admin:admin" "http://localhost:${GRAFANA_PORT}/api/org" 2>/dev/null)
    if ! echo "$auth_check" | grep -q '"id":1'; then
        print_error "Grafana started but default credentials don't work"
        print_error "Please check Grafana logs: docker logs xrpl-monitor-grafana"
        return
    fi
    print_status "Grafana ready"

    # Import dashboards via API
    print_info "Importing dashboards..."
    local main_dashboard="config/grafana/provisioning/dashboards/xrpl-validator-main.json"
    if [ -f "$main_dashboard" ]; then
        local import_payload
        import_payload=$(jq 'del(.id) | .version = 0 | {dashboard: ., overwrite: true}' "$main_dashboard" 2>/dev/null)
        if [ -n "$import_payload" ]; then
            echo "$import_payload" | curl -s -X POST "http://localhost:${GRAFANA_PORT}/api/dashboards/db" \
                -u "admin:admin" -H "Content-Type: application/json" -d @- > /dev/null 2>&1
            print_status "Main dashboard imported"
        fi
    fi

    local cyberpunk_dashboard="config/grafana/provisioning/dashboards/xrpl-validator-cyberpunk.json"
    if [ -f "$cyberpunk_dashboard" ]; then
        local import_payload
        import_payload=$(jq 'del(.id) | .version = 0 | {dashboard: ., overwrite: true}' "$cyberpunk_dashboard" 2>/dev/null)
        if [ -n "$import_payload" ]; then
            echo "$import_payload" | curl -s -X POST "http://localhost:${GRAFANA_PORT}/api/dashboards/db" \
                -u "admin:admin" -H "Content-Type: application/json" -d @- > /dev/null 2>&1
            print_status "Cyberpunk dashboard imported"
        fi
    fi

    # Import contact point via API (use email from .env if available)
    print_info "Creating contact point..."
    curl -s -X POST "http://localhost:${GRAFANA_PORT}/api/v1/provisioning/contact-points" \
        -u "admin:admin" -H "Content-Type: application/json" \
        -d "{
            \"name\": \"xrpl-monitor-email\",
            \"type\": \"email\",
            \"settings\": {
                \"addresses\": \"${contact_email}\",
                \"singleEmail\": false
            },
            \"disableResolveMessage\": false
        }" > /dev/null 2>&1
    print_status "Contact point created (${contact_email})"

    # Configure notification policy
    print_info "Configuring notification policy..."
    curl -s -X PUT "http://localhost:${GRAFANA_PORT}/api/v1/provisioning/policies" \
        -u "admin:admin" -H "Content-Type: application/json" \
        -d '{
            "receiver": "xrpl-monitor-email",
            "group_by": ["grafana_folder", "alertname"],
            "group_wait": "30s",
            "group_interval": "5m",
            "repeat_interval": "4h"
        }' > /dev/null 2>&1
    print_status "Notification policy configured"

    # Re-import saved dashboards with timestamp in title (for comparison)
    # Do this BEFORE password change so we can use admin:admin
    if [ -n "$saved_main" ] && [ -f "data/dashboard-backups/main-${timestamp}.json" ]; then
        print_info "Importing your previous dashboard as '${saved_main}'..."
        local backup_payload
        backup_payload=$(jq --arg title "$saved_main" \
            'del(.id) | .uid = "backup-main-'"${timestamp}"'" | .title = $title | .version = 0 | {dashboard: ., overwrite: true}' \
            "data/dashboard-backups/main-${timestamp}.json" 2>/dev/null)
        if [ -n "$backup_payload" ]; then
            echo "$backup_payload" | curl -s -X POST "http://localhost:${GRAFANA_PORT}/api/dashboards/db" \
                -u "admin:admin" -H "Content-Type: application/json" -d @- > /dev/null 2>&1
            print_status "Previous main dashboard imported"
        fi
    fi

    if [ -n "$saved_cyberpunk" ] && [ -f "data/dashboard-backups/cyberpunk-${timestamp}.json" ]; then
        print_info "Importing your previous dashboard as '${saved_cyberpunk}'..."
        local backup_payload
        backup_payload=$(jq --arg title "$saved_cyberpunk" \
            'del(.id) | .uid = "backup-cyberpunk-'"${timestamp}"'" | .title = $title | .version = 0 | {dashboard: ., overwrite: true}' \
            "data/dashboard-backups/cyberpunk-${timestamp}.json" 2>/dev/null)
        if [ -n "$backup_payload" ]; then
            echo "$backup_payload" | curl -s -X POST "http://localhost:${GRAFANA_PORT}/api/dashboards/db" \
                -u "admin:admin" -H "Content-Type: application/json" -d @- > /dev/null 2>&1
            print_status "Previous cyberpunk dashboard imported"
        fi
    fi

    # Re-import user dashboards from backup folder
    if [ -d "data/dashboard-backups/user-dashboards-${timestamp}" ]; then
        local user_files=$(ls -1 "data/dashboard-backups/user-dashboards-${timestamp}/"*.json 2>/dev/null)
        if [ -n "$user_files" ]; then
            print_info "Importing your custom dashboards..."
            local user_counter=1
            for dash_file in data/dashboard-backups/user-dashboards-${timestamp}/*.json; do
                if [ -f "$dash_file" ]; then
                    # Get original title from the JSON
                    local orig_title=$(jq -r '.title // "Unknown"' "$dash_file" 2>/dev/null)
                    local new_title="${orig_title}-${timestamp}"
                    # Use short UID to stay under 40 char limit: bu-COUNTER-TIMESTAMP
                    local new_uid="bu-${user_counter}-${timestamp}"

                    # Import with new UID and timestamped title
                    local user_payload
                    user_payload=$(jq --arg title "$new_title" --arg uid "$new_uid" \
                        'del(.id) | .uid = $uid | .title = $title | .version = 0 | {dashboard: ., overwrite: true}' \
                        "$dash_file" 2>/dev/null)
                    if [ -n "$user_payload" ]; then
                        echo "$user_payload" | curl -s -X POST "http://localhost:${GRAFANA_PORT}/api/dashboards/db" \
                            -u "admin:admin" -H "Content-Type: application/json" -d @- > /dev/null 2>&1
                        echo "    Imported: ${orig_title}"
                    fi
                    user_counter=$((user_counter + 1))
                fi
            done
            local imported_count=$(ls -1 "data/dashboard-backups/user-dashboards-${timestamp}/"*.json 2>/dev/null | wc -l)
            print_status "$imported_count custom dashboard(s) imported"
        fi
    fi

    # Change admin password LAST (after all imports are done)
    print_info "Setting Grafana password..."
    local pw_response
    pw_response=$(curl -s -X PUT "http://localhost:${GRAFANA_PORT}/api/admin/users/1/password" \
        -u "admin:admin" -H "Content-Type: application/json" \
        -d "{\"password\": \"${new_password}\"}" 2>&1)

    if echo "$pw_response" | grep -qi "updated"; then
        print_status "Password updated"
    else
        print_warning "Could not update password automatically"
        print_warning "API response: $pw_response"
        print_info "Default password is 'admin' - change it on first login"
    fi

    # Wait for services to stabilize
    print_info "Waiting for services to stabilize..."
    sleep 5

    # Verify health
    echo ""
    print_info "Verifying service health..."
    show_status

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    Update Complete!                           ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Please log in at: http://localhost:${GRAFANA_PORT}"
    echo "  Username: admin"
    echo "  Password: (the password you entered)"
    echo ""
    if [ "$contact_email" != "example@email.com" ]; then
        echo -e "${GREEN}✓${NC} Contact point configured with: ${contact_email}"
    else
        echo -e "${YELLOW}!${NC} Configure email alerts: ./manage.sh → 11) Setup Gmail Alerts"
    fi

    # Show backup info if dashboards were saved
    if [ -n "$saved_main" ] || [ -n "$saved_cyberpunk" ]; then
        echo ""
        echo -e "${BLUE}Your previous dashboards have been imported for comparison:${NC}"
        if [ -n "$saved_main" ]; then
            echo "  - ${saved_main}"
        fi
        if [ -n "$saved_cyberpunk" ]; then
            echo "  - ${saved_cyberpunk}"
        fi
    fi

    # Show user dashboard info
    if [ -d "data/dashboard-backups/user-dashboards-${timestamp}" ]; then
        local user_count=$(ls -1 "data/dashboard-backups/user-dashboards-${timestamp}/"*.json 2>/dev/null | wc -l)
        if [ "$user_count" -gt 0 ]; then
            echo ""
            echo -e "${BLUE}Your custom dashboards have also been imported:${NC}"
            for dash_file in data/dashboard-backups/user-dashboards-${timestamp}/*.json; do
                if [ -f "$dash_file" ]; then
                    local orig_title=$(jq -r '.title // "Unknown"' "$dash_file" 2>/dev/null)
                    echo "  - ${orig_title}-${timestamp}"
                fi
            done
        fi
    fi

    if [ -n "$saved_main" ] || [ -n "$saved_cyberpunk" ]; then
        echo ""
        echo "You can find them all in the Grafana dashboard list."
        echo "JSON backups saved to: data/dashboard-backups/"
    fi
    echo ""
}

# ==============================================================================
# GMAIL ALERT SETUP
# ==============================================================================

# Check if Gmail is already configured
check_gmail_config() {
    if [ -f .env ]; then
        source .env
        if [ -n "$GF_SMTP_USER" ] && [[ "$GF_SMTP_USER" == *"@gmail.com" ]]; then
            return 0  # Configured
        fi
    fi
    return 1  # Not configured
}

# Get masked email for display
mask_email() {
    local email=$1
    local user="${email%@*}"
    local domain="${email#*@}"
    local user_len=${#user}

    if [ $user_len -le 4 ]; then
        echo "${user:0:1}***@${domain}"
    else
        echo "${user:0:4}****@${domain}"
    fi
}

# Validate Gmail address
validate_gmail() {
    local email=$1
    # Case-insensitive check for @gmail.com
    if [[ "${email,,}" == *"@gmail.com" ]]; then
        return 0
    fi
    return 1
}

# Validate App Password format (16 characters, ignoring spaces)
validate_app_password() {
    local password=$1
    # Remove spaces
    local clean_password="${password// /}"
    if [ ${#clean_password} -eq 16 ]; then
        return 0
    fi
    return 1
}

# Mask app password for display (show first 4 and last 4)
mask_password() {
    local password=$1
    local len=${#password}
    if [ $len -ge 8 ]; then
        echo "${password:0:4}........${password: -4}"
    else
        echo "****"
    fi
}

# Show test instructions after Gmail update
show_gmail_test_instructions() {
    local grafana_port=${GRAFANA_PORT:-3000}
    echo ""
    echo "To verify your changes:"
    echo -e "  1. ${YELLOW}Refresh your browser${NC} (Ctrl+R or Cmd+R)"
    echo "  2. Go to: Alerting → Contact points"
    echo "  3. Click 'View' on the right of xrpl-monitor-email"
    echo "  4. Click 'Test' → 'Send test notification'"
    echo "  5. Check your inbox"
    echo ""
}

# Update .env with Gmail SMTP settings
update_env_gmail() {
    local email=$1
    local password=$2

    # Remove existing SMTP settings from .env
    if [ -f .env ]; then
        sed -i '/^GF_SMTP_ENABLED=/d' .env
        sed -i '/^GF_SMTP_HOST=/d' .env
        sed -i '/^GF_SMTP_USER=/d' .env
        sed -i '/^GF_SMTP_PASSWORD=/d' .env
        sed -i '/^GF_SMTP_FROM_ADDRESS=/d' .env
        sed -i '/^# SMTP Configuration/d' .env
        sed -i '/^# Gmail SMTP/d' .env
    fi

    # Append new SMTP settings
    cat >> .env << EOF

# Gmail SMTP Configuration (configured via manage.sh)
GF_SMTP_ENABLED=true
GF_SMTP_HOST=smtp.gmail.com:587
GF_SMTP_USER=${email}
GF_SMTP_PASSWORD=${password}
GF_SMTP_FROM_ADDRESS=${email}
EOF
}

# Update contact point via Grafana API
update_contact_points() {
    local email=$1
    local grafana_port=${GRAFANA_PORT:-3000}

    # Get credentials from user
    echo ""
    read -p "Enter Grafana username [admin]: " grafana_user </dev/tty
    grafana_user=${grafana_user:-admin}
    read -s -p "Enter Grafana password: " grafana_pass </dev/tty
    echo ""

    if [ -z "$grafana_pass" ]; then
        echo -e "${RED}Password required${NC}"
        return 1
    fi

    # First, get the UID of the existing contact point
    local response
    response=$(curl -s -u "${grafana_user}:${grafana_pass}" \
        "http://localhost:${grafana_port}/api/v1/provisioning/contact-points" 2>&1)

    # Check for auth error
    if echo "$response" | grep -q "Invalid username or password"; then
        echo -e "${RED}Authentication failed${NC}"
        return 1
    fi

    # Find the xrpl-monitor-email UID
    local uid
    uid=$(echo "$response" | jq -r '.[] | select(.name == "xrpl-monitor-email") | .uid' 2>/dev/null)

    if [ -z "$uid" ] || [ "$uid" = "null" ]; then
        # Contact point doesn't exist, create it
        echo -e "${YELLOW}Creating new contact point...${NC}"
        response=$(curl -s -w "\n%{http_code}" \
            -X POST "http://localhost:${grafana_port}/api/v1/provisioning/contact-points" \
            -u "${grafana_user}:${grafana_pass}" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"xrpl-monitor-email\",
                \"type\": \"email\",
                \"settings\": {
                    \"addresses\": \"${email}\",
                    \"singleEmail\": false
                },
                \"disableResolveMessage\": false
            }" 2>&1)
    else
        # Update existing contact point
        response=$(curl -s -w "\n%{http_code}" \
            -X PUT "http://localhost:${grafana_port}/api/v1/provisioning/contact-points/${uid}" \
            -u "${grafana_user}:${grafana_pass}" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"xrpl-monitor-email\",
                \"type\": \"email\",
                \"settings\": {
                    \"addresses\": \"${email}\",
                    \"singleEmail\": false
                },
                \"disableResolveMessage\": false
            }" 2>&1)
    fi

    local http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "200" ] || [ "$http_code" = "202" ]; then
        return 0
    else
        echo -e "${RED}Failed to update contact point (HTTP $http_code)${NC}"
        return 1
    fi
}

# Disable Gmail alerts
disable_gmail_alerts() {
    if [ -f .env ]; then
        sed -i 's/^GF_SMTP_ENABLED=true/GF_SMTP_ENABLED=false/' .env
    fi
}

# Enable Gmail alerts (if previously disabled)
enable_gmail_alerts() {
    if [ -f .env ]; then
        sed -i 's/^GF_SMTP_ENABLED=false/GF_SMTP_ENABLED=true/' .env
    fi
}

# Test Gmail alert via Grafana API
test_gmail_alert() {
    local grafana_port=${GRAFANA_PORT:-3000}

    echo ""
    echo "To test your Gmail alert configuration:"
    echo ""
    echo "  1. Open Grafana: http://localhost:${grafana_port}"
    echo "  2. Log in with admin credentials"
    echo "  3. Go to: Alerting → Contact points"
    echo "  4. Click 'View' on the right of xrpl-monitor-email"
    echo "  5. Click 'Test' → 'Send test notification'"
    echo "  6. Check your inbox (and spam folder)"
    echo ""
    echo "If you don't receive the test email:"
    echo "  - Verify App Password is correct"
    echo "  - Check that 2FA is enabled on your Google account"
    echo "  - Look for security alerts in your Gmail inbox"
    echo "  - Check logs: docker compose logs grafana | grep -i smtp"
    echo ""
    echo "See docs/ALERTS.md for detailed troubleshooting."
    echo ""
}

# Show current Gmail config screen
show_gmail_current_config() {
    source .env 2>/dev/null

    local masked_email=$(mask_email "$GF_SMTP_USER")
    local status="Enabled"
    local status_color="${GREEN}"

    if [ "$GF_SMTP_ENABLED" != "true" ]; then
        status="Disabled"
        status_color="${YELLOW}"
    fi

    clear
    echo ""
    echo -e "${BLUE}━━━ Gmail Alert Configuration ━━━${NC}"
    echo ""
    echo "Current Configuration:"
    echo "  Email:        ${masked_email}"
    echo "  App Password: ****  (configured)"
    echo -e "  Status:       ${status_color}${status}${NC}"
    echo ""
    echo "Options:"
    echo "  [u] Update email address"
    echo "  [p] Update app password"
    echo "  [t] How to test email alert"
    if [ "$GF_SMTP_ENABLED" = "true" ]; then
        echo "  [d] Disable email alerts"
    else
        echo "  [e] Enable email alerts"
    fi
    echo "  [b] Back to main menu"
    echo ""

    read -p "Choose: " config_choice

    case "${config_choice,,}" in
        u)
            setup_gmail_email
            ;;
        p)
            setup_gmail_password true  # true = update mode
            ;;
        t)
            test_gmail_alert
            read -p "Press Enter to continue..."
            show_gmail_current_config
            ;;
        d)
            echo ""
            print_info "Disabling email alerts..."
            disable_gmail_alerts
            docker compose up -d grafana --force-recreate >/dev/null 2>&1
            print_status "Email alerts disabled"
            sleep 2
            show_gmail_current_config
            ;;
        e)
            echo ""
            print_info "Enabling email alerts..."
            enable_gmail_alerts
            docker compose up -d grafana --force-recreate >/dev/null 2>&1
            print_status "Email alerts enabled"
            sleep 2
            show_gmail_current_config
            ;;
        b)
            return
            ;;
        *)
            show_gmail_current_config
            ;;
    esac
}

# Setup Gmail email address
setup_gmail_email() {
    local update_mode=${1:-false}

    clear
    echo ""
    echo -e "${BLUE}━━━ Gmail Alert Setup ━━━${NC}"
    echo ""
    echo "XRPL Monitor can send email alerts for all 14 configured alerts, such as:"
    echo "  • Validator not proposing"
    echo "  • Node offline or degraded"
    echo "  • Low peer count or amendment blocked"
    echo "  • ...and more"
    echo ""
    echo "Requirements:"
    echo "  • Gmail account"
    echo "  • Gmail App Password (NOT your regular password)"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local email=""
    while true; do
        read -p "Enter your Gmail address: " email

        if [ -z "$email" ]; then
            echo ""
            read -p "Cancel setup? [y/N]: " cancel
            if [[ "${cancel,,}" == "y" ]]; then
                return 1
            fi
            continue
        fi

        if validate_gmail "$email"; then
            print_status "Email accepted: ${email}"
            break
        else
            print_error "Invalid: Must be a @gmail.com address"
            echo ""
        fi
    done

    echo ""
    read -p "Is this correct? [Y/n]: " confirm
    if [[ "${confirm,,}" == "n" ]]; then
        setup_gmail_email "$update_mode"
        return $?
    fi

    # Store email for later
    GMAIL_ADDRESS="$email"

    # If update mode and only updating email, apply now
    if [ "$update_mode" = true ]; then
        source .env 2>/dev/null
        local current_password="${GF_SMTP_PASSWORD}"

        echo ""
        print_info "Updating email address..."
        update_env_gmail "$email" "$current_password"
        update_contact_points "$email"

        echo ""
        print_info "Recreating Grafana container..."
        docker compose up -d grafana --force-recreate >/dev/null 2>&1
        sleep 5

        print_status "Email address updated!"
        show_gmail_test_instructions
        read -p "Press Enter to continue..."
        show_gmail_current_config
        return 0
    fi

    # Continue to password setup
    setup_gmail_password false
}

# Setup Gmail App Password
setup_gmail_password() {
    local update_only=${1:-false}

    clear
    echo ""
    echo -e "${BLUE}━━━ Gmail App Password ━━━${NC}"
    echo ""
    echo "Gmail requires an 'App Password' for SMTP access."
    echo "This is a 16-character code (NOT your regular password)."
    echo ""
    echo -e "${CYAN}How to get an App Password:${NC}"
    echo "  1. Go to: https://myaccount.google.com/apppasswords"
    echo "  2. Sign in to your Google account"
    echo "  3. Select app: 'Mail'"
    echo "  4. Select device: 'Other' → name it 'XRPL Monitor'"
    echo "  5. Click 'Generate'"
    echo "  6. Copy the 16-character password"
    echo ""
    echo -e "${YELLOW}Note: 2-Factor Authentication must be enabled on your Google account.${NC}"
    echo "See docs/ALERTS.md for detailed instructions."
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local password=""
    while true; do
        read -s -p "Enter App Password: " password
        echo ""

        if [ -z "$password" ]; then
            echo ""
            read -p "Cancel setup? [y/N]: " cancel
            if [[ "${cancel,,}" == "y" ]]; then
                return 1
            fi
            continue
        fi

        # Remove spaces from password
        password="${password// /}"

        if validate_app_password "$password"; then
            print_status "Password format valid (16 characters)"
            break
        else
            print_error "Invalid: App Password must be 16 characters"
            echo "  (spaces are automatically removed)"
            echo ""
        fi
    done

    # Show masked password so user can verify
    local masked_pwd=$(mask_password "$password")
    echo ""
    echo "You entered: ${masked_pwd}"
    echo ""
    echo "Options:"
    echo "  [Enter] Continue (password looks correct)"
    echo "  [r]     Re-enter password"
    echo "  [b]     Back/Cancel"
    echo ""
    read -p "Choose: " pwd_choice

    case "${pwd_choice,,}" in
        r)
            setup_gmail_password "$update_only"
            return $?
            ;;
        b)
            return 1
            ;;
    esac

    # Store password
    GMAIL_PASSWORD="$password"

    # If update mode, apply now
    if [ "$update_only" = true ]; then
        source .env 2>/dev/null
        local current_email="${GF_SMTP_USER}"

        echo ""
        print_info "Updating app password..."
        update_env_gmail "$current_email" "$password"

        echo ""
        print_info "Recreating Grafana container..."
        docker compose up -d grafana --force-recreate >/dev/null 2>&1
        sleep 5

        print_status "App password updated!"
        show_gmail_test_instructions
        read -p "Press Enter to continue..."
        show_gmail_current_config
        return 0
    fi

    # Continue to confirmation
    confirm_gmail_setup
}

# Confirm and apply Gmail setup
confirm_gmail_setup() {
    clear
    echo ""
    echo -e "${BLUE}━━━ Confirm Gmail Configuration ━━━${NC}"
    echo ""
    echo "Email Address:  ${GMAIL_ADDRESS}"
    echo "App Password:   ****............****  (configured)"
    echo ""
    echo "This will update:"
    echo "  • .env (SMTP settings)"
    echo "  • contact-points.yaml (alert recipient)"
    echo ""
    echo "Then recreate Grafana container to apply changes."
    echo -e "${YELLOW}⚠ This will NOT affect your dashboards or metrics data.${NC}"
    echo ""
    echo "Options:"
    echo "  [Enter] Apply configuration"
    echo "  [e]     Edit settings"
    echo "  [c]     Cancel"
    echo ""

    read -p "Choose: " confirm_choice

    case "${confirm_choice,,}" in
        e)
            setup_gmail_email
            return $?
            ;;
        c)
            print_info "Setup cancelled"
            sleep 2
            return 1
            ;;
    esac

    # Apply the configuration
    apply_gmail_setup
}

# Apply Gmail configuration
apply_gmail_setup() {
    echo ""
    echo -e "${BLUE}━━━ Applying Gmail Configuration ━━━${NC}"
    echo ""

    print_info "Updating .env with SMTP settings..."
    update_env_gmail "$GMAIL_ADDRESS" "$GMAIL_PASSWORD"
    print_status ".env updated"

    print_info "Updating contact-points.yaml..."
    if update_contact_points "$GMAIL_ADDRESS"; then
        print_status "contact-points.yaml updated"
    else
        print_warning "contact-points.yaml not found (alerts may need manual config)"
    fi

    print_info "Recreating Grafana container..."
    docker compose up -d grafana --force-recreate >/dev/null 2>&1

    print_info "Waiting for Grafana to start (10 seconds)..."
    sleep 10

    # Check Grafana health
    local grafana_port=${GRAFANA_PORT:-3000}
    if curl -s "http://localhost:${grafana_port}/api/health" 2>/dev/null | grep -q "ok"; then
        print_status "Grafana is healthy"
    else
        print_warning "Grafana may still be starting..."
    fi

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    print_status "Gmail alerts configured successfully!"
    echo ""
    echo "To test your configuration:"
    echo "  1. Open Grafana: http://localhost:${grafana_port}"
    echo -e "  2. ${YELLOW}Refresh your browser${NC} (Ctrl+R or Cmd+R)"
    echo "  3. Go to: Alerting → Contact points"
    echo "  4. Click 'View' on the right of xrpl-monitor-email"
    echo "  5. Click 'Test' → 'Send test notification'"
    echo "  6. Check your inbox for the test email"
    echo ""
    echo "See docs/ALERTS.md for more details."
}

# Main Gmail setup menu entry point
setup_gmail_alerts() {
    if ! is_dashboard_installed; then
        prompt_install
        return
    fi
    if check_gmail_config; then
        show_gmail_current_config
    else
        setup_gmail_email false
    fi
}

# Advanced settings menu
advanced_settings_menu() {
    if ! is_dashboard_installed; then
        prompt_install
        return
    fi
    clear
    echo ""
    echo "Advanced Settings"
    echo ""
    echo "  1) Adjust data retention period"
    echo "  2) Restore default dashboard"
    echo "  3) Back to main menu"
    echo ""

    read -p "Select option [1-3]: " settings_choice

    case $settings_choice in
        1)
            adjust_retention
            ;;
        2)
            restore_default_dashboard
            ;;
        3)
            return
            ;;
        *)
            print_error "Invalid choice"
            sleep 2
            ;;
    esac
}

# Interactive menu
show_menu() {
    clear
    show_banner

    echo -e "${BLUE}💡 Tip: For quick commands, run './manage.sh --help'${NC}"
    echo ""

    show_status

    echo "What would you like to do?"
    echo ""
    echo "   1) Start the stack"
    echo "   2) Stop the stack"
    echo "   3) Restart the stack"
    echo "   4) Manage a single service"
    echo "   5) View logs (all services)"
    echo "   6) View logs (specific service)"
    echo "   7) Check service status"
    echo "   8) Rebuild service"
    echo "   9) Backup & Restore"
    echo "  10) Update Dashboard (after git pull)"
    echo "  11) Setup Gmail Alerts"
    echo "  12) Advanced settings"
    echo "  13) Exit"
    echo ""

    read -p "Enter your choice 1-13 [13]: " choice
    choice=${choice:-13}

    case $choice in
        1)
            echo ""
            start_services
            ;;
        2)
            if ! is_dashboard_installed; then
                prompt_install
            else
                echo ""
                read -p "Stop the stack? [y/N]: " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    echo ""
                    stop_services
                else
                    print_info "Cancelled"
                fi
            fi
            ;;
        3)
            echo ""
            restart_services
            ;;
        4)
            manage_single_service
            ;;
        5)
            if ! is_dashboard_installed; then
                prompt_install
            else
                echo ""
                print_info "Viewing logs for all services... (Press Ctrl+C to exit)"
                echo ""
                docker compose logs -f --tail=50
            fi
            ;;
        6)
            if ! is_dashboard_installed; then
                prompt_install
            else
                echo ""
                echo "Available services: ${SERVICES[*]}"
                read -p "Enter service name [collector]: " service
                service=${service:-collector}
                echo ""
                view_logs "$service"
            fi
            ;;
        7)
            echo ""
            show_status
            ;;
        8)
            if ! is_dashboard_installed; then
                prompt_install
            else
                echo ""
                echo "Available services: ${SERVICES[*]}"
                read -p "Enter service name: " service
                echo ""
                rebuild_service "$service"
            fi
            ;;
        9)
            backup_restore_menu
            ;;
        10)
            update_dashboard_menu
            ;;
        11)
            setup_gmail_alerts
            ;;
        12)
            advanced_settings_menu
            ;;
        13)
            echo ""
            print_info "Goodbye!"
            exit 0
            ;;
        *)
            echo ""
            print_error "Invalid choice. Please select 1-13."
            sleep 2
            ;;
    esac

    # Return to menu unless exiting
    if [ "$choice" != "13" ]; then
        echo ""
        read -p "Press Enter to return to menu..."
        show_menu
    fi
}

# Main
main() {
    # Check if running in project directory
    if [ ! -f "docker-compose.yml" ]; then
        print_error "Error: docker-compose.yml not found"
        print_info "Please run this script from the XRPL Monitor directory"
        exit 1
    fi

    # Parse command line arguments
    case "${1:-}" in
        start)
            show_banner
            start_services
            ;;
        stop)
            show_banner
            stop_services
            ;;
        restart)
            show_banner
            restart_services "$2"
            ;;
        status)
            show_banner
            show_status
            ;;
        logs)
            show_banner
            view_logs "$2"
            ;;
        rebuild)
            show_banner
            rebuild_service "$2"
            ;;
        --help|-h|help)
            show_help
            ;;
        "")
            # No arguments - show interactive menu
            show_menu
            ;;
        *)
            print_error "Unknown command: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main
main "$@"
