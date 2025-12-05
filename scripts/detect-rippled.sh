#!/bin/bash
#
# rippled Auto-Detection Script
# Detects rippled deployment type, API endpoints, and validates connectivity
#

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# Detection results
RIPPLED_TYPE=""  # "native" or "docker"
RIPPLED_CONTAINER=""
RIPPLED_WS_URL=""
RIPPLED_HTTP_URL=""
RIPPLED_DATA_PATH=""
VALIDATOR_PUBLIC_KEY=""

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  rippled Auto-Detection${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# ==============================================================================
# Step 1: Detect if rippled is running (Docker or native)
# ==============================================================================

print_info "Detecting rippled deployment..."

# Check for Docker rippled first
if command -v docker &> /dev/null; then
    DOCKER_RIPPLED=$(docker ps --format '{{.Names}}' | grep -i rippled | head -1)

    if [ -n "$DOCKER_RIPPLED" ]; then
        RIPPLED_TYPE="docker"
        RIPPLED_CONTAINER="$DOCKER_RIPPLED"
        print_status "Found rippled running in Docker: $RIPPLED_CONTAINER"
    fi
fi

# Check for native rippled
if [ -z "$RIPPLED_TYPE" ]; then
    if pgrep -x rippled > /dev/null 2>&1; then
        RIPPLED_TYPE="native"
        print_status "Found rippled running natively (process ID: $(pgrep -x rippled))"
    elif command -v rippled &> /dev/null; then
        RIPPLED_TYPE="native"
        print_warning "rippled binary found but not running"
    fi
fi

if [ -z "$RIPPLED_TYPE" ]; then
    print_error "rippled not found (checked Docker containers and native processes)"
    echo ""
    echo "Please ensure rippled is installed and running before installing XRPL Monitor."
    echo ""
    echo "Installation options:"
    echo "  - Docker: https://hub.docker.com/r/xrpllabsofficial/xrpld"
    echo "  - Native: https://xrpl.org/install-rippled.html"
    exit 1
fi

echo ""

# ==============================================================================
# Step 2: Auto-detect rippled API ports by scanning listening ports
# ==============================================================================

print_info "Scanning for rippled API endpoints..."

# Get all listening TCP ports on localhost
LISTENING_PORTS=$(ss -tuln 2>/dev/null | grep -E '127\.0\.0\.1:|localhost:|\*:' | awk '{print $5}' | grep -oE '[0-9]+$' | sort -nu)

if [ -z "$LISTENING_PORTS" ]; then
    # Fallback to netstat if ss fails
    LISTENING_PORTS=$(netstat -tuln 2>/dev/null | grep -E '127\.0\.0\.1:|localhost:' | awk '{print $4}' | grep -oE '[0-9]+$' | sort -nu)
fi

# Test each listening port for rippled HTTP RPC API
print_info "Testing listening ports for rippled HTTP RPC API..."
for port in $LISTENING_PORTS; do
    # Skip well-known non-rippled ports to speed up detection
    case $port in
        22|80|443|3000|8080|8428|8427|9090|9100|9101|9102) continue ;;
    esac

    # Test if this port responds to rippled server_info
    if timeout 2 curl -s "http://localhost:$port" \
        -d '{"method":"server_info"}' \
        -H "Content-Type: application/json" 2>/dev/null | grep -q '"result"'; then
        RIPPLED_HTTP_URL="http://localhost:$port"
        print_status "Found rippled HTTP RPC API on port $port"
        break
    fi
done

# Test each listening port for rippled WebSocket API
print_info "Testing listening ports for rippled WebSocket API..."
for port in $LISTENING_PORTS; do
    # Skip well-known non-rippled ports and the HTTP port we already found
    case $port in
        22|80|443|3000|8080|8428|8427|9090|9100|9101|9102) continue ;;
    esac

    # Skip the HTTP RPC port we already found
    if [ -n "$RIPPLED_HTTP_URL" ] && [[ "$RIPPLED_HTTP_URL" == *":$port" ]]; then
        continue
    fi

    # Test if this port responds like a rippled WebSocket endpoint
    # WebSocket endpoints return "rippled" in response to HTTP GET
    if timeout 2 curl -s "http://localhost:$port" 2>/dev/null | grep -qi "rippled"; then
        RIPPLED_WS_URL="ws://localhost:$port"
        print_status "Found rippled WebSocket API on port $port"
        break
    fi
done

echo ""

# ==============================================================================
# Step 3: Handle detection results - prompt if needed
# ==============================================================================

