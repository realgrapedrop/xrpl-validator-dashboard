# **__ARCHITECTURE OVERVIEW__**

*Event-driven real-time monitoring system architecture for XRPL Validator Dashboard.*

---

# System Design Philosophy

v3.0 is built on three core principles:

1. **Event-Driven** - React to real-time events, don't poll unnecessarily
2. **Type-Safe** - Use Python type hints and validated models throughout
3. **Simple** - Single database, official libraries, clean separation of concerns

---

# Table of Contents

- [System Design Philosophy](#system-design-philosophy)
- [High-Level Architecture](#high-level-architecture)
- [Data Flow - Detailed](#data-flow---detailed)
- [Component Details](#component-details)
- [Technology Choices](#technology-choices)
- [Deployment Architecture](#deployment-architecture)
- [Error Handling Strategy](#error-handling-strategy)
- [Performance Characteristics](#performance-characteristics)
- [Security Considerations](#security-considerations)
- [Scalability](#scalability)

---

# High-Level Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    XRPL Validator Node (rippled)                                       │
│                                                                                                        │
│       ┌─────────────────────────────┐                     ┌───────────────────────────────┐            │
│       │    WebSocket API :6006      │                     │    HTTP JSON-RPC :5005        │            │
│       │                             │                     │                               │            │
│       │    Streams:                 │                     │    Methods:                   │            │
│       │    • ledger                 │                     │    • server_info              │            │
│       │    • server                 │                     │    • peers                    │            │
│       │    • validations            │                     │    • server_state             │            │
│       └─────────────────────────────┘                     └───────────────────────────────┘            │
└────────────────────────────────────────────────────────────────────────────────────────────────────────┘
              ▲                ▲                                    ▲                     ▲
              │                │                                    │                     │
              │ WS :6006       │ WS :6006                           │ HTTP :5005          │ HTTP :5005
              │ (uptime)       │ (streams)                          │ (polling)           │ (state/peers)
              │                │                                    │                     │
┌─────────────┼────────────────┼────────────────────────────────────┼─────────────────────┼────────────────┐
│             │                │                                    │                     │                │
│             │                │         DOCKER CONTAINERS          │                     │                │
│             │                │                                    │                     │                │
│  ╔══════════╧═════════╗  ╔═══╧═══════════════════════════╗  ┌─────┴─────────────┐  ╔════╧═════════════╗  │
│  ║  Uptime Exporter * ║  ║         Collector *           ║  │   Node Exporter   │  ║ State Exporter * ║  │
│  ║    (Python app)    ║  ║        (Python app)           ║  │      (Go app)     │  ║   (Python app)   ║  │
│  ║       :9101        ║  ║          :8090                ║  │      :9100        │  ║     :9102        ║  │
│  ║                    ║  ║  • WebSocket streams          ║  │                   │  ║                  ║  │
│  ║  • Uptime          ║  ║  • HTTP polling (5s/60s/5m)   ║  │  • CPU, RAM       │  ║  • State (1s)    ║  │
│  ║    formatted       ║  ║  • Event handlers             ║  │  • Disk, Net      │  ║  • Peers (5s)    ║  │
│  ║                    ║  ║  • Validation tracking        ║  │  • System load    │  ║                  ║  │
│  ╚════════════════════╝  ╚═══════════════════════════════╝  └───────────────────┘  ╚══════════════════╝  │
│            ▲                          ▲                              ▲                    ▲              │
│            │                          │                              │                    │              │
│            │                          │                              │                    │              │
│            │ GET /metrics             │ POST :8428                   │ GET /metrics       │ GET /metrics │
│            │ (vmagent scrapes)        │ /api/v1/import/              │ (vmagent scrapes)  │ (vmagent)    │
│            │                          │ prometheus                   │                    │              │
│            │                          │                              │                    │              │
│  ┌─────────┴──────────────────────────┴──────────────────────────────┴────────────────────┴───────────┐  │
│  │                                      vmagent :8427                                                 │  │
│  │                                                                                                    │  │
│  │       Scrapes /metrics from exporters (initiates GET requests):                                    │  │
│  │       • Node Exporter :9100 (every 15s)                                                            │  │
│  │       • Uptime Exporter * :9101 (every 10s)                                                        │  │
│  │       • State Exporter * :9102 (every 5s)                                                          │  │
│  └────────────────────────────────────────┬───────────────────────────────────────────────────────────┘  │
│                                           │                                                              │
│                                           │ POST /api/v1/write                                           │
│                                           │ (remote write)                                               │
│                                           ▼                                                              │
│  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                   VictoriaMetrics :8428                                            │  │
│  │                                                                                                    │  │
│  │       Time-series database                                        (Collector * pushes here)        │  │
│  │       • Stores all historical metrics                                                              │  │
│  │       • PromQL query interface                                                                     │  │
│  │       • 365-day retention                                                                          │  │
│  │       • 7x better compression than Prometheus                                                      │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                              ▲                                                           │
│                                              │ PromQL queries                                            │
│                                              │ (Grafana initiates)                                       │
│                                              │                                                           │
│       ┌──────────────────────────────────────┴────────────────────────────────────────────────────┐      │
│       │                                                                                           │      │
│       │       ┌────────────────────────────────────────────────────────────────────────────┐      │      │
│       │       │                            Grafana :3000                                   │      │      │
│       │       │                                                                            │      │      │
│       │       │       Dashboard & Alerting                                                 │      │      │
│       │       │       • Queries VictoriaMetrics for historical data                        │      │      │
│       │       │       • Queries StateExporter for near-real-time state (1s) & peers        │      │      │
│       │       │       • Auto-provisioned dashboards                                        │      │      │
│       │       │       • Email/webhook alerts                                               │      │      │
│       │       └────────────────────────────────┬───────────────────────────────────────────┘      │      │
│       │                                        │                                                  │      │
│       │                                        │ GET /api/v1/query                                │      │
│       │                                        │ (Grafana initiates)                              │      │
│       │                                        ▼                                                  │      │
│       │                             ╔════════════════════════╗                                    │      │
│       │                             ║    State Exporter *    ║                                    │      │
│       │                             ║       (Python app)     ║                                    │      │
│       │                             ║         :9102          ║                                    │      │
│       │                             ║  (same component as    ║                                    │      │
│       │                             ║  above - direct query) ║                                    │      │
│       │                             ╚════════════════════════╝                                    │      │
│       │                                                                                           │      │
│       └───────────────────────────────────────────────────────────────────────────────────────────┘      │
│                                                 ▲                                                        │
│                                                 │ HTTP :3000 (Web UI)                                    │
│                                                 │ (User initiates)                                       │
└─────────────────────────────────────────────────┼────────────────────────────────────────────────────────┘
                                                  │
                                            [User Browser]

Legend:  ┌───┐ Open Source    ╔═══╗ Custom Code *
         └───┘                ╚═══╝

Note: State Exporter has TWO data paths:
  1. vmagent scrapes /metrics → VictoriaMetrics (historical data, alerts)
  2. Grafana queries /api/v1/query directly (real-time state, 1-2s latency)

Arrow Direction: Shows who initiates the request (initiator ──► target)
```

**Data Flow Summary (Initiator → Target):**

| Initiator | Target | Protocol | Purpose |
|-----------|--------|----------|---------|
| Collector | rippled | WS :6006 | Subscribe to ledger/server/validation streams |
| Collector | rippled | HTTP :5005 | Poll server_info (5s), peers (60s), server_state (5m) |
| State Exporter | rippled | HTTP :5005 | Poll state (1s) and peers (5s) |
| Uptime Exporter | rippled | WS :6006 | Fetch uptime data |
| Collector | VictoriaMetrics | HTTP POST /api/v1/import/prometheus | Push real-time events |
| vmagent | Node/Uptime/State Exporters | HTTP GET /metrics | Scrape metrics (15s/10s/5s) |
| vmagent | VictoriaMetrics | HTTP POST /api/v1/write | Remote write scraped data |
| Grafana | VictoriaMetrics | PromQL POST | Query historical data |
| Grafana | State Exporter | HTTP GET /api/v1/query | Query near-real-time state & peers |
| User Browser | Grafana | HTTP :3000 | Access web dashboard UI |

**Port Summary:**

| Service | Port | Purpose |
|---------|------|---------|
| Grafana | 3000 | Web dashboard UI |
| VictoriaMetrics | 8428 | Time-series database |
| vmagent | 8427 | Metrics scraper |
| Node Exporter | 9100 | System metrics (CPU, RAM, disk) |
| Uptime Exporter | 9101 | Formatted uptime display |
| State Exporter | 9102 | Real-time state & peer metrics |
| Collector | 8090 | Health check endpoint |

---

# Data Flow - Detailed

### 1. WebSocket Flow (Real-Time Events)

```
rippled WebSocket API
         │
         │ 1. Collector opens WebSocket connection
         │    (XRPLWebSocketClient.connect())
         ▼
rippled accepts connection
         │
         │ 2. Collector sends Subscribe request
         │    (streams: ledger, server, validations)
         ▼
rippled acknowledges subscription
         │
         │ 3. rippled pushes events as they occur
         │    • ledgerClosed (every 3-5 seconds)
         │    • serverStatus (on state changes)
         │    • validationReceived (real-time)
         ▼
XRPLWebSocketClient receives event
         │
         │ 4. Routes to appropriate handler
         ▼
Event Handler processes event
         │
         │ 5. Extracts metrics from event data
         ▼
VictoriaMetrics Client formats + batches
         │
         │ 6. HTTP POST to VictoriaMetrics
         ▼
VictoriaMetrics stores time-series data
```

**Latency:** 0-100ms from rippled event to VictoriaMetrics storage

---

### 2. HTTP Polling Flow (Supplementary Metrics)

```
Timer triggers (5s, 60s, or 5min)
         │
         │ 1. HTTPPoller initiates HTTP request
         ▼
HTTP POST to rippled JSON-RPC API
         │
         │ 2. rippled processes request
         │    (server_info, peers, or server_state)
         ▼
rippled returns JSON response
         │
         │ 3. HTTPPoller receives response
         ▼
HTTPPoller extracts metrics
         │
         │ 4. Converts to Prometheus format
         ▼
VictoriaMetrics Client formats + batches
         │
         │ 5. HTTP POST to VictoriaMetrics
         ▼
VictoriaMetrics stores time-series data
```

**Latency:** 10-50ms per HTTP request + polling interval

---

# Component Details

### 1. main.py (Orchestrator)

**Role:** Main coordinator and entry point

**Responsibilities:**
- Load configuration from environment variables
- Initialize VictoriaMetrics client
- Initialize XRPL WebSocket client
- Initialize XRPL HTTP client (wrapped in HTTPPoller)
- Create event handlers (Ledger, Server, Validations)
- Subscribe to WebSocket streams
- Start HTTP polling tasks
- Route incoming WebSocket messages to handlers
- Coordinate graceful shutdown
- Handle top-level errors

**Key Features:**
- Fully async using asyncio
- Runs multiple tasks concurrently (WebSocket listener + 3 HTTP pollers)
- Automatic reconnection on WebSocket failures
- Signal handling (SIGTERM, SIGINT)
- Background uptime metric updater

**Flow:**
```python
async def main():
    # 1. Initialize clients
    victoria_client = VictoriaMetricsClient(vm_url)
    xrpl_client = XRPLWebSocketClient(ws_url, http_url)

    # 2. Connect to rippled
    await xrpl_client.connect()

    # 3. Initialize handlers
    ledger_handler = LedgerHandler(victoria_client)
    server_handler = ServerHandler(victoria_client)
    validations_handler = ValidationsHandler(victoria_client)

    # 4. Subscribe to WebSocket streams
    await xrpl_client.subscribe(streams=["ledger", "server", "validations"])

    # 5. Set up message routing
    handlers = {
        'ledgerClosed': ledger_handler.handle,
        'serverStatus': server_handler.handle,
        'validationReceived': validations_handler.handle
    }

    # 6. Start HTTP poller (background tasks)
    http_poller = HTTPPoller(xrpl_client, victoria_client)
    await http_poller.start()

    # 7. Listen for WebSocket events (blocks until shutdown)
    await xrpl_client.listen(handlers)
```

---

### 2. XRPLWebSocketClient (src/clients/xrpl_client.py)

**Role:** WebSocket connection manager

**Responsibilities:**
- Maintain persistent WebSocket connection to rippled
- Send Subscribe requests
- Receive and route incoming events
- Handle reconnection on disconnect
- Provide connection health monitoring

**Uses xrpl-py:**
- `AsyncWebsocketClient` - Official XRPL Python WebSocket client
- Type-safe request/response models

**Key Methods:**
```python
async def connect() -> bool:
    """Open WebSocket connection to rippled"""

async def subscribe(streams: List[str]):
    """Subscribe to WebSocket streams"""

async def listen(handlers: Dict[str, Callable]):
    """Listen for events and route to handlers"""
    # async for message in self.client:
    #     msg_type = message.get("type")
    #     if msg_type in handlers:
    #         await handlers[msg_type](message)

async def disconnect():
    """Close WebSocket connection"""
```

---

### 3. HTTPPoller (src/monitor/http_poller.py)

**Role:** Periodic metric collection via HTTP JSON-RPC

**Responsibilities:**
- Poll rippled HTTP API at scheduled intervals
- Collect metrics not available in WebSocket streams
- Write metrics to VictoriaMetrics
- Handle polling errors gracefully

**Polling Schedule:**

| Method | Interval | Metrics Collected |
|--------|----------|-------------------|
| `server_info` | 5 seconds | io_latency, load_factor, validation_quorum, proposers, uptime, peer_disconnects |
| `peers` | 60 seconds | peer_inbound, peer_outbound, peer_insane, peer_latency_p90 |
| `server_state` | 5 minutes | state_accounting, database_sizes |
| `server_state` | Startup | server_info (build_version, node_size, pubkey_validator) |

**Uses xrpl-py:**
- `AsyncJsonRpcClient` - Official XRPL Python HTTP client
- `ServerInfo`, `Peers`, `ServerState` - Type-safe request models

**Key Methods:**
```python
async def start(shutdown_event):
    """Start all polling tasks"""
    await asyncio.gather(
        self._poll_server_info(shutdown_event),  # Every 5s
        self._poll_peers(shutdown_event),         # Every 60s
        self._poll_server_state(shutdown_event)   # Every 5min
    )

async def _poll_server_info(shutdown_event):
    """Poll server_info every 5 seconds"""
    while not shutdown_event.is_set():
        response = await self.http_client.request(ServerInfo())
        metrics = extract_metrics(response)
        await self.victoria_client.write(metrics)
        await asyncio.sleep(5)
```

---

### 3.1. Connection Resilience - WebSocket Auto-Reconnect

**Challenge:** WebSocket connections can drop due to network issues, rippled restarts, or infrastructure hiccups.

**Solution:** Exponential backoff reconnection with automatic stream re-subscription

**Sequence Diagram:**

```
Collector                  WebSocket Client              rippled
   │                              │                           │
   │─────subscribe───────────────>│                           │
   │                              │──────connect─────────────>│
   │                              │<──────connected───────────│
   │                              │──────subscribe───────────>│
   │                              │      (ledger, server,     │
   │                              │       validations)        │
   │                              │<──────subscribed──────────│
   │                              │                           │
   │                              │<──────events──────────────│
   │<────handle_events────────────│                           │
   │                              │                           │
   │                              │         ❌ Connection     │
   │                              │            Lost           │
   │                              │                           │
   │                              │                           │
   │                       [Detect Disconnect]                │
   │                              │                           │
   │                       [Wait 1 second]                    │
   │                              │                           │
   │                              │──────reconnect (1)───────>│
   │                              │         ❌ Failed         │
   │                              │                           │
   │                       [Wait 2 seconds]                   │
   │                              │                           │
   │                              │──────reconnect (2)───────>│
   │                              │         ❌ Failed         │
   │                              │                           │
   │                       [Wait 4 seconds]                   │
   │                              │                           │
   │                              │──────reconnect (3)───────>│
   │                              │<──────connected───────────│
   │                              │                           │
   │                       [Re-subscribe to streams]          │
   │                              │──────subscribe───────────>│
   │                              │<──────subscribed──────────│
   │                              │                           │
   │                              │<──────events──────────────│
   │<────handle_events────────────│    (resumed normal ops)   │
```

**How It Works:**

1. **Connection Monitoring** - The WebSocket client continuously monitors connection health
2. **Detection** - When disconnection is detected (connection closed, timeout, error):
   - Log the disconnection event
   - Set reconnection backoff timer
3. **Exponential Backoff** - Retry connection with increasing delays:
   - Attempt 1: Wait 1 second
   - Attempt 2: Wait 2 seconds
   - Attempt 3: Wait 4 seconds
   - Attempt 4: Wait 8 seconds
   - Max wait: 60 seconds between attempts
4. **Reconnection** - On successful reconnection:
   - Re-subscribe to all streams (ledger, server, validations)
   - Resume event processing
   - Reset backoff timer
5. **Health Metrics** - Expose `xrpl_websocket_connected` metric (1 = healthy, 0 = disconnected)

**Benefits:**
- **Zero data loss** - Automatically recovers from transient failures
- **Self-healing** - No manual intervention required
- **Graceful degradation** - Backoff prevents overwhelming the server during issues

**Key Implementation:**
```python
async def connect_with_retry(max_retries=None):
    """Connect to WebSocket with exponential backoff"""
    attempt = 0
    backoff = 1  # Start with 1 second

    while True:
        try:
            await self.client.connect()
            logger.info("WebSocket connected successfully")
            return True
        except Exception as e:
            attempt += 1
            if max_retries and attempt >= max_retries:
                raise

            wait_time = min(backoff, 60)  # Cap at 60 seconds
            logger.warning(f"Connection failed, retrying in {wait_time}s...")
            await asyncio.sleep(wait_time)
            backoff *= 2  # Exponential increase
```

---

### 3.2. Connection Resilience - HTTP RPC Retry Logic

**Challenge:** HTTP RPC calls can fail due to network glitches, temporary rippled unavailability, or rate limiting.

**Solution:** Automatic retry with exponential backoff for failed requests

**Sequence Diagram:**

```
HTTP Poller              HTTP RPC Client                rippled
   │                            │                          │
   │────poll_server_info───────>│                          │
   │     (every 10s)            │                          │
   │                            │─────POST /rpc───────────>│
   │                            │    (server_info)         │
   │                            │<─────response────────────│
   │<───metrics─────────────────│     ✅ Success           │
   │                            │                          │
   │──write_to_victoriametrics──>                          │
   │                            │                          │
   │                                                       │
   │─── Next Poll (10s later) ────────────────────────────>│
   │                            │                          │
   │                            │─────POST /rpc───────────>│
   │                            │        ❌ Timeout/Error  │
   │                            │                          │
   │                     [Retry Logic Triggered]           │
   │                            │                          │
   │                     [Wait 1 second]                   │
   │                            │                          │
   │                            │────POST /rpc (retry 1)──>│
   │                            │         ❌ Failed        │
   │                            │                          │
   │                     [Wait 2 seconds]                  │
   │                            │                          │
   │                            │────POST /rpc (retry 2)──>│
   │                            │         ❌ Failed        │
   │                            │                          │
   │                     [Wait 4 seconds]                  │
   │                            │                          │
   │                            │────POST /rpc (retry 3)──>│
   │                            │<─────response────────────│
   │<───metrics─────────────────│     ✅ Success           │
   │                            │                          │
   │──write_to_victoriametrics──>    (no data gap)         │
   │                            │                          │
   │                            │                          │
   │─── Next Poll (continues normally) ───────────────────>│
```

**How It Works:**

1. **Request Attempt** - Execute HTTP RPC call (server_info, peers, validators, etc.)
2. **Failure Detection** - Catch request failures:
   - Network timeout
   - Connection refused
   - HTTP 5xx errors
   - Request exceptions
3. **Retry Logic** - Automatically retry with exponential backoff:
   - Retry 1: Wait 1 second
   - Retry 2: Wait 2 seconds
   - Retry 3: Wait 4 seconds
   - Max retries: 3 attempts per request
4. **Success/Failure** - On success, return response; on final failure, log error and continue
5. **Health Metrics** - Expose `xrpl_http_rpc_connected` metric (1 = healthy, 0 = failing)

**Benefits:**
- **Resilient polling** - Survives transient network issues
- **No monitoring gaps** - Automatically recovers without data loss
- **Rate limit friendly** - Backoff prevents hammering during issues
- **Production-ready** - Handles real-world network instability

**Request Types Protected:**
- `server_info` - Server health metrics (every 10s)
- `validators` - Validator list and agreements (every 60s)
- `peers` - Peer connection stats (every 60s)
- Validator domain/toml lookups (per validation event)

**Key Implementation:**
```python
async def request_with_retry(method, max_retries=3):
    """Execute HTTP RPC request with exponential backoff retry"""
    attempt = 0
    backoff = 1

    while attempt < max_retries:
        try:
            response = await self.client.request(method)
            return response  # Success
        except Exception as e:
            attempt += 1
            if attempt >= max_retries:
                logger.error(f"Request failed after {max_retries} attempts")
                raise

            wait_time = backoff
            logger.warning(f"Request failed, retrying in {wait_time}s... (attempt {attempt}/{max_retries})")
            await asyncio.sleep(wait_time)
            backoff *= 2  # Exponential increase (1s → 2s → 4s)
```

**Real-World Performance:**
- 8-hour monitoring: 10,360+ HTTP requests
- Success rate: 100% (zero retries needed)
- Demonstrates both reliability and resilience

---

### 3.3. Multi-Layer Resilience - Defense in Depth

**Challenge:** Real-world failures can be complex - WebSocket connections can hang, heartbeats can fail silently, or supervisor loops can get stuck. A single recovery mechanism isn't enough.

**Solution:** Three-layer defense system with automatic escalation

**Architecture:**

```
Layer 1: Heartbeat Detection (30-90s)
         ├─> Forces WebSocket close on 3 failures
         └─> Triggers listen loop exit

Layer 2: Supervisor Reconnection Loop
         ├─> Detects disconnection immediately
         ├─> Exponential backoff (2s, 4s, 8s, 16s, 32s, 60s)
         └─> Max 10 reconnection attempts

Layer 3: Docker Health + Autoheal (90s+)
         ├─> HTTP health endpoint (:8090/health)
         ├─> Healthcheck every 30s (3 retries = 90s)
         └─> Autoheal restarts unhealthy containers (10s check)
```

**Sequence Diagram - Complete Resilience Flow:**

```
Time    Heartbeat Monitor    Listen Loop    Supervisor    Healthcheck    Autoheal
──────────────────────────────────────────────────────────────────────────────────
0s      │ ping rippled      │ receiving   │ running     │ 200 OK       │
        │<──── timeout      │ events      │             │              │
        │ (failure 1)       │             │             │              │
        │                   │             │             │              │
30s     │ ping rippled      │ receiving   │ running     │ 200 OK       │
        │<──── timeout      │ events      │             │              │
        │ (failure 2)       │             │             │              │
        │                   │             │             │              │
60s     │ ping rippled      │ receiving   │ running     │ 503 FAIL     │
        │<──── timeout      │ events      │             │ (retry 1)    │
        │ (failure 3)       │             │             │              │
        │                   │             │             │              │
        │ [TRIGGER]         │             │             │              │
        │ Force close WS ───┼────────────>│             │              │
        │ Set disconnected  │             │             │              │
        │                   │             │             │              │
        │                   │ [CHECK]     │             │              │
        │                   │ disconnected│             │              │
        │                   │ break loop  │             │              │
        │                   │             │             │              │
        │                   │ exit loop   │             │              │
        │                   │─────────────┼────────────>│              │
        │                   │             │ [DETECT]    │              │
        │                   │             │ not conn.   │              │
        │                   │             │             │              │
        │                   │             │ [WAIT 2s]   │              │
        │                   │             │             │              │
62s     │                   │             │ reconnect(1)│              │
        │                   │             │<──failed    │              │
        │                   │             │             │              │
        │                   │             │ [WAIT 4s]   │              │
        │                   │             │             │              │
66s     │                   │             │ reconnect(2)│              │
        │                   │             │<──failed    │              │
        │                   │             │             │              │
90s     │                   │             │             │ 503 FAIL     │
        │                   │             │             │ (retry 2)    │
        │                   │             │             │              │
        │                   │             │ [WAIT 8s]   │              │
        │                   │             │             │              │
        │                   │             │ (continues  │              │
        │                   │             │  trying...) │              │
        │                   │             │             │              │
120s    │                   │             │             │ 503 FAIL     │
        │                   │             │             │ (retry 3)    │
        │                   │             │             │ UNHEALTHY    │
        │                   │             │             │──────────────┼───────>│
        │                   │             │             │              │ [DETECT]
        │                   │             │             │              │ restart
        │                   │             │             │              │ container
        │                   │             │             │              │
130s    │ [CONTAINER RESTART]──────────────────────────────────────────────────>│
        │                   │             │             │              │
        │ reconnect to rippled            │             │              │
        │ subscribe streams               │             │              │
        │                   │             │             │              │
140s    │ ping rippled ✓    │ receiving   │ running     │ 200 OK       │
        │ (healthy)         │ events ✓    │ listening ✓ │ (healthy)    │
```

**How It Works:**

**Layer 1: Heartbeat Detection (First Line of Defense)**
1. Every 30 seconds, send WebSocket ping to rippled
2. Track consecutive failures (timeout = stuck connection)
3. After 3 failures (90s), force close WebSocket connection
4. Set `_is_connected = False` flag
5. Listen loop checks this flag every message iteration
6. When flag is false, break out of `async for` loop

**Layer 2: Supervisor Reconnection (Application Self-Healing)**
1. Supervisor loop monitors the listen task
2. When listen task exits, check `is_connected` property
3. If disconnected, initiate reconnection sequence:
   - Attempt 1: Wait 2 seconds, try to reconnect
   - Attempt 2: Wait 4 seconds, try to reconnect
   - Attempt 3: Wait 8 seconds, try to reconnect
   - Continue with exponential backoff (max 60s between attempts)
4. Max 10 reconnection attempts before giving up
5. On successful reconnection:
   - Re-subscribe to all streams
   - Reset reconnection counter
   - Resume normal monitoring

**Layer 3: Docker Health + Autoheal (Failsafe)**
1. HTTP health endpoint reports WebSocket status
   - `/health` returns 200 if `is_healthy` (heartbeat passing)
   - Returns 503 if disconnected or unhealthy
2. Docker healthcheck polls endpoint every 30s
   - 3 consecutive failures = container marked unhealthy
3. Autoheal monitors all containers every 10s
   - Detects unhealthy containers
   - Sends SIGTERM to restart container
4. Container restarts and reconnects fresh

**Benefits:**

- **Fast recovery** - Supervisor reconnection usually succeeds within 2-10 seconds
- **Stuck connection detection** - Heartbeat monitor catches silent failures
- **Guaranteed recovery** - Even if supervisor fails, Docker will restart the container
- **Observable** - Health endpoint exposes current state
- **Production-tested** - Handles router outages, rippled restarts, and network glitches

**Key Implementation:**

```python
# Layer 1: Heartbeat with forced close
async def _heartbeat_monitor(self):
    """Monitor connection health and force close on failures"""
    while self._is_connected:
        await asyncio.sleep(30)  # Check every 30s

        try:
            # Send ping
            await asyncio.wait_for(self._client.ping(), timeout=10)
            self._heartbeat_failures = 0
        except asyncio.TimeoutError:
            self._heartbeat_failures += 1

            if self._heartbeat_failures >= 3:
                logger.error("Connection stuck (3 heartbeat failures), forcing reconnection")
                self._connection_healthy = False
                self._is_connected = False

                # Force close WebSocket to trigger loop exit
                if self._client:
                    await self._client.close()
                break

# Layer 1: Listen loop with disconnection check
async def listen(self, handlers):
    """Listen for WebSocket messages"""
    try:
        async for message in self._client:
            # Check if heartbeat closed connection
            if not self._is_connected:
                logger.warning("Connection marked as closed, exiting listen loop")
                break

            # Process message...
            await self._process_message(message, handlers)

    except Exception as e:
        logger.error(f"Listen error: {e}")
        self._is_connected = False

    # If loop exits normally (no exception), mark as disconnected
    if self._is_connected:
        logger.warning("WebSocket message stream ended unexpectedly")
        self._is_connected = False

# Layer 2: Supervisor reconnection loop
async def run_monitor(config):
    """Main supervisor loop"""
    reconnect_attempt = 0
    max_reconnect_attempts = 10

    while not shutdown_event.is_set():
        # Start listen task
        listen_task = asyncio.create_task(xrpl_client.listen(handlers))

        # Wait for completion or shutdown
        done, pending = await asyncio.wait(
            [listen_task, asyncio.create_task(shutdown_event.wait())],
            return_when=asyncio.FIRST_COMPLETED
        )

        if shutdown_event.is_set():
            break

        # Listen task completed - check if we should reconnect
        if not xrpl_client.is_connected:
            reconnect_attempt += 1

            if reconnect_attempt > max_reconnect_attempts:
                logger.error("Failed to reconnect after 10 attempts, giving up")
                break

            # Exponential backoff: 2^attempt seconds, capped at 60
            delay = min(2 ** reconnect_attempt, 60)
            logger.warning(f"Reconnection attempt {reconnect_attempt}/10 in {delay}s...")

            await asyncio.sleep(delay)

            # Attempt reconnection
            if await xrpl_client.connect():
                logger.info("✓ Reconnected successfully!")
                await xrpl_client.subscribe(streams=["ledger", "server", "validations"])
                reconnect_attempt = 0  # Reset on success
            else:
                logger.error(f"Reconnection attempt {reconnect_attempt} failed")

# Layer 3: Health endpoint
async def health_check_handler(request):
    """HTTP health check for Docker healthcheck"""
    xrpl_client = request.app['xrpl_client']

    if xrpl_client and xrpl_client.is_healthy:
        return web.Response(text="OK\nWebSocket: connected\nStatus: healthy\n", status=200)
    else:
        return web.Response(text="UNHEALTHY\nWebSocket: disconnected\n", status=503)

# Layer 3: Docker healthcheck (docker-compose.yml)
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8090/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s

# Layer 3: Autoheal (docker-compose.yml)
autoheal:
  image: willfarrell/autoheal:latest
  environment:
    - AUTOHEAL_CONTAINER_LABEL=all
    - AUTOHEAL_INTERVAL=10  # Check every 10 seconds
    - AUTOHEAL_START_PERIOD=30
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
```

**Real-World Testing:**

Tested with simulated rippled failure (stopped container):
1. **T+60s**: Heartbeat detected 3 failures, forced WebSocket close
2. **T+60s**: Listen loop exited immediately (checked `_is_connected`)
3. **T+62s**: Supervisor detected disconnection, attempted reconnection
4. **T+62-120s**: Supervisor made multiple reconnection attempts (failed because rippled still down)
5. **T+90s**: Docker healthcheck marked container unhealthy (3 × 30s checks)
6. **T+120s**: Autoheal detected unhealthy status and restarted container
7. **T+130s**: Container restarted, rippled available, reconnected successfully
8. **T+140s**: All systems healthy, monitoring resumed

**Metrics Exposed:**
- `xrpl_websocket_connected` - WebSocket connection state (1 = connected, 0 = disconnected)
- `xrpl_websocket_healthy` - Heartbeat health (1 = healthy, 0 = unhealthy)
- `xrpl_http_rpc_connected` - HTTP RPC health (1 = healthy, 0 = failing)
- `xrpl_monitor_uptime_seconds` - Collector uptime (resets on container restart)

---

### 3.5. State Exporter (src/exporters/state_exporter.py)

**Role:** Real-time state monitoring with sub-second latency for Grafana dashboard

**Purpose:** The State Exporter was created to solve VictoriaMetrics storage lag. When metrics flow through the normal pipeline (Collector → VictoriaMetrics → Grafana), there's a 20-30 second delay due to scrape intervals, storage writes, and query caching. For the State panel, which shows the current validator state (PROPOSING, FULL, SYNCING, etc.), this delay is unacceptable - operators need instant visibility when state changes.

**Solution:** The State Exporter polls rippled's HTTP API every 1 second and implements a minimal Prometheus query API (`/api/v1/query`). Grafana is configured with a dedicated "StateExporter" datasource that queries this exporter directly, bypassing VictoriaMetrics entirely.

**Key Features:**
- 1-second polling interval for near-real-time state updates
- Custom HTTP server with `/metrics`, `/api/v1/query`, and `/health` endpoints
- Implements Prometheus query API format so Grafana can query directly
- Thread-safe state storage with mutex protection
- State change detection and logging
- Handles DOWN state when rippled is unreachable or starting up

**Metrics Exported:**

*State metrics (1s polling):*
- `xrpl_state_realtime_value{instance="validator"}` - Numeric state value (0-7)
- `xrpl_state_realtime{instance="validator",state="..."}` - Per-state gauge (1=current, 0=other)
- `xrpl_build_version_realtime{instance="validator",version="..."}` - Current rippled version (always 1)
- `xrpl_pubkey_realtime{instance="validator",pubkey="..."}` - Validator public key (always 1)

*Peer metrics (5s polling):*
- `xrpl_peer_count_realtime{instance="validator"}` - Total connected peers
- `xrpl_peers_inbound_realtime{instance="validator"}` - Inbound peer connections
- `xrpl_peers_outbound_realtime{instance="validator"}` - Outbound peer connections
- `xrpl_peers_insane_realtime{instance="validator"}` - Peers on wrong fork
- `xrpl_peer_latency_p90_realtime{instance="validator"}` - P90 peer latency (ms)

**State Value Mapping:**
| State | Value | Description |
|-------|-------|-------------|
| down | 0 | rippled not responding or starting up |
| disconnected | 1 | Not connected to peer network |
| connected | 2 | Connected but not synced |
| syncing | 3 | Downloading ledgers |
| tracking | 4 | Synced, passive observer |
| full | 5 | Fully synced, ready for consensus |
| validating | 6 | Signing validations (legacy) |
| proposing | 7 | Actively proposing in consensus |

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│  State Exporter Container (port 9102)                       │
│                                                             │
│  ┌───────────────────┐      ┌──────────────────────────┐    │
│  │  Polling Loops    │      │  HTTP Server (threaded)  │    │
│  │  (async)          │─────►│                          │    │
│  │                   │      │  GET /metrics            │    │
│  │  State: 1s poll   │      │  GET /api/v1/query       │◄───┼── Grafana
│  │  Peers: 5s poll   │      │  GET /health             │    │
│  │  from rippled     │      │                          │    │
│  └───────────────────┘      └──────────────────────────┘    │
│           │                                                 │
│           │ Global state (thread-safe)                      │
│           └──► current_metrics{state, peers, version, etc}  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
            │
            │ HTTP POST :5005
            ▼
    ┌───────────────────┐
    │  rippled          │
    │  (server_info,    │
    │   peers)          │
    └───────────────────┘
```

**Performance:**
- CPU: ~0.4% (polling + HTTP serving)
- Memory: ~22 MB
- Latency: ~1 second state update, ~5 seconds peer update (vs 20-30s via VictoriaMetrics)

**Key Implementation:**
```python
# HTTP handler serves Prometheus query API format
def serve_query(self, parsed, post_params=None):
    """Serve Prometheus query API response for Grafana"""
    response = {
        "status": "success",
        "data": {
            "resultType": "vector",
            "result": [{
                "metric": {"__name__": "xrpl_state_realtime_value"},
                "value": [timestamp, str(state_value)]
            }]
        }
    }
```

**Grafana Datasource Configuration:**
```yaml
- name: StateExporter
  type: prometheus
  url: http://localhost:9102
  access: proxy
  isDefault: false
```

**Dashboard Panel Query:**
The State panel uses `StateExporter` datasource with query:
```promql
xrpl_state_realtime_value{instance="validator"}
```

---

### 3.6. Uptime Exporter (src/exporters/uptime_exporter.py)

**Role:** Dedicated lightweight exporter for formatted uptime metrics

**Responsibilities:**
- Maintain persistent WebSocket connection to rippled
- Fetch uptime every 5 seconds via `server_state` command
- Format uptime as human-readable string (e.g., "1d:18h:15m")
- Export formatted uptime as Prometheus metric with label
- Clear old time series to prevent metric proliferation

**Why a Separate Exporter:**
The uptime metric needs special handling for Grafana display. The formatted string
(e.g., "1d:18h:15m") is stored as a Prometheus label on a gauge metric, allowing
Grafana to display the text directly instead of trying to format raw seconds.

**Metrics Exported:**
- `xrpl_rippled_uptime_seconds{instance="validator"}` - Raw uptime in seconds
- `xrpl_rippled_uptime_formatted{instance="validator",uptime="1d:18h:15m"}` - Formatted uptime with value always set to 1

**Format Details:**
- Time is floored to the current minute (not rounded) to prevent bouncing
- Format: "Xd:Xh:Xm" with colons as separators
- No seconds component (prevents constant updates)
- Updates every 60 seconds when minute changes

**Key Methods:**
```python
async def fetch_uptime_seconds(client: AsyncWebsocketClient) -> int:
    """Fetch uptime from rippled via WebSocket"""
    request = ServerState()
    response = await client.request(request)
    return response.result["state"]["uptime"]

def format_uptime(seconds: int) -> str:
    """Format uptime seconds as 'Xd:Xh:Xm' (no seconds, with colons)"""
    days = seconds // 86400
    hours = (seconds % 86400) // 3600
    minutes = (seconds % 3600) // 60
    return ":".join(parts)  # e.g., "1d:18h:15m"
```

**Deployment:**
- Runs as separate Docker container (xrpl-monitor-uptime-exporter)
- Exposes Prometheus metrics on port 9101
- Scraped by vmagent every 10 seconds
- Uses minimal resources (WebSocket only, no HTTP polling)

---

### 4. Event Handlers

**Role:** Parse WebSocket events and extract metrics

**Components:**

#### LedgerHandler (src/handlers/ledger_handler.py)
- Handles `ledgerClosed` events
- Extracts: ledger_sequence, ledger_age, base_fee, reserves, txn_count
- Calculates: transaction_rate (txn_count / ledger_interval)

#### ServerHandler (src/handlers/server_handler.py)
- Handles `serverStatus` events
- Extracts: server_state, load_factor (if present)
- Tracks state transitions

#### ValidationsHandler (src/handlers/validations_handler.py)
- Handles `validationReceived` events
- Tracks validation agreement rates
- Compares validation ledger hashes with closed ledger hashes
- Calculates 1h and 24h agreement rates
- Filters our validator's validations (if configured)

**Common Pattern:**
```python
class LedgerHandler:
    def __init__(self, victoria_client):
        self.victoria_client = victoria_client

    async def handle(self, event: dict):
        """Process ledgerClosed event"""
        # 1. Extract data from event
        ledger_index = event.get("ledger_index")
        ledger_time = event.get("ledger_time")
        txn_count = event.get("txn_count")

        # 2. Calculate derived metrics
        metrics = self._extract_metrics(event)

        # 3. Write to VictoriaMetrics
        await self.victoria_client.write(metrics)
```

---

### 5. VictoriaMetrics Client (src/clients/victoria_client.py)

**Role:** Database interface and metrics writer

**Responsibilities:**
- Format metrics in Prometheus exposition format
- Batch writes for efficiency
- Handle write errors and retries
- Health checks

**Metric Format:**
```python
# Prometheus exposition format
xrpl_ledger_sequence{validator="validator1"} 85000000 1699564800000
xrpl_server_state_value{state="proposing"} 6 1699564800000
```

**Key Features:**
- Batch writes (up to 100 metrics per request)
- Automatic timestamp handling
- Label support
- Error retry with exponential backoff
- HTTP POST to `/api/v1/import/prometheus`

**Key Methods:**
```python
async def write_metric(metric: str, flush_immediately=False):
    """Add metric to batch queue"""

async def flush():
    """Flush all pending metrics to VictoriaMetrics"""

async def health_check() -> bool:
    """Check if VictoriaMetrics is healthy"""
```

---

# Technology Choices

### Why xrpl-py?

- ✅ **Official library** - Maintained by XRPL team
- ✅ **Type-safe** - Full Python type hints
- ✅ **Auto-validated** - Requests and responses validated
- ✅ **Async-native** - AsyncWebsocketClient and AsyncJsonRpcClient
- ✅ **Production-proven** - Used by major XRPL projects
- ✅ **Less code** - 60% reduction vs manual HTTP/WebSocket

### Why VictoriaMetrics?

- ✅ **Single database** - Replaces SQLite + Prometheus (simpler)
- ✅ **PromQL compatible** - Grafana dashboards work unchanged
- ✅ **Better compression** - 7x better than Prometheus
- ✅ **Lower resources** - 26-35% less RAM, 66-76% less disk
- ✅ **Production-proven** - Used at scale
- ✅ **Easy to operate** - Single binary, no dependencies

### Why Async Python?

- ✅ **Non-blocking** - WebSocket listener doesn't block HTTP polling
- ✅ **Efficient** - Single process handles all monitoring
- ✅ **Modern** - Python 3.8+ async/await is mature
- ✅ **Scalable** - Can handle high-volume streams (validations = 50-100/sec)

---

# Deployment Architecture

### Docker Compose Stack

```yaml
services:
  collector:
    # Python monitoring application (main.py)
    # Connects to rippled via host network
    # Writes to VictoriaMetrics
    # Health endpoint on :8090

  victoria-metrics:
    # Time-series database
    # Stores all metrics
    # HTTP API on :8428

  vmagent:
    # Metrics scraper
    # Scrapes exporters and pushes to VictoriaMetrics
    # HTTP API on :8427

  grafana:
    # Dashboards and alerts
    # Queries VictoriaMetrics + StateExporter
    # Web UI on :3000

  node-exporter:
    # System metrics (CPU, memory, disk, network)
    # Prometheus format metrics
    # HTTP API on :9100

  uptime-exporter:
    # Formatted uptime metrics
    # WebSocket connection to rippled
    # HTTP API on :9101

  state-exporter:
    # Real-time state and peer monitoring
    # Polls rippled HTTP API (state: 1s, peers: 5s)
    # Exposes /api/v1/query for direct Grafana queries
    # Bypasses VictoriaMetrics for instant updates
    # HTTP API on :9102
```

**Network:**
- Collector → rippled (host network - localhost)
- Collector → VictoriaMetrics (localhost:8428 via port mapping)
- Grafana → VictoriaMetrics (Docker bridge network)
- User → Grafana (exposed port 3000)

**Volumes:**
- `victoria_data` - Persistent metrics storage
- `grafana_data` - Dashboard and config storage
- `/var/lib/rippled` - Mounted read-only for database size monitoring

---

# Error Handling Strategy

### Connection Errors

**WebSocket disconnect:**
1. Log error
2. Wait 5 seconds
3. Reconnect automatically
4. Re-subscribe to streams

**HTTP timeout:**
1. Log warning
2. Retry with exponential backoff (max 3 attempts)
3. Continue on failure (don't crash)

### Data Errors

**Invalid event:**
1. Log error with event details
2. Skip event
3. Continue processing

**VictoriaMetrics write failure:**
1. Log error
2. Retry once
3. Drop metrics on failure (don't queue - prevents memory leak)

### Fatal Errors

**xrpl-py client initialization failure:**
- Log error
- Exit with non-zero code
- Docker will restart container

---

# Performance Characteristics

### Resource Usage

| Resource | v2.0 (actual) | v3.0 (actual) | Change |
|----------|---------------|---------------|--------|
| **CPU (idle)** | <3% | <3% | Comparable |
| **CPU (active)** | <3% | <3% | Comparable |
| **RAM** | ~609 MB | ~729 MB | +120 MB (+20%) |
| **Disk (30d)** | ~9.5 GB | ~70 MB | -9.43 GB (-99%) |
| **Network** | 42 req/min × 50KB ≈ 2 MB/min | 3.2 req/min × 50KB + WS ≈ 0.5 MB/min | 75% less |

**Note:** v3.0 uses slightly more RAM to power real-time WebSocket streams and VictoriaMetrics' superior compression, delivering 99% disk savings in return.

### Throughput

**WebSocket events:**
- Ledger closes: ~20-30/min (every 3-5 seconds)
- Server status: Variable (state changes)
- Validations: ~1,500-3,000/min (50-100 per ledger)

**Total event rate:** ~1,500-3,500 events/min

**VictoriaMetrics writes:** ~1-2 writes/second (batched)

---

# Security Considerations

### rippled API Access

**WebSocket (port 6006):**
- Should only accept localhost connections
- No authentication by default (secured by firewall)
- Configured via `admin = 127.0.0.1` in rippled.cfg

**HTTP Admin API (port 5005):**
- Should only accept localhost connections
- No authentication by default (secured by firewall)

**Recommendation:** Collector uses host network mode to access localhost:6006 and localhost:5005

### Grafana

**Default credentials:** admin/admin (must change on first login)

**Recommendations:**
- Change default password immediately
- Enable HTTPS (reverse proxy)
- Restrict access to dashboard (IP whitelist or VPN)

### VictoriaMetrics

**No authentication** by default

**Recommendations:**
- Not exposed to internet (Docker internal network)
- Only Grafana and collector can access
- Optional: Add auth proxy if needed

---

# Scalability

### Current Scale
- **Single validator** monitoring
- **40 metrics** tracked
- **~3,500 events/min** processed

### Future Scale (v3.1+)
- **Multiple validators** (10-100)
- **400-4,000 metrics** (40 per validator)
- **35,000-350,000 events/min**

**Scalability Strategy:**
- Async Python can handle this load easily
- VictoriaMetrics can handle millions of samples/sec
- May need to shard VictoriaMetrics if >1000 validators

---

**Document Version:** 2.6
**Date:** 2025-11-30
**Status:** Production-validated architecture with multi-layer resilience system

**Port Summary (Default):**
| Service | Port | Purpose |
|---------|------|---------|
| Grafana | 3000 | Web UI |
| VictoriaMetrics | 8428 | Time-series database |
| vmagent | 8427 | Metrics scraper |
| Node Exporter | 9100 | System metrics |
| Uptime Exporter | 9101 | Formatted uptime |
| State Exporter | 9102 | Real-time state & peers |
| Collector Health | 8090 | Health check endpoint |
