# Cloudflare Tunnel Setup Guide

*Expose your Grafana dashboard publicly using Cloudflare Tunnel.*

---

## Overview

Cloudflare Tunnel creates a secure connection from your server to Cloudflare's edge without opening firewall ports.

```
┌─────────────────────────────────────────────────────────┐
│                  Public Internet                        │
│            https://monitor.yourdomain.com               │
└────────────────────────┬────────────────────────────────┘
                         │
                         │ HTTPS:443
                         ↓
┌─────────────────────────────────────────────────────────┐
│              Cloudflare Edge                            │
│  • SSL termination                                      │
│  • DDoS protection                                      │
└────────────────────────┬────────────────────────────────┘
                         │
                         │ Cloudflare Tunnel (TLS encrypted)
                         ↓
┌─────────────────────────────────────────────────────────┐
│              Your Server (cloudflared)                  │
│  • Systemd service                                      │
│  • Outbound connections only                            │
└────────────────────────┬────────────────────────────────┘
                         │
                         │ HTTP:3000 (localhost)
                         ↓
┌─────────────────────────────────────────────────────────┐
│              Grafana                                    │
│  • Anonymous auth enabled (read-only)                   │
│  • Embedding allowed                                    │
└─────────────────────────────────────────────────────────┘
```

**Benefits:**
- No port forwarding or firewall changes
- TLS encryption end-to-end
- Free tier available
- DDoS protection included

---

## Prerequisites

1. **Cloudflare account** with a domain
2. **cloudflared** installed:
   ```bash
   # Download latest
   sudo curl -L --output /usr/local/bin/cloudflared \
     https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
   sudo chmod +x /usr/local/bin/cloudflared

   # Verify
   cloudflared --version
   ```
3. **Authenticate** (one-time):
   ```bash
   cloudflared tunnel login
   ```

---

## Grafana Configuration

Add these environment variables to enable public read-only access:

```yaml
# In your docker-compose.yml environment section
GF_AUTH_ANONYMOUS_ENABLED: "true"
GF_AUTH_ANONYMOUS_ORG_ROLE: "Viewer"
GF_SECURITY_ALLOW_EMBEDDING: "true"
```

Restart Grafana after adding these settings.

---

## Tunnel Setup

### Step 1: Create Tunnel

```bash
cloudflared tunnel create TUNNEL_NAME
```

Save the tunnel ID from the output (e.g., `a1aec802-96a1-4b36-b87f-0bfcf169c213`).

### Step 2: Create Config File

Create a dedicated config file (don't use default `config.yml` when running multiple tunnels):

```bash
vim ~/.cloudflared/config-TUNNEL_NAME.yml
```

Add:

```yaml
tunnel: TUNNEL_ID_FROM_STEP_1
credentials-file: /home/YOUR_USER/.cloudflared/TUNNEL_ID.json
connections: 4

ingress:
  - hostname: subdomain.yourdomain.com
    service: http://127.0.0.1:3000
  - service: http_status:404
```

**Example:**

```yaml
tunnel: a1aec802-96a1-4b36-b87f-0bfcf169c213
credentials-file: /home/grapedrop/.cloudflared/a1aec802-96a1-4b36-b87f-0bfcf169c213.json
connections: 4

ingress:
  - hostname: monitor.grapedrop.xyz
    service: http://127.0.0.1:3000
  - service: http_status:404
```

### Step 3: Create DNS Record

In Cloudflare Dashboard → DNS → Records:

| Field | Value |
|-------|-------|
| Type | CNAME |
| Name | `subdomain` (e.g., `monitor`) |
| Target | `TUNNEL_ID.cfargotunnel.com` |
| Proxy | Enabled (orange cloud) |

### Step 4: Test Tunnel

```bash
cloudflared tunnel --config ~/.cloudflared/config-TUNNEL_NAME.yml run TUNNEL_NAME
```

Visit `https://subdomain.yourdomain.com` to verify it works.

### Step 5: Create Systemd Service

```bash
sudo vim /etc/systemd/system/cloudflared-TUNNEL_NAME.service
```

Add:

```ini
[Unit]
Description=Cloudflare Tunnel - DESCRIPTION
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=YOUR_USER
ExecStart=/usr/local/bin/cloudflared tunnel --config /home/YOUR_USER/.cloudflared/config-TUNNEL_NAME.yml run TUNNEL_NAME
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

### Step 6: Enable and Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable cloudflared-TUNNEL_NAME
sudo systemctl start cloudflared-TUNNEL_NAME
```

Verify:

```bash
systemctl status cloudflared-TUNNEL_NAME
```

---

## Multiple Tunnels

Each tunnel gets its own:
- Config file: `~/.cloudflared/config-TUNNEL_NAME.yml`
- Systemd service: `/etc/systemd/system/cloudflared-TUNNEL_NAME.service`

Never rely on the default `config.yml` or run without `--config` flag when managing multiple tunnels.

---

## Useful Commands

```bash
# List tunnels
cloudflared tunnel list

# Tunnel info
cloudflared tunnel info TUNNEL_NAME

# Delete tunnel
cloudflared tunnel delete TUNNEL_NAME

# View service logs
journalctl -u cloudflared-TUNNEL_NAME -f

# Restart service
sudo systemctl restart cloudflared-TUNNEL_NAME
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Invalid tunnel ID" | Verify tunnel ID matches `cloudflared tunnel list` |
| "Credentials file not found" | Check path in config file |
| "Connection refused" | Verify Grafana is running on the specified port |
| DNS not resolving | Wait 5 min for propagation, verify CNAME in Cloudflare |

---

## Optional: Cloudflare Worker for Clean URLs

If you want a clean URL without `?kiosk` parameters visible, deploy a Cloudflare Worker that wraps the dashboard in an iframe. See the [Cloudflare Workers documentation](https://developers.cloudflare.com/workers/) for details.

Basic worker example:

```javascript
export default {
  async fetch(req) {
    const url = new URL(req.url);

    if (url.pathname === "/") {
      return new Response(`<!doctype html>
<html>
<head><title>Dashboard</title></head>
<body style="margin:0">
<iframe src="/d/DASHBOARD_UID/DASHBOARD_SLUG?kiosk&refresh=10s"
        style="width:100%;height:100vh;border:0"></iframe>
</body>
</html>`, { headers: { "content-type": "text/html" } });
    }

    return fetch(req);
  }
}
```

---

**Last Updated:** December 2025
