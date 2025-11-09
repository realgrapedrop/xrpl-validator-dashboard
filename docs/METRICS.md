# XRPL Validator Dashboard Metrics Guide

## Introduction

This guide provides a comprehensive overview of all metrics displayed in the XRPL Validator Dashboard. Metrics are organized into logical categories to help you quickly assess your validator's health, performance, and network participation.

## Dashboard Overview

![XRPL Validator Dashboard](../images/xrpl-validator-monitor-dashboard-inaction.gif)

The dashboard displays 40+ real-time and historical metrics across 9 rows, organized into 4 main categories:

1. **Infrastructure & System Resources** - Server hardware and OS metrics
2. **Validator Overview** - Identity, status, and ledger information
3. **Validation & Network Performance** - Real-time validation and peer metrics
4. **Historical Trends & Analysis** - Time-series graphs for performance tracking

---

## Color Legend

Dashboard panels use color-coded thresholds to indicate metric health:

| Color | Meaning | Typical Use |
|-------|---------|-------------|
| **Green** | Healthy / Optimal | Validation rate ≥99%, state = proposing/validating |
| **Yellow** | Warning / Degraded | Validation rate 95-99%, moderate load, state = tracking |
| **Red** | Critical / Problem | Validation rate <95%, high load, state = syncing/disconnected |
| **Blue** | Informational | Neutral metrics without health thresholds |

**State-Specific Colors:**
- **Dark Green**: Proposing (state 6) - validator is actively proposing
- **Light Green**: Validating (state 5) - validator is validating
- **Blue**: Tracking/Full (states 3-4) - syncing with network
- **Orange**: Syncing (state 2) - catching up to network
- **Yellow**: Connected (state 1) - connected but not synced
- **Red**: Disconnected (state 0) - no connection to rippled

---

## Category 1: Infrastructure & System Resources

**Location**: Row 1
**Purpose**: Monitor server hardware health and resource utilization

### Quick Reference

| Metric | Description | Healthy Range | Alert If |
|--------|-------------|---------------|----------|
| **Uptime** | Time since validator last restarted | N/A | Frequent restarts |
| **CPU Usage** | Processor utilization | <60% | >80% sustained |
| **Memory Usage** | RAM utilization | <70% | >85% |
| **Disk Usage** | Storage capacity used | <80% | >90% |
| **Network I/O** | Inbound/outbound bandwidth | Varies | Sudden drops |

### Metrics Detail

#### Uptime
- **Format**: Human-readable duration (e.g., "3d 14h 27m")
- **What it means**: How long rippled has been running without restart
- **Why it matters**: Frequent restarts may indicate stability issues
- **Typical value**: Days to weeks (longer is generally better)

#### CPU Load
- **Format**: Percentage (0-100%)
- **What it means**: Current processor utilization
- **Why it matters**: High CPU can slow validation and consensus
- **Typical value**: 20-50% (varies by hardware and network activity)
- **Thresholds**:
  - Green: <60%
  - Yellow: 60-80%
  - Red: >80%

#### Memory Usage
- **Format**: Percentage (0-100%)
- **What it means**: RAM utilization
- **Why it matters**: Low memory can cause swapping and performance degradation
- **Typical value**: 40-70% (depends on rippled configuration)
- **Action needed**: If consistently >85%, consider adding RAM

#### Disk Usage
- **Format**: Percentage (0-100%)
- **What it means**: Storage capacity used
- **Why it matters**: Full disk can halt rippled and cause data corruption
- **Typical value**: Increases gradually as ledger history grows
- **Action needed**: If >90%, clean old ledgers or expand storage

#### Network Traffic
- **Format**: Mbps (megabits per second) or Bps (bytes per second)
- **What it means**: Data transfer rate in/out of validator
- **Why it matters**: Network issues can cause consensus problems
- **Typical value**: 1-10 Mbps (varies by peer count and network activity)

---

## Category 2: Validator Overview

### Row 2: Identity & Status

