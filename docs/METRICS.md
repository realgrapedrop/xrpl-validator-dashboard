# **__METRICS REFERENCE__**

*Complete reference for all metrics collected and displayed by XRPL Monitor.*

---

# Table of Contents

- [Overview](#overview)
- [Quick Reference](#quick-reference)
- [Validation Metrics](#validation-metrics)
- [Ledger Metrics](#ledger-metrics)
- [Server Metrics](#server-metrics)
- [Network Metrics](#network-metrics)
- [Storage Metrics](#storage-metrics)
- [DB State Accounting Metrics](#db-state-accounting-metrics)
- [Performance Metrics](#performance-metrics)
- [Monitor Health Metrics](#monitor-health-metrics)
- [State Exporter Metrics](#state-exporter-metrics)
- [Understanding Metric Relationships](#understanding-metric-relationships)
- [Metric Collection Architecture](#metric-collection-architecture)

---

# Overview

The dashboard displays **41 validator-specific panels** covering all aspects of validator health and performance.

| Panel Type | Count | Examples |
|------------|-------|----------|
| **Stat** | 19 | Agreements, Validations Sent, Pubkey, Rippled, State, Uptime |
| **Gauge** | 12 | UNL Expiry, Peer Latency, Load Factor, Proposers, Quorum |
| **Time Series** | 10 | Activity Rates, IO Latency, Consensus Converge Time |
| **Total** | **40** | All panels include threshold/range documentation |

| Category | Panels | Source |
|----------|--------|--------|
| **Validation** | 10 | WebSocket `validations` stream (real-time) + derived metrics |
| **Network** | 9 | WebSocket `peer_status` + HTTP `peers` + State Exporter |
| **Performance** | 7 | HTTP `server_info` (5s) + WebSocket streams |
| **Server** | 6 | WebSocket `server` stream + HTTP `server_info` (5s) |
| **Ledger** | 5 | WebSocket `ledger` stream (instant) |
| **Storage** | 2 | HTTP `server_state` (5min polling) + filesystem |
| **Upgrade** | 1 | State Exporter peer crawl + `server_info` (5min) |
| **Info** | 1 | HTTP `server_info` (network fee settings) |

**51-63% of metrics come from real-time WebSocket streams.**

The dashboard also includes **118 system monitoring panels** from Node Exporter (CPU, memory, disk, network) for comprehensive server health visibility.

---

# Quick Reference

All XRPL validator metrics at a glance. For detailed explanations, see the sections below.

**Note:** The dashboard "XRPL Validator" row contains 40 monitoring panels. Some panels appear multiple times in different dashboard locations to show different time ranges (e.g., Transaction Rate and Validation Rate appear in both 1-hour and 24-hour views). The dashboard also includes additional system monitoring panels from Node Exporter that track server hardware (CPU, memory, disk, network).

| # | Panel Name | Category | PanelType | Explanation |
|---|------------|----------|-----------|-------------|
| 1 | **Activity Rates** | Performance | Time Series | Your validator vs network validation rates (Green=network ~3000/min, Yellow=yours ~15-20/min) |
| 2 | **Agreement % Trend** | Validation | Time Series | Historical consensus agreement (Target: ≥99% excellent, 95-99% good, <90% critical) |
| 3 | **Agreements (1h)** | Validation | Stat | How many validators agreed with your validations in the last hour |
| 4 | **Agreements % (1h)** | Validation | Stat | Percentage of validators that agreed with your validations in the last hour |
| 5 | **Agreements (24h)** | Validation | Stat | How many validators agreed with your validations in the last 24 hours |
| 6 | **Agreements % (24h)** | Validation | Stat | Percentage of validators that agreed with your validations in the last 24 hours |
| 7 | **Consensus** | Performance | Gauge | Consensus health and performance metrics (24-hour view) |
| 8 | **Consensus Converge Time** | Performance | Time Series | Time to reach consensus (Fast: 2-3s, Normal: 3-4s, Slow: 4-6s, Investigate: >6s) |
| 9 | **Current Ledger** | Ledger | Stat | Current validated ledger index (blockchain height) |
| 10 | **Inbound Peers** | Network | Gauge | Peers connecting TO your validator (real-time, updates every 5s) |
| 11 | **Insane Peers** | Network | Gauge | Peers with divergent ledger views (real-time, updates every 5s) |
| 12 | **IO Latency** | Performance | Time Series | Disk I/O latency (NVMe: <5ms, SSD: 5-15ms, Acceptable: 15-30ms, Investigate: >30ms) |
| 13 | **Ledger Age** | Ledger | Gauge | Age of the last validated ledger in seconds |
| 14 | **Ledger DB** | Storage | Stat | SQL ledger database disk usage |
| 15 | **Ledger NuDB** | Storage | Stat | NuDB key-value store disk usage |
| 16 | **Ledgers Per Minute** | Ledger | Stat | How fast the XRPL network is closing ledgers (15-20/min normal) |
| 17 | **Load Factor** | Server | Gauge | Server load multiplier (1.0 = normal, >5 = high load) |
| 18 | **Load Factor Over Time** | Server | Time Series | Load factor trend (Normal: ~1.0, Elevated: 1-2, High: 2-5, Critical: >5) |
| 19 | **Missed (1h)** | Validation | Stat | Validation rounds YOUR validator missed in the last hour |
| 20 | **Missed (24h)** | Validation | Stat | Validation rounds YOUR validator missed in the last 24 hours |
| 21 | **Network TCP In / Out** | Network | Time Series | TCP traffic (Idle: 100-500, Normal: 500-2000, High: 2000+ seg/s) |
| 22 | **Outbound Peers** | Network | Gauge | Peers your validator connects TO (real-time, updates every 5s) |
| 23 | **Peer Count Over Time** | Network | Time Series | Peer connection trend (Healthy: 21-50, Acceptable: 15-21, Critical: <10) |
| 24 | **Peer Disconnects** | Network | Stat | Cumulative peer disconnections |
| 25 | **Peer Latency** | Network | Gauge | P90 network latency to peers in milliseconds (real-time, updates every 5s) |
| 26 | **Proposers** | Performance | Gauge | Number of trusted validators proposing |
| 27 | **Pubkey** | Server | Stat | Your validator public key (updates every 5-60s) |
| 28 | **Quorum** | Performance | Gauge | Number of validations needed for quorum |
| 29 | **Release Version** | Server | Stat | rippled build version (updates every 5-60s after upgrade) |
| 30 | **Rippled** | Upgrade | Stat | Upgrade status: ✅ Current, ⚠️ Behind, ⛔ Blocked, 🚨 Critical (5-7 min detection) |
| 31 | **State** | Server | Stat | Current rippled state (DISCONNECTED, FULL, PROPOSING, etc.) - Real-time via State Exporter (~1s latency) |
| 32 | **Total Peers** | Network | Gauge | Number of peer connections (healthy: 10-30, real-time updates every 5s) |
| 33 | **Transaction Rate** (1h) | Ledger | Gauge | Transactions per second on the network (1-hour view) |
| 34 | **Transaction Rate** (24h) | Ledger | Time Series | TPS trend (Low: 5-15, Normal: 15-40, High: 40-100, Spike: >100) |
| 35 | **UNL Expiry** | Network | Gauge | Days until Validator List (UNL) expires (real-time, updates every 2s) |
| 36 | **Uptime** | Server | Stat | Time since rippled started (displayed as Xd:Xh:Xm) |
| 37 | **Validation Rate** (1h) | Validation | Stat | How many validations YOUR validator sends per minute (1-hour view) |
| 38 | **Validation Rate** (24h) | Validation | Time Series | Your validation rate trend (Healthy: 12-18/min, Low: 10-12/min, Critical: <10/min) |
| 39 | **Validator CPU Load** | Performance | Time Series | rippled CPU usage (Normal: 5-30%, High: 30-80%, Investigate: >100% sustained) |
| 40 | **Validations Sent** | Validation | Stat | Validations sent by YOUR validator since rippled restarted (smart counter with restart detection) |
| 41 | **XRP Fees** | Info | Stat | Network fee information (updates every 5-60s) |

**Total: 41 panels** in the XRPL Validator dashboard row covering all aspects of validator monitoring.

---

# Validation Metrics

These metrics track your validator's participation in the XRPL consensus process.

### `xrpl_validations_total`

**Type**: Counter
**Unit**: Count
**Source**: WebSocket validation stream

Total number of validation messages published by YOUR validator since rippled last restarted.

**What it measures**: Each time your validator agrees with a proposed ledger, it publishes a validation message to the network. This counter increments with each validation.

**Smart counter recovery** (v3.0+):
- **Survives monitor restarts**: Counter value is recovered from VictoriaMetrics when the monitor restarts
- **Resets on rippled restart**: Automatically detects when rippled restarts (via uptime monitoring) and resets counter to 0
- **Tracks validator uptime**: Provides accurate count of validations since your validator node last restarted

**How restart detection works**:
The monitor compares rippled's current uptime with uptime from 5 minutes ago. If uptime decreased, rippled restarted and the counter resets. Otherwise, the counter recovers its last value from VictoriaMetrics.

**Healthy values**: Continuously increasing, tracking the network ledger rate (~15-20/min).

**Warning signs**:
- Not increasing → Validator not publishing validations
- Increasing slower than network → Missing validation rounds

### `xrpl_validation_agreements_1h` / `xrpl_validation_agreements_24h`

**Type**: Gauge (calculated from `xrpl_validation_agreements_total` counter via `increase()` function)
**Unit**: Count
**Source**: Derived from validation events via WebSocket stream

Total number of validation agreements YOUR validator produced in the last 1 hour or 24 hours.

**What it measures**: Each time your validator publishes a validation that matches the network consensus hash, it counts as one agreement. This tracks the total validation agreements over a sliding time window. The count represents real-time local metrics straight from your validator's WebSocket stream - more accurate than aggregated network observers like XRPScan.

**Healthy values**:
- 1h: ~900-960 agreements (typical range for ~15.5 validations/min)
- 24h: ~21,600-23,040 agreements (24 × hourly rate)

**Normal behavior - Sliding Window Oscillation**:
You'll see values naturally oscillate by ±2-3 as the sliding window moves forward (e.g., 927 → 928 → 929 → 928). This is **expected** because:
- New validations enter the window every ~4 seconds
- Old validations from exactly 60 minutes ago drop off
- Ledger close timing has natural variance
- The sliding window captures real-time ebb and flow

**Warning signs**:
- Consistently <900/hour → Validator may be missing validations or out of sync
- Large swings (>10) → Network connectivity issues or validator performance problems
- Steady decline → Performance degradation or increasing missed validations

### `xrpl_validation_missed_1h` / `xrpl_validation_missed_24h`

**Type**: Gauge
**Unit**: Count
**Source**: Derived from validation reconciliation

Number of validation rounds YOUR validator missed in the last 1 hour or 24 hours.

**What it measures**: Ledgers that closed without your validator publishing a validation message, tracked via the reconciliation system. When a ledger closes and your validator doesn't send a validation within the 8-second grace period, it's counted as "missed."

**Time-windowed behavior**:
- **Increments**: When ledgers are missed (e.g., during rippled restart/downtime)
- **Stays elevated**: For the duration of the time window (1h or 24h)
- **Rolls back to 0**: As missed records age out of the window (if no new misses occur)

**Example during rippled restart**:
- Rippled is down for 30 seconds → ~6-10 ledgers missed
- Missed (1h) shows 6-10 for 1 hour
- After 1 hour, Missed (1h) returns to 0 (those records aged out)

**Healthy values**: 0-5 per hour (occasional misses are normal)

**Warning signs**:
- Consistently >10/hour → Performance or connectivity issues
- Sudden spike → Temporary outage or sync problem
- Not returning to 0 after 1h → Ongoing validation issues

---

### 📊 How Agreements and Missed Validations Are Calculated

Understanding how these critical metrics are calculated helps you interpret your validator's performance accurately and trust the methodology.

#### Agreement vs Missed: The Core Concept

The monitor tracks whether YOUR validator's proposed ledger hash matches the **network consensus hash** for each ledger.

**✅ AGREEMENT** = Your validator's hash **matched** the consensus hash (correct validation)

**❌ MISSED** = Your validator's hash **did NOT match** consensus OR **didn't validate at all**

**Critical:** The system detects THREE scenarios:
1. **Agreement**: Your validation hash matched consensus (validator performing correctly)
2. **Disagreement**: Your validation hash differed from consensus (rare, investigate if persistent)
3. **Unsent Validation**: Ledger closed but your validator didn't send a validation (validator offline/unhealthy)

#### How It Works: Full Reconciliation Approach

**v3.0+ uses "full reconciliation"** to achieve 100% complete validation tracking. This method is XRPSCAN-compatible and handles out-of-order messages, network delays, and validator offline scenarios.

**1. Event Registration**

The monitor subscribes to two WebSocket streams:

**Ledger Stream** - Network consensus:
- Event: `ledgerClosed` (every 3-5 seconds)
- Data: `ledger_index`, `ledger_hash` (consensus hash)
- Action: Records consensus hash with timestamp

**Validation Stream** - Your validator's votes:
- Event: `validationReceived` (filtered by your `VALIDATOR_PUBLIC_KEY`)
- Data: `ledger_index`, `ledger_hash` (your validation hash)
- Action: Records your validation hash with timestamp

**2. Pending Ledger Tracking**

Each ledger gets a `PendingLedgerRecord` tracking:
- Consensus hash (from ledger stream)
- Your validation hash (from validation stream)
- Ledger close time
- Validation send time
- Finalization status

**3. Reconciliation with Grace Period**

A background task runs every 1 second to reconcile pending ledgers:

```python
# Wait 8 seconds after ledger close (grace period)
if (now - ledger_close_time) < 8 seconds:
    continue  # Wait for late validations

# Grace period expired - finalize status
if our_hash and consensus_hash:
    if our_hash == consensus_hash:
        agreements_total += 1  # ✅ AGREEMENT
    else:
        missed_total += 1      # ❌ DISAGREEMENT
elif not our_hash:
    missed_total += 1          # ❌ UNSENT (validator offline?)
```

**Why 8 seconds?**
- Accounts for network latency and message ordering
- Validations may arrive slightly after ledger close
- Prevents false positives from timing issues
- XRPSCAN-compatible grace period

**4. Late Repair Window (5 minutes)**

If a validation arrives late (within 5 minutes), the system can fix false positives:

```python
# Late validation arrived after being marked as missed
if validation_arrives_late and (now - marked_missed_time) < 5 minutes:
    missed_total -= 1  # Reverse the missed count
    if late_hash == consensus_hash:
        agreements_total += 1  # Count as late agreement
```

**5. Cleanup (10 minutes)**

Finalized ledger records are removed after 10 minutes to prevent memory leak.

**Example Scenarios:**

**Scenario 1: Normal Agreement**
```
14:30:00  Ledger 100195123 closes (consensus_hash = "ABC123...")
14:30:01  Your validator sends validation (your_hash = "ABC123...")
14:30:08  Grace period expires
          → RECONCILED: Hashes match → AGREEMENT ✅
          → agreements_total += 1
```

**Scenario 2: Disagreement (Rare)**
```
14:30:00  Ledger 100195123 closes (consensus_hash = "ABC123...")
14:30:01  Your validator sends validation (your_hash = "XYZ789...")
14:30:08  Grace period expires
          → RECONCILED: Hashes differ → DISAGREEMENT ❌
          → missed_total += 1
```

**Scenario 3: Unsent Validation (Validator Offline)**
```
14:30:00  Ledger 100195123 closes (consensus_hash = "ABC123...")
          (No validation from your validator)
14:30:08  Grace period expires
          → RECONCILED: No validation received → UNSENT ❌
          → missed_total += 1
```

**Scenario 4: Late Validation (Recovered)**
```
14:30:00  Ledger 100195123 closes (consensus_hash = "ABC123...")
14:30:08  Grace period expires → Marked as UNSENT ❌
14:31:45  Late validation arrives (your_hash = "ABC123...")
          → REPAIRED: Late arrival within 5 min window
          → missed_total -= 1 (undo)
          → agreements_total += 1 (count as late agreement) ✅
```

#### Measurement Accuracy

**Expected Accuracy: 100% in typical operation**

**Why Full Reconciliation is Accurate:**
- ✅ **Grace period (8s)** handles network delays and message ordering
- ✅ **Detects unsent validations** (validator offline scenarios)
- ✅ **Late repair window (5min)** fixes false positives
- ✅ **Handles out-of-order messages** (validation before ledger close)
- ✅ **XRPSCAN-compatible** methodology
- ✅ **No edge cases** - all scenarios covered

**High Accuracy When:**
- ✅ Validator is healthy and well-connected
- ✅ Network latency is reasonable (< 5 seconds)
- ✅ System clocks are synchronized (NTP)

**No Edge Cases:**
Unlike simple hash comparison, reconciliation has no race conditions or timing issues. The grace period and late repair window ensure 100% accuracy.

**If you see <99% agreement**, investigate:
- Validator performance (CPU, disk I/O)
- Network connectivity (peer count, latency)
- Validator configuration (UNL, rippled.cfg)
- System resources (memory, disk space)

#### State Persistence & Auto-Recovery

**Problem Solved:** Prior to v3.0, restarting the monitor would reset agreement/missed metrics to zero, causing user frustration as panels would "count up again" over hours.

**Solution:** The monitor now automatically recovers metric state on restart, providing seamless continuity.

**Metrics with Auto-Recovery:**

**1. Validations Sent (`xrpl_validations_total`)**
- **Smart counter recovery with rippled restart detection**
- On monitor restart, queries VictoriaMetrics for last known value
- Compares rippled uptime (current vs 5 minutes ago):
  - If uptime **decreased** → rippled restarted → resets counter to 0
  - If uptime **same/increased** → rippled still running → restores counter value
- **Result**: Tracks "validations since rippled last restarted" accurately

**2. Agreements & Missed (1h/24h) (`xrpl_validation_agreements_*`, `xrpl_validation_missed_*`)**
- **Gauge recovery** (added Nov 2025)
- On monitor restart, queries VictoriaMetrics for last known gauge values:
  - `xrpl_validation_agreements_1h`
  - `xrpl_validation_missed_1h`
  - `xrpl_validation_agreements_24h`
  - `xrpl_validation_missed_24h`
- Writes recovered values back immediately
- Dashboard shows last known values instead of zero
- **Result**: Zero user frustration - panels maintain state across restarts

**Example Recovery Log:**
```
2025-11-14 14:23:01 - INFO - Recovered validations checked counter: 16,195,615
2025-11-14 14:23:01 - INFO - Rippled still running: uptime 300180s (was 299880s 300s ago)
2025-11-14 14:23:01 - INFO - Recovered validations_total counter: 28,710
2025-11-14 14:23:01 - INFO - Recovered 1h agreements: 11
2025-11-14 14:23:01 - INFO - Recovered 1h missed: 0
2025-11-14 14:23:01 - INFO - Recovered 24h agreements: 11
2025-11-14 14:23:01 - INFO - Recovered 24h missed: 0
2025-11-14 14:23:01 - INFO - Agreement gauge recovery complete: 4/4 metrics restored
```

**Why This Matters:**
- ✅ **Professional user experience** - Metrics don't reset arbitrarily
- ✅ **Accurate trend analysis** - Historical context preserved
- ✅ **Confidence in monitoring** - Data integrity across system restarts
- ✅ **Reduced confusion** - No need to explain "why did everything reset?"

**Technical Details:**
- Recovery happens automatically during monitor initialization
- Uses simple last-value queries (not historical range queries)
- No memory overhead (single value per metric)
- Code: `src/handlers/validations_handler.py` (lines 217-320)
- Documentation: `docs/VALIDATION_EVENT_FIX.md`

#### Expected Values & Health Indicators

**Healthy Validator Performance:**
- **Agreement %**: 99-100% (near perfect consensus alignment)
- **Agreements (1h)**: Varies based on ledger rate (~900-1200 for 15-20 ledgers/min)
- **Missed (1h)**: 0-2 (occasional misses are normal due to network timing)
- **Missed (24h)**: 0-50 (less than 0.1% miss rate)

**Warning Signs:**
- **Agreement % < 95%**: Network connectivity issues or validator performance problems
- **Missed > 10/hour**: Investigate load factor, disk I/O, or peer connectivity
- **Declining trend**: Monitor for progressive degradation
- **Sudden spike in misses**: Possible network partition or resource saturation

**What This Tells You:**
- **100% agreement** = Your validator is perfectly aligned with network consensus (excellent!)
- **95-99% agreement** = Minor timing issues or occasional disagreements (investigate if persistent)
- **<95% agreement** = Significant problems requiring immediate attention

**Why Agreement % Matters More Than Count:**
- Absolute counts vary with network activity (ledger close rate)
- Percentage normalizes for validator uptime and activity level
- Trend analysis over 24+ hours provides best health indicator

#### Comparing with External Services (xrpscan.com, etc.)

**Why numbers may differ from xrpscan.com or other monitoring services:**

Our monitoring measures **YOUR validator's consensus alignment** (did your hash match the network consensus?), while external services may track different metrics entirely:

**Key Differences:**

1. **Different measurement approach:**
   - **This dashboard**: Compares your validator's hash with consensus hash (binary: match or no match)
   - **xrpscan.com**: May track network-wide validation participation, UNL validator counts, or aggregated statistics across multiple nodes

2. **Data source perspective:**
   - **This dashboard**: Direct from YOUR rippled node (first-hand data)
   - **External services**: Aggregated from multiple network nodes (second-hand data)

3. **Time synchronization:**
   - **This dashboard**: Real-time as events arrive at your node
   - **External services**: May have different data ingestion timing and aggregation delays

4. **Calculation windows:**
   - **This dashboard**: Exact 1h/24h rolling windows from your monitor's perspective
   - **External services**: May use different time window definitions or UTC-based boundaries

5. **Edge case handling:**
   - **This dashboard**: Conservative bias (defaults to "agreed" on race conditions)
   - **External services**: May handle forks, network partitions, or duplicate validations differently

**Expected variance:** Small differences (±1-5%) are normal and expected due to these methodological differences.

**What matters most:**
- ✅ **Trend consistency** - Your agreement % should be stable over time
- ✅ **This dashboard's accuracy** - Direct hash comparison with consensus (98-99% accurate)
- ⚠️ **Large discrepancies** - If your dashboard shows 100% but xrpscan shows <90%, investigate network connectivity

**Trust your dashboard:** The full reconciliation methodology provides the most accurate real-time view of YOUR validator's consensus alignment.

---

# Ledger Metrics

These metrics track the XRPL network's ledger progression.

### `xrpl_ledger_sequence`

**Type**: Gauge
**Unit**: Ledger index
**Source**: WebSocket ledger stream

The current validated ledger index on the network.

**What it measures**: Each closed ledger increments this value by 1. Represents the "height" of the blockchain.

**Healthy values**: Continuously increasing at ~15-20 per minute.

**Warning signs**:
- Stalled → Network consensus issues (rare)
- Your value lags significantly → Your rippled is out of sync

### `xrpl_ledger_close_time`

**Type**: Gauge
**Unit**: Seconds
**Source**: Ledger stream (ledger close time)

Duration between the previous ledger close and current ledger close.

**What it measures**: How long it took for the network to reach consensus on this ledger.

**Healthy values**: 3-5 seconds (XRPL targets ~3.5s per ledger)

**Warning signs**:
- Consistently >6s → Network may be experiencing high load
- Highly variable → Network instability

### Ledgers Per Minute (Derived Metric)

**Calculation**: `increase(xrpl_ledger_sequence[1m])`
**Unit**: Ledgers per minute

**What it measures**: How fast the **XRPL network** is closing ledgers. This is a network-wide metric showing the consensus completion rate.

**Healthy values**: 15-20 ledgers per minute (network typically closes a ledger every 3-4 seconds)

**See Also**: [Validation Rate vs Ledgers Per Minute](#validation-rate-vs-ledgers-per-minute)

---

# Server Metrics

These metrics track your rippled server's operational state.

### `xrpl_server_state` / `xrpl_validator_state_value`

**Type**: Gauge (encoded)
**Unit**: Enum (0-7)
**Source**: WebSocket `server` stream (event-driven, ~3-10s)

Current state of the rippled server. This metric comes from the real-time WebSocket `server` stream, providing instant updates on state changes.

#### Complete Server State Reference

| Server State     | Value | Dashboard Display | Meaning                                                                 | Consensus Role          | Node Type               |
|------------------|-------|-------------------|-------------------------------------------------------------------------|-------------------------|-------------------------|
| `disconnected`   | 0     | DISCONNECTED      | Not connected to the peer network                                        | Not participating       | All nodes               |
| `connected`      | 1     | CONNECTED         | Connected to peers but not yet caught up                                 | Not yet participating   | All nodes               |
| `syncing`        | 2     | SYNCING           | Downloading recent ledgers to catch up                                   | Catch-up phase          | All nodes               |
| `tracking`       | 3     | TRACKING          | Synced with validated ledger chain but not proposing or validating       | Passive observer        | Non-validator nodes     |
| `full`           | 4     | FULL              | Fully synced and ready to participate in consensus                       | Active participant      | Validator nodes         |
| `validating`     | 5     | VALIDATING        | Signing validation messages (legacy state, rarely used)                  | Actively validating     | Validator nodes         |
| `proposing`      | 6     | PROPOSING         | Creating and broadcasting proposals during consensus rounds               | Actively proposing      | UNL members             |
| `standalone`     | 7     | STANDALONE        | Running in stand-alone mode (no peer connections, testing only)          | No consensus            | Stand-alone nodes       |

**\*Note**: With v3.0's real-time monitoring (1-second refresh), the dashboard accurately captures rapid state transitions between state 4 (`full`) and state 6 (`proposing`). See [Understanding Real-Time State Monitoring](#understanding-real-time-state-monitoring) below.

#### Understanding Real-Time State Monitoring

**v3.0's real-time advantage**: The State Exporter provides ~1 second state update latency by polling rippled directly and implementing a Prometheus query API that Grafana queries without going through VictoriaMetrics. This bypasses the 20-30 second storage lag of the normal metrics pipeline.

**What you'll observe**:
- During active consensus, validators rapidly flip between state 4 (`full`) and state 6 (`proposing`)
- When actively proposing: Dashboard shows state 6 (`proposing`)
- Between proposals: Dashboard may briefly show state 4 (`full`)
- Both states indicate healthy, active participation

**State definitions**:
- State 4 (`full`): Fully synced and ready to participate in consensus
- State 5 (`validating`): Legacy state, deprecated
- State 6 (`proposing`): Actively proposing in the current consensus round

**Why this works in v3.0**:
The combination of 1-second dashboard refresh and immediate metric flushing allows the monitoring system to capture state changes that happen every few seconds during consensus rounds.

#### Normal Validator Lifecycle

**Typical progression**:
```
disconnected → connected → syncing → tracking → full → (stays at full)
                                                  ↓
                                          actively validating
```

**Healthy values**:
- Validators: State 4 (`full`) or State 6 (`proposing`) - both indicate active participation
- Non-validators: State 3 (`tracking`)

**Warning signs**:
- 0-2 → Server not synced with network
- 3 on a validator → Not participating in consensus (check validator config)

### `xrpl_server_load_factor`

**Type**: Gauge
**Unit**: Multiplier
**Source**: HTTP `server_info` API

Server load multiplier used for calculating transaction fee requirements.

**What it measures**: How loaded your server is. Used by the network to calculate minimum transaction fees during high load.

**Healthy values**: 1.0 (normal load)

**Warning signs**:
- 2-5 → Moderate load, may indicate resource constraints
- >5 → High load, performance degradation likely
- >10 → Severe load, may drop validations

### `xrpl_server_uptime`

**Type**: Gauge
**Unit**: Seconds
**Source**: HTTP `server_info` API

Time since rippled server started.

**What it measures**: Server uptime in seconds.

**Dashboard Display Format**: The Uptime panel displays uptime in human-readable format following standard Linux/Unix conventions:

- **Format**: `Xd:Xh:Xm` (days, hours, minutes - no seconds)
- **Examples**:
  - `5d:12h:30m` - 5 days, 12 hours, 30 minutes
  - `45d:10h:32m` - 45 days, 10 hours, 32 minutes
  - `365d:8h:15m` - 365 days, 8 hours, 15 minutes

**No month conversion**: Following industry-standard practice (similar to Linux `uptime` command), days continue incrementing indefinitely without converting to months. This provides unambiguous measurement since months vary in length (28-31 days). A validator running continuously for a year will display `365d:Xh:Xm`.

**Healthy values**: Continuously increasing

**Warning signs**:
- Frequent resets → Server stability issues
- Value decreases → Unexpected restart

### `xrpl_validator_state_info`

**Type**: Info (label-only metric)
**Unit**: N/A
**Source**: HTTP polling (every 5 seconds)

Static node identification metadata.

**What it measures**: Provides static node identification labels for correlation with other metrics.

**Labels**:
- `pubkey_node`: Node public key (for node identification)

> **Note**: `build_version` and `pubkey_validator` were moved to State Exporter metrics (`xrpl_build_version_realtime`, `xrpl_pubkey_realtime`) for real-time display without VictoriaMetrics stale series issues.

### `xrpl_time_in_current_state_seconds`

**Type**: Gauge
**Unit**: Seconds
**Source**: WebSocket `server` stream (event-driven, updated continuously)

Time elapsed since the validator entered its current state.

**What it measures**: How long the validator has been in its current state. Resets to 0 on each state transition.

**Healthy values**:
- Proposing: Hours to days (stable)
- Syncing: Minutes (should transition quickly)
- Connected: Seconds to minutes (transitional state)

**Warning signs**:
- Stuck in "syncing" for >30 minutes → Sync issues
- Frequent resets (rapid state changes) → Network or config problems
- Time in "connected" or "tracking" on a validator → Not participating properly

### `xrpl_state_changes_total`

**Type**: Counter
**Unit**: Count
**Source**: WebSocket `server` stream (event-driven)

Total number of state transitions since monitoring started.

**What it measures**: Cumulative count of state changes. Increments by 1 each time the validator transitions between states (e.g., syncing → full).

**Healthy values**:
- Low count after initial startup (0-5)
- Rarely increasing after initial sync

**Warning signs**:
- Frequently increasing → Unstable validator or network connectivity issues
- Rapid changes → Configuration problems or system resource constraints

---

# Network Metrics

These metrics track your validator's network connectivity.

### `xrpl_peers_count`

**Type**: Gauge
**Unit**: Count
**Source**: HTTP `peers` API or `docker exec` fallback

Number of peer connections your rippled server maintains.

**What it measures**: Active peer-to-peer connections to other rippled servers.

**Healthy values**: 10-30 peers

**Warning signs**:
- <5 → Poor connectivity, may miss validations
- 0 → Isolated from network
- >50 → Excessive peer count, may impact performance

---

# Storage Metrics

These metrics track rippled's database usage.

### `xrpl_nudb_size_bytes`

**Type**: Gauge
**Unit**: Bytes
**Source**: Filesystem (NuDB data files)

Total size of the NuDB key-value store on disk.

**What it measures**: Disk space used by rippled's ledger database.

**Healthy values**: Grows over time as historical ledgers accumulate

**Warning signs**:
- Sudden large increase → Database corruption or replay
- Not growing → Database not updating

**Note**: Requires access to rippled data directory. See `RIPPLED_DATA_PATH` configuration.

---

# DB State Accounting Metrics

These metrics track historical database state accounting from rippled's `server_state` API. They differ from the real-time Node State metrics - these show cumulative duration and transition counts for each state over the validator's lifetime.

**Source**: HTTP `server_state` API (polled every 5 minutes)

### `xrpl_state_accounting_duration_seconds`

**Type**: Gauge (with labels)
**Unit**: Seconds
**Source**: HTTP `server_state` (5min polling)

Cumulative time the validator has spent in each state since rippled started.

**What it measures**: Total historical duration for each state (disconnected, connected, syncing, tracking, full, validating, proposing). Unlike `xrpl_time_in_current_state_seconds` which tracks the current state duration, this metric shows lifetime totals.

**Labels**:
- `state`: State name (disconnected, connected, syncing, tracking, full, validating, proposing)

**Example values**:
```
xrpl_state_accounting_duration_seconds{state="full"} 2,592,000     # 30 days
xrpl_state_accounting_duration_seconds{state="syncing"} 3,600      # 1 hour
xrpl_state_accounting_duration_seconds{state="connected"} 120      # 2 minutes
```

**Healthy pattern**:
- Most time in "full" state (99%+)
- Minimal time in "syncing", "connected", "disconnected"
- Low values for transitional states

**Warning signs**:
- Significant time in "syncing" or "connected" → Frequent sync issues
- Growing "disconnected" duration → Network connectivity problems
- Time in "tracking" on a validator → Configuration issue (not set to validate)

### `xrpl_state_accounting_transitions`

**Type**: Gauge (with labels)
**Unit**: Count
**Source**: HTTP `server_state` (5min polling)

Number of times the validator has transitioned to each state since rippled started.

**What it measures**: Historical count of state entries. Unlike `xrpl_state_changes_total` which counts total transitions, this metric shows how many times each specific state was entered.

**Labels**:
- `state`: State name (disconnected, connected, syncing, tracking, full, validating, proposing)

**Example values**:
```
xrpl_state_accounting_transitions{state="full"} 5        # Entered 'full' 5 times
xrpl_state_accounting_transitions{state="syncing"} 6     # Re-synced 6 times
xrpl_state_accounting_transitions{state="connected"} 8   # Connected 8 times
```

**Healthy values**:
- Low counts for all states (1-10 after initial startup)
- "full" count equals number of restarts + re-sync events

**Warning signs**:
- High counts → Frequent state changes indicate instability
- Growing "syncing" transitions → Repeated sync issues
- Many "disconnected" transitions → Network problems

### `xrpl_ledger_db_bytes`

**Type**: Gauge
**Unit**: Bytes
**Source**: HTTP `server_state` + filesystem monitoring (5min polling)

Total size of the ledger database directory (`db/` folder).

**What it measures**: Disk space used by rippled's SQL-based ledger database. This is separate from NuDB (the key-value store).

**Healthy values**: Grows slowly over time as ledger history accumulates

**Warning signs**:
- Sudden large increase → Possible database corruption or replay
- Not growing → Database not updating properly
- Excessive size → May need to reduce online_delete retention

**Note**: This is measured via filesystem (directory size) as rippled doesn't expose it via API. Different from `xrpl_nudb_size_bytes` which tracks the NuDB key-value store.

### `xrpl_ledger_nudb_bytes`

**Type**: Gauge
**Unit**: Bytes
**Source**: HTTP `server_state` + filesystem monitoring (5min polling)

Total size of the NuDB key-value database.

**What it measures**: Disk space used by rippled's NuDB database (usually in `nudb/` folder). This is the primary ledger object store.

**Healthy values**: Grows over time as ledger history accumulates

**Warning signs**:
- Sudden large increase → Database corruption or replay
- Not growing → Database not updating
- Rapid growth → May need to configure online_delete

**Note**: This metric attempts to auto-discover the NuDB path by checking common locations. Requires read access to rippled data directory.

### `xrpl_initial_sync_duration_seconds`

**Type**: Gauge
**Unit**: Seconds
**Source**: HTTP `server_state` (5min polling)

Time taken for rippled's initial sync after startup.

**What it measures**: Duration from rippled start to reaching fully synced state. Only meaningful after a fresh start or restart.

**Healthy values**:
- Fast sync (SSD): 30-300 seconds (0.5-5 minutes)
- Normal sync (HDD): 300-1800 seconds (5-30 minutes)
- Full history sync: Hours to days (depending on history size)

**Warning signs**:
- Consistently >30 minutes with online_delete enabled → Performance issues
- Growing sync times → Disk, network, or peer connectivity problems

---

# Performance Metrics

These metrics track system and process performance.

### `xrpl_rippled_cpu_percent`

**Type**: Gauge
**Unit**: Percentage (0-100+)
**Source**: `docker stats` or `psutil`

CPU usage of the rippled process.

**What it measures**: Percentage of CPU time used by rippled. Can exceed 100% on multi-core systems.

**Healthy values**:
- Idle: 5-20%
- Active validation: 30-60%
- High load: 60-100%

**Warning signs**:
- Consistently >100% → May need more CPU resources
- Consistently >200% → Performance bottleneck likely
- Sudden spikes → Investigate workload

**Note**: For Docker deployments, requires Docker socket access.

---

# Monitor Health Metrics

These metrics track the health of the monitoring system itself, providing visibility into the XRPL Monitor stack components.

The **🛡️ Monitor Component Health** row in the dashboard displays real-time status for all monitoring components with 5-10 second detection time.

### `xrpl_state_health`

**Type**: Gauge
**Unit**: Health status (0=Failed, 0.5=Degraded, 1=OK)
**Update Frequency**: Every 30 seconds

**What it measures**: Overall health of the state management system, including state persistence and metric backup functionality.

**Dashboard Label**: "Monitor Health"

**Values**:
- `1.0` = OK - State manager operational, backups successful
- `0.5` = Degraded - State manager running but backups failing or stale
- `0.0` = Failed - State manager not responding

**Warning signs**:
- Value = 0.5 → Check state directory permissions and disk space
- Value = 0.0 → Collector process stopped or crashed

### `xrpl_websocket_healthy`

**Type**: Gauge
**Unit**: Boolean (0=Unhealthy, 1=Healthy)
**Update Frequency**: Every 30 seconds

**What it measures**: WebSocket connection health to rippled, including heartbeat monitoring and connection stability.

**Dashboard Label**: "WebSocket"

**Values**:
- `1` = Healthy - WebSocket connected, heartbeat successful
- `0` = Unhealthy - WebSocket disconnected or heartbeat failing

**Features**:
- Heartbeat monitoring (ping every 30s with 10s timeout)
- Auto-reconnection with exponential backoff (1s → 2s → 5s → 10s → 30s)
- 3 consecutive heartbeat failures trigger reconnection

**Warning signs**:
- Intermittent failures → Check network connectivity to rippled
- Persistent failures → Verify rippled is running and WebSocket port (6006) is accessible

**Related metrics**:
- `xrpl_websocket_connected` - Connection status (0/1)
- `xrpl_websocket_heartbeat_failures` - Consecutive failure count
- `xrpl_websocket_reconnect_attempts` - Reconnection attempt counter

### `xrpl_validator_uptime_seconds`

**Type**: Gauge
**Unit**: Seconds
**Update Frequency**: Every 5 seconds (via uptime-exporter)

**What it measures**: HTTP RPC connection health to rippled by tracking uptime data availability.

**Dashboard Label**: "HTTP RPC"
**Dashboard Query**: `clamp_max(xrpl_validator_uptime_seconds > bool 0, 1)`

**Values**:
- `1` = Up - HTTP RPC endpoint responding
- `0` = Down - HTTP RPC endpoint unreachable

**Detection time**: 3-6 seconds (5s scrape interval + refresh)

**Warning signs**:
- Intermittent down status → Check rippled HTTP port (5005)
- Persistent down status → Verify rippled is running and HTTP RPC is enabled

### `xrpl_monitor_uptime_seconds`

**Type**: Gauge
**Unit**: Seconds
**Update Frequency**: Every 30 seconds

**What it measures**: Collector process health by tracking how long the monitoring application has been running.

**Dashboard Label**: "Collector"
**Dashboard Query**: `clamp_max(xrpl_monitor_uptime_seconds > bool 0, 1)`

**Values**:
- `1` = Up - Collector process running and emitting metrics
- `0` = Down - Collector process stopped or crashed

**Warning signs**:
- Sudden drops to 0 → Collector container crashed or was stopped
- Value stops increasing → Collector hung or stopped emitting metrics

### Database Health

**Metric**: Derived from query success
**Dashboard Query**: `clamp_max(count(xrpl_monitor_uptime_seconds) > bool 0, 1)`

**What it measures**: VictoriaMetrics database health by verifying it can respond to queries.

**Dashboard Label**: "Database"

**Values**:
- `1` = Up - VictoriaMetrics responding to queries
- `0` (No Data) = Down - VictoriaMetrics not responding

**Detection time**: 5-10 seconds (based on Grafana refresh interval)

**Warning signs**:
- Database down → All dashboard panels will fail
- Check VictoriaMetrics container status
- Verify disk space and memory availability

### `xrpl_ledgers_closed_total`

**Type**: Counter
**Unit**: Count
**Update Frequency**: Real-time (on each ledger close event)

**What it measures**: Data collection pipeline health by checking if ledger events are being received and processed.

**Dashboard Label**: "Data Collection"
**Dashboard Query**: `clamp_max((time() - timestamp(xrpl_ledgers_closed_total)) < bool 60, 1)`

**Values**:
- `1` = Active - Ledger data being collected (updated within last 60 seconds)
- `0` = Stopped - No new ledger data (stale or missing)

**Detection time**: Up to 60 seconds

**Warning signs**:
- Stopped status → WebSocket stream disconnected or collector not processing events
- Check WebSocket health panel
- Verify rippled is producing ledgers

### Health Monitoring Features

**Auto-Recovery**:
- WebSocket automatically reconnects on failure
- State manager validates directory on startup (fail-fast)
- Exponential backoff prevents connection storms

**State Persistence**:
- Dual-layer backup (VictoriaMetrics + JSON files)
- Automatic recovery on collector restart
- Critical metrics backed up every 5 minutes
- Validation counts persist across restarts

**Failure Detection**:
- 5-10 second detection time for most components
- Graceful degradation (panels show helpful "No Data" messages)
- Cascading failure visibility (Database down affects all panels)

---

# Understanding Metric Relationships

### Validation Rate vs Ledgers Per Minute

These two metrics are related but measure different things:

#### Validation Rate

**Calculation**: `rate(xrpl_validations_total[5m]) * 60`
**Unit**: Rounds per minute (rd/m)

**What it measures**: How many validation messages **YOUR validator** publishes per minute.

**Simple explanation**: Ledgers close every 3-5 seconds, so your validator should send 12-20 validations per minute if healthy. This is your "participation score" showing how consistently you're validating ledgers in real-time.

**Example**: If your validator published 15.1 validations in the last minute, the Validation Rate is 15.1 rd/m.

#### Ledgers Per Minute

**Calculation**: `increase(xrpl_ledger_sequence[1m])`
**Unit**: Ledgers per minute

**What it measures**: How fast the **XRPL network** is closing ledgers (network-wide metric).

**Example**: If the network closed 16 ledgers in the last minute, Ledgers Per Minute is 16.

#### Why They Should Match

**Healthy behavior**: These values should be nearly identical (~94%+ match).

```
Validation Rate:      15.1 rd/m
Ledgers Per Minute:   16.0 ledgers/min
Participation:        94.4% (15.1 / 16.0)
```

This indicates your validator is participating in nearly every ledger consensus round.

#### When They Differ

**Scenario 1: Validation Rate < Ledgers Per Minute**

Your validator is missing some validation rounds.

**Possible causes**:
- Network latency or connectivity issues
- CPU overload causing validation delays
- Sync issues with the network
- Brief outages or restarts

**Action**: Investigate server performance, network connectivity, and logs.

**Scenario 2: Validation Rate ≈ Ledgers Per Minute**

Healthy! Your validator is keeping up with the network.

**Scenario 3: Validation Rate > Ledgers Per Minute**

This should not happen and may indicate:
- Duplicate validations (bug)
- Measurement window mismatch
- Time synchronization issues

**Action**: Check system time (NTP) and monitor logs for errors.

#### Participation Rate

Calculate your validator's participation:

```
Participation % = (Validation Rate / Ledgers Per Minute) × 100
```

**Healthy**: >94%
**Warning**: 80-94% (occasional misses)
**Critical**: <80% (frequent misses, investigate immediately)

---

# State Exporter Metrics

The State Exporter provides real-time state and peer monitoring with ~1 second state latency and ~5 second peer latency, bypassing VictoriaMetrics for instant updates.

### `xrpl_state_realtime_value`

**Type**: Gauge
**Unit**: Numeric state value (0-7)
**Source**: State Exporter (HTTP poll every 1s)
**Port**: 9102

Current validator state as a numeric value. This is the primary metric used by the State panel.

**Value mapping**:
- 0 = DOWN (rippled not responding)
- 1 = DISCONNECTED
- 2 = CONNECTED
- 3 = SYNCING
- 4 = TRACKING
- 5 = FULL
- 6 = VALIDATING
- 7 = PROPOSING

**Why State Exporter exists**: Normal metrics flow through Collector → VictoriaMetrics → Grafana with 20-30 second latency. The State Exporter polls rippled directly every 1 second and implements a Prometheus query API (`/api/v1/query`) that Grafana can query directly, achieving ~1 second state update latency.

### `xrpl_state_realtime`

**Type**: Gauge (per-state)
**Unit**: Boolean (0 or 1)
**Source**: State Exporter (HTTP poll every 1s)
**Port**: 9102

Per-state gauges where the current state has value 1 and all others have value 0.

**Labels**:
- `instance`: Validator instance (default: "validator")
- `state`: State name (down, disconnected, connected, syncing, tracking, full, validating, proposing)

**Example**:
```
xrpl_state_realtime{instance="validator",state="proposing"} 1
xrpl_state_realtime{instance="validator",state="full"} 0
xrpl_state_realtime{instance="validator",state="syncing"} 0
```

### Real-Time Peer Metrics

The State Exporter also provides real-time peer metrics with ~5 second update latency, enabling rapid peer count updates during rippled restarts.

### `xrpl_peer_count_realtime`

**Type**: Gauge
**Unit**: Count
**Source**: State Exporter (HTTP poll every 5s)
**Port**: 9102

Total number of connected peers. Used by the "Total Peers" dashboard panel.

### `xrpl_peers_inbound_realtime`

**Type**: Gauge
**Unit**: Count
**Source**: State Exporter (HTTP poll every 5s)
**Port**: 9102

Number of inbound peer connections (peers that connected TO your validator).

### `xrpl_peers_outbound_realtime`

**Type**: Gauge
**Unit**: Count
**Source**: State Exporter (HTTP poll every 5s)
**Port**: 9102

Number of outbound peer connections (peers your validator connected TO).

### `xrpl_peers_insane_realtime`

**Type**: Gauge
**Unit**: Count
**Source**: State Exporter (HTTP poll every 5s)
**Port**: 9102

Number of peers on a different ledger chain (wrong fork). Usually 0-3 during normal operation.

### `xrpl_peer_latency_p90_realtime`

**Type**: Gauge
**Unit**: Milliseconds
**Source**: State Exporter (HTTP poll every 5s)
**Port**: 9102

P90 (90th percentile) peer latency. Shows the latency that 90% of peers experience or better, filtering out the slowest 10% outliers.

**Example**:
```
xrpl_peer_count_realtime{instance="validator"} 21
xrpl_peers_inbound_realtime{instance="validator"} 11
xrpl_peers_outbound_realtime{instance="validator"} 10
xrpl_peers_insane_realtime{instance="validator"} 1
xrpl_peer_latency_p90_realtime{instance="validator"} 245
```

### Real-Time Server Info Metrics

The State Exporter provides real-time server info metrics for the Release Version and Pubkey dashboard panels. These bypass VictoriaMetrics to avoid the "stale series" issue where both old and new values would briefly display during rippled version changes.

### `xrpl_build_version_realtime`

**Type**: Gauge (info-style with label)
**Unit**: Always 1 (version in label)
**Source**: State Exporter (HTTP poll every 1s)
**Port**: 9102

Current rippled build version. The version is stored in the `version` label.

**Labels**:
- `instance`: Validator instance (default: "validator")
- `version`: rippled version string (e.g., "2.3.0")

**Example**:
```
xrpl_build_version_realtime{instance="validator",version="2.3.0"} 1
```

**Why this exists**: When rippled upgrades, VictoriaMetrics would briefly show both old and new version values as separate time series. The State Exporter always returns only the current value.

### `xrpl_pubkey_realtime`

**Type**: Gauge (info-style with label)
**Unit**: Always 1 (pubkey in label)
**Source**: State Exporter (HTTP poll every 1s)
**Port**: 9102

Current validator public key. The pubkey is stored in the `pubkey` label.

**Labels**:
- `instance`: Validator instance (default: "validator")
- `pubkey`: Validator public key (base58 encoded)

**Example**:
```
xrpl_pubkey_realtime{instance="validator",pubkey="nHD3hEnshArWJFtFoHtDKbMdoTr1FyKTyLWFE55jLM245uAfTa1v"} 1
```

**Why this exists**: Same as build_version - avoids VictoriaMetrics stale series showing both old and new pubkey values during key rotation.

### Upgrade Status Metrics

The State Exporter monitors rippled version status by crawling peer versions and checking for amendment blocking. These metrics power the **Rippled** dashboard panel.

### `xrpl_upgrade_status_realtime`

**Type**: Gauge
**Unit**: Status code (0-3)
**Source**: State Exporter (calculated from peer crawl + server_info)
**Port**: 9102
**Update Frequency**: Every 5 minutes (peer crawl interval)

Combined upgrade status indicating whether your rippled version needs updating.

**Value mapping**:

| Value | Status | Display | Meaning |
|-------|--------|---------|---------|
| 0 | Current | ✅ Current | Running current version, no action needed |
| 1 | Behind | ⚠️ Behind | >60% of peers on newer version, upgrade soon |
| 2 | Blocked | ⛔ Blocked | Amendment blocked, upgrade required |
| 3 | Critical | 🚨 Critical | Both behind AND blocked, upgrade immediately |

**Formula**: `upgrade_status = upgrade_recommended + (amendment_blocked × 2)`

**Detection timing**: Status changes may take 5-7 minutes to reflect due to:
- Peer crawl interval (every 5 minutes)
- rippled amendment_blocked detection time (can take several minutes after restart)

**Example**:
```
xrpl_upgrade_status_realtime{instance="validator"} 0
```

### `xrpl_amendment_blocked_realtime`

**Type**: Gauge
**Unit**: Boolean (0 or 1)
**Source**: State Exporter (from `server_info` API)
**Port**: 9102

Whether rippled is amendment blocked.

**Values**:
- `0` = Not blocked - validator operating normally
- `1` = Blocked - validator non-functional, upgrade required immediately

**What it means**: When an amendment is enabled on the network that your rippled version doesn't support, your node becomes "amendment blocked" and cannot participate in consensus until upgraded.

**Example**:
```
xrpl_amendment_blocked_realtime{instance="validator"} 0
```

### `xrpl_upgrade_recommended_realtime`

**Type**: Gauge
**Unit**: Boolean (0 or 1)
**Source**: State Exporter (calculated from peer version comparison)
**Port**: 9102

Whether an upgrade is recommended based on peer versions.

**Values**:
- `0` = Current - your version matches majority of peers
- `1` = Upgrade recommended - >60% of peers running higher version

**Threshold**: The 60% threshold mirrors rippled's internal upgrade notification logic.

**Example**:
```
xrpl_upgrade_recommended_realtime{instance="validator"} 0
```

### `xrpl_peers_higher_version_realtime`

**Type**: Gauge
**Unit**: Count
**Source**: State Exporter (from `/crawl` endpoint on port 51235)
**Port**: 9102

Number of crawled peers running a higher rippled version than yours.

**Example**:
```
xrpl_peers_higher_version_realtime{instance="validator"} 0
```

### `xrpl_peers_higher_version_pct_realtime`

**Type**: Gauge
**Unit**: Percentage (0-100)
**Source**: State Exporter (calculated from peer crawl)
**Port**: 9102

Percentage of crawled peers running a higher rippled version.

**Example**:
```
xrpl_peers_higher_version_pct_realtime{instance="validator"} 0.0
```

### `xrpl_crawl_peer_count_realtime`

**Type**: Gauge
**Unit**: Count
**Source**: State Exporter (from `/crawl` endpoint on port 51235)
**Port**: 9102

Number of peers discovered via the peer crawl endpoint.

**Note**: This may differ from `xrpl_peer_count_realtime` as `/crawl` returns peers visible to the overlay network, not just direct connections.

**Example**:
```
xrpl_crawl_peer_count_realtime{instance="validator"} 10
```

### Upgrade Status Configuration

To enable peer version crawling, set `PEER_CRAWL_PORT` in your `.env` file:

```bash
PEER_CRAWL_PORT=51235
```

If not set or set to 0, peer version comparison is disabled and only amendment blocking is monitored.

**Port 51235** is the default rippled peer protocol port where the `/crawl` endpoint is available.

---

# Metric Collection Architecture

### Real-time Streams (WebSocket)

**Node State (server stream)**:
- `xrpl_validator_state_value` / `xrpl_server_state`
- `xrpl_validator_state_info`
- `xrpl_time_in_current_state_seconds`
- `xrpl_state_changes_total`

**Validation Tracking (validations stream)**:
- `xrpl_validations_total`
- `xrpl_validation_agreements_*`
- `xrpl_validation_missed_*`

**Ledger Tracking (ledger stream)**:
- `xrpl_ledger_sequence`
- `xrpl_ledger_close_time`

**Latency**: <100ms
**Update frequency**: Event-driven (3-10s typical for state changes, every ledger ~3-5s for ledger events)

### Polling (HTTP API)

**Performance Metrics (`server_info` - every 5s)**:
- `xrpl_peer_count`
- `xrpl_server_load_factor`
- `xrpl_io_latency_ms`
- `xrpl_consensus_converge_time_seconds`
- `xrpl_unl_expiry_days_realtime` (State Exporter)
- `xrpl_peer_disconnects_total`
- `xrpl_peer_disconnects_resources_total`
- `xrpl_server_uptime`
- `xrpl_server_state_duration_seconds`
- `xrpl_validation_quorum`
- `xrpl_proposers`

**Network Metrics (`peers` - every 60s)**:
- `xrpl_peers_count`

**DB State Accounting (`server_state` - every 300s/5min)**:
- `xrpl_state_accounting_duration_seconds{state="..."}`
- `xrpl_state_accounting_transitions{state="..."}`
- `xrpl_ledger_db_bytes`
- `xrpl_ledger_nudb_bytes`
- `xrpl_initial_sync_duration_seconds`

**Update frequency**:
- `server_info`: Every 5s
- `peers`: Every 60s
- `server_state`: Every 300s (5 minutes)

### Filesystem Monitoring

- `xrpl_nudb_size_bytes` (from filesystem scan)
- `xrpl_ledger_db_bytes` (from filesystem scan)

**Update frequency**: Every 300s (5 minutes)

### Process Monitoring

- `xrpl_rippled_cpu_percent`

**Update frequency**: Every 5s

---

# Data Persistence

All metrics are stored in VictoriaMetrics with:

**Retention**: 30 days (configurable in docker-compose.yml)
**Resolution**: Native (no downsampling)

**Validation events** are also persisted individually to enable recovery after monitor restarts:
- Metric: `xrpl_validation_event`
- Labels: `validator_key`, `ledger_sequence`, `ledger_hash`, `timestamp`
- Enables reconstruction of 1h/24h agreement windows after restart

---

# Querying Metrics

### VictoriaMetrics API

Query individual metrics:
```bash
curl "http://localhost:8428/api/v1/query?query=xrpl_ledger_sequence"
```

Query rate calculations:
```bash
curl "http://localhost:8428/api/v1/query?query=rate(xrpl_validations_total[5m])*60"
```

### Grafana

All metrics are available in Grafana via the VictoriaMetrics datasource.

**Dashboard**: `XRPL Validator Monitor`
**URL**: http://localhost:3000 (default)

---

# Troubleshooting

### No data for validation metrics

**Check**:
1. Is `VALIDATOR_PUBLIC_KEY` set in `.env`?
2. Is your validator actively validating?
3. Check monitor logs for validation stream errors

### NuDB size shows 0 or N/A

**Check**:
1. Is `RIPPLED_DATA_PATH` set correctly in `.env`?
2. Does the monitor have read access to the rippled data directory?
3. Check monitor logs for filesystem errors

### CPU metric not updating

**Check**:
1. For Docker: Is `DOCKER_GID` correct in `.env`?
2. For Docker: Is `/var/run/docker.sock` mounted?
3. For Native: Does monitor have permission to read process stats?

### Peer count shows 0

**Check**:
1. Is rippled `peers` API enabled in rippled.cfg?
2. If using Docker fallback: Is `RIPPLED_DOCKER_CONTAINER` set?
3. Check monitor logs for peer collection errors

---

# See Also

- [DOCKER_ADVANCED.md](DOCKER_ADVANCED.md) - Docker deployment guide
- [README.md](README.md) - Project overview and setup
- [Grafana Dashboard](http://localhost:3000) - Live metrics visualization
- [VictoriaMetrics](http://localhost:8428) - Metrics database UI