# If HTTP RPC not found, prompt user
if [ -z "$RIPPLED_HTTP_URL" ]; then
    print_warning "Could not auto-detect rippled HTTP RPC API"
    echo ""
    echo "Please enter the rippled HTTP RPC URL (or press Enter for default):"
    read -p "HTTP RPC URL [http://localhost:5005]: " user_http_url </dev/tty || user_http_url=""
    RIPPLED_HTTP_URL="${user_http_url:-http://localhost:5005}"

    # Verify user-provided URL
    print_info "Verifying $RIPPLED_HTTP_URL..."
    if timeout 3 curl -s "$RIPPLED_HTTP_URL" \
        -d '{"method":"server_info"}' \
        -H "Content-Type: application/json" 2>/dev/null | grep -q '"result"'; then
        print_status "HTTP RPC API verified: $RIPPLED_HTTP_URL"
    else
        print_warning "Could not verify HTTP RPC API (may still work if rippled starts later)"
    fi
fi

# If WebSocket not found, prompt user
if [ -z "$RIPPLED_WS_URL" ]; then
    print_warning "Could not auto-detect rippled WebSocket API"
    echo ""
    echo "Please enter the rippled WebSocket URL (or press Enter for default):"
    read -p "WebSocket URL [ws://localhost:6006]: " user_ws_url </dev/tty || user_ws_url=""
    RIPPLED_WS_URL="${user_ws_url:-ws://localhost:6006}"

    # Verify user-provided URL (test HTTP endpoint of WS port)
    WS_PORT=$(echo "$RIPPLED_WS_URL" | grep -oE '[0-9]+$')
    print_info "Verifying WebSocket port $WS_PORT..."
    if timeout 2 curl -s "http://localhost:$WS_PORT" 2>/dev/null | grep -qi "rippled"; then
        print_status "WebSocket API verified: $RIPPLED_WS_URL"
    else
        print_warning "Could not verify WebSocket API (may still work if rippled starts later)"
    fi
fi

echo ""

# ==============================================================================
# Step 4: Detect rippled data directory
# ==============================================================================

print_info "Detecting rippled data directory..."

if [ "$RIPPLED_TYPE" = "docker" ]; then
    # For Docker, find the host path mounted to /var/lib/rippled inside container
    # This is where rippled stores its data (db/, nudb/, etc.)
    if command -v jq &> /dev/null; then
        DATA_VOLUME=$(docker inspect "$RIPPLED_CONTAINER" 2>/dev/null | \
            jq -r '.[0].Mounts[] | select(.Destination=="/var/lib/rippled") | .Source' 2>/dev/null)
    else
        # Fallback if jq not available - use grep with more specific pattern
        DATA_VOLUME=$(docker inspect "$RIPPLED_CONTAINER" 2>/dev/null | \
            grep -B2 '"/var/lib/rippled"' | grep '"Source"' | grep -o '"/[^"]*"' | tr -d '"' | head -1)
    fi

    if [ -n "$DATA_VOLUME" ] && [ -d "$DATA_VOLUME" ]; then
        RIPPLED_DATA_PATH="$DATA_VOLUME"
        print_status "Data directory detected: $RIPPLED_DATA_PATH (Docker volume mount)"
    else
        RIPPLED_DATA_PATH="/var/lib/rippled"
        print_warning "Could not detect Docker volume mount, using default: $RIPPLED_DATA_PATH"
    fi
else
    # For native rippled
    if [ -d "/var/lib/rippled" ]; then
        RIPPLED_DATA_PATH="/var/lib/rippled"
        print_status "Data directory detected: $RIPPLED_DATA_PATH"
    elif [ -d "$HOME/.local/share/rippled" ]; then
        RIPPLED_DATA_PATH="$HOME/.local/share/rippled"
        print_status "Data directory detected: $RIPPLED_DATA_PATH"
    else
        RIPPLED_DATA_PATH="/var/lib/rippled"
        print_warning "Could not detect data directory, using default: $RIPPLED_DATA_PATH"
    fi
fi

echo ""

# ==============================================================================
# Step 5: Extract validator public key (if HTTP RPC is accessible)
# ==============================================================================

if [ -n "$RIPPLED_HTTP_URL" ]; then
    HTTP_RESPONSE=$(timeout 5 curl -s "$RIPPLED_HTTP_URL" \
        -d '{"method":"server_info"}' \
        -H "Content-Type: application/json" 2>/dev/null)

    if echo "$HTTP_RESPONSE" | grep -q '"result"'; then
        # Extract validator public key if available
        VALIDATOR_PUBLIC_KEY=$(echo "$HTTP_RESPONSE" | \
            grep -o '"pubkey_validator":"[^"]*"' | cut -d'"' -f4)

        if [ -n "$VALIDATOR_PUBLIC_KEY" ]; then
            print_status "Validator public key detected: ${VALIDATOR_PUBLIC_KEY:0:20}..."
        fi
    fi