**Purpose**: Core validator identification and operational status

| Metric | Description | Healthy Value | Alert If |
|--------|-------------|---------------|----------|
| **State** | Current server state | Proposing (6) or Validating (5) | <5 for >1 minute |
| **Validation Rate** | % of ledgers successfully validated | ≥99% | <95% |
| **Release Version** | rippled software version | Latest stable | Outdated by >2 versions |
| **Pubkey** | Validator public key | Your key | Unexpected change |
| **XRP Fees (USD)** | Transaction cost in dollars | N/A | Dramatic spikes |

#### State
- **Values**: 0-6 (disconnected → proposing)
  - **6 = Proposing** (optimal): Actively participating in consensus
  - **5 = Validating** (optimal): Validating ledgers
  - **4 = Full** (acceptable): Synced with full history
  - **3 = Tracking** (acceptable): Following network without full history
  - **2 = Syncing** (warning): Catching up to network
  - **1 = Connected** (warning): Connected but not synced
  - **0 = Disconnected** (critical): No connection

**What's normal**: Should remain at 5-6 during normal operation. Brief drops to 3-4 during high network activity are acceptable.

**Investigate if**: State drops below 3 for more than 1 minute, or frequently oscillates between states.

#### Validation Rate
- **Format**: Percentage (0-100%)
- **What it means**: Proportion of ledgers where your validator successfully validated
- **Target**: ≥99.5% is excellent, ≥99% is good
- **Why it matters**: Low rates indicate your validator is missing ledgers (network issues, resource constraints, or misconfiguration)
- **Thresholds**:
  - Green: ≥99%
  - Yellow: 95-99%
  - Red: <95%

#### Release Version
- **Format**: Semantic version (e.g., "2.2.0")
- **What it means**: Your currently running rippled version
- **Why it matters**: Outdated versions may have security vulnerabilities or miss new features
- **Action needed**: Update within 1-2 releases of latest stable version

#### Pubkey (Validator Public Key)
- **Format**: Base58-encoded string starting with "nH"
- **What it means**: Your validator's unique identifier on the network
- **Why it matters**: Used by others to add you to their UNL (Unique Node List)
- **Verification**: Should match your `validator-keys.json` public key

#### XRP Fees (USD)
- **Format**: Dollar amount (e.g., "$0.00001")
- **What it means**: Current cost to submit a transaction, converted to USD
- **Why it matters**: Tracks transaction cost changes (note: requires external price feed)
- **Typical value**: Fractions of a cent during normal operation

---

### Row 3: Ledger & Database

**Purpose**: Ledger progression and database health

| Metric | Description | Healthy Value | Alert If |
|--------|-------------|---------------|----------|
| **Current Ledger** | Latest validated ledger number | Incrementing | Stalled for >30s |
| **Ledger Age** | Time since last ledger close | <10 seconds | >30 seconds |
| **Ledgers/Min** | Ledger validation rate | 15-20/min | <10/min |
| **Load Factor** | Server load multiplier | 1 | >10 sustained |
| **Validations Checked** | Total validations processed | Increasing | Stalled |
| **Peer Latency (P90)** | 90th percentile peer latency | <200ms | >400ms |
| **Ledger DB** | Ledger database size | Growing slowly | Sudden jumps |
| **Ledger NuDB** | NuDB storage size | Growing slowly | Sudden jumps |

#### Current Ledger
- **Format**: Integer (e.g., 92,847,123)
- **What it means**: Sequence number of the most recently validated ledger
- **Why it matters**: Should increment every 3-5 seconds; stalls indicate problems
- **Monitor**: Should be close to the network's current ledger (check xrpscan.com)

#### Ledger Age
- **Format**: Seconds
- **What it means**: How old the current validated ledger is
- **Why it matters**: Fresh ledgers (<10s) mean you're in sync with the network
- **Thresholds**:
  - Green: <10 seconds
  - Yellow: 10-30 seconds
  - Red: >30 seconds
