#!/bin/bash
#
# XRPL Monitor v3.0 - Installation Script
# Interactive wizard with navigation and clean UI
#
# Version: 3.0.0
# Last Updated: 2025-12-04
#
# Flow:
#   Step 1: rippled Detection - Find and verify rippled connectivity
#   Step 2: System Requirements - Check/install Docker & Docker Compose
#   Step 3: Dashboard Ports - Configure monitoring service ports
#   Step 4: Review & Install - Summary and installation
#

set -e  # Exit on error

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "" 1>&2
    echo "Error: This script must be run with root privileges." 1>&2
    echo "" 1>&2
    echo "Root access is required to:" 1>&2
    echo "  - Install system dependencies (Docker, curl, jq, etc.)" 1>&2
    echo "  - Configure Docker permissions" 1>&2
    echo "  - Set up systemd services" 1>&2
    echo "" 1>&2
    echo "Please run the installer with sudo:" 1>&2
    echo "  sudo ./install.sh" 1>&2
    echo "" 1>&2
    exit 1
fi

# Installation log file
LOG_FILE="/tmp/xrpl-monitor-install-$(date +%Y%m%d-%H%M%S).log"

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

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
    printf "\033c"  # More forceful clear that resets terminal
    echo -e "${BLUE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║           XRPL Monitor v3.0 - Installation Wizard             ║
║    Real-time validator monitoring with automated alerting     ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Function to print status messages
print_status() {
    echo -e "${GREEN}✓${NC} $1"
    log "SUCCESS: $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    log "ERROR: $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
    log "INFO: $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    log "WARNING: $1"
}

print_step() {
    echo -e "${CYAN}${BOLD}━━━ Step $1 of 4: $2 ━━━${NC}"
    echo ""
}

# Install required system dependencies (curl, jq)
install_dependencies() {
    local missing_pkgs=""

    command -v curl &> /dev/null || missing_pkgs="$missing_pkgs curl"
    command -v jq &> /dev/null || missing_pkgs="$missing_pkgs jq"

    if [ -n "$missing_pkgs" ]; then
        echo ""
        print_info "Installing required packages:$missing_pkgs"
        if apt-get update -qq && apt-get install -y -qq $missing_pkgs > /dev/null 2>&1; then
            print_status "Required packages installed"
        else
            print_error "Failed to install packages:$missing_pkgs"
            echo "Please install manually: sudo apt-get install$missing_pkgs"
            exit 1
        fi
    fi
}

# Install dependencies early (before any curl/jq usage)
install_dependencies

# Progress breadcrumb - NEW ORDER
show_progress() {
    local current=$1
    echo ""
    echo -e "${BLUE}Progress: ${NC}"

    # Step 1: rippled
    if [ $current -ge 1 ]; then
        echo -ne "${GREEN}[✓] rippled${NC}"
    else
        echo -ne "${BLUE}[ ] rippled${NC}"
    fi

    echo -n " → "

    # Step 2: Requirements
    if [ $current -ge 2 ]; then
        echo -ne "${GREEN}[✓] Requirements${NC}"
    elif [ $current -eq 2 ]; then
        echo -ne "${CYAN}[•] Requirements${NC}"
    else
        echo -ne "${BLUE}[ ] Requirements${NC}"
    fi

    echo -n " → "

    # Step 3: Ports
    if [ $current -ge 3 ]; then
        echo -ne "${GREEN}[✓] Ports${NC}"
    elif [ $current -eq 3 ]; then
        echo -ne "${CYAN}[•] Ports${NC}"
    else
        echo -ne "${BLUE}[ ] Ports${NC}"
    fi

    echo -n " → "

    # Step 4: Install
    if [ $current -ge 4 ]; then
        echo -ne "${GREEN}[✓] Install${NC}"
    elif [ $current -eq 4 ]; then
        echo -ne "${CYAN}[•] Install${NC}"
    else
        echo -ne "${BLUE}[ ] Install${NC}"
    fi

    echo ""
    echo ""
}

# State variables (preserved across navigation)
RIPPLED_WS_URL=""
RIPPLED_HTTP_URL=""
RIPPLED_DATA_PATH=""
RIPPLED_TYPE=""
VALIDATOR_PUBLIC_KEY=""
GRAFANA_PORT=""
VICTORIA_PORT=""
NODE_EXPORTER_PORT=""
UPTIME_EXPORTER_PORT=""
STATE_EXPORTER_PORT=""
VMAGENT_PORT=""
COLLECTOR_PORT=""
RIPPLED_CHECKED=false
REQUIREMENTS_CHECKED=false

# Cleanup function for rollback
cleanup_on_error() {
    print_error "Installation failed. See $LOG_FILE for details."
    if [ -f "docker-compose.yml.backup" ]; then
        print_info "Restoring docker-compose.yml from backup..."
        mv docker-compose.yml.backup docker-compose.yml
    fi
    exit 1
}

trap cleanup_on_error ERR

log "Installation started"

# ==============================================================================
# DASHBOARD IMPORT VIA GRAFANA API
# ==============================================================================
# Import dashboards via API instead of file provisioning.
# This allows users to customize dashboards and save changes.

import_dashboards_via_api() {
    local grafana_port=$1
    local max_wait=60
    local wait_count=0

    print_info "Importing dashboards via Grafana API..."

    # Wait for Grafana to be ready
    while [ $wait_count -lt $max_wait ]; do
        if curl -s "http://localhost:${grafana_port}/api/health" 2>/dev/null | grep -q "ok"; then
            break
        fi
        sleep 2
        wait_count=$((wait_count + 2))
    done

    if [ $wait_count -ge $max_wait ]; then
        print_warning "Grafana not ready after ${max_wait}s, skipping API import"
        print_warning "Dashboards can be imported later via: ./manage.sh → Advanced → Restore default"
        return 1
    fi

    # Import main dashboard
    local main_dashboard="config/grafana/provisioning/dashboards/xrpl-validator-main.json"
    if [ -f "$main_dashboard" ]; then
        # Prepare import payload: remove id, set version to 0, wrap for import API
        local import_payload
        import_payload=$(jq 'del(.id) | .version = 0 | {dashboard: ., overwrite: true}' "$main_dashboard" 2>/dev/null)

        if [ -n "$import_payload" ]; then
            local response
            response=$(echo "$import_payload" | curl -s -w "\n%{http_code}" \
                -X POST "http://localhost:${grafana_port}/api/dashboards/db" \
                -u "admin:admin" \
                -H "Content-Type: application/json" \
                -d @- 2>&1)

            local http_code=$(echo "$response" | tail -n1)
            local body=$(echo "$response" | head -n-1)

            if [ "$http_code" = "200" ]; then
                print_status "Main dashboard imported successfully"
                log "Dashboard imported: xrpl-validator-main.json"
            elif [ "$http_code" = "412" ]; then
                # Already exists - OK
                print_status "Main dashboard imported (already exists)"
            else
                print_warning "Dashboard import returned HTTP $http_code"
                log "Dashboard import warning: HTTP $http_code - $body"
            fi
        else
            print_warning "Failed to prepare main dashboard payload"
        fi
    else
        print_warning "Main dashboard file not found: $main_dashboard"
    fi

    # Import cyberpunk dashboard if it exists
    local cyberpunk_dashboard="config/grafana/provisioning/dashboards/xrpl-validator-cyberpunk.json"
    if [ -f "$cyberpunk_dashboard" ]; then
        local import_payload
        import_payload=$(jq 'del(.id) | .version = 0 | {dashboard: ., overwrite: true}' "$cyberpunk_dashboard" 2>/dev/null)

        if [ -n "$import_payload" ]; then
            local response
            response=$(echo "$import_payload" | curl -s -w "\n%{http_code}" \
                -X POST "http://localhost:${grafana_port}/api/dashboards/db" \
                -u "admin:admin" \
                -H "Content-Type: application/json" \
                -d @- 2>&1)

            local http_code=$(echo "$response" | tail -n1)

            if [ "$http_code" = "200" ] || [ "$http_code" = "412" ]; then
                print_status "Cyberpunk dashboard imported"
                log "Dashboard imported: xrpl-validator-cyberpunk.json"
            fi
        fi
    fi

    # Import light mode dashboard if it exists
    local light_dashboard="config/grafana/provisioning/dashboards/xrpl-validator-light-mode.json"
    if [ -f "$light_dashboard" ]; then
        local import_payload
        import_payload=$(jq 'del(.id) | .version = 0 | {dashboard: ., overwrite: true}' "$light_dashboard" 2>/dev/null)

        if [ -n "$import_payload" ]; then
            local response
            response=$(echo "$import_payload" | curl -s -w "\n%{http_code}" \
                -X POST "http://localhost:${grafana_port}/api/dashboards/db" \
                -u "admin:admin" \
                -H "Content-Type: application/json" \
                -d @- 2>&1)

            local http_code=$(echo "$response" | tail -n1)

            if [ "$http_code" = "200" ] || [ "$http_code" = "412" ]; then
                print_status "Light mode dashboard imported"
                log "Dashboard imported: xrpl-validator-light-mode.json"
            fi
        fi
    fi

    return 0
}

