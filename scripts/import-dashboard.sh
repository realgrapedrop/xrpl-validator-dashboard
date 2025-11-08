#!/bin/bash
#
# Import Grafana Dashboard
# Run this if the dashboard didn't import during initial setup
#

set -e

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${BLUE}XRPL Validator Dashboard - Dashboard Import${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo ""

# Get the project directory (parent of scripts/)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# Check if Grafana is running
if ! docker ps | grep -q xrpl-dashboard-grafana; then
    echo -e "${RED}Error: Grafana container is not running${NC}"
    echo "Start it with: docker compose up -d grafana"
    exit 1
fi

echo -e "${BLUE}Importing dashboard...${NC}"
echo ""

# Run the import using Python
python3 << 'EOF'
import sys
import json
import urllib.request
import urllib.error
import base64
from pathlib import Path

# Color codes
GREEN = '\033[0;32m'
BLUE = '\033[0;34m'
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
NC = '\033[0m'

def print_success(msg):
    print(f"{GREEN}✓ {msg}{NC}")

def print_error(msg):
    print(f"{RED}✗ {msg}{NC}")

def print_info(msg):
    print(f"{BLUE}ℹ {msg}{NC}")

# Configuration
GRAFANA_PORT = 3003
PROMETHEUS_PORT = 9092
NODE_EXPORTER_PORT = 9102
DASHBOARD_FILE = Path(__file__).parent / 'dashboards' / 'categories' / 'xrpl-monitor-dashboard.json'

# Check if dashboard file exists
if not DASHBOARD_FILE.exists():
    # We're running from stdin, so use absolute path
    DASHBOARD_FILE = Path.cwd() / 'dashboards' / 'categories' / 'xrpl-monitor-dashboard.json'
    if not DASHBOARD_FILE.exists():
        print_error(f"Dashboard file not found: {DASHBOARD_FILE}")
        sys.exit(1)

print_info(f"Reading dashboard from: {DASHBOARD_FILE}")

try:
    # Read dashboard JSON
    with open(DASHBOARD_FILE, 'r') as f:
        dashboard_json = json.load(f)

    # Query Prometheus for hostname
    print_info("Querying Prometheus for node hostname...")
    prom_url = f'http://127.0.0.1:{PROMETHEUS_PORT}/api/v1/query?query=node_uname_info'
    prom_response = urllib.request.urlopen(prom_url, timeout=10)
    prom_data = json.loads(prom_response.read().decode('utf-8'))

    nodename = 'xrpl-validator'
    if prom_data.get('status') == 'success' and prom_data.get('data', {}).get('result'):
        result = prom_data['data']['result'][0]
        nodename = result.get('metric', {}).get('nodename', 'xrpl-validator')

    print_info(f"Detected hostname: {nodename}")

    # Update dashboard template variables with defaults
    if 'templating' in dashboard_json and 'list' in dashboard_json['templating']:
        for template_var in dashboard_json['templating']['list']:
            var_name = template_var.get('name', '')

            if var_name == 'job':
                template_var['current'] = {
                    'selected': True,
                    'text': 'xrpl-validator',
                    'value': 'xrpl-validator'
                }
            elif var_name == 'node':
                template_var['current'] = {
                    'selected': True,
                    'text': f'127.0.0.1:{NODE_EXPORTER_PORT}',
                    'value': f'127.0.0.1:{NODE_EXPORTER_PORT}'
                }
            elif var_name == 'nodename':
                template_var['current'] = {
                    'selected': True,
                    'text': nodename,
                    'value': nodename
                }

    # Prepare import payload
    payload = {
        "dashboard": dashboard_json,
        "overwrite": True,
        "message": "Imported by import-dashboard.sh"
    }

    # Import dashboard
    url = f'http://127.0.0.1:{GRAFANA_PORT}/api/dashboards/db'
    data = json.dumps(payload).encode('utf-8')
    credentials = base64.b64encode(b'admin:admin').decode('ascii')
    headers = {
        'Content-Type': 'application/json',
        'Authorization': f'Basic {credentials}'
    }

    request = urllib.request.Request(url, data=data, headers=headers, method='POST')
    response = urllib.request.urlopen(request, timeout=10)

    if response.status == 200:
        response_data = json.loads(response.read().decode('utf-8'))
        dashboard_uid = response_data.get('uid', '')
        dashboard_name = dashboard_json.get('title', 'Dashboard')

        print_success(f"Dashboard imported: {dashboard_name}")
        print_info(f"Configured defaults: Job=xrpl-validator, Instance=127.0.0.1:{NODE_EXPORTER_PORT}, Nodename={nodename}")

        # Set as home dashboard
        if dashboard_uid:
            prefs_payload = {"homeDashboardUID": dashboard_uid}
            prefs_data = json.dumps(prefs_payload).encode('utf-8')
            prefs_request = urllib.request.Request(
                f'http://127.0.0.1:{GRAFANA_PORT}/api/org/preferences',
                data=prefs_data,
                headers=headers,
                method='PUT'
            )
            try:
                urllib.request.urlopen(prefs_request, timeout=10)
                print_success("Dashboard set as home page (opens automatically on login)")
            except:
                pass

        print("")
        print(f"{GREEN}================================================================================================{NC}")
        print(f"{GREEN}Dashboard Import Complete!{NC}")
        print(f"{GREEN}================================================================================================{NC}")
        print("")
        print_info("Access your dashboard:")
        print(f"  1. Set up SSH tunnel (if remote): ssh -i <key> -L {GRAFANA_PORT}:localhost:{GRAFANA_PORT} ubuntu@<server-ip>")
        print(f"  2. Open browser: http://localhost:{GRAFANA_PORT}")
        print(f"  3. Login: admin / admin (or your changed password)")
        print(f"  4. Dashboard opens automatically!")
        print("")

    else:
        print_error(f"Import failed: HTTP {response.status}")
        sys.exit(1)

except urllib.error.HTTPError as e:
    error_msg = e.read().decode() if e.fp else str(e)
    print_error(f"HTTP error {e.code}: {error_msg}")
    if e.code == 401:
        print_info("Note: Default credentials are admin/admin. Change them in the script if you've updated your password.")
    sys.exit(1)
except Exception as e:
    print_error(f"Import failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

EOF

echo ""