- **Action needed**: If consistently yellow/red, check network connectivity and CPU load

#### Ledgers Per Minute
- **Format**: Number (e.g., 17.2)
- **What it means**: Rate at which ledgers are being validated
- **Why it matters**: XRPL targets 3-5 second ledger close times (12-20 ledgers/min)
- **Typical value**: 15-20 ledgers/min
- **Concern if**: <10/min sustained

#### Load Factor
- **Format**: Integer (typically 1-1000+)
- **What it means**: Server load multiplier (affects transaction fee requirements)
- **Why it matters**: Values >1 indicate server is under stress
- **Thresholds**:
  - Green: 1 (normal)
  - Yellow: 2-10 (moderate load)
  - Red: >10 (high load)
- **Typical value**: Should be 1 most of the time
- **Action needed**: If frequently >1, investigate CPU/memory/disk bottlenecks

#### Validations Checked
- **Format**: Count (resets on monitor restart)
- **What it means**: Total number of validation messages processed by the monitor
- **Why it matters**: Should steadily increase; indicates monitor is receiving data
- **Note**: This is a monitor metric, not a rippled metric

#### Peer Latency (P90)
- **Format**: Milliseconds
- **What it means**: 90% of your peers have latency below this value
- **Why it matters**: High latency can delay consensus participation
- **Thresholds**:
  - Green: <200ms
  - Yellow: 200-400ms
  - Red: >400ms
- **Typical value**: 50-150ms
- **Action needed**: If consistently red, check network quality or peer selection

#### Ledger DB Size
- **Format**: Bytes (displayed as GB)
- **What it means**: Size of the SQLite ledger database on disk
- **Why it matters**: Grows over time; monitor for capacity planning
- **Growth rate**: ~1-5 GB per month (depends on history retention)
- **Action needed**: Configure `online_delete` in rippled.cfg to limit growth

#### Ledger NuDB Size
- **Format**: Bytes (displayed as GB)
- **What it means**: Size of the NuDB key-value store (transaction/account data)
- **Why it matters**: Larger database means more disk I/O
- **Typical size**: 10-50 GB (depends on online_delete settings)
- **Action needed**: Same as Ledger DB - configure retention policies

---

## Category 3: Validation & Network Performance

### Row 4: 1-Hour Validation Window

**Purpose**: Short-term validation performance and peer health

| Metric | Description | Healthy Value | Alert If |
|--------|-------------|---------------|----------|
| **Agreements % (1h)** | % of ledgers agreed with consensus | ≥99% | <95% |
| **Agreements (1h)** | Total ledgers agreed in last hour | ~900-1200 | <500 |
| **Missed (1h)** | Ledgers missed/disagreed | 0-5 | >20 |
| **Total Peers** | Current peer connections | 10-30 | <5 or >50 |

#### Agreements % (1h)
- **Format**: Percentage (0-100%)
- **What it means**: What proportion of ledgers your validator agreed with consensus (last 60 minutes)
- **Why it matters**: Direct measure of validation quality
- **Thresholds**:
  - Green: ≥99%
  - Yellow: 95-99%
  - Red: <95%
- **Expected value**: 99-100% during normal operation
- **Action needed**: If <99%, investigate network connectivity, CPU load, or clock synchronization

#### Agreements (1h)
- **Format**: Count
- **What it means**: Absolute number of ledgers where you agreed with consensus (last 60 minutes)
- **Why it matters**: Context for the percentage - 99% of 1000 ledgers vs 99% of 100 ledgers
- **Expected value**: ~900-1200 (15-20 ledgers/min × 60 min)
- **Has sparkline**: Shows trend over time

#### Missed (1h)
- **Format**: Count
- **What it means**: Number of ledgers where your validator disagreed or didn't validate (last 60 minutes)
- **Why it matters**: Even small numbers can indicate intermittent issues
- **Thresholds**:
  - Green: 0-1
  - Yellow: 2-5
  - Red: >5