# ==============================================================================
# SET HOME DASHBOARD VIA GRAFANA API
# ==============================================================================
# Set the default home dashboard via API (not env var) to allow dashboard saving.
# Using GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH causes "Save as copy" limitation.

set_home_dashboard() {
    local grafana_port=$1

    # Set home dashboard for organization via API
    # This allows the dashboard to be fully editable (no "Save as copy" restriction)
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -X PATCH "http://localhost:${grafana_port}/api/org/preferences" \
        -u "admin:admin" \
        -H "Content-Type: application/json" \
        -d '{"homeDashboardUID": "xrpl-validator-monitor-full"}' 2>&1)

    local http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "200" ]; then
        print_status "Home dashboard set to XRPL Validator Dashboard"
        log "Home dashboard set via API: xrpl-validator-monitor-full"
    else
        print_warning "Could not set home dashboard (HTTP $http_code)"
        log "Home dashboard warning: HTTP $http_code"
    fi
}

# ==============================================================================
# CONTACT POINT IMPORT VIA GRAFANA API
# ==============================================================================
# Import default email contact point via API instead of file provisioning.
# This allows users to fully edit/delete contact points in Grafana UI.

import_contact_point_via_api() {
    local grafana_port=$1

    print_info "Creating default email contact point via API..."

    # Create email contact point with placeholder
    # Users can edit this in Grafana UI: Alerting → Contact points
    local payload='{
        "name": "xrpl-monitor-email",
        "type": "email",
        "settings": {
            "addresses": "example@email.com",
            "singleEmail": false
        },
        "disableResolveMessage": false
    }'

    local response
    response=$(echo "$payload" | curl -s -w "\n%{http_code}" \
        -X POST "http://localhost:${grafana_port}/api/v1/provisioning/contact-points" \
        -u "admin:admin" \
        -H "Content-Type: application/json" \
        -d @- 2>&1)

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)

    if [ "$http_code" = "202" ] || [ "$http_code" = "200" ]; then
        print_status "Email contact point created"
        print_info "Configure your email: Grafana → Alerting → Contact points"
        log "Contact point created: xrpl-monitor-email"
    elif echo "$body" | grep -q "already exists"; then
        print_status "Email contact point already exists"
    else
        print_warning "Contact point creation returned HTTP $http_code"
        log "Contact point warning: HTTP $http_code - $body"
    fi

    # Now set up the notification policy to use this contact point
    print_info "Configuring notification policy..."

    local policy_payload='{
        "receiver": "xrpl-monitor-email",
        "group_by": ["grafana_folder", "alertname"],
        "group_wait": "30s",
        "group_interval": "5m",
        "repeat_interval": "4h"
    }'

    response=$(echo "$policy_payload" | curl -s -w "\n%{http_code}" \
        -X PUT "http://localhost:${grafana_port}/api/v1/provisioning/policies" \
        -u "admin:admin" \
        -H "Content-Type: application/json" \
        -d @- 2>&1)

    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "202" ] || [ "$http_code" = "200" ]; then
        print_status "Notification policy configured"
        log "Notification policy set to use xrpl-monitor-email"
    else
        print_warning "Notification policy returned HTTP $http_code"
        log "Notification policy warning: HTTP $http_code"
    fi

    return 0
}

# ==============================================================================
# STEP 1: RIPPLED DETECTION (NEW - was Step 3)
# ==============================================================================