fi

echo ""

# ==============================================================================
# Step 6: Display detection summary
# ==============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Detection Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Deployment Type:     $RIPPLED_TYPE"
[ -n "$RIPPLED_CONTAINER" ] && echo "Container Name:      $RIPPLED_CONTAINER"
echo "WebSocket API:       $RIPPLED_WS_URL"
echo "HTTP API:            $RIPPLED_HTTP_URL"
echo "Data Directory:      $RIPPLED_DATA_PATH"
[ -n "$VALIDATOR_PUBLIC_KEY" ] && echo "Validator Pubkey:    $VALIDATOR_PUBLIC_KEY"
echo ""

# ==============================================================================
# Step 7: Generate .env file
# ==============================================================================

ENV_FILE="${1:-.env}"

# IMPORTANT: Save detected values BEFORE sourcing old .env
# (sourcing .env would overwrite our detected variables)
DETECTED_WS_URL="$RIPPLED_WS_URL"
DETECTED_HTTP_URL="$RIPPLED_HTTP_URL"
DETECTED_DATA_PATH="$RIPPLED_DATA_PATH"
DETECTED_CONTAINER="$RIPPLED_CONTAINER"
DETECTED_PUBKEY="$VALIDATOR_PUBLIC_KEY"
DETECTED_TYPE="$RIPPLED_TYPE"

# Preserve existing settings that user may have configured
EXISTING_SMTP_ENABLED=""
EXISTING_SMTP_HOST=""
EXISTING_SMTP_USER=""
EXISTING_SMTP_PASSWORD=""
EXISTING_SMTP_FROM=""
EXISTING_GRAFANA_PORT=""
EXISTING_VICTORIA_PORT=""
EXISTING_COLLECTOR_PORT=""
EXISTING_VMAGENT_PORT=""
EXISTING_NODE_EXPORTER_PORT=""
EXISTING_UPTIME_EXPORTER_PORT=""
EXISTING_STATE_EXPORTER_PORT=""

if [ -f "$ENV_FILE" ]; then
    print_warning "$ENV_FILE already exists - preserving custom settings"
    cp "$ENV_FILE" "$ENV_FILE.backup-$(date +%Y%m%d-%H%M%S)"

    # Read existing values to preserve (only non-rippled settings)
    source "$ENV_FILE" 2>/dev/null || true
    EXISTING_SMTP_ENABLED="${GF_SMTP_ENABLED:-}"
    EXISTING_SMTP_HOST="${GF_SMTP_HOST:-}"
    EXISTING_SMTP_USER="${GF_SMTP_USER:-}"
    EXISTING_SMTP_PASSWORD="${GF_SMTP_PASSWORD:-}"
    EXISTING_SMTP_FROM="${GF_SMTP_FROM_ADDRESS:-}"
    EXISTING_GRAFANA_PORT="${GRAFANA_PORT:-}"
    EXISTING_VICTORIA_PORT="${VICTORIA_METRICS_PORT:-}"
    EXISTING_COLLECTOR_PORT="${COLLECTOR_PORT:-}"
    EXISTING_VMAGENT_PORT="${VMAGENT_PORT:-}"
    EXISTING_NODE_EXPORTER_PORT="${NODE_EXPORTER_PORT:-}"
    EXISTING_UPTIME_EXPORTER_PORT="${UPTIME_EXPORTER_PORT:-}"
    EXISTING_STATE_EXPORTER_PORT="${STATE_EXPORTER_PORT:-}"
fi

# Restore detected values (in case source overwrote them)
RIPPLED_WS_URL="$DETECTED_WS_URL"
RIPPLED_HTTP_URL="$DETECTED_HTTP_URL"
RIPPLED_DATA_PATH="$DETECTED_DATA_PATH"
RIPPLED_CONTAINER="$DETECTED_CONTAINER"
VALIDATOR_PUBLIC_KEY="$DETECTED_PUBKEY"
RIPPLED_TYPE="$DETECTED_TYPE"

print_info "Generating $ENV_FILE with detected settings..."

cat > "$ENV_FILE" << EOF
# XRPL Monitor v3.0 - Environment Configuration
# Auto-generated on $(date)
# Detection: rippled is running as $RIPPLED_TYPE

# rippled WebSocket API (required)
RIPPLED_WS_URL=$RIPPLED_WS_URL

# rippled HTTP JSON-RPC API (optional, used for fallback operations)
RIPPLED_HTTP_URL=$RIPPLED_HTTP_URL