- **Expected value**: 0-5 (occasional misses are normal)
- **Investigate if**: Consistently >10, or sudden spikes

#### Total Peers
- **Format**: Count
- **What it means**: Number of peer rippled servers currently connected
- **Why it matters**: Too few peers = network isolation risk; too many = resource waste
- **Thresholds**:
  - Red: <5 (isolation risk)
  - Yellow: 5-10 (minimal but acceptable)
  - Green: >10 (healthy)
- **Typical value**: 10-30 peers
- **Optimal**: 15-25 peers with diverse geography and operators
- **Configure**: Set `peers_max` in rippled.cfg (default: 21)

---

### Row 5: 24-Hour Validation & Network Activity

**Purpose**: Long-term trends and comprehensive network health

| Metric | Description | Healthy Value | Alert If |
|--------|-------------|---------------|----------|
| **Agreements % (24h)** | 24-hour consensus agreement rate | ≥99% | <95% |
| **Agreements (24h)** | Total ledgers agreed (24h) | ~21,600-28,800 | <15,000 |
| **Missed (24h)** | Ledgers missed (24h) | 0-50 | >500 |
| **Transaction Rate** | Transactions processed per second | Varies (0-50) | N/A |
| **Inbound Peers** | Incoming peer connections | 5-20 | N/A |
| **Proposers** | Validators currently proposing | 20-35 | <15 |
| **Outbound Peers** | Outgoing peer connections | 5-15 | N/A |
| **Quorum** | Validation quorum size | 20-30 | <15 |
| **Insane Peers** | Peers with bad behavior | 0 | >0 |
| **Consensus Time** | Average time to reach consensus | 2-4 seconds | >6 seconds |
| **Peer Disconnects** | Rate of peer disconnections | <0.01/sec | >0.1/sec |
| **Job Queue** | Queued background jobs | 0 | >10 sustained |

#### Agreements % (24h)
- **Format**: Percentage (0-100%)
- **What it means**: Validation agreement rate over 24 hours (more stable than 1h metric)
- **Why it matters**: Better indicator of overall validator reliability
- **Target**: ≥99.5% is excellent
- **Thresholds**: Same as 1-hour metric

#### Agreements (24h) & Missed (24h)
- **Expected agreements**: ~21,600-28,800 (15-20 ledgers/min × 1440 min)
- **Expected misses**: <50 (represents <0.2% miss rate)
- **Use case**: Long-term performance tracking and SLA monitoring

#### Transaction Rate
- **Format**: Transactions per second
- **What it means**: Network-wide transaction processing rate
- **Why it matters**: Indicates network activity level (not validator-specific)
- **Typical value**: 5-20 TPS during normal operation, spikes during high activity
- **Note**: This is informational only - not a validator health metric

#### Inbound Peers
- **Format**: Count
- **What it means**: Peers that connected TO your validator
- **Why it matters**: Indicates your validator is reachable from the network
- **Typical value**: 5-20
- **Concern if**: Always 0 (may indicate firewall/NAT issues)

#### Proposers
- **Format**: Count
- **What it means**: Number of validators actively proposing in the current round
- **Why it matters**: Network health indicator - low count suggests network issues
- **Thresholds**:
  - Yellow: <20 proposers
  - Green: ≥20 proposers
- **Typical value**: 20-35 validators
- **Network issue if**: <15 sustained

#### Outbound Peers
- **Format**: Count
- **What it means**: Peers YOUR validator connected to
- **Typical value**: 5-15
- **Configure**: Managed by rippled based on `[ips]` and `[ips_fixed]` in config

#### Quorum
- **Format**: Count
- **What it means**: Number of validations needed to reach consensus
- **Why it matters**: Lower quorum = faster consensus but less security
- **Thresholds**:
  - Red: <15 (potential network partition)
  - Green: ≥20
- **Typical value**: 20-30
- **Formula**: Usually ~80% of trusted validators in UNL

