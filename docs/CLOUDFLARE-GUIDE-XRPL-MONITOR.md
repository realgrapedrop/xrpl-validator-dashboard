# **__CLOUDFLARE PUBLIC DASHBOARD DEPLOYMENT GUIDE__**

*Deploy your Grafana dashboard publicly using Cloudflare Tunnel and Workers.*

---

# Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Complete Setup Process](#complete-setup-process)
- [Configuration Examples](#configuration-examples)
- [Deployment Steps](#deployment-steps)
- [Verification & Testing](#verification--testing)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)
- [Security Considerations](#security-considerations)
- [Common Issues & Solutions](#common-issues--solutions)

---

# Overview

This guide documents a proven three-tier architecture for publicly exposing a Grafana dashboard:

1. **Cloudflare Worker** - Provides clean URLs and kiosk mode embedding
2. **Cloudflare Tunnel** - Secure tunnel from your server to Cloudflare's edge
3. **Grafana Container** - Dashboard backend with anonymous authentication

**Benefits:**
- ✅ No port forwarding or firewall changes needed
- ✅ Clean URLs (no query parameters visible)
- ✅ Secure tunnel (TLS encrypted)
- ✅ Anonymous read-only access (kiosk mode)
- ✅ Free tier available (Cloudflare)
- ✅ Easy to deploy and maintain

**Use Cases:**
- Public monitoring dashboards
- Status pages
- Analytics displays
- Data visualization for public consumption

---

# Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Public Internet                        │
│              https://monitor.yourdomain.com             │
└────────────────────────┬────────────────────────────────┘
                         │
                         │ HTTPS:443
                         ↓
┌─────────────────────────────────────────────────────────┐
│              Cloudflare Worker (Edge)                   │
│  • Intercepts root path (/)                             │
│  • Returns HTML with embedded iframe                    │
│  • Iframe loads dashboard with kiosk params             │
│  • URL stays clean in browser                           │
│  • Provides /health endpoint                            │
└────────────────────────┬────────────────────────────────┘
                         │
                         │ Cloudflare Tunnel (TLS encrypted)
                         ↓
┌─────────────────────────────────────────────────────────┐
│              Cloudflare Tunnel (cloudflared)            │
│  • Systemd service on your server                       │
│  • 4 concurrent connections to Cloudflare               │
│  • No inbound firewall rules needed                     │
└────────────────────────┬────────────────────────────────┘
                         │
                         │ HTTP:3000 (localhost)
                         ↓
┌─────────────────────────────────────────────────────────┐
│              Grafana Container (Docker)                 │
│  • Container: xrpl-monitor-grafana-prod                 │
│  • Anonymous authentication enabled                     │
│  • Viewer role (read-only)                              │
│  • Login form disabled                                  │
│  • Embedding allowed                                    │
│  • Connects to data sources (Prometheus, etc.)          │
└─────────────────────────────────────────────────────────┘
```

### Why This Architecture?

**Cloudflare Worker Approach (Chosen):**
- ✅ Clean URL stays in address bar (`https://monitor.yourdomain.com`)
- ✅ No visible redirects
- ✅ Simple HTML + iframe approach
- ✅ Full-screen kiosk experience
- ✅ Easy to debug

**Alternative: Direct Access (Not Recommended):**
- ❌ Query parameters visible in URL (`?kiosk&refresh=10s`)
- ❌ Users see Grafana branding
- ❌ Harder to control UX
- ❌ Less professional appearance

---

# Prerequisites

### Required Software

```bash
# Docker & Docker Compose
docker --version  # Should be 20.10+
docker compose version  # Should be 2.0+

# Cloudflared CLI
cloudflared --version  # Latest version

# Wrangler CLI (Cloudflare Workers)
wrangler --version  # 3.x or 4.x

# jq (for JSON manipulation)
jq --version
```

### Cloudflare Account Setup

1. **Active Cloudflare account** with a domain
2. **Domain DNS** managed by Cloudflare (yourdomain.com)
3. **Cloudflared authenticated:**
   ```bash
   cloudflared tunnel login
   ```
4. **Wrangler authenticated:**
   ```bash
   wrangler login
   ```

### Server Requirements

- Ubuntu 20.04+ or similar Linux distribution
- 2+ GB RAM
- Docker installed and running
- Grafana dashboard already created
- Data source configured (Prometheus, InfluxDB, etc.)

---

# Complete Setup Process

### Phase 1: Grafana Configuration

#### 1.1 Create Docker Compose File

**Directory structure:**
```
/home/user/monitoring/
├── compose/
│   └── prod-xrpl-monitor/
│       ├── docker-compose.yaml
│       ├── custom.css (recommended - hides panel menus)
│       └── index.html (recommended - loads custom CSS)
├── data/
│   └── xrpl-monitor-grafana-prod/  # Grafana data persistence
└── provisioning/
    └── prod-xrpl-monitor/
        ├── dashboards/
        │   └── xrpl-validator-dashboard.json
        └── datasources/
            └── datasource.yaml
```

#### 1.2 Docker Compose Configuration

**File:** `compose/prod-xrpl-monitor/docker-compose.yaml`

```yaml
name: prod-xrpl-monitor

services:
  xrpl-monitor-grafana-prod:
    image: grafana/grafana:12.1.1
    container_name: xrpl-monitor-grafana-prod
    network_mode: host
    restart: unless-stopped

    user: "472:0"
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL

    environment:
      # Server Configuration
      GF_SERVER_HTTP_PORT: "3000"
      GF_SERVER_ROOT_URL: "https://monitor.yourdomain.com"
      GF_SERVER_ENABLE_GZIP: "true"
      GF_LOG_MODE: "console"
      GF_LOG_LEVEL: "warn"

      # Database
      GF_DATABASE_TYPE: "sqlite3"
      GF_DATABASE_WAL: "true"

      # Data Proxy (important for performance)
      GF_DATAPROXY_TIMEOUT: "90s"
      GF_DATAPROXY_DIAL_TIMEOUT: "10s"
      GF_DATAPROXY_KEEP_ALIVE_SECONDS: "120"
      GF_DATAPROXY_IDLE_CONN_TIMEOUT_SECONDS: "90"
      GF_DATAPROXY_TLS_HANDSHAKE_TIMEOUT_SECONDS: "10"
      GF_DATAPROXY_MAX_CONNS_PER_HOST: "256"
      GF_DATAPROXY_MAX_IDLE_CONNECTIONS: "512"

      # Anonymous Authentication (KEY SETTINGS)
      GF_USERS_DEFAULT_THEME: "dark"
      GF_USERS_ALLOW_SIGN_UP: "false"
      GF_AUTH_ANONYMOUS_ENABLED: "true"
      GF_AUTH_ANONYMOUS_ORG_ROLE: "Viewer"
      GF_AUTH_ANONYMOUS_ORG_NAME: "Main Org."
      GF_AUTH_DISABLE_LOGIN_FORM: "true"
      GF_AUTH_BASIC_ENABLED: "false"

      # Security (for iframe embedding)
      GF_SECURITY_ALLOW_EMBEDDING: "true"
      GF_PANELS_DISABLE_SANITIZE_HTML: "true"

      # Default Dashboard
      GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH: "/etc/grafana/provisioning/dashboards/xrpl-validator-dashboard.json"

      # Metrics
      GF_METRICS_ENABLED: "true"
      GF_METRICS_DISABLE_TOTAL_STATS: "true"

    volumes:
      - /home/user/monitoring/data/xrpl-monitor-grafana-prod:/var/lib/grafana
      - /home/user/monitoring/provisioning/prod-xrpl-monitor:/etc/grafana/provisioning:ro
      - /home/user/monitoring/compose/prod-xrpl-monitor/custom.css:/usr/share/grafana/public/css/custom.css:ro
      - /home/user/monitoring/compose/prod-xrpl-monitor/index.html:/usr/share/grafana/public/views/index.html:ro

    ulimits:
      nofile:
        soft: 262144
        hard: 262144

    cpus: "2.0"
    mem_limit: "4g"

    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:3000/api/health"]
      interval: 30s
      timeout: 5s
      retries: 5
```

**Key Environment Variables:**

| Variable | Purpose |
|----------|---------|
| `GF_SERVER_HTTP_PORT` | Port 3000 - Grafana listen port |
| `GF_SERVER_ROOT_URL` | https://monitor.yourdomain.com |
| `GF_AUTH_ANONYMOUS_ENABLED` | Enables public access without login |
| `GF_AUTH_ANONYMOUS_ORG_ROLE` | Set to "Viewer" for read-only |
| `GF_AUTH_DISABLE_LOGIN_FORM` | Hides login UI |
| `GF_SECURITY_ALLOW_EMBEDDING` | Required for iframe embedding |

#### 1.3 Custom CSS to Hide Panel Menus (Optional but Recommended)

To create a cleaner kiosk experience, create a custom CSS file that hides panel menus, headers, and navigation elements.

**File:** `compose/prod-xrpl-monitor/custom.css`

```css
/* Hide panel menus & headers for clean kiosk mode (Grafana 11.x+) */

/* Hide kebab menu and panel toolbar buttons */
[data-testid="panel-menu-toggle"],
[data-testid="panel-header-menu"],
[aria-label="Panel menu"],
button[aria-label*="Menu"],
.panel-menu,
.panel-menu-container,
.panel-header__menu,
.panel-header .panel-menu,
.panel-title-container:hover .panel-menu,
[role="toolbar"][aria-label*="Panel"] {
  display: none !important;
  visibility: hidden !important;
  pointer-events: none !important;
}

/* Remove panel header bar and any leftover space */
.panel-header,
.panel-container .panel-header,
div[aria-label="Panel header"],
div[data-testid="panel-header"],
div[data-testid="panel-header-actions"] {
  height: 0 !important;
  min-height: 0 !important;
  padding: 0 !important;
  border: 0 !important;
  overflow: hidden !important;
}

/* Tighten layout spacing */
.react-grid-item,
.panel-container {
  margin: 2px !important;
  padding: 0 !important;
}

.react-grid-layout {
  margin: 0 !important;
}

/* In kiosk mode, hide top nav if it shows */
:root[kiosk] header[aria-label="Top navigation"],
:root[kiosk] [data-testid="top-nav"] {
  display: none !important;
}

/* Hide panel count indicator on collapsed row headers */
span.css-1g2nl71,
.css-1g2nl71 {
  display: none !important;
  visibility: hidden !important;
  opacity: 0 !important;
  width: 0 !important;
  height: 0 !important;
  overflow: hidden !important;
  font-size: 0 !important;
}
```

**Why this works:**
- Hides all panel menu buttons (three-dot/kebab menus)
- Removes panel headers entirely
- Tightens spacing for better layout
- Ensures top navigation is hidden in kiosk mode
- Removes panel count indicators from collapsed rows

#### 1.4 Modified Index.html to Load Custom CSS

You need to modify Grafana's default `index.html` to load the custom CSS file.

**Option A: Extract from your Grafana container (Recommended)**

```bash
# Extract the default index.html from Grafana 12.1.1
docker run --rm grafana/grafana:12.1.1 cat /usr/share/grafana/public/views/index.html > index.html
```

Then add this line after the `<base>` tag (around line 17):

```html
<link rel="stylesheet" href="public/css/custom.css?v=2" />
```

**Option B: Use the complete modified index.html**

The key modification is adding the custom CSS link. Here's the critical section of `index.html`:

```html
<!DOCTYPE html>
<html lang="[[.User.Language]]">
  <head>
    <meta charset="utf-8" />
    <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1" />
    <meta name="viewport" content="width=device-width" />
    <meta name="theme-color" content="#000" />

    <title>[[.AppTitle]]</title>

    <base href="[[.AppSubUrl]]/" />

    <!-- Add custom CSS to hide panel menus and headers -->
    <link rel="stylesheet" href="public/css/custom.css?v=2" />

    <link rel="icon" type="image/png" href="[[.FavIcon]]" />
    <!-- rest of file... -->
```

**Note:** The full `index.html` is ~340 lines. The only change needed is adding the custom CSS link tag shown above.

#### 1.5 Dashboard Provisioning Configuration

Grafana needs to know where to find your dashboard files. Create a provisioning config:

**File:** `provisioning/prod-xrpl-monitor/dashboards/dashboards.yaml`

```yaml
apiVersion: 1

providers:
  - name: 'XRPL Monitor'
    folder: 'XRPL Monitor'
    type: file
    allowUiUpdates: true
    updateIntervalSeconds: 10
    options:
      path: /etc/grafana/provisioning/dashboards
```

**Key settings:**
- `name`: Display name in Grafana
- `folder`: Organizes dashboards in a folder
- `type: file`: Load from JSON files
- `allowUiUpdates: true`: Allows editing in UI (changes won't persist)
- `updateIntervalSeconds: 10`: How often to check for changes
- `path`: Directory containing dashboard JSON files

**Place your dashboard JSON file here:**
`provisioning/prod-xrpl-monitor/dashboards/xrpl-validator-dashboard.json`

#### 1.6 Datasource Provisioning Configuration

Configure your data source (example uses Prometheus - adjust for your needs):

**File:** `provisioning/prod-xrpl-monitor/datasources/prometheus.yaml`

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    isDefault: true
    url: http://localhost:9090
    jsonData:
      httpMethod: POST
      timeInterval: 30s
    editable: true
```

**For ClickHouse (if using):**

**File:** `provisioning/prod-xrpl-monitor/datasources/clickhouse.yaml`

```yaml
apiVersion: 1

datasources:
  - name: ClickHouse
    type: grafana-clickhouse-datasource
    access: proxy
    isDefault: true
    jsonData:
      host: localhost
      port: 9000
      protocol: native
      username: default
      defaultDatabase: xrpl_monitor
    editable: true
```

**Important Notes:**
- Datasource `name` must match what your dashboard JSON references
- `url` or `host` should point to your actual data source location
- Use `localhost` if data source runs on same host (with network_mode: host)
- For multiple datasources, create separate YAML files or add to same file

#### 1.7 Start Grafana

```bash
cd /home/user/monitoring/compose/prod-xrpl-monitor
docker compose up -d

# Verify health
curl http://localhost:3000/api/health
# Expected: {"database":"ok","version":"12.1.1",...}
```

---

### Phase 2: Cloudflare Tunnel Setup

#### 2.1 Create Tunnel

```bash
# Create tunnel (one-time setup)
cloudflared tunnel create xrpl-monitor

# Output will show tunnel ID:
# Created tunnel xrpl-monitor with id a1aec802-96a1-4b36-b87f-0bfcf169c213

# Save this tunnel ID!
TUNNEL_ID="a1aec802-96a1-4b36-b87f-0bfcf169c213"
```

#### 2.2 Configure DNS

**Option A: Using Cloudflared CLI (Recommended)**

```bash
cloudflared tunnel route dns xrpl-monitor monitor.yourdomain.com
```

**Option B: Manual DNS (Cloudflare Dashboard)**

1. Go to Cloudflare Dashboard → DNS → Records
2. Add CNAME record:
   - **Type:** CNAME
   - **Name:** `xrpl-monitor`
   - **Target:** `a1aec802-96a1-4b36-b87f-0bfcf169c213.cfargotunnel.com` (use your tunnel ID)
   - **Proxy status:** Enabled (orange cloud)
   - **TTL:** Auto

#### 2.3 Create Tunnel Configuration

**File:** `~/.cloudflared/config-xrpl-monitor.yml`

```yaml
tunnel: a1aec802-96a1-4b36-b87f-0bfcf169c213  # Your tunnel ID
credentials-file: /home/user/.cloudflared/a1aec802-96a1-4b36-b87f-0bfcf169c213.json
connections: 4  # Number of concurrent connections

ingress:
  - hostname: monitor.yourdomain.com
    service: http://127.0.0.1:3000
  - service: http_status:404  # Catch-all
```

**Important Notes:**
- `tunnel`: Must match your tunnel ID
- `credentials-file`: Auto-created when tunnel is created
- `connections`: 4 is recommended for reliability
- `service`: Must use port 3000 to match Grafana

#### 2.4 Install as Systemd Service

**Create service file:**

```bash
sudo tee /etc/systemd/system/cloudflared-xrpl-monitor.service > /dev/null <<'EOF'
[Unit]
Description=Cloudflare Tunnel (xrpl-monitor)
After=network-online.target
Wants=network-online.target

[Service]
User=user  # Your username
Group=user
ExecStart=/usr/local/bin/cloudflared tunnel --config /home/user/.cloudflared/config-xrpl-monitor.yml run
Restart=always
RestartSec=3
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
```

**Enable and start service:**

```bash
sudo systemctl daemon-reload
sudo systemctl enable cloudflared-xrpl-monitor
sudo systemctl start cloudflared-xrpl-monitor

# Check status
systemctl status cloudflared-xrpl-monitor

# Should show:
# Active: active (running)
# And 4 "Registered tunnel connection" messages
```

---

### Phase 3: Cloudflare Worker Deployment

#### 3.1 Create Worker Directory

```bash
mkdir -p /home/user/monitoring/workers/xrpl-monitor/src
cd /home/user/monitoring/workers/xrpl-monitor
```

#### 3.2 Create Worker Code

**File:** `src/index.js`

```javascript
export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);

    // Health check endpoint
    if (url.pathname === "/health") {
      return new Response(JSON.stringify({ status: "ok" }), {
        status: 200,
        headers: {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-store"
        }
      });
    }

    // Root path - return HTML with iframe
    if (url.pathname === "/" || url.pathname === "/index.html") {
      // XRPL Validator Monitor dashboard
      const dashboardPath = "/d/xrpl-validator-monitor-full/xrpl-validator-dashboard-opaque";
      const kioskParams = "?kiosk&refresh=10s";
      const kiosk = `${dashboardPath}${kioskParams}`;

      const html = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width,initial-scale=1"/>
    <title>XRPL Validator Monitor</title>
    <style>
      html,body,iframe{margin:0;padding:0;height:100%;width:100%;border:0;background:#000}
      body{overflow:hidden}
    </style>
  </head>
  <body>
    <iframe src="${kiosk}" allow="fullscreen" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>
  </body>
</html>`;

      return new Response(html, {
        headers: {
          "content-type": "text/html; charset=utf-8",
          "cache-control": "no-store"
        }
      });
    }

    // All other requests - pass through to Grafana
    return fetch(req);
  }
}
```

**Dashboard Details:**
- **UID:** `xrpl-validator-monitor-full` (stable identifier)
- **Slug:** `xrpl-validator-dashboard-opaque` (can change with dashboard title)
- **Full Path:** `/d/xrpl-validator-monitor-full/xrpl-validator-dashboard-opaque`

**Kiosk Parameters:**
- `kiosk` - Full-screen mode, no sidebar
- `refresh=10s` - Auto-refresh every 10 seconds
- Optional: `&theme=dark` - Force dark theme

#### 3.3 Create Wrangler Config

**File:** `wrangler.toml`

```toml
name = "xrpl-monitor-kiosk"
main = "src/index.js"
compatibility_date = "2025-11-07"

routes = [
  { pattern = "monitor.yourdomain.com/*", zone_name = "yourdomain.com" }
]
```

**Important:**
- `name`: Worker name (shows in Cloudflare dashboard)
- `pattern`: Must match full subdomain
- `zone_name`: Root domain (yourdomain.com)

#### 3.4 Deploy Worker

```bash
cd /home/user/monitoring/workers/xrpl-monitor

# Deploy
wrangler deploy

# Expected output:
# ⛅️ wrangler 4.37.1
# Total Upload: 1.25 KiB / gzip: 0.62 KiB
# Uploaded xrpl-monitor-kiosk (3.15 sec)
# Deployed xrpl-monitor-kiosk triggers (1.68 sec)
#   monitor.yourdomain.com/* (zone name: yourdomain.com)
```

**Verify deployment:**

```bash
# Check worker list
wrangler deployments list

# Test health endpoint
curl https://monitor.yourdomain.com/health
# Expected: {"status":"ok"}
```

---

# Verification & Testing

### Step 1: Local Grafana Test

```bash
# Health check
curl http://localhost:3000/api/health

# Dashboard exists
curl http://localhost:3000/api/dashboards/uid/xrpl-validator-monitor-full | jq .

# Anonymous auth enabled
curl http://localhost:3000/api/user | jq .
# Expected: {"id":1,"orgId":1,"role":"Viewer"}
```

### Step 2: Tunnel Test

```bash
# Check service status
systemctl status cloudflared-xrpl-monitor

# Should show:
# - Active (running)
# - 4 "Registered tunnel connection" messages

# Check logs
sudo journalctl -u cloudflared-xrpl-monitor -f
```

### Step 3: Worker Test

```bash
# Health endpoint
curl https://monitor.yourdomain.com/health

# HTML response
curl https://monitor.yourdomain.com/ | grep iframe
# Should show iframe with dashboard path
```

### Step 4: Browser Test

1. **Open:** `https://monitor.yourdomain.com`

2. **Verify:**
   - ✅ URL stays clean (no redirects visible)
   - ✅ Dashboard loads in full-screen kiosk mode
   - ✅ No Grafana sidebar or admin UI
   - ✅ Data displays correctly
   - ✅ No login prompt

3. **Test auto-refresh:**
   - Wait 10 seconds
   - Dashboard should auto-refresh

---

# Troubleshooting

### Issue: "No data" in Grafana panels

**Possible Causes:**
1. Datasource not configured
2. Datasource UID mismatch
3. Database connection failed

**Solution:**

```bash
# Check datasource configuration
curl -s http://localhost:3000/api/datasources | jq '.[] | {name, uid, type}'

# Check dashboard datasource references
curl -s http://localhost:3000/api/dashboards/uid/xrpl-validator-monitor-full | \
  jq '.dashboard.panels[0].targets[0].datasource'

# If UIDs don't match, update dashboard JSON and restart Grafana
```

### Issue: Tunnel not connecting

**Check logs:**

```bash
sudo journalctl -u cloudflared-xrpl-monitor -n 50
```

**Common errors:**

| Error | Solution |
|-------|----------|
| "Invalid tunnel ID" | Verify `tunnel:` in config matches `cloudflared tunnel list` |
| "Credentials file not found" | Check path in `credentials-file:` |
| "Connection refused" | Grafana not running on port 3000 |
| "Failed to register" | DNS not configured correctly |

**Restart tunnel:**

```bash
sudo systemctl restart cloudflared-xrpl-monitor
```

### Issue: Worker not intercepting requests

**Verify worker route:**

```bash
# Check routes in Cloudflare dashboard
# Workers & Pages → xrpl-monitor-kiosk → Settings → Triggers

# Should show:
# Route: monitor.yourdomain.com/*
# Zone: yourdomain.com
```

**Common issues:**
- DNS CNAME points to wrong target
- Worker route pattern doesn't match
- Worker not deployed (check `wrangler deployments list`)

**Re-deploy worker:**

```bash
cd /home/user/monitoring/workers/xrpl-monitor
wrangler deploy
```

### Issue: "Ugly dashboard" (sidebar visible)

**Cause:** Kiosk mode not applied

**Verify iframe:**

```bash
curl https://monitor.yourdomain.com/ | grep -o 'src="[^"]*"'
# Should show: src="/d/xrpl-validator-monitor-full/xrpl-validator-dashboard-opaque?kiosk&refresh=10s"
```

**Check browser:**
- Clear browser cache
- Try incognito mode
- Check browser console for errors

### Issue: Dashboard shows login form

**Cause:** Anonymous auth not enabled

**Verify Grafana config:**

```bash
docker exec xrpl-monitor-grafana-prod env | grep AUTH
# Should show:
# GF_AUTH_ANONYMOUS_ENABLED=true
# GF_AUTH_DISABLE_LOGIN_FORM=true
```

**Fix:**
1. Update `docker-compose.yaml`
2. Restart container: `docker compose restart`

### Issue: Tunnel has 0 connections

**Check systemd service:**

```bash
systemctl status cloudflared-xrpl-monitor | grep "Registered tunnel connection"
```

**If 0 connections:**

1. Check config file syntax:
   ```bash
   cat ~/.cloudflared/config-xrpl-monitor.yml
   ```

2. Verify credentials file exists:
   ```bash
   ls -la ~/.cloudflared/*.json
   ```

3. Check cloudflared logs:
   ```bash
   sudo journalctl -u cloudflared-xrpl-monitor -n 100
   ```

---

# Maintenance

### Update Dashboard

```bash
# 1. Edit dashboard in Grafana UI or JSON file

# 2. Export dashboard (if edited in UI)
curl -s http://localhost:3000/api/dashboards/uid/xrpl-validator-monitor-full | \
  jq '.dashboard' > /path/to/dashboard.json

# 3. Copy to provisioning directory
cp /path/to/dashboard.json /home/user/monitoring/provisioning/prod-xrpl-monitor/dashboards/

# 4. Restart Grafana (or wait for auto-reload)
cd /home/user/monitoring/compose/prod-xrpl-monitor
docker compose restart
```

### Update Worker

```bash
# 1. Edit src/index.js
vi /home/user/monitoring/workers/xrpl-monitor/src/index.js

# 2. Deploy
cd /home/user/monitoring/workers/xrpl-monitor
wrangler deploy

# Changes take effect immediately (no restart needed)
```

### Update Grafana Version

```bash
# 1. Edit docker-compose.yaml
# Change: image: grafana/grafana:12.1.1
#     To: image: grafana/grafana:12.2.0

# 2. Recreate container
cd /home/user/monitoring/compose/prod-xrpl-monitor
docker compose up -d --force-recreate

# 3. Verify health
curl http://localhost:3000/api/health
```

### Update Cloudflared

```bash
# Download latest version
sudo curl -L --output /usr/local/bin/cloudflared \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64

# Make executable
sudo chmod +x /usr/local/bin/cloudflared

# Restart service
sudo systemctl restart cloudflared-xrpl-monitor
```

### View Logs

```bash
# Grafana logs
docker logs xrpl-monitor-grafana-prod -f

# Tunnel logs
sudo journalctl -u cloudflared-xrpl-monitor -f

# Worker logs
# View in Cloudflare Dashboard:
# Workers & Pages → xrpl-monitor-kiosk → Logs → Real-time logs
```

---

# Security Considerations

### Anonymous Access

**What's exposed:**
- ✅ Dashboard data (read-only)
- ✅ Panel queries
- ✅ Dashboard structure

**What's NOT exposed:**
- ❌ Admin functions
- ❌ Dashboard editing
- ❌ User management
- ❌ Data source credentials
- ❌ Server logs

**User capabilities:**
- View dashboards
- Use time range selector
- View panel tooltips
- Use dashboard variables (if configured)

**User CANNOT:**
- Create/edit dashboards
- Create annotations
- Create alerts
- Access admin settings
- Query data sources directly

### Network Security

**Grafana:**
- Listens only on `localhost` (127.0.0.1) port 3000
- No direct internet exposure
- Accessible only via tunnel

**Tunnel:**
- TLS encrypted end-to-end
- Authenticated to Cloudflare
- No inbound firewall rules needed
- Outbound HTTPS only

**Worker:**
- Runs on Cloudflare's edge
- Stateless (no data storage)
- Transparent proxy for assets

### Data Privacy

**Considerations:**
- All dashboard data becomes public
- Consider sanitizing sensitive information:
  - IP addresses
  - Internal hostnames
  - User identifiers
  - API keys (never store in dashboards!)

**Best Practices:**
- Review dashboard queries before deploying
- Use aggregated data when possible
- Whitelist only necessary panels
- Monitor access logs (Cloudflare Analytics)

---

# Common Issues & Solutions

### Dashboard Performance

**Issue:** Slow loading or timeouts

**Solutions:**

1. **Increase dataproxy timeouts:**
   ```yaml
   GF_DATAPROXY_TIMEOUT: "120s"
   GF_DATAPROXY_DIAL_TIMEOUT: "15s"
   ```

2. **Optimize queries:**
   - Use time range limits
   - Add indexes to database
   - Use query result caching

3. **Increase container resources:**
   ```yaml
   cpus: "4.0"
   mem_limit: "8g"
   ```

### Worker Errors

**Issue:** "Error 1101: Worker threw exception"

**Check:**

```bash
# View worker logs in Cloudflare dashboard
# Workers & Pages → xrpl-monitor-kiosk → Logs

# Common causes:
# - Syntax error in index.js
# - Invalid response format
# - Uncaught exception
```

**Fix:**
- Check browser console for errors
- Validate JavaScript syntax
- Add try-catch blocks
- Test locally with wrangler dev

### DNS Propagation

**Issue:** "DNS_PROBE_FINISHED_NXDOMAIN"

**Wait time:** 5-30 minutes for DNS propagation

**Verify:**

```bash
# Check DNS resolution
dig monitor.yourdomain.com

# Should show CNAME pointing to tunnel
nslookup monitor.yourdomain.com
```

### Certificate Errors

**Issue:** "NET::ERR_CERT_COMMON_NAME_INVALID"

**Cause:** DNS not fully propagated to Cloudflare

**Solution:**
1. Wait 5-10 minutes
2. Verify DNS in Cloudflare dashboard
3. Check SSL/TLS mode (should be "Full" or "Full (strict)")

### Dashboard Not Loading in Iframe

**Issue:** "Refused to display in a frame"

**Cause:** `GF_SECURITY_ALLOW_EMBEDDING` not set

**Fix:**

```bash
# Check environment variable
docker exec xrpl-monitor-grafana-prod env | grep EMBEDDING

# Should show:
# GF_SECURITY_ALLOW_EMBEDDING=true

# If missing, add to docker-compose.yaml and restart
```

---

# Dashboard Customization

This section covers common dashboard customizations to enhance the user experience, based on the XRP Watchdog implementation.

### Time Range Quick Links

Add clickable time range buttons at the top of your dashboard for easy navigation between different time periods.

**How it works:**
- Creates a Text panel with HTML content
- Links update both the dashboard time range and any time-based variables
- Users can quickly switch between 5m, 1h, 6h, 24h, 7d, 30d, etc.

**Step 1: Create a Text Panel**

In Grafana's dashboard edit mode:
1. Add a new panel
2. Select "Text" visualization
3. Set panel height to 2 (in grid units)
4. Set panel width to 24 (full width)
5. Set transparent background (in panel options)

**Step 2: Configure the HTML Content**

In the Text panel options:
- Set **Mode** to "HTML"
- Add this HTML content (customize for your dashboard):

```html
<div style="display:flex;align-items:center;margin-top:10px;font-size:1.3rem;line-height:1.8;">
  <div style="font-weight:bold;margin-right:12px;font-size:1.4rem;">📊 Adjust analysis time range:</div>
  <div style="display:flex;align-items:center;flex-wrap:wrap;gap:8px;">
    <a href="/d/xrpl-validator-monitor-full/xrpl-validator-dashboard-opaque?var-window=5m&from=now-5m&to=now"
       style="color:#4da3ff;text-decoration:none;margin:0 6px;font-size:1.3rem;font-weight:500;">5m</a> ▪
    <a href="/d/xrpl-validator-monitor-full/xrpl-validator-dashboard-opaque?var-window=1h&from=now-1h&to=now"
       style="color:#4da3ff;text-decoration:none;margin:0 6px;font-size:1.3rem;font-weight:500;">1h</a> ▪
    <a href="/d/xrpl-validator-monitor-full/xrpl-validator-dashboard-opaque?var-window=6h&from=now-6h&to=now"
       style="color:#4da3ff;text-decoration:none;margin:0 6px;font-size:1.3rem;font-weight:500;">6h</a> ▪
    <a href="/d/xrpl-validator-monitor-full/xrpl-validator-dashboard-opaque?var-window=24h&from=now-24h&to=now"
       style="color:#4da3ff;text-decoration:none;margin:0 6px;font-size:1.3rem;font-weight:500;">24h</a> ▪
    <a href="/d/xrpl-validator-monitor-full/xrpl-validator-dashboard-opaque?var-window=2d&from=now-2d&to=now"
       style="color:#4da3ff;text-decoration:none;margin:0 6px;font-size:1.3rem;font-weight:500;">2d</a> ▪
    <a href="/d/xrpl-validator-monitor-full/xrpl-validator-dashboard-opaque?var-window=7d&from=now-7d&to=now"
       style="color:#4da3ff;text-decoration:none;margin:0 6px;font-size:1.3rem;font-weight:500;">7d</a> ▪
    <a href="/d/xrpl-validator-monitor-full/xrpl-validator-dashboard-opaque?var-window=14d&from=now-14d&to=now"
       style="color:#4da3ff;text-decoration:none;margin:0 6px;font-size:1.3rem;font-weight:500;">14d</a> ▪
    <a href="/d/xrpl-validator-monitor-full/xrpl-validator-dashboard-opaque?var-window=30d&from=now-30d&to=now"
       style="color:#4da3ff;text-decoration:none;margin:0 6px;font-size:1.3rem;font-weight:500;">30d</a>
  </div>
</div>
```

**Step 3: Customize the URLs**

Replace the dashboard path in each link with your own:
- **Dashboard UID:** `xrpl-validator-monitor-full` (your stable dashboard UID)
- **Dashboard Slug:** `xrpl-validator-dashboard-opaque` (your dashboard URL slug)

**URL Parameters Explained:**

| Parameter | Purpose | Example |
|-----------|---------|---------|
| `var-window=5m` | Sets dashboard variable (if you have one) | `var-window=24h` |
| `from=now-5m` | Sets time range start | `from=now-24h` |
| `to=now` | Sets time range end (usually "now") | `to=now` |

**Example URL breakdown:**
```
/d/xrpl-validator-monitor-full/xrpl-validator-dashboard-opaque?var-window=24h&from=now-24h&to=now
│   │                          │                              │          │              │
│   └─ Dashboard UID           └─ Dashboard slug             │          │              └─ End time
│                                                             │          └─ Start time
└─ Dashboard path                                             └─ Variable (optional)
```

**Step 4: Position the Panel**

In dashboard edit mode:
- Drag the panel to the top of your dashboard
- Place it directly under the title row
- Set width to 24 (full width) and height to 2

**Optional: If You Don't Have Dashboard Variables**

If your dashboard doesn't use variables, omit the `var-window` parameter:

```html
<a href="/d/your-dashboard-uid/your-dashboard-slug?from=now-5m&to=now"
   style="color:#4da3ff;text-decoration:none;margin:0 6px;font-size:1.3rem;font-weight:500;">5m</a>
```

**Styling Tips:**

- **Font size:** Adjust `font-size:1.3rem` to make links larger/smaller
- **Color:** Change `color:#4da3ff` to match your theme
- **Spacing:** Adjust `margin` and `gap` values for tighter/looser layout
- **Bullet separators:** The `▪` character can be changed to `|`, `•`, or removed

**Result:**

Users will see a row of clickable time range buttons that instantly update the dashboard view, making it easy to analyze different time periods without using the Grafana time picker.

---

# Advanced Configuration

### Multiple Dashboards

**Serve multiple dashboards from one tunnel:**

**Worker code:**

```javascript
export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);

    // Route based on path
    const dashboards = {
      "/": "/d/xrpl-validator-monitor-full/xrpl-validator-dashboard-opaque?kiosk",
      "/performance": "/d/performance-dashboard/performance?kiosk",
      "/network": "/d/network-dashboard/network?kiosk"
    };

    const dashboardPath = dashboards[url.pathname];

    if (dashboardPath) {
      const html = `<!doctype html>
<html>
  <head><title>XRPL Validator Monitor</title></head>
  <body style="margin:0">
    <iframe src="${dashboardPath}" style="width:100%;height:100vh;border:0"></iframe>
  </body>
</html>`;
      return new Response(html, {
        headers: { "content-type": "text/html" }
      });
    }

    return fetch(req);
  }
}
```

### Custom Branding

**Add logo and custom CSS:**

```javascript
const html = `<!doctype html>
<html>
  <head>
    <title>XRPL Validator Monitor</title>
    <style>
      body { margin: 0; font-family: sans-serif; }
      .header {
        background: #1a1a1a;
        color: white;
        padding: 10px 20px;
        display: flex;
        align-items: center;
      }
      .header img { height: 30px; margin-right: 15px; }
      iframe { width: 100%; height: calc(100vh - 50px); border: 0; }
    </style>
  </head>
  <body>
    <div class="header">
      <img src="/logo.png" alt="Logo">
      <h1>XRPL Validator Monitor</h1>
    </div>
    <iframe src="${kiosk}"></iframe>
  </body>
</html>`;
```

### Authentication

**Add basic password protection:**

```javascript
export default {
  async fetch(req, env, ctx) {
    const PASSWORD = env.DASHBOARD_PASSWORD; // Set in Worker settings

    const url = new URL(req.url);
    const auth = req.headers.get("Authorization");

    if (!auth || auth !== `Bearer ${PASSWORD}`) {
      return new Response("Unauthorized", {
        status: 401,
        headers: { "WWW-Authenticate": "Bearer" }
      });
    }

    // ... rest of worker code
  }
}
```

---

# Automation Scripts

### Complete Deployment Script

```bash
#!/bin/bash
# deploy-xrpl-monitor.sh - Automated dashboard deployment

set -e

# Configuration
DOMAIN="monitor.yourdomain.com"
GRAFANA_PORT="3000"
DASHBOARD_UID="xrpl-validator-monitor-full"
TUNNEL_NAME="xrpl-monitor"

# Create tunnel
cloudflared tunnel create $TUNNEL_NAME
TUNNEL_ID=$(cloudflared tunnel list | grep $TUNNEL_NAME | awk '{print $1}')

# Configure DNS
cloudflared tunnel route dns $TUNNEL_NAME $DOMAIN

# Create tunnel config
cat > ~/.cloudflared/config-${TUNNEL_NAME}.yml <<EOF
tunnel: $TUNNEL_ID
credentials-file: ~/.cloudflared/${TUNNEL_ID}.json
connections: 4
ingress:
  - hostname: $DOMAIN
    service: http://127.0.0.1:${GRAFANA_PORT}
  - service: http_status:404
EOF

# Install systemd service
sudo tee /etc/systemd/system/cloudflared-${TUNNEL_NAME}.service > /dev/null <<EOF
[Unit]
Description=Cloudflare Tunnel ($TUNNEL_NAME)
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
Group=$USER
ExecStart=/usr/local/bin/cloudflared tunnel --config ~/.cloudflared/config-${TUNNEL_NAME}.yml run
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Start service
sudo systemctl daemon-reload
sudo systemctl enable cloudflared-${TUNNEL_NAME}
sudo systemctl start cloudflared-${TUNNEL_NAME}

echo "✓ Tunnel deployed: $DOMAIN"
echo "✓ Next: Deploy Cloudflare Worker"
```

---

# Reference

### Useful Commands

```bash
# Tunnel management
cloudflared tunnel list
cloudflared tunnel info xrpl-monitor
cloudflared tunnel delete xrpl-monitor

# Worker management
wrangler deployments list
wrangler tail  # Stream logs
wrangler dev   # Local testing

# Docker
docker compose ps
docker compose logs -f
docker compose restart

# Systemd
systemctl status cloudflared-xrpl-monitor
journalctl -u cloudflared-xrpl-monitor -f
```

### Environment Variables Reference

| Variable | Default | Purpose |
|----------|---------|---------|
| `GF_SERVER_HTTP_PORT` | `3000` | Grafana listen port |
| `GF_SERVER_ROOT_URL` | - | Public URL (required) |
| `GF_AUTH_ANONYMOUS_ENABLED` | `false` | Enable public access |
| `GF_AUTH_ANONYMOUS_ORG_ROLE` | `Viewer` | Anonymous user role |
| `GF_AUTH_DISABLE_LOGIN_FORM` | `false` | Hide login UI |
| `GF_SECURITY_ALLOW_EMBEDDING` | `false` | Allow iframe embedding |
| `GF_DATAPROXY_TIMEOUT` | `30s` | Query timeout |

---

# Support & Resources

### Official Documentation

- **Cloudflare Tunnel:** https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
- **Cloudflare Workers:** https://developers.cloudflare.com/workers/
- **Grafana:** https://grafana.com/docs/
- **Wrangler CLI:** https://developers.cloudflare.com/workers/wrangler/

### Community Resources

- Cloudflare Community: https://community.cloudflare.com/
- Grafana Community: https://community.grafana.com/
- Reddit: r/grafana, r/cloudflare

---

# License & Credits

This guide is based on the successful deployment of:
- **XRPL Validator Monitor:** https://monitor.yourdomain.com
- **Maintainer:** @realGrapedrop

Feel free to use this guide for your own projects.

---

**Last Updated:** November 13, 2025
**Tested With:**
- Grafana 12.1.1
- Cloudflared 2024.11.0
- Wrangler 4.37.1