step_rippled_detection() {
    clear_screen
    show_progress 1
    print_step 1 "rippled Detection"

    if [ "$RIPPLED_CHECKED" = true ] && [ -n "$RIPPLED_WS_URL" ]; then
        print_info "rippled previously detected and verified."
        echo ""
        echo "Current configuration:"
        echo "  WebSocket:  $RIPPLED_WS_URL"
        echo "  HTTP RPC:   $RIPPLED_HTTP_URL"
        [ -n "$VALIDATOR_PUBLIC_KEY" ] && echo "  Pubkey:     ${VALIDATOR_PUBLIC_KEY:0:20}..."
        echo ""
        echo "Options:"
        echo "  [Enter] Continue with this configuration"
        echo "  [r]     Re-detect rippled"
        echo "  [q]     Quit installation"
        echo ""
        read -p "Choose: " -n 1 -r choice </dev/tty || choice=""
        echo

        case $choice in
            r|R)
                RIPPLED_CHECKED=false
                RIPPLED_WS_URL=""
                RIPPLED_HTTP_URL=""
                # Fall through to detection
                ;;
            q|Q)
                print_info "Installation cancelled"
                exit 0
                ;;
            *)
                return 0  # Continue to next step
                ;;
        esac
    fi

    echo "The XRPL Monitor dashboard requires a running rippled node."
    echo ""
    echo "This step will:"
    echo "  • Scan for rippled (native or Docker)"
    echo "  • Detect WebSocket and HTTP RPC ports"
    echo "  • Verify connectivity"
    echo ""
    echo "Options:"
    echo "  [Enter] Scan for rippled"
    echo "  [m]     Enter rippled URLs manually"
    echo "  [q]     Quit installation"
    echo ""
    while true; do
        read -p "Choose: " -n 1 -r choice </dev/tty || choice=""
        echo

        case $choice in
            q|Q) print_info "Installation cancelled"; exit 0 ;;
            m|M)
                # Manual entry
                echo ""
                while true; do
                    read -p "WebSocket URL or port [ws://localhost:6006]: " ws_input </dev/tty || ws_input=""
                    if [ -z "$ws_input" ]; then
                        RIPPLED_WS_URL="ws://localhost:6006"
                        break
                    elif [[ "$ws_input" =~ ^[0-9]+$ ]]; then
                        RIPPLED_WS_URL="ws://localhost:$ws_input"
                        break
                    elif [[ "$ws_input" =~ ^wss?://[a-zA-Z0-9.-]+:[0-9]+$ ]] || [[ "$ws_input" =~ ^wss?://[a-zA-Z0-9.-]+$ ]]; then
                        RIPPLED_WS_URL="$ws_input"
                        break
                    else
                        print_warning "Invalid input. Enter a port number (e.g., 6006) or full URL (e.g., ws://localhost:6006)"
                    fi
                done

                while true; do
                    read -p "HTTP RPC URL or port [http://localhost:5005]: " http_input </dev/tty || http_input=""
                    if [ -z "$http_input" ]; then
                        RIPPLED_HTTP_URL="http://localhost:5005"
                        break
                    elif [[ "$http_input" =~ ^[0-9]+$ ]]; then
                        RIPPLED_HTTP_URL="http://localhost:$http_input"
                        break
                    elif [[ "$http_input" =~ ^https?://[a-zA-Z0-9.-]+:[0-9]+$ ]] || [[ "$http_input" =~ ^https?://[a-zA-Z0-9.-]+$ ]]; then
                        RIPPLED_HTTP_URL="$http_input"
                        break
                    else
                        print_warning "Invalid input. Enter a port number (e.g., 5005) or full URL (e.g., http://localhost:5005)"
                    fi
                done

                echo ""
                print_info "Verifying connectivity..."
                break
                ;;
            "")
                # Auto-detect (Enter key pressed)
                break
                ;;
            *)
                # Invalid input - show error and loop
                print_warning "Invalid option '$choice'. Please press Enter, m, or q."
                continue
                ;;
        esac
    done

    if [ "$choice" = "" ]; then
        # Auto-detect
            echo ""
            print_info "Scanning for rippled..."
            echo ""

            # Detect rippled type (native or Docker)
            if command -v docker &> /dev/null; then
                DOCKER_RIPPLED=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i rippled | head -1 || true)
                if [ -n "$DOCKER_RIPPLED" ]; then
                    RIPPLED_TYPE="docker"
                    print_status "Found rippled in Docker: $DOCKER_RIPPLED"
                fi
            fi

            if [ -z "$RIPPLED_TYPE" ]; then
                if pgrep -x rippled > /dev/null 2>&1; then
                    RIPPLED_TYPE="native"
                    print_status "Found rippled running natively (PID: $(pgrep -x rippled))"
                fi
            fi

            if [ -z "$RIPPLED_TYPE" ]; then
                print_error "rippled not found!"
                echo ""
                echo "Please ensure rippled is installed and running before installing XRPL Monitor."
                echo ""
                echo "Options:"
                echo "  [m] Enter rippled URLs manually"
                echo "  [q] Quit installation"
                echo ""
                while true; do
                    read -p "Choose: " -n 1 -r retry </dev/tty || retry=""
                    echo

                    case $retry in
                        m|M)
                            echo ""
                            while true; do
                                read -p "WebSocket URL or port [ws://localhost:6006]: " ws_input </dev/tty || ws_input=""
                                if [ -z "$ws_input" ]; then
                                    RIPPLED_WS_URL="ws://localhost:6006"
                                    break
                                elif [[ "$ws_input" =~ ^[0-9]+$ ]]; then
                                    RIPPLED_WS_URL="ws://localhost:$ws_input"
                                    break
                                elif [[ "$ws_input" =~ ^wss?://[a-zA-Z0-9.-]+:[0-9]+$ ]] || [[ "$ws_input" =~ ^wss?://[a-zA-Z0-9.-]+$ ]]; then
                                    RIPPLED_WS_URL="$ws_input"
                                    break
                                else
                                    print_warning "Invalid input. Enter a port number (e.g., 6006) or full URL (e.g., ws://localhost:6006)"
                                fi
                            done

                            while true; do
                                read -p "HTTP RPC URL or port [http://localhost:5005]: " http_input </dev/tty || http_input=""
                                if [ -z "$http_input" ]; then
                                    RIPPLED_HTTP_URL="http://localhost:5005"
                                    break
                                elif [[ "$http_input" =~ ^[0-9]+$ ]]; then
                                    RIPPLED_HTTP_URL="http://localhost:$http_input"
                                    break
                                elif [[ "$http_input" =~ ^https?://[a-zA-Z0-9.-]+:[0-9]+$ ]] || [[ "$http_input" =~ ^https?://[a-zA-Z0-9.-]+$ ]]; then
                                    RIPPLED_HTTP_URL="$http_input"
                                    break
                                else
                                    print_warning "Invalid input. Enter a port number (e.g., 5005) or full URL (e.g., http://localhost:5005)"
                                fi
                            done
                            break
                            ;;
                        q|Q)
                            print_info "Installation cancelled"
                            exit 1
                            ;;
                        *)
                            print_warning "Invalid option '$retry'. Please press m or q."
                            continue
                            ;;
                    esac
                done
            else
                # Auto-detect ports by scanning listening ports
                echo ""
                print_info "Scanning for rippled API ports..."

                LISTENING_PORTS=$(ss -tuln 2>/dev/null | grep -E '127\.0\.0\.1:|localhost:|\*:|0\.0\.0\.0:' | awk '{print $5}' | grep -oE '[0-9]+$' | sort -nu || true)

                # Test for HTTP RPC
                for port in $LISTENING_PORTS; do
                    case $port in
                        22|80|443|3000|8080|8428|8427|9090|9100|9101|9102) continue ;;
                    esac

                    if timeout 2 curl -s "http://localhost:$port" \
                        -d '{"method":"server_info"}' \
                        -H "Content-Type: application/json" 2>/dev/null | grep -q '"result"'; then
                        RIPPLED_HTTP_URL="http://localhost:$port"
                        print_status "Found HTTP RPC on port $port"
                        break
                    fi
                done

                # Test for WebSocket - collect candidates then find admin port
                # Strategy: combine multiple detection methods for maximum compatibility
                WS_CANDIDATES=""

                # Method 1: Check ports that respond with "ripple" HTML (public WS ports)
                for port in $LISTENING_PORTS; do
                    case $port in
                        22|80|443|3000|8080|8428|8427|9090|9100|9101|9102) continue ;;
                    esac

                    # Skip HTTP port we found
                    if [ -n "$RIPPLED_HTTP_URL" ] && [[ "$RIPPLED_HTTP_URL" == *":$port" ]]; then
                        continue
                    fi

                    if timeout 2 curl -s "http://localhost:$port" 2>/dev/null | grep -qi "ripple"; then
                        WS_CANDIDATES="$WS_CANDIDATES $port"
                    fi
                done

                # Method 2: Add common rippled WebSocket ports if they're listening
                # These are typical admin WS ports that may not respond to HTTP GET
                for port in 6006 6005 6007 51233; do
                    # Skip if already in candidates
                    if echo "$WS_CANDIDATES" | grep -qw "$port"; then
                        continue
                    fi
                    # Skip HTTP port
                    if [ -n "$RIPPLED_HTTP_URL" ] && [[ "$RIPPLED_HTTP_URL" == *":$port" ]]; then
                        continue
                    fi
                    # Check if port is listening
                    if echo "$LISTENING_PORTS" | grep -qw "$port"; then
                        WS_CANDIDATES="$WS_CANDIDATES $port"
                    fi
                done

                # Method 3: For Docker rippled, check container port mappings
                if [ "$RIPPLED_TYPE" = "docker" ] && [ -n "$DOCKER_RIPPLED" ]; then
                    DOCKER_WS_PORTS=$(docker inspect "$DOCKER_RIPPLED" 2>/dev/null | \
                        jq -r '.[0].NetworkSettings.Ports | to_entries[] | select(.key | contains("/tcp")) | .value[]?.HostPort // empty' 2>/dev/null | sort -u)
                    for port in $DOCKER_WS_PORTS; do
                        # Skip if already in candidates or is HTTP port
                        if echo "$WS_CANDIDATES" | grep -qw "$port"; then
                            continue
                        fi
                        if [ -n "$RIPPLED_HTTP_URL" ] && [[ "$RIPPLED_HTTP_URL" == *":$port" ]]; then
                            continue
                        fi
                        # Skip peer port (usually 51235)
                        if [ "$port" = "51235" ]; then
                            continue
                        fi
                        WS_CANDIDATES="$WS_CANDIDATES $port"
                    done
                fi

                # If we found WebSocket candidates, test for admin access
                if [ -n "$WS_CANDIDATES" ]; then
                    # Check if websocket-client is available for admin detection
                    if python3 -c "import websocket" 2>/dev/null; then
                        # Try to find admin WebSocket port using Python
                        # Note: heredoc without quotes to allow $WS_CANDIDATES expansion
                        ADMIN_WS_PORT=$(python3 << PYEOF 2>/dev/null
import sys
try:
    import websocket
    import json

    candidates = [int(p) for p in "$WS_CANDIDATES".split()]

    for port in candidates:
        try:
            ws = websocket.create_connection(f"ws://localhost:{port}", timeout=3)
            ws.send(json.dumps({"command": "peers"}))
            result = json.loads(ws.recv())
            ws.close()

            # Check if we got peers (admin access) or forbidden error (no admin)
            if "peers" in result.get("result", {}):
                print(port)
                sys.exit(0)
            # Also check top-level error (some rippled versions)
            if result.get("error") == "forbidden":
                continue
        except:
            continue

    # No admin port found, return first candidate
    if candidates:
        print(candidates[0])
except Exception as e:
    pass
PYEOF
)
                        # Clean up - get only first line/word (remove any extra output)
                        ADMIN_WS_PORT=$(echo "$ADMIN_WS_PORT" | head -1 | tr -d '[:space:]')
                        if [ -n "$ADMIN_WS_PORT" ]; then
                            RIPPLED_WS_URL="ws://localhost:$ADMIN_WS_PORT"
                            # Check if this is admin or fallback
                            if python3 -c "