#### Insane Peers
- **Format**: Count
- **What it means**: Peers reporting impossible/contradictory ledger data
- **Why it matters**: Indicates compromised nodes or network attacks
- **Thresholds**:
  - Green: 0 (always)
  - Yellow: 1
  - Red: ≥2
- **Expected value**: 0 always
- **Action needed**: If >0, investigate peer list and consider blocking bad peers

#### Consensus Time
- **Format**: Seconds
- **What it means**: Average time to reach consensus on a ledger
- **Why it matters**: Longer times indicate network disagreement or latency issues
- **Thresholds**:
  - Green: <5 seconds
  - Yellow: 5-8 seconds
  - Red: >8 seconds
- **Typical value**: 2-4 seconds
- **Network-wide metric**: Not specific to your validator

#### Peer Disconnects
- **Format**: Operations per second (rate)
- **What it means**: How often peer connections are dropping
- **Why it matters**: Frequent disconnects suggest network instability
- **Typical value**: <0.01/sec (occasional disconnects are normal)
- **Concern if**: >0.1/sec sustained

#### Job Queue
- **Format**: Count
- **What it means**: Number of background tasks waiting to execute
- **Why it matters**: High queue depth indicates server overload
- **Thresholds**:
  - Green: 0
  - Yellow: 1-10
  - Red: >10
- **Expected value**: 0-2 most of the time
- **Action needed**: If consistently >10, upgrade hardware or reduce load

---

## Category 4: Historical Trends & Analysis

**Purpose**: Time-series graphs for identifying patterns, trends, and anomalies

### Row 6: CPU & Network Activity

| Graph | What It Shows | Look For |
|-------|---------------|----------|
| **Validator CPU Load** | CPU usage % over time | Spikes, sustained high usage, correlations with events |
| **Network TCP In/Out** | Inbound/outbound bandwidth | Drops (connection loss), spikes (DDoS?), asymmetry |
| **Activity Rates** | Validations/sec, state changes/sec, alerts/sec | Gaps (downtime), alert spikes |

#### Validator CPU Load
- **Pattern to expect**: Relatively stable with minor fluctuations (±10-20%)
- **Spikes are normal**: During state transitions or high network activity
- **Investigate if**:
  - Sustained >80% usage
  - Sudden drops to 0% (process crash?)
  - Sawtooth pattern (memory leak causing restarts?)

#### Network TCP In/Out
- **Pattern to expect**: Symmetrical in/out with steady baseline
- **Typical bandwidth**: 1-10 Mbps depending on peer count
- **Investigate if**:
  - Sudden drops to zero (network outage)
  - In/out highly asymmetrical (routing issue?)
  - Unusual spikes (DDoS attempt?)

#### Activity Rates
- **Validations/sec**: Should be steady ~0.25-0.35/sec (15-20/min)
- **State changes/sec**: Should be near-zero (only changes on state transitions)
- **Alerts/sec**: Should be near-zero (spikes indicate issues)

---

### Row 7: Load & Transactions

| Graph | What It Shows | Look For |
|-------|---------------|----------|
| **Load Factor Over Time** | Server load multiplier history | Frequent spikes above 1, correlations with other metrics |
| **Transaction Rate** | Network TPS over time | Daily patterns, unusual spikes/drops |
| **Agreement % Trend** | Validation agreement rate (1h) | Dips below 99%, extended periods of poor performance |
| **IO Latency** | Disk I/O latency | Increasing trend, spikes >100ms |

#### Load Factor Over Time
- **Ideal**: Flat line at 1.0
- **Acceptable**: Brief spikes to 2-5 during network congestion
- **Investigate if**: Frequently >10, or sustained >2

#### Transaction Rate
- **Pattern**: Shows network-wide activity cycles (higher during business hours)
- **Not validator-specific**: This is a network metric
- **Use for**: Correlating validator performance with network load

