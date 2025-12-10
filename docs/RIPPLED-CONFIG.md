# **__RIPPLED CONFIGURATION GUIDE__**

*Configure rippled for optimal monitoring with XRPL Monitor.*

---

# Table of Contents

- [Quick Configuration Check](#quick-configuration-check)
- [Understanding Admin Access](#understanding-admin-access)
- [Example Configurations](#example-configurations)
- [How the Monitor Collects Metrics](#how-the-monitor-collects-metrics)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)

---

# Quick Configuration Check

Run this command to verify your rippled admin configuration:

```bash
grep -A 10 "port_rpc_admin_local\|port_ws_admin_local" /etc/rippled.cfg
```

You should see `admin = 127.0.0.1` (or your monitor's IP address) in both sections.

---

# Understanding Admin Access

### Admin Commands vs Public Commands

rippled has two types of API commands:

| Type | Examples | Access Level |
|------|----------|--------------|
| **Public** | `server_info`, `ledger`, `account_info` | Available to anyone |
| **Admin** | `peers`, `server_state`, `stop`, `logrotate` | Restricted by `admin` directive |

### Why Admin Access Matters for Monitoring

The monitor needs **admin access** to collect these metrics:

1. **Peer Metrics** (Total Peers, Inbound, Outbound, Latency)
   - Requires: `peers` command
   - Frequency: Every 60 seconds

2. **Server State** (Uptime, State Accounting, Database Sizes)
   - Requires: `server_state` command
   - Frequency: Every 5 minutes + once at startup

### WebSocket vs HTTP Admin Access

**Important distinction discovered during development:**

| Protocol | Port | Admin Command Support | Used By Monitor |
|----------|------|----------------------|-----------------|
| **HTTP** | 5005 | Reliable admin access | ✅ Used for `peers` command |
| **WebSocket** | 6006 | May reject admin commands | ✅ Used for streams only |

**Key Finding:** Even with correct `admin` directive configuration (e.g., `admin = 127.0.0.1, 172.17.0.0/16`), the WebSocket admin API may return "Forbidden" for the `peers` command while the HTTP admin API works reliably.

**Monitor Implementation:**
- **HTTP API (port 5005):** Used for `peers` command (60s polling)
- **WebSocket API (port 6006):** Used for real-time streams (`ledger`, `server`, `validations`) and `server_info` queries

This hybrid approach ensures reliable peer metrics collection while maintaining real-time event streaming capabilities.

---

# Example Configurations

### Scenario 1: Same-Host Deployment (Recommended)

**When to use:** Monitor runs on the same physical server as rippled (most common setup).

```ini
# /etc/rippled.cfg or /path/to/rippled.cfg

[port_rpc_admin_local]
port = 5005
ip = 0.0.0.0                    # Bind to all interfaces
admin = 127.0.0.1               # Allow admin from localhost
protocol = http

[port_ws_admin_local]
port = 6006
ip = 0.0.0.0                    # Bind to all interfaces
admin = 127.0.0.1               # Allow admin from localhost
protocol = ws
send_queue_limit = 100

[port_peer]
port = 51235
ip = 0.0.0.0
protocol = peer

[port_ws_public]
port = 5006
ip = 0.0.0.0
protocol = ws
```

**Monitor Configuration (.env):**
```bash
RIPPLED_WS_URL=ws://localhost:6006
RIPPLED_HTTP_URL=http://localhost:5005
```

**Firewall:** No changes needed. Localhost traffic bypasses firewall rules.

**Security:** Most secure. Admin commands only accessible locally.

---

### Scenario 2: Docker rippled with Monitor on Host

**When to use:** rippled runs in Docker, monitor runs natively on host.

```ini
# /path/to/rippled/config/rippled.cfg

[port_rpc_admin_local]
port = 5005
ip = 0.0.0.0                    # Must be 0.0.0.0 for Docker port forwarding
admin = 127.0.0.1, 172.17.0.1   # localhost + Docker bridge network
protocol = http

[port_ws_admin_local]
port = 6006
ip = 0.0.0.0                    # Must be 0.0.0.0 for Docker port forwarding
admin = 127.0.0.1, 172.17.0.1   # localhost + Docker bridge network
protocol = ws
send_queue_limit = 100
```

**Docker Compose (rippled service):**
```yaml
services:
  rippled:
    image: xrpllabsofficial/xrpld:latest
    ports:
      - "5005:5005"     # HTTP admin
      - "6006:6006"     # WebSocket admin
      - "51235:51235"   # Peer protocol
    volumes:
      - ./rippled.cfg:/etc/rippled/rippled.cfg:ro
      - rippled_data:/var/lib/rippled
```

**Monitor Configuration (.env):**
```bash
RIPPLED_WS_URL=ws://localhost:6006
RIPPLED_HTTP_URL=http://localhost:5005
RIPPLED_DOCKER_CONTAINER=rippledvalidator  # For docker exec fallback
RIPPLED_DATA_PATH=/path/to/rippled/data    # For NuDB metrics
```

**Firewall:** No changes needed (localhost connections).

**Security:** Admin ports bound to all interfaces (`0.0.0.0`) for Docker forwarding, but admin access restricted to localhost and Docker bridge by `admin` directive.

---

### Scenario 3: All-in-One Docker Stack (Rippled-In-A-Box)

**When to use:** Everything runs in Docker containers on a bridge network.

```ini
# /path/to/rippled/config/rippled.cfg

[port_rpc_admin_local]
port = 5005
ip = 0.0.0.0
admin = 127.0.0.1, 172.17.0.0/16  # localhost + entire Docker network
protocol = http

[port_ws_admin_local]
port = 6006
ip = 0.0.0.0
admin = 127.0.0.1, 172.17.0.0/16  # localhost + entire Docker network
protocol = ws
send_queue_limit = 100
```

**Docker Compose:**
```yaml
networks:
  xrpl-monitor-network:
    driver: bridge

services:
  rippled:
    image: xrpllabsofficial/xrpld:latest
    container_name: rippledvalidator
    volumes:
      - rippled_data:/var/lib/rippled
      - ./rippled.cfg:/etc/rippled/rippled.cfg:ro
    networks:
      - xrpl-monitor-network

  collector:
    build: .
    environment:
      - RIPPLED_WS_URL=ws://rippledvalidator:6006      # Use container name
      - RIPPLED_HTTP_URL=http://rippledvalidator:5005
      - RIPPLED_DOCKER_CONTAINER=rippledvalidator
      - RIPPLED_DATA_PATH=/rippled-data
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - rippled_data:/rippled-data:ro
    networks:
      - xrpl-monitor-network

volumes:
  rippled_data:
```

**Firewall:** No external access needed. All communication happens within Docker network.

**Security:** Admin commands accessible within Docker network, but isolated from internet.

---

### Scenario 4: Remote Monitoring (Advanced)

**When to use:** Monitor runs on different server from rippled (requires careful security).

```ini
# /etc/rippled.cfg

[port_rpc_admin_local]
port = 5005
ip = 0.0.0.0
admin = 127.0.0.1, 10.0.1.100     # localhost + monitor server IP
protocol = http

[port_ws_admin_local]
port = 6006
ip = 0.0.0.0
admin = 127.0.0.1, 10.0.1.100     # localhost + monitor server IP
protocol = ws
send_queue_limit = 100
```

**Firewall Rules (validator server):**
```bash
# Allow monitor server to access admin ports
sudo ufw allow from 10.0.1.100 to any port 5005 proto tcp
sudo ufw allow from 10.0.1.100 to any port 6006 proto tcp

# Block admin ports from internet
sudo ufw deny 5005/tcp
sudo ufw deny 6006/tcp
```

**Monitor Configuration (.env):**
```bash
RIPPLED_WS_URL=ws://10.0.1.50:6006
RIPPLED_HTTP_URL=http://10.0.1.50:5005
```

**Security:**
- ⚠️ Admin ports exposed on network
- ✅ Restricted by IP address in rippled config
- ✅ Firewall enforces IP restriction
- ✅ Use VPN/private network, never public internet

---

# How the Monitor Collects Metrics

### Metric Collection Methods

The monitor uses multiple methods to collect comprehensive metrics:

```
┌─────────────────────────────────────────────────────────────┐
│                    XRPL Monitor Collection                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. WebSocket Streams (Primary - Real-time)                 │
│     ├─ ledger stream → Ledger metrics (instant)             │
│     ├─ server stream → Server state changes                 │
│     ├─ peer_status stream → Peer connection events          │
│     ├─ consensus stream → Consensus metrics                 │
│     └─ validations stream → Validation events               │
│                                                              │
│  2. HTTP Admin Commands (Polling)                           │
│     ├─ peers command → Peer list & latency (60s)            │
│     └─ server_state command → State details (5min)          │
│                                                              │
│  3. WebSocket Public Commands (Polling)                     │
│     └─ server_info → General metrics (5s)                   │
│                                                              │
│  4. Docker Exec Fallback (Only if HTTP/WS fail)             │
│     └─ docker exec rippled peers → Peer metrics             │
│                                                              │
│  5. Filesystem Access (Direct read)                         │
│     └─ /var/lib/rippled/db/nudb → Database sizes            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Peer Metrics Collection (Detailed Flow)

The monitor uses an intelligent fallback mechanism for peer metrics:

```python
# src/monitor/http_poller.py:_peers_poller()

async def _peers_poller(self):
    """
    Collects peer metrics every 60 seconds

    Metrics: Total peers, inbound, outbound, latency p90, peer disconnects
    """
    while True:
        # Try WebSocket API first (PREFERRED METHOD)
        peers = await self.xrpl_client.get_peers()

        # If WebSocket fails and Docker is configured, use fallback
        if not peers and self.docker_container:
            peers = self._get_peers_docker()

        if peers:
            # Process and send metrics to VictoriaMetrics
            await self._process_peer_metrics(peers)
        else:
            # Log warning, continue monitoring
            logger.warning("Peer metrics unavailable")

        await asyncio.sleep(60)
```

**What the Monitor Does:**

1. **Every 60 seconds**, the monitor sends a `peers` command via **HTTP admin API**
2. **If successful** (admin access granted):
   - Parses peer list
   - Calculates: total peers, inbound count, outbound count
   - Computes P90 latency across all peers
   - Sends metrics to VictoriaMetrics

3. **If HTTP returns "Forbidden"** (admin denied):
   - Falls back to `docker exec <container> rippled peers`
   - Requires Docker socket access (`DOCKER_GID` in .env)
   - Logs: "API peers failed, trying docker exec fallback..."

4. **If both methods fail**:
   - Logs warning
   - Other metrics continue to be collected
   - Peer panels in Grafana show "No data"

**Note:** The monitor uses HTTP instead of WebSocket for the `peers` command due to more reliable admin authentication behavior on the HTTP admin API.

### Database Size Collection (NuDB Metrics)

```bash
# Monitor reads NuDB directory size directly from filesystem
# Requires read access to rippled data directory

/var/lib/rippled/db/nudb/
├── nudb.dat
├── nudb.key
└── ... (other NuDB files)

# Monitor calculates total directory size
# Sent to VictoriaMetrics as: xrpl_db_ledger_nudb_mb
```

**Requirements:**
- Read-only access to rippled data directory
- Set `RIPPLED_DATA_PATH=/var/lib/rippled` in .env
- For Docker rippled, mount the volume: `rippled_data:/rippled-data:ro`

---

# Security Considerations

### Admin Port Exposure

**Default Validator Security Posture:**

```bash
# Typical firewall on validator (GOOD)
sudo ufw status

Status: active

To                         Action      From
--                         ------      ----
51235/tcp                  ALLOW       Anywhere       # Peer protocol
2459/tcp                   ALLOW       Anywhere       # Validation messages
22/tcp                     LIMIT       Anywhere       # SSH
5005/tcp                   DENY        Anywhere       # Admin HTTP (blocked)
6006/tcp                   DENY        Anywhere       # Admin WS (blocked)
```

**Why This is Secure:**

1. **Admin ports (5005, 6006) are blocked from internet** by firewall
2. **Localhost traffic bypasses firewall rules** - monitor can still access
3. **rippled's `admin` directive** provides additional layer of IP restriction
4. **Only SSH and validator ports exposed** to internet

### Admin Access Risk Levels

| Configuration | Risk Level | When to Use |
|--------------|------------|-------------|
| `admin = 127.0.0.1` | 🟢 **Low** | Same-host deployment (recommended) |
| `admin = 127.0.0.1, 172.17.0.1` | 🟢 **Low** | Docker rippled + host monitor |
| `admin = 127.0.0.1, 172.17.0.0/16` | 🟡 **Medium** | All-in-one Docker stack |
| `admin = 127.0.0.1, 10.0.1.100` | 🟠 **Medium-High** | Remote monitor on private network |
| `admin = 127.0.0.1, 0.0.0.0` | 🔴 **CRITICAL** | **NEVER USE** - Allows admin from anywhere |

### Best Practices

1. **Prefer same-host deployment** - Monitor and rippled on same server
2. **Never expose admin ports to internet** - Use firewall to block 5005, 6006
3. **Use Docker socket fallback sparingly** - Only when WebSocket admin fails
4. **Read-only access for NuDB** - Monitor never writes to rippled data
5. **Audit admin access regularly** - Review `admin` directive in rippled.cfg

---

# Troubleshooting

### Problem: Peer metrics showing "No data"

**Symptoms:**
- Dashboard panels for "Total Peers", "Inbound Peers", "Outbound Peers" show no data
- Grafana shows "No data" message

**Diagnosis:**

1. Check if monitor is running:
   ```bash
   docker compose ps collector
   # or for native Python:
   ps aux | grep "python.*monitor"
   ```

2. Check monitor logs for peer collection:
   ```bash
   docker compose logs collector | grep -i peer
   # Look for messages like:
   # "peers request failed: Forbidden"
   # "API peers failed, trying docker exec fallback..."
   # "✓ Peer metrics collected via docker exec fallback"
   ```

3. Test HTTP admin access manually:
   ```bash
   # Using curl (HTTP is more reliable for peers command)
   curl -X POST http://localhost:5005 \
     -H "Content-Type: application/json" \
     -d '{"method":"peers","params":[{}]}'
   # Should return peer list with "status":"success"
   ```

**Solutions:**

| Error Message | Cause | Fix |
|--------------|-------|-----|
| "peers request failed: Forbidden" (HTTP) | HTTP admin denied | Add `admin = 127.0.0.1` to `[port_rpc_admin_local]` in rippled.cfg |
| "peers request failed: Forbidden" (WebSocket) | WebSocket admin auth issue | Monitor automatically uses HTTP instead (no action needed) |
| "API peers failed, trying docker exec..." | Both HTTP and WebSocket failed | Check admin config on both ports in rippled.cfg |
| "docker exec failed: permission denied" | Monitor not in docker group | Set `DOCKER_GID` in .env: `getent group docker \| cut -d: -f3` |
| "RIPPLED_DOCKER_CONTAINER not set" | Fallback unavailable | Set `RIPPLED_DOCKER_CONTAINER=rippledvalidator` in .env |

---

### Problem: "Forbidden" response on WebSocket but HTTP works

**This is NORMAL behavior.** In some configurations, rippled's WebSocket admin API may reject certain admin commands (like `peers`) even with correct `admin` directive configuration, while the HTTP admin API works reliably.

**Example:**
```bash
# WebSocket may return Forbidden
wscat -c ws://localhost:6006
> {"command":"peers"}
> {"error": "forbidden", ...}  # WebSocket rejects

# HTTP works fine (MONITOR USES THIS)
curl -X POST http://localhost:5005 \
  -H "Content-Type: application/json" \
  -d '{"method":"peers","params":[{}]}'
> {"result": {"status":"success", "peers": [...]}}  # SUCCESS
```

**Why this happens:**
- rippled's WebSocket and HTTP admin APIs have different authentication behavior
- Monitor automatically uses HTTP for `peers` command to ensure reliability
- WebSocket is still used for real-time streams and other queries
- No action needed - this is expected behavior

---

### Problem: NuDB size metrics not updating

**Symptoms:**
- "Ledger DB" and "Ledger NuDB" panels show stale data or "No data"

**Diagnosis:**

1. Check rippled data path configuration:
   ```bash
   echo $RIPPLED_DATA_PATH
   # Should show: /var/lib/rippled or /path/to/rippled/data
   ```

2. Verify NuDB directory exists:
   ```bash
   ls -la $RIPPLED_DATA_PATH/db/nudb/
   # Should show NuDB files
   ```

3. Check monitor has read access:
   ```bash
   # For native Python monitor:
   sudo -u $(whoami) ls $RIPPLED_DATA_PATH/db/nudb/

   # For Docker monitor:
   docker compose exec collector ls /rippled-data/db/nudb/
   ```

**Solutions:**

| Issue | Fix |
|-------|-----|
| Path not set | Set `RIPPLED_DATA_PATH=/var/lib/rippled` in .env |
| Permission denied | For Docker: Ensure volume mounted as `:ro` |
| Directory not found | Verify rippled is actually storing data at that path |
| Wrong path | For Docker rippled, use host mount path, not container path |

---

### Problem: Monitor cannot connect to rippled

**Symptoms:**
- Monitor logs show "Connection refused" or "Connection timeout"
- No metrics being collected

**Diagnosis:**

```bash
# Test WebSocket connectivity
curl -i -N -H "Connection: Upgrade" \
     -H "Upgrade: websocket" \
     -H "Host: localhost:6006" \
     http://localhost:6006/

# Test HTTP connectivity
curl -X POST http://localhost:5005 -d '{"method":"server_info","params":[{}]}'
```

**Solutions:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| Connection refused | rippled not running | Start rippled: `systemctl start rippled` |
| Connection refused (Docker) | Wrong container name | Verify container name: `docker ps` |
| Connection timeout | Firewall blocking | Check: `sudo iptables -L \| grep 6006` |
| Wrong URL | Monitor .env misconfigured | Fix `RIPPLED_WS_URL` and `RIPPLED_HTTP_URL` |

---

### Verify Your Configuration

Run these commands to verify your setup:

```bash
# 1. Check rippled admin configuration
grep -A 5 "port_ws_admin_local" /etc/rippled.cfg
# Should show: admin = 127.0.0.1 (or your monitor IP)

# 2. Test WebSocket admin access
wscat -c ws://localhost:6006
> {"command":"peers"}
# Should return peer list

# 3. Check monitor is collecting peer metrics
docker compose logs collector | grep -i peer | tail -20
# Should show successful peer collections

# 4. Query VictoriaMetrics for peer metrics
curl -s 'http://localhost:8428/api/v1/query?query=xrpl_peers_total' | jq
# Should return recent peer counts

# 5. Verify NuDB access
ls -la $RIPPLED_DATA_PATH/db/nudb/
# Should list NuDB files
```

---

# Summary: What You Need

### Minimum Configuration (Same-Host)

**rippled.cfg:**
```ini
[port_ws_admin_local]
port = 6006
ip = 0.0.0.0
admin = 127.0.0.1
protocol = ws
```

**Monitor .env:**
```bash
RIPPLED_WS_URL=ws://localhost:6006
RIPPLED_DATA_PATH=/var/lib/rippled
VALIDATOR_PUBLIC_KEY=nHB6bPcp9jk8QbUZiGXoonERK9rcDvjZUJAoFsGVCs2ZgUdCtnSV
```

**Result:** All metrics collected via WebSocket, no Docker fallback needed.

---

### With Docker Fallback (Optional)

**Additional .env variables:**
```bash
RIPPLED_DOCKER_CONTAINER=rippledvalidator
DOCKER_GID=999  # Find with: getent group docker | cut -d: -f3
```

**Result:** If WebSocket admin fails, monitor falls back to `docker exec`.

---

# Quick Reference: Port Summary

| Port | Protocol | Purpose | Admin Required | Monitor Uses |
|------|----------|---------|----------------|--------------|
| **5005** | HTTP | RPC commands | Some commands | ✅ Yes (`peers` command) |
| **6006** | WebSocket | RPC commands & streams | Some commands | ✅ Yes (streams & queries) |
| **5006** | WebSocket | Public RPC | No | ❌ No |
| **51235** | Peer | Validator P2P | N/A | ❌ No |

---

# Additional Resources

- [rippled Configuration Reference](https://xrpl.org/configure-rippled.html)
- [rippled Admin API Methods](https://xrpl.org/admin-rippled-methods.html)
- [XRPL Monitor Network Access Guide](DOCKER_ADVANCED.md#network-access--firewall-requirements)

---

**Questions or issues?** Check the [FAQ](FAQ.md) or open an issue on GitHub.