import websocket, json
ws = websocket.create_connection('ws://localhost:$ADMIN_WS_PORT', timeout=3)
ws.send(json.dumps({'command': 'peers'}))
r = json.loads(ws.recv())
ws.close()
exit(0 if 'peers' in r.get('result', {}) else 1)
" 2>/dev/null; then
                                print_status "Found admin WebSocket on port $ADMIN_WS_PORT"
                            else
                                print_status "Found WebSocket on port $ADMIN_WS_PORT"
                                print_warning "Note: This may be a public WebSocket port (admin port preferred)"
                            fi
                        else
                            # Fallback to first candidate if Python detection failed
                            FIRST_WS=$(echo $WS_CANDIDATES | awk '{print $1}')
                            RIPPLED_WS_URL="ws://localhost:$FIRST_WS"
                            print_status "Found WebSocket on port $FIRST_WS"
                        fi
                    else
                        # websocket-client not available, use first candidate and warn user
                        FIRST_WS=$(echo $WS_CANDIDATES | awk '{print $1}')
                        RIPPLED_WS_URL="ws://localhost:$FIRST_WS"
                        print_status "Found WebSocket on port $FIRST_WS"
                        # Check if there are multiple candidates
                        WS_COUNT=$(echo $WS_CANDIDATES | wc -w)
                        if [ "$WS_COUNT" -gt 1 ]; then
                            print_warning "Multiple WebSocket ports found: $WS_CANDIDATES"
                            print_warning "Could not detect admin port (websocket-client not installed)"
                            print_warning "If this is wrong, press 'e' to edit after detection completes"
                        fi
                    fi
                fi

                # Fallback - require user input if not found
                if [ -z "$RIPPLED_HTTP_URL" ]; then
                    print_warning "HTTP RPC not auto-detected"
                    while true; do
                        read -p "HTTP RPC port (e.g., 5005): " http_input </dev/tty || http_input=""
                        if [ -z "$http_input" ]; then
                            print_warning "Port is required. Please enter the HTTP RPC port number."
                            continue
                        elif [[ "$http_input" =~ ^[0-9]+$ ]]; then
                            RIPPLED_HTTP_URL="http://localhost:$http_input"
                            break
                        elif [[ "$http_input" =~ ^https?://[a-zA-Z0-9.-]+:[0-9]+$ ]] || [[ "$http_input" =~ ^https?://[a-zA-Z0-9.-]+$ ]]; then
                            RIPPLED_HTTP_URL="$http_input"
                            break
                        else
                            print_warning "Invalid input. Enter a port number (e.g., 5005)"
                        fi
                    done
                fi

                if [ -z "$RIPPLED_WS_URL" ]; then
                    print_warning "WebSocket not auto-detected"
                    while true; do
                        read -p "WebSocket port (e.g., 6006): " ws_input </dev/tty || ws_input=""
                        if [ -z "$ws_input" ]; then
                            print_warning "Port is required. Please enter the WebSocket port number."
                            continue
                        elif [[ "$ws_input" =~ ^[0-9]+$ ]]; then
                            RIPPLED_WS_URL="ws://localhost:$ws_input"
                            break
                        elif [[ "$ws_input" =~ ^wss?://[a-zA-Z0-9.-]+:[0-9]+$ ]] || [[ "$ws_input" =~ ^wss?://[a-zA-Z0-9.-]+$ ]]; then
                            RIPPLED_WS_URL="$ws_input"
                            break
                        else
                            print_warning "Invalid input. Enter a port number (e.g., 6006)"
                        fi
                    done
                fi
            fi
    fi

    # Verify connectivity
    echo ""
    print_info "Verifying rippled connectivity..."

    # Test HTTP RPC
    local http_state=""
    http_state=$(curl -s -m 5 -X POST -H 'Content-Type: application/json' \
        -d '{"method":"server_info"}' "$RIPPLED_HTTP_URL" 2>/dev/null | \
        grep -o '"server_state":"[^"]*"' | cut -d'"' -f4 || true)

    if [ -n "$http_state" ]; then
        case "$http_state" in
            proposing|full)
                print_status "HTTP RPC: ${GREEN}$http_state${NC} - $RIPPLED_HTTP_URL"
                ;;
            connected|syncing|tracking)
                print_warning "HTTP RPC: ${YELLOW}$http_state${NC} - $RIPPLED_HTTP_URL (still syncing)"
                ;;
            *)
                print_warning "HTTP RPC: $http_state - $RIPPLED_HTTP_URL"
                ;;
        esac

        # Extract validator public key
        VALIDATOR_PUBLIC_KEY=$(curl -s -m 5 -X POST -H 'Content-Type: application/json' \
            -d '{"method":"server_info"}' "$RIPPLED_HTTP_URL" 2>/dev/null | \
            grep -o '"pubkey_validator":"[^"]*"' | cut -d'"' -f4 || true)

        if [ -n "$VALIDATOR_PUBLIC_KEY" ]; then
            print_status "Validator pubkey: ${VALIDATOR_PUBLIC_KEY:0:20}..."
        fi
    else
        print_error "HTTP RPC unreachable: $RIPPLED_HTTP_URL"
        echo ""
        echo "Cannot connect to rippled HTTP RPC API."
        echo ""
        echo "Options:"
        echo "  [Enter/r] Re-enter URLs"
        echo "  [c]       Continue anyway (may cause issues)"
        echo "  [q]       Quit installation"
        echo ""
        while true; do
            read -p "Choose: " -n 1 -r retry </dev/tty || retry=""
            echo

            case $retry in
                r|R|"")
                    RIPPLED_CHECKED=false
                    step_rippled_detection
                    return $?
                    ;;
                c|C)
                    print_warning "Continuing without verified connectivity..."
                    break
                    ;;
                q|Q)
                    print_info "Installation cancelled"
                    exit 1
                    ;;
                *)
                    print_warning "Invalid option '$retry'. Please press Enter, r, c, or q."
                    continue
                    ;;
            esac
        done
    fi

    # Test WebSocket
    local ws_port=$(echo "$RIPPLED_WS_URL" | grep -oE '[0-9]+$')
    if timeout 2 curl -s "http://localhost:$ws_port" 2>/dev/null | grep -qi "ripple"; then
        print_status "WebSocket: healthy - $RIPPLED_WS_URL"
    else
        print_warning "WebSocket: could not verify - $RIPPLED_WS_URL"
    fi

    # Detect data directory
    if [ "$RIPPLED_TYPE" = "docker" ] && [ -n "$DOCKER_RIPPLED" ]; then
        # For Docker rippled, find the volume mount for /var/lib/rippled
        DOCKER_DATA_PATH=$(docker inspect "$DOCKER_RIPPLED" 2>/dev/null | jq -r '.[0].Mounts[] | select(.Destination == "/var/lib/rippled") | .Source' 2>/dev/null)
        if [ -n "$DOCKER_DATA_PATH" ] && sudo test -d "$DOCKER_DATA_PATH/db" 2>/dev/null; then
            RIPPLED_DATA_PATH="$DOCKER_DATA_PATH"
            print_status "Found Docker volume: $RIPPLED_DATA_PATH"
        else
            # Fallback to default path
            RIPPLED_DATA_PATH="/var/lib/rippled"
            print_warning "Could not detect Docker volume path, using default"
        fi
    elif [ "$RIPPLED_TYPE" = "native" ] && [ -d "/var/lib/rippled" ]; then
        RIPPLED_DATA_PATH="/var/lib/rippled"
    else
        RIPPLED_DATA_PATH="/var/lib/rippled"
    fi

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Detected Configuration:"
    echo "  WebSocket URL:    $RIPPLED_WS_URL"
    echo "  HTTP RPC URL:     $RIPPLED_HTTP_URL"
    echo "  Data Directory:   $RIPPLED_DATA_PATH"
    [ -n "$VALIDATOR_PUBLIC_KEY" ] && echo "  Validator Pubkey: ${VALIDATOR_PUBLIC_KEY:0:30}..."
    echo ""
    echo "Options:"
    echo "  [Enter] Accept and continue"
    echo "  [e]     Edit configuration"
    echo "  [q]     Quit installation"
    echo ""
    read -p "Choose: " -n 1 -r choice </dev/tty || choice=""
    echo

    case $choice in
        e|E)
            echo ""
            # Edit WebSocket URL
            while true; do
                read -p "WebSocket URL or port [$RIPPLED_WS_URL]: " ws_input </dev/tty || ws_input=""
                if [ -z "$ws_input" ]; then
                    break  # Keep existing value
                elif [[ "$ws_input" =~ ^[0-9]+$ ]]; then
                    RIPPLED_WS_URL="ws://localhost:$ws_input"
                    break
                elif [[ "$ws_input" =~ ^wss?://[a-zA-Z0-9.-]+:[0-9]+$ ]] || [[ "$ws_input" =~ ^wss?://[a-zA-Z0-9.-]+$ ]]; then
                    RIPPLED_WS_URL="$ws_input"
                    break
                else
                    print_warning "Invalid input. Enter a port number or full URL (e.g., ws://localhost:6006)"
                fi
            done

            # Edit HTTP RPC URL
            while true; do
                read -p "HTTP RPC URL or port [$RIPPLED_HTTP_URL]: " http_input </dev/tty || http_input=""
                if [ -z "$http_input" ]; then
                    break  # Keep existing value
                elif [[ "$http_input" =~ ^[0-9]+$ ]]; then
                    RIPPLED_HTTP_URL="http://localhost:$http_input"
                    break
                elif [[ "$http_input" =~ ^https?://[a-zA-Z0-9.-]+:[0-9]+$ ]] || [[ "$http_input" =~ ^https?://[a-zA-Z0-9.-]+$ ]]; then
                    RIPPLED_HTTP_URL="$http_input"
                    break
                else
                    print_warning "Invalid input. Enter a port number or full URL (e.g., http://localhost:5005)"
                fi
            done

            read -p "Data Directory [$RIPPLED_DATA_PATH]: " data_input </dev/tty || data_input=""
            [ -n "$data_input" ] && RIPPLED_DATA_PATH="$data_input"
            ;;
        q|Q)
            print_info "Installation cancelled"
            exit 0
            ;;
    esac

    RIPPLED_CHECKED=true
    return 0
}

# ==============================================================================
# STEP 2: SYSTEM REQUIREMENTS (was Step 1)
# ==============================================================================

check_system_requirements() {
    REQUIREMENTS_MET=true
    REQUIREMENTS_WARNINGS=0
    MISSING_COMPONENTS=()

    # Get actual user
    if [[ $EUID -eq 0 ]]; then
        ACTUAL_USER="${SUDO_USER:-$(logname)}"
    else
        ACTUAL_USER="$(whoami)"
    fi

    # Check CPU cores
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -ge 4 ]; then
        print_status "CPU cores: $CPU_CORES (recommended: 4+)"
    elif [ "$CPU_CORES" -ge 2 ]; then
        print_warning "CPU cores: $CPU_CORES (minimum met, recommended: 4+)"
        ((REQUIREMENTS_WARNINGS++))
    else
        print_error "CPU cores: $CPU_CORES (minimum: 2, recommended: 4+)"
        REQUIREMENTS_MET=false
    fi

    # Check available RAM
    RAM_AVAILABLE_GB=$(free -g | awk '/^Mem:/{print $7}')
    RAM_AVAILABLE_MB=$(free -m | awk '/^Mem:/{print $7}')
    if [ "$RAM_AVAILABLE_GB" -ge 4 ]; then
        print_status "Available RAM: ${RAM_AVAILABLE_GB} GB (recommended: 4+ GB)"
    elif [ "$RAM_AVAILABLE_GB" -ge 2 ]; then
        print_warning "Available RAM: ${RAM_AVAILABLE_GB} GB (minimum met, recommended: 4+ GB)"
        ((REQUIREMENTS_WARNINGS++))
    elif [ "$RAM_AVAILABLE_MB" -ge 2048 ]; then
        print_warning "Available RAM: ${RAM_AVAILABLE_MB} MB (minimum met, recommended: 4+ GB)"
        ((REQUIREMENTS_WARNINGS++))
    else
        print_error "Available RAM: ${RAM_AVAILABLE_MB} MB (minimum: 2 GB, recommended: 4+ GB)"
        REQUIREMENTS_MET=false
    fi

    # Check available disk space
    DISK_AVAILABLE_GB=$(df -BG . | awk 'NR==2{print $4}' | tr -d 'G')
    if [ "$DISK_AVAILABLE_GB" -ge 5 ]; then
        print_status "Available disk: ${DISK_AVAILABLE_GB} GB (recommended: 5+ GB)"
    elif [ "$DISK_AVAILABLE_GB" -ge 1 ]; then
        print_warning "Available disk: ${DISK_AVAILABLE_GB} GB (minimum met, recommended: 5+ GB)"
        ((REQUIREMENTS_WARNINGS++))
    else
        print_error "Available disk: Less than 1 GB (minimum: 1 GB, recommended: 5+ GB)"
        REQUIREMENTS_MET=false
    fi

    # Check OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
        OS_VERSION=$VERSION_ID
    else
        print_error "Cannot detect operating system"
        exit 1
    fi

    if [ "$OS_ID" != "ubuntu" ]; then
        print_error "This installer requires Ubuntu 20.04 LTS or later"
        print_info "For other distributions, install Docker Compose manually"
        exit 1
    fi

    VERSION_MAJOR="${OS_VERSION%%.*}"
    if [ "$VERSION_MAJOR" -lt 20 ]; then
        print_error "Ubuntu 20.04 LTS or later is required (detected: $OS_VERSION)"
        exit 1
    fi
    print_status "Operating system: Ubuntu $OS_VERSION"

    # Check for Docker
    if ! command -v docker &> /dev/null; then
        print_warning "Docker is not installed"
        MISSING_COMPONENTS+=("Docker")
    else
        print_status "Docker is installed"
    fi

    # Check for Docker Compose
    if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
        print_warning "Docker Compose is not installed"
        MISSING_COMPONENTS+=("Docker Compose")
    else
        print_status "Docker Compose is installed"
    fi
}

install_missing_components() {
    if [ ${#MISSING_COMPONENTS[@]} -eq 0 ]; then
        return 0
    fi

    echo ""
    echo -e "${BLUE}Installing missing components...${NC}"
    echo ""

    for component in "${MISSING_COMPONENTS[@]}"; do
        case $component in
            "Docker")
                print_info "Installing Docker..."
                if curl -fsSL https://get.docker.com | sh; then
                    print_status "Docker installed successfully"
                    if [[ $EUID -eq 0 ]]; then
                        print_info "Adding user $ACTUAL_USER to docker group..."
                        usermod -aG docker $ACTUAL_USER
                        print_warning "You may need to log out and back in for docker group membership to take effect"
                    fi
                else
                    print_error "Failed to install Docker"
                    print_info "Please install Docker manually: https://docs.docker.com/engine/install/"
                    exit 1
                fi
                ;;
            "Docker Compose")
                print_info "Installing Docker Compose..."
                if apt-get update && apt-get install -y docker-compose-plugin; then
                    print_status "Docker Compose installed successfully"
                else
                    print_error "Failed to install Docker Compose"
                    exit 1
                fi
                ;;
        esac
    done

    echo ""
    print_status "All components installed successfully!"
}

step_requirements() {
    clear_screen
    show_progress 2
    print_step 2 "System Requirements"

    if [ "$REQUIREMENTS_CHECKED" = true ]; then
        print_info "Requirements previously checked and met."
        echo ""
        echo "Options:"
        echo "  [Enter] Continue to Port Configuration"
        echo "  [r]     Re-run requirements check"
        echo "  [b]     Go back to rippled Detection"
        echo "  [q]     Quit installation"
        echo ""
        read -p "Choose: " -n 1 -r choice </dev/tty || choice=""
        echo

        case $choice in
            r|R)
                REQUIREMENTS_CHECKED=false
                ;;
            b|B)
                return 1  # Go back
                ;;
            q|Q)
                print_info "Installation cancelled"
                exit 0
                ;;
            *)
                return 0  # Continue
                ;;
        esac
    fi

    echo "Checking system requirements for the monitoring dashboard..."
    echo ""

    check_system_requirements

    echo ""

    if [ ${#MISSING_COMPONENTS[@]} -gt 0 ]; then
        echo -e "${YELLOW}The following components need to be installed:${NC}"
        for component in "${MISSING_COMPONENTS[@]}"; do
            echo "  • $component"
        done
        echo ""
        echo "Options:"
        echo "  [Enter] Install missing components and continue"
        echo "  [b]     Go back to rippled Detection"
        echo "  [q]     Quit installation"
        echo ""
        read -p "Choose: " -n 1 -r choice </dev/tty || choice=""
        echo

        case $choice in
            b|B) return 1 ;;
            q|Q) print_info "Installation cancelled"; exit 0 ;;
        esac

        install_missing_components
    else
        print_status "All requirements met!"
    fi

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Options:"
    echo "  [Enter] Continue to Port Configuration"
    echo "  [b]     Go back to rippled Detection"
    echo "  [q]     Quit installation"
    echo ""
    read -p "Choose: " -n 1 -r choice </dev/tty || choice=""
    echo

    case $choice in
        b|B) return 1 ;;
        q|Q) print_info "Installation cancelled"; exit 0 ;;
    esac

    REQUIREMENTS_CHECKED=true
    return 0
}