#### Agreement % Trend
- **Should be**: Flat line at 99-100%
- **Brief dips OK**: Occasional drops to 97-98% during network events
- **Investigate if**: Extended periods <99%, or frequent oscillations

#### IO Latency
- **Typical**: 1-10ms for SSD, 10-50ms for HDD
- **Trending up?**: May indicate disk aging or increasing DB size
- **Spikes >100ms**: Can cause validation delays
- **Action needed**: Consider faster storage or DB optimization

---

### Row 8: Validation & Consensus Trends

| Graph | What It Shows | Look For |
|-------|---------------|----------|
| **Validation Rate** | Validations processed per minute | Gaps (downtime), rate changes |
| **Consensus Converge Time** | Time to reach consensus on each ledger | Increasing trend, spikes >6s |
| **Peer Count Over Time** | Number of connected peers | Drops below 10, sudden changes |

#### Validation Rate
- **Expect**: Steady line at 15-20 validations/min
- **Gaps indicate**: Monitor downtime or data collection issues
- **Rate changes**: May reflect network fork or consensus changes

#### Consensus Converge Time
- **Typical**: 2-4 seconds per ledger
- **Network metric**: Reflects overall network health
- **Investigate if**: Sustained >6 seconds (network issues or attack)

#### Peer Count Over Time
- **Should be**: Relatively stable
- **Gradual changes**: Normal as peers come and go
- **Sudden drops**: Network issues, firewall changes, or configuration problems
- **Investigate if**: Drops below 5 peers

---

### Row 9: System Resources

| Graph | What It Shows | Look For |
|-------|---------------|----------|
| **Basic CPU/Mem/Net/Disk** | Combined system metrics | Resource bottlenecks, correlated issues |

#### Combined System View
- **Purpose**: See all resource metrics in one place for correlation analysis
- **Example patterns**:
  - High CPU + high network = heavy processing load
  - High disk + low CPU = I/O bottleneck
  - High memory + increasing disk = potential memory leak
- **Use for**: Root cause analysis when investigating performance issues

---

## Interpreting Dashboard Colors

### Green Dashboard = Healthy Validator
- State: Proposing or Validating
- Validation rate: 99-100%
- Load factor: 1
- Peer count: 10-30
- Missed validations: 0-5 (1h)
- Insane peers: 0
- Job queue: 0

### Yellow/Orange = Warning Signs
- State: Tracking or Full (acceptable) or Syncing (warning)
- Validation rate: 95-99%
- Load factor: 2-10
- Peer count: 5-10
- Review logs and metrics for root cause

### Red = Immediate Attention Required
- State: Connected or Disconnected
- Validation rate: <95%
- Load factor: >10
- Peer count: <5
- Insane peers: >0
- Job queue: >10
- Check: Network connectivity, system resources, rippled logs

---

## Quick Health Checklist

Use this checklist to verify your validator is healthy:

- [ ] **State** = Proposing (6) or Validating (5)
- [ ] **Validation Rate** ≥99%
- [ ] **Agreements (1h)** ~900-1200, **Missed (1h)** <10
- [ ] **Ledger Age** <10 seconds
- [ ] **Load Factor** = 1
- [ ] **Total Peers** ≥10
- [ ] **Insane Peers** = 0
- [ ] **Job Queue** = 0
- [ ] **CPU Load** <60%
- [ ] **Disk Usage** <80%
- [ ] **No sustained red/yellow panels**

**All checked?** Your validator is healthy!

**Some unchecked?** Review the relevant metric sections above for guidance.

---

## Related Documentation

- **[GRAFANA_DASHBOARD.md](GRAFANA_DASHBOARD.md)** - Detailed panel configuration and PromQL queries
- **[HOW_IT_WORKS.md](HOW_IT_WORKS.md)** - Architecture and data flow
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
- **[TIPS.md](TIPS.md)** - Optimization and best practices

---

**Document Version**: 1.0
**Last Updated**: November 9, 2025
**Metrics Documented**: 40+
**Categories**: 4