# rippled data directory path (for database size metrics)
# For Docker rippled: This should be the HOST path where rippled data is stored
# For native rippled: Usually /var/lib/rippled
RIPPLED_DATA_PATH=$RIPPLED_DATA_PATH

# If rippled runs in Docker, specify the container name
# Leave blank for native rippled installations
RIPPLED_DOCKER_CONTAINER=$RIPPLED_CONTAINER

# Validator public key (optional, for validator-specific features)
# Auto-detected: $VALIDATOR_PUBLIC_KEY
VALIDATOR_PUBLIC_KEY=${VALIDATOR_PUBLIC_KEY:-}

# VictoriaMetrics URL (internal Docker network)
VICTORIA_METRICS_URL=http://localhost:8428

# Docker group ID (for docker socket access, usually 999)
DOCKER_GID=999

# Log level (DEBUG, INFO, WARNING, ERROR)
LOG_LEVEL=INFO
EOF

# Append port configuration if any custom ports were set
if [ -n "$EXISTING_GRAFANA_PORT" ] || [ -n "$EXISTING_VICTORIA_PORT" ] || \
   [ -n "$EXISTING_COLLECTOR_PORT" ] || [ -n "$EXISTING_VMAGENT_PORT" ] || \
   [ -n "$EXISTING_NODE_EXPORTER_PORT" ] || [ -n "$EXISTING_UPTIME_EXPORTER_PORT" ] || \
   [ -n "$EXISTING_STATE_EXPORTER_PORT" ]; then
    cat >> "$ENV_FILE" << EOF

# Custom port configuration (preserved from previous .env)
EOF
    [ -n "$EXISTING_GRAFANA_PORT" ] && echo "GRAFANA_PORT=$EXISTING_GRAFANA_PORT" >> "$ENV_FILE"
    [ -n "$EXISTING_VICTORIA_PORT" ] && echo "VICTORIA_METRICS_PORT=$EXISTING_VICTORIA_PORT" >> "$ENV_FILE"
    [ -n "$EXISTING_COLLECTOR_PORT" ] && echo "COLLECTOR_PORT=$EXISTING_COLLECTOR_PORT" >> "$ENV_FILE"
    [ -n "$EXISTING_VMAGENT_PORT" ] && echo "VMAGENT_PORT=$EXISTING_VMAGENT_PORT" >> "$ENV_FILE"
    [ -n "$EXISTING_NODE_EXPORTER_PORT" ] && echo "NODE_EXPORTER_PORT=$EXISTING_NODE_EXPORTER_PORT" >> "$ENV_FILE"
    [ -n "$EXISTING_UPTIME_EXPORTER_PORT" ] && echo "UPTIME_EXPORTER_PORT=$EXISTING_UPTIME_EXPORTER_PORT" >> "$ENV_FILE"
    [ -n "$EXISTING_STATE_EXPORTER_PORT" ] && echo "STATE_EXPORTER_PORT=$EXISTING_STATE_EXPORTER_PORT" >> "$ENV_FILE"
    print_status "Custom port settings preserved"
fi

# Append SMTP configuration if it existed
if [ -n "$EXISTING_SMTP_ENABLED" ]; then
    cat >> "$ENV_FILE" << EOF

# SMTP Configuration for Grafana email alerts (preserved from previous .env)
GF_SMTP_ENABLED=$EXISTING_SMTP_ENABLED
GF_SMTP_HOST=$EXISTING_SMTP_HOST
GF_SMTP_USER=$EXISTING_SMTP_USER
GF_SMTP_PASSWORD=$EXISTING_SMTP_PASSWORD
GF_SMTP_FROM_ADDRESS=$EXISTING_SMTP_FROM
EOF
    print_status "SMTP email settings preserved"
fi

print_status "$ENV_FILE created successfully"
echo ""

# ==============================================================================
# Step 8: Provide recommendations
# ==============================================================================

echo -e "${YELLOW}📋 Important Configuration Notes:${NC}"
echo ""

if [ "$RIPPLED_TYPE" = "native" ] && [ -n "$RIPPLED_CONTAINER" ]; then
    print_warning "Both native and Docker rippled detected - using Docker container"
fi

if [ -z "$VALIDATOR_PUBLIC_KEY" ]; then
    print_info "Validator public key not detected - this is optional"
    echo "   You can add it later to .env as VALIDATOR_PUBLIC_KEY=..."
fi

echo ""
echo "Review the generated .env file and adjust if needed:"
echo "  cat $ENV_FILE"
echo ""
print_status "Auto-detection complete!"