# ==============================================================================
# STEP 3: PORT CONFIGURATION (was Step 2)
# ==============================================================================

check_port() {
    local port=$1
    if command -v lsof &> /dev/null; then
        lsof -i :"$port" > /dev/null 2>&1
        return $?
    elif command -v ss &> /dev/null; then
        ss -tuln | grep -q ":$port "
        return $?
    else
        return 1
    fi
}

find_available_port() {
    local default_port=$1
    local current_port=$default_port

    while check_port "$current_port"; do
        ((current_port++))
        if [ "$current_port" -gt $((default_port + 100)) ]; then
            echo "$default_port"
            return
        fi
    done

    echo "$current_port"
}

is_port_already_selected() {
    local port=$1
    local exclude_service=$2

    [ -n "$GRAFANA_PORT" ] && [ "$GRAFANA_PORT" = "$port" ] && [ "$exclude_service" != "grafana" ] && echo "Grafana" && return 0
    [ -n "$VICTORIA_PORT" ] && [ "$VICTORIA_PORT" = "$port" ] && [ "$exclude_service" != "victoria" ] && echo "VictoriaMetrics" && return 0
    [ -n "$VMAGENT_PORT" ] && [ "$VMAGENT_PORT" = "$port" ] && [ "$exclude_service" != "vmagent" ] && echo "vmagent" && return 0
    [ -n "$NODE_EXPORTER_PORT" ] && [ "$NODE_EXPORTER_PORT" = "$port" ] && [ "$exclude_service" != "node" ] && echo "Node Exporter" && return 0
    [ -n "$UPTIME_EXPORTER_PORT" ] && [ "$UPTIME_EXPORTER_PORT" = "$port" ] && [ "$exclude_service" != "uptime" ] && echo "Uptime Exporter" && return 0
    [ -n "$STATE_EXPORTER_PORT" ] && [ "$STATE_EXPORTER_PORT" = "$port" ] && [ "$exclude_service" != "state" ] && echo "State Exporter" && return 0
    [ -n "$COLLECTOR_PORT" ] && [ "$COLLECTOR_PORT" = "$port" ] && [ "$exclude_service" != "collector" ] && echo "Collector" && return 0

    return 1
}

read_port_with_navigation() {
    local prompt="$1"
    local suggested_port="$2"
    local user_input

    read -p "$prompt" user_input </dev/tty || user_input=""
    user_input=$(echo "$user_input" | xargs)
    local user_input_lower=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')

    if [ "$user_input_lower" = "b" ] || [ "$user_input_lower" = "back" ]; then
        echo "BACK"
        return
    elif [ "$user_input_lower" = "q" ] || [ "$user_input_lower" = "quit" ]; then
        echo "QUIT"
        return
    fi

    if [ -z "$user_input" ]; then
        echo "$suggested_port"
        return
    fi

    echo "$user_input"
}

configure_single_port() {
    local service_name="$1"
    local var_name="$2"
    local default_port="$3"
    local exclude_key="$4"

    local suggested_port=$(find_available_port $default_port)
    if [ "$suggested_port" -ne "$default_port" ]; then
        print_warning "Port $default_port is in use"
    fi

    while true; do
        local port_input=$(read_port_with_navigation "$service_name port [$suggested_port]: " "$suggested_port")

        if [ "$port_input" = "BACK" ]; then
            return 1
        elif [ "$port_input" = "QUIT" ]; then
            print_info "Installation cancelled"
            exit 0
        fi

        if ! [[ "$port_input" =~ ^[0-9]+$ ]] || [ "$port_input" -lt 1024 ] || [ "$port_input" -gt 65535 ]; then
            print_error "Invalid port. Enter a port between 1024-65535"
            continue
        fi

        if check_port "$port_input"; then
            suggested_port=$(find_available_port $((port_input + 1)))
            # Also check that new suggested port isn't already selected
            while is_port_already_selected "$suggested_port" "$exclude_key" > /dev/null; do
                suggested_port=$((suggested_port + 1))
            done
            print_warning "Port $port_input is in use. Try $suggested_port"
            continue
        fi

        local conflict_service=$(is_port_already_selected "$port_input" "$exclude_key")
        if [ -n "$conflict_service" ]; then
            suggested_port=$(find_available_port $((port_input + 1)))
            # Also check that new suggested port isn't already selected
            while is_port_already_selected "$suggested_port" "$exclude_key" > /dev/null; do
                suggested_port=$((suggested_port + 1))
            done
            print_warning "Port $port_input is already selected for $conflict_service. Try $suggested_port"
            continue
        fi

        eval "$var_name=$port_input"
        print_status "$service_name port: $port_input"
        break
    done

    return 0
}

step_port_configuration() {
    clear_screen
    show_progress 3
    print_step 3 "Dashboard Port Configuration"

    echo "Configure ports for monitoring services."
    echo "Options: [Enter] use suggested port | [b] go back | [q] quit"
    echo ""

    # Configure each port
    local ports_to_configure=(
        "Grafana:GRAFANA_PORT:3000:grafana"
        "VictoriaMetrics:VICTORIA_PORT:8428:victoria"
        "vmagent:VMAGENT_PORT:8427:vmagent"
        "Node Exporter:NODE_EXPORTER_PORT:9100:node"
        "Uptime Exporter:UPTIME_EXPORTER_PORT:9101:uptime"
        "State Exporter:STATE_EXPORTER_PORT:9102:state"
        "Collector:COLLECTOR_PORT:8090:collector"
    )

    for port_config in "${ports_to_configure[@]}"; do
        IFS=':' read -r service_name var_name default_port exclude_key <<< "$port_config"

        # Check if already configured
        eval "current_val=\$$var_name"
        if [ -n "$current_val" ]; then
            print_status "$service_name port: $current_val (previously configured)"
        else
            if ! configure_single_port "$service_name" "$var_name" "$default_port" "$exclude_key"; then
                return 1  # Go back
            fi
        fi
        echo ""
    done

    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Options:"
    echo "  [Enter] Continue to Review & Install"
    echo "  [r]     Reconfigure ports"
    echo "  [b]     Go back to System Requirements"
    echo "  [q]     Quit installation"
    echo ""
    read -p "Choose: " -n 1 -r choice </dev/tty || choice=""
    echo

    case $choice in
        r|R)
            GRAFANA_PORT=""
            VICTORIA_PORT=""
            NODE_EXPORTER_PORT=""
            UPTIME_EXPORTER_PORT=""
            STATE_EXPORTER_PORT=""
            VMAGENT_PORT=""
            COLLECTOR_PORT=""
            step_port_configuration
            return $?
            ;;
        b|B) return 1 ;;
        q|Q) print_info "Installation cancelled"; exit 0 ;;
        *) return 0 ;;
    esac
}

# ==============================================================================
# STEP 4: REVIEW & INSTALL
# ==============================================================================

step_review_and_install() {
    clear_screen
    show_progress 4
    print_step 4 "Review Configuration & Install"

    echo "Please review your configuration:"
    echo ""
    echo -e "${CYAN}rippled Configuration:${NC}"
    echo "  WebSocket URL:    $RIPPLED_WS_URL"
    echo "  HTTP RPC URL:     $RIPPLED_HTTP_URL"
    if [ -n "$VALIDATOR_PUBLIC_KEY" ]; then
        echo "  Validator Pubkey: ${VALIDATOR_PUBLIC_KEY:0:20}..."
    fi
    echo ""
    echo -e "${CYAN}Dashboard Ports:${NC}"
    echo "  Grafana:          http://localhost:$GRAFANA_PORT"
    echo "  VictoriaMetrics:  http://localhost:$VICTORIA_PORT"
    echo "  vmagent:          http://localhost:$VMAGENT_PORT"
    echo "  Node Exporter:    http://localhost:$NODE_EXPORTER_PORT"
    echo "  Uptime Exporter:  http://localhost:$UPTIME_EXPORTER_PORT"
    echo "  State Exporter:   http://localhost:$STATE_EXPORTER_PORT"
    echo "  Collector:        http://localhost:$COLLECTOR_PORT"
    echo "  Autoheal:         (container recovery, no port)"
    echo ""
    echo -e "${CYAN}Alert Configuration:${NC}"
    echo "  14 alert rules will be automatically configured"
    echo "  Post-install: Configure email/webhooks in Grafana"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Options:"
    echo "  [Enter] Start Installation"
    echo "  [b]     Go back to Port Configuration"
    echo "  [q]     Quit installation"
    echo ""
    read -p "Choose: " -n 1 -r choice </dev/tty || choice=""
    echo

    case $choice in
        b|B) return 1 ;;
        q|Q) print_info "Installation cancelled"; exit 0 ;;
    esac

    # === GENERATE .ENV FILE ===
    echo ""
    print_info "Generating configuration..."

    cat > .env << EOF
# XRPL Monitor v3.0 - Environment Configuration
# Auto-generated on $(date)

# rippled WebSocket API (required)
RIPPLED_WS_URL=$RIPPLED_WS_URL

# rippled HTTP JSON-RPC API (optional, used for fallback operations)
RIPPLED_HTTP_URL=$RIPPLED_HTTP_URL

# rippled data directory path (for database size metrics)
RIPPLED_DATA_PATH=$RIPPLED_DATA_PATH

# If rippled runs in Docker, specify the container name
RIPPLED_DOCKER_CONTAINER=

# Validator public key (optional, for validator-specific features)
VALIDATOR_PUBLIC_KEY=${VALIDATOR_PUBLIC_KEY:-}

# VictoriaMetrics URL (internal Docker network)
VICTORIA_METRICS_URL=http://localhost:$VICTORIA_PORT

# Docker group ID (for docker socket access)
DOCKER_GID=$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo "999")

# Log level (DEBUG, INFO, WARNING, ERROR)
LOG_LEVEL=INFO

# Port Configuration (auto-configured by installer)
GRAFANA_PORT=$GRAFANA_PORT
VICTORIA_METRICS_PORT=$VICTORIA_PORT
NODE_EXPORTER_PORT=$NODE_EXPORTER_PORT
UPTIME_EXPORTER_PORT=$UPTIME_EXPORTER_PORT
STATE_EXPORTER_PORT=$STATE_EXPORTER_PORT
VMAGENT_PORT=$VMAGENT_PORT
COLLECTOR_PORT=$COLLECTOR_PORT

# Peer Version Check (polls /crawl endpoint to detect if upgrade needed)
# Set to 0 to disable, or 51235 (default rippled peer port) to enable
PEER_CRAWL_PORT=51235
EOF

    print_status ".env file created"

    # Fix ownership if running as sudo (so manage.sh can modify .env later)
    if [ -n "$SUDO_USER" ]; then
        chown "$SUDO_USER:$SUDO_USER" .env
        log "Fixed .env ownership to $SUDO_USER"
    fi

    # === GENERATE CONFIG FILES FROM TEMPLATES ===
    print_info "Configuring ports..."

    export VICTORIA_METRICS_PORT=$VICTORIA_PORT
    export NODE_EXPORTER_PORT
    export UPTIME_EXPORTER_PORT
    export STATE_EXPORTER_PORT
    export VMAGENT_PORT
    export COLLECTOR_PORT

    if [ -f "config/vmagent/scrape.yml.template" ]; then
        envsubst < config/vmagent/scrape.yml.template > config/vmagent/scrape.yml
        log "Generated config/vmagent/scrape.yml from template"
    else
        print_error "scrape.yml.template not found!"
        exit 1
    fi

    if [ -f "config/grafana/provisioning/datasources/datasource.yml.template" ]; then
        envsubst < config/grafana/provisioning/datasources/datasource.yml.template > config/grafana/provisioning/datasources/datasource.yml
        log "Generated datasource.yml from template"
    else
        print_error "datasource.yml.template not found!"
        exit 1
    fi

    # Fix ownership of generated config files if running as sudo
    if [ -n "$SUDO_USER" ]; then
        chown "$SUDO_USER:$SUDO_USER" config/vmagent/scrape.yml 2>/dev/null
        chown "$SUDO_USER:$SUDO_USER" config/grafana/provisioning/datasources/datasource.yml 2>/dev/null
    fi

    print_status "Ports configured"

    # Process dashboard template
    print_info "Configuring dashboard..."
    if [ -f "config/grafana/provisioning/dashboards/xrpl-validator-main.json.template" ]; then
        sed "s/{{VALIDATOR_PUBLIC_KEY}}/${VALIDATOR_PUBLIC_KEY:-VALIDATOR_KEY_NOT_SET}/g" \
            config/grafana/provisioning/dashboards/xrpl-validator-main.json.template > \
            config/grafana/provisioning/dashboards/xrpl-validator-main.json
        print_status "Dashboard configured"
    else
        print_warning "Dashboard template not found, skipping"
    fi

    # Build and start containers
    print_info "Building Docker images..."
    docker compose build 2>&1 | tee -a "$LOG_FILE"

    print_info "Starting containers..."
    docker compose up -d 2>&1 | tee -a "$LOG_FILE"

    # Wait for services
    print_info "Waiting for services to start (30 seconds)..."
    sleep 30

    # Health checks
    print_info "Running health checks..."

    if docker compose ps | grep -q "Up"; then
        print_status "All containers are running"
    else
        print_warning "Some containers may not have started"
    fi

    if timeout 10 curl -s "http://localhost:$VICTORIA_PORT/metrics" > /dev/null 2>&1; then
        print_status "VictoriaMetrics is responding"
    else
        print_warning "VictoriaMetrics not responding yet"
    fi

    if timeout 10 curl -s "http://localhost:$GRAFANA_PORT/api/health" | grep -q "ok"; then
        print_status "Grafana is responding"

        # Import dashboards via API (allows user customization)
        import_dashboards_via_api "$GRAFANA_PORT"

        # Set home dashboard via API (allows dashboard to be saved, not just "Save as copy")
        set_home_dashboard "$GRAFANA_PORT"

        # Import contact point via API (allows user to edit/delete)
        import_contact_point_via_api "$GRAFANA_PORT"
    else
        print_warning "Grafana not responding yet"
        print_warning "Dashboards can be imported later via: ./manage.sh → Advanced → Restore default"
    fi

    log "Installation completed successfully"

    # Success screen
    clear_screen
    echo -e "${GREEN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║                   Installation Complete! ✓                    ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    print_status "XRPL Monitor is now running"
    echo ""
    echo -e "${CYAN}Access your dashboard:${NC}"
    echo "  Grafana:          http://localhost:$GRAFANA_PORT"
    echo "  VictoriaMetrics:  http://localhost:$VICTORIA_PORT"
    echo ""
    echo -e "${CYAN}Default Grafana credentials:${NC}"
    echo "  Username: admin"
    echo "  Password: admin"
    echo -e "  ${YELLOW}(Change on first login)${NC}"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Log into Grafana and change the admin password"
    echo "  2. Customize your dashboard (changes are saved!)"
    echo "  3. Configure email/webhook notifications:"
    echo "     See: docs/ALERTS.md"
    echo "  4. Review alert rules in Grafana → Alerting"
    echo ""
    echo -e "${CYAN}Useful commands:${NC}"
    echo "  View logs:        docker compose logs -f"
    echo "  Stop services:    docker compose stop"
    echo "  Restart services: docker compose restart"
    echo "  Management:       ./manage.sh"
    echo ""
    echo -e "${BLUE}Installation log: $LOG_FILE${NC}"
    echo ""
}

# ==============================================================================
# MAIN INSTALLATION FLOW
# ==============================================================================

main() {
    # Initial screen
    clear_screen
    echo ""
    print_info "Installation log: $LOG_FILE"
    echo ""
    echo "This wizard will guide you through installing XRPL Monitor v3.0."
    echo ""
    echo "Prerequisites:"
    echo "  • rippled node running and accessible"
    echo "  • Root/sudo access (for Docker installation)"
    echo ""
    read -p "Press Enter to begin installation..." </dev/tty

    # Step tracker (allows navigation)
    current_step=1

    while true; do
        case $current_step in
            1)
                if step_rippled_detection; then
                    current_step=2
                else
                    # Can't go back from step 1
                    clear_screen
                    echo ""
                    print_info "Installation log: $LOG_FILE"
                    echo ""
                    echo "Options:"
                    echo "  [Enter] Retry rippled detection"
                    echo "  [q]     Quit installation"
                    echo ""
                    read -p "Choose: " -n 1 -r choice </dev/tty || choice=""
                    echo
                    case $choice in
                        q|Q) print_info "Installation cancelled"; exit 0 ;;
                        *) current_step=1 ;;
                    esac
                fi
                ;;
            2)
                if step_requirements; then
                    current_step=3
                else
                    current_step=1  # Go back to rippled
                fi
                ;;
            3)
                if step_port_configuration; then
                    current_step=4
                else
                    current_step=2  # Go back to requirements
                fi
                ;;
            4)
                if step_review_and_install; then
                    break  # Installation complete
                else
                    current_step=3  # Go back to ports
                fi
                ;;
            *)
                print_error "Invalid step: $current_step"
                exit 1
                ;;
        esac
    done
}

# Run installation
main
