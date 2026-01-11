# **__PERFORMANCE TUNING GUIDE__**

*Optimize XRPL Validator Monitor for your specific hardware and workload.*

---

# Table of Contents

- [Quick Start](#quick-start)
- [Resource Limits Tuning](#resource-limits-tuning)
- [VictoriaMetrics Optimization](#victoriametrics-optimization)
- [Grafana Performance](#grafana-performance)
- [Collector Configuration](#collector-configuration)
- [Log Verbosity & Storage](#log-verbosity--storage)
- [Disk I/O Optimization](#disk-io-optimization)
- [Network Tuning](#network-tuning)
- [rippled online_delete Tuning](#rippled-online_delete-tuning)
- [Monitoring Your Monitor](#monitoring-your-monitor)
- [Common Scenarios](#common-scenarios)
- [Troubleshooting Performance Issues](#troubleshooting-performance-issues)

---

# Quick Start

**In This Section:**
- [Check Current Resource Usage](#check-current-resource-usage)
- [Apply Tuning Changes](#apply-tuning-changes)

---

### Check Current Resource Usage

```bash
# View all container resource usage
docker stats --no-stream | grep xrpl-monitor

# Check specific container
docker stats --no-stream xrpl-monitor-grafana

# View disk usage
docker exec xrpl-monitor-victoria du -sh /victoria-metrics-data
```

### Apply Tuning Changes

After editing configuration files:

```bash
# For docker-compose.yml changes
docker compose up -d

# For environment variable changes
docker compose restart <container-name>

# To recreate a specific container
docker compose up -d --force-recreate <container-name>
```

---

# Resource Limits Tuning

Resource limits prevent containers from consuming excessive resources and protect your rippled validator.

**In This Section:**
- [Configuration File](#configuration-file)
- [Default Limits (Optimized - Recommended)](#default-limits-optimized---recommended)
- [Tuning for Different Hardware](#tuning-for-different-hardware)
- [CPU vs Memory Trade-offs](#cpu-vs-memory-trade-offs)
- [Apply Changes](#apply-changes)

---

### Configuration File

**Edit:** `docker-compose.yml` (project root)

### Default Limits (Optimized - Recommended)

These are the tested, optimized defaults that provide excellent performance:

```yaml
services:
  # Grafana - Dashboard visualization
  grafana:
    cpus: "2.0"
    mem_limit: "1g"

  # Node Exporter - System metrics
  node-exporter:
    cpus: "0.2"
    mem_limit: "128m"

  # Uptime Exporter - rippled uptime
  uptime-exporter:
    cpus: "0.1"
    mem_limit: "128m"

  # VictoriaMetrics - Time-series database (HIGH-PERFORMANCE CONFIG)
  victoria-metrics:
    # Memory limits set via command args (see VictoriaMetrics section)
    command:
      - '--memory.allowedBytes=512MB'      # Optimized for performance
      - '--search.maxMemoryPerQuery=100MB' # Supports complex queries
      - '--storage.cacheSizeIndexDBIndexBlocks=64MB'
      - '--storage.cacheSizeIndexDBDataBlocks=64MB'
      - '--storage.cacheSizeStorageTSID=64MB'
```

**Proven Performance (Measured):**
- Cache hit rate: 98.6% (3.2% improvement over 256MB config)
- CPU usage: 51% lower than baseline (3.98% → 1.95%)
- Memory cost: Only +27 MB for 2x cache size
- Query speed: 3.2% fewer disk reads

### Tuning for Different Hardware

#### Low-Resource Systems (2-4 GB RAM)

If running on a small VPS or limited hardware:

```yaml
  grafana:
    cpus: "1.0"          # Reduce to 1 core
    mem_limit: "512m"    # Reduce to 512 MB

  victoria-metrics:
    command:
      - '--memory.allowedBytes=128MB'      # Reduce cache
      - '--search.maxMemoryPerQuery=25MB'  # Reduce query memory
      - '--storage.cacheSizeIndexDBIndexBlocks=16MB'
      - '--storage.cacheSizeIndexDBDataBlocks=16MB'
```

**Trade-off:** Slower query performance, less concurrent viewers

#### High-Resource Systems (16+ GB RAM)

If you have plenty of resources and want maximum performance:

```yaml
  grafana:
    cpus: "4.0"          # Increase for multiple concurrent viewers
    mem_limit: "2g"      # More memory for complex queries

  victoria-metrics:
    command:
      - '--memory.allowedBytes=512MB'      # Larger cache
      - '--search.maxMemoryPerQuery=100MB' # Support complex queries
      - '--storage.cacheSizeIndexDBIndexBlocks=64MB'
      - '--storage.cacheSizeIndexDBDataBlocks=64MB'
```

**Benefit:** Faster queries, more concurrent viewers, better caching

#### Production Public Dashboards

For public-facing deployments (like Cloudflare setup):

```yaml
  grafana:
    cpus: "4.0"          # Handle traffic spikes
    mem_limit: "4g"      # Large safety margin

  victoria-metrics:
    command:
      - '--memory.allowedBytes=1GB'        # Large cache for frequent queries
      - '--search.maxMemoryPerQuery=200MB' # Support heavy concurrent load
```

### CPU vs Memory Trade-offs

| Resource | Low | Medium (Recommended) | High | Use Case |
|----------|-----|----------------------|------|----------|
| **Grafana CPU** | 1.0 | 2.0 | 4.0 | Single user / Dev / Production |
| **Grafana RAM** | 512MB | 1GB | 2-4GB | Light / Normal / Heavy load |
| **VM Memory** | 128MB | **512MB** ⭐ | 1GB | Minimal / **Optimized** / Maximum |

⭐ **512MB is now the recommended default** based on proven 51% CPU reduction and 98.6% cache hit rate.

### Apply Changes

```bash
# Edit docker-compose.yml with your desired limits (in project root)
nano docker-compose.yml

# Recreate containers with new limits
docker compose up -d

# Verify new limits
docker inspect xrpl-monitor-grafana | grep -A 5 "Memory\|Cpu"
```

---

# VictoriaMetrics Optimization

VictoriaMetrics is the time-series database - optimizing it improves query speed and reduces disk usage.

**In This Section:**
- [Configuration File](#configuration-file-1)
- [Key Parameters](#key-parameters)
- [Example Configurations](#example-configurations)
- [Apply VictoriaMetrics Changes](#apply-victoriametrics-changes)

---

### Configuration File

**Edit:** `docker-compose.yml` (project root) under `victoria-metrics` service `command:` section

### Key Parameters

#### Data Retention

```yaml
- '--retentionPeriod=30d'  # How long to keep metrics
```

**Options:**
- `7d` - One week (minimal disk usage)
- `30d` - One month (default, balanced)
- `90d` - Three months (better historical analysis)
- `1y` - One year (maximum historical data)

**Disk Impact:**
- 30 days: ~290 MB
- 90 days: ~870 MB
- 1 year: ~3.5 GB

**Recommendation:**
- Development: 30d
- Production: 90d-180d
- Demo/Showcase: 90d-1y

#### Memory Configuration

```yaml
# Total memory VictoriaMetrics can use
- '--memory.allowedBytes=256MB'

# Memory per query (prevents expensive queries from OOM)
- '--search.maxMemoryPerQuery=50MB'
```

**Tuning Guide:**

| System RAM | allowedBytes | maxMemoryPerQuery | Notes |
|------------|--------------|-------------------|-------|
| < 4 GB | 128MB | 25MB | Minimal |
| 4-8 GB | 256MB | 50MB | Default |
| 8-16 GB | 512MB | 100MB | Recommended |
| 16+ GB | 1GB | 200MB | High performance |

#### Cache Tuning

```yaml
# Index cache (faster label lookups)
- '--storage.cacheSizeIndexDBIndexBlocks=32MB'
- '--storage.cacheSizeIndexDBDataBlocks=32MB'

# Time series ID cache (faster metric queries)
- '--storage.cacheSizeStorageTSID=32MB'
```

**Performance Impact:**
- Larger cache = faster queries, more memory
- Smaller cache = slower queries, less memory

**Recommendations:**

| Performance Goal | Index Blocks | Data Blocks | TSID | Total Cache |
|------------------|--------------|-------------|------|-------------|
| Minimal | 16MB | 16MB | 16MB | 48MB |
| Balanced | 32MB | 32MB | 32MB | 96MB |
| Fast | 64MB | 64MB | 64MB | 192MB |
| Maximum | 128MB | 128MB | 128MB | 384MB |

### Example Configurations

#### Minimal (Low-Resource VPS)

```yaml
victoria-metrics:
  command:
    - '--storageDataPath=/victoria-metrics-data'
    - '--retentionPeriod=7d'
    - '--httpListenAddr=:8428'
    - '--memory.allowedBytes=128MB'
    - '--search.maxMemoryPerQuery=25MB'
    - '--storage.cacheSizeIndexDBIndexBlocks=16MB'
    - '--storage.cacheSizeIndexDBDataBlocks=16MB'
    - '--storage.cacheSizeStorageTSID=16MB'
```

#### Balanced (Default - Recommended)

```yaml
victoria-metrics:
  command:
    - '--storageDataPath=/victoria-metrics-data'
    - '--retentionPeriod=30d'
    - '--httpListenAddr=:8428'
    - '--memory.allowedBytes=256MB'
    - '--search.maxMemoryPerQuery=50MB'
    - '--storage.cacheSizeIndexDBIndexBlocks=32MB'
    - '--storage.cacheSizeIndexDBDataBlocks=32MB'
    - '--storage.cacheSizeStorageTSID=32MB'
```

#### High-Performance (Production)

```yaml
victoria-metrics:
  command:
    - '--storageDataPath=/victoria-metrics-data'
    - '--retentionPeriod=90d'
    - '--httpListenAddr=:8428'
    - '--memory.allowedBytes=512MB'
    - '--search.maxMemoryPerQuery=100MB'
    - '--storage.cacheSizeIndexDBIndexBlocks=64MB'
    - '--storage.cacheSizeIndexDBDataBlocks=64MB'
    - '--storage.cacheSizeStorageTSID=64MB'
    - '--search.maxConcurrentRequests=16'
    - '--search.maxQueueDuration=30s'
```

### Apply VictoriaMetrics Changes

```bash
# Edit docker-compose.yml (in project root)
nano docker-compose.yml

# Restart VictoriaMetrics (queries will briefly pause)
docker compose restart victoria-metrics

# Verify settings
docker logs xrpl-monitor-victoria | grep -E "memory|cache|retention"
```

---

# Grafana Performance

Grafana serves the dashboards - optimize for responsiveness and concurrent viewers.

**In This Section:**
- [Configuration Files](#configuration-files)
- [Resource Allocation](#resource-allocation)
- [Dashboard Refresh Rate](#dashboard-refresh-rate)
- [Query Timeout](#query-timeout)
- [Concurrent Connections](#concurrent-connections)

---

### Configuration Files

- `docker-compose.yml` (project root) - Resource limits
- Environment variables in `docker-compose.yml`

### Resource Allocation

```yaml
grafana:
  cpus: "2.0"      # CPU cores
  mem_limit: "1g"  # Memory limit
```

**Tuning Guide:**

| Use Case | CPU | Memory | Reasoning |
|----------|-----|--------|-----------|
| Single user (dev) | 1.0 | 512MB | Light load |
| Normal usage | 2.0 | 1GB | Default, balanced |
| Multiple viewers | 4.0 | 2GB | Concurrent users |
| Public dashboard | 4.0 | 4GB | High traffic, safety margin |

### Dashboard Refresh Rate

**Edit:** Dashboard settings or `docker-compose.yml` (project root) environment

```yaml
environment:
  - GF_DASHBOARDS_MIN_REFRESH_INTERVAL=1s  # Minimum allowed refresh rate
```

**Options:**
- `1s` - Real-time monitoring (current default)
- `5s` - Balanced (reduces query load)
- `10s` - Conservative (minimal load)

**Trade-off:**
- Lower interval = more real-time, higher load
- Higher interval = less load, delayed updates

**Change in Dashboard:**
1. Open dashboard
2. Click time range picker (top right)
3. Set "Refresh" to desired interval
4. Save dashboard

### Query Timeout

```yaml
environment:
  - GF_DATAPROXY_TIMEOUT=90s           # Total query timeout
  - GF_DATAPROXY_DIAL_TIMEOUT=10s      # Connection timeout
  - GF_DATAPROXY_KEEP_ALIVE_SECONDS=120
```

**When to increase:**
- Large time ranges (30d, 90d queries)
- Complex aggregations
- Timeout errors in Grafana

**Recommendation:**
- Default: 90s
- Heavy queries: 120s-180s

### Concurrent Connections

```yaml
environment:
  - GF_DATAPROXY_MAX_CONNS_PER_HOST=256      # Max connections to data source
  - GF_DATAPROXY_MAX_IDLE_CONNECTIONS=512    # Connection pool size
```

**When to increase:**
- Multiple concurrent viewers
- Many panels refreshing simultaneously
- Public dashboards

---

# Collector Configuration

The collector gathers metrics from rippled - adjust polling intervals based on your needs.

**In This Section:**
- [Configuration File](#configuration-file-2)
- [Default Configuration](#default-configuration)
- [Logging Levels](#logging-levels)
- [Reduce Collector Load](#reduce-collector-load)

---

### Configuration File

**Edit:** `.env` (project root)

### Default Configuration

```bash
# rippled connection
RIPPLED_WS_URL=ws://localhost:6006
RIPPLED_HTTP_URL=http://localhost:5005

# VictoriaMetrics endpoint
VICTORIA_METRICS_URL=http://localhost:8428

# Polling intervals (not directly configurable in current version)
# HTTP polling: 5 seconds (server_info)
# HTTP polling: 60 seconds (peers)
# HTTP polling: 5 minutes (server_state, db size)
# WebSocket: Real-time (instant event delivery)

# Logging
LOG_LEVEL=INFO
```

### Logging Levels

```bash
LOG_LEVEL=INFO  # Default, balanced
```

**Options:**
- `DEBUG` - Verbose, useful for troubleshooting
- `INFO` - Standard, recommended
- `WARNING` - Minimal, only warnings/errors
- `ERROR` - Critical only

**Impact:**
- `DEBUG` increases CPU/memory slightly due to logging overhead
- `WARNING`/`ERROR` reduces log file size

### Reduce Collector Load

If collector is using too much CPU/memory:

```yaml
collector:
  cpus: "0.5"      # Limit CPU usage
  mem_limit: "128m" # Limit memory
```

**Trade-off:** May slow down metric processing during high validator activity

---

# Log Verbosity & Storage

Understanding log output rates and storage requirements helps you plan capacity and adjust verbosity for your deployment.

**In This Section:**
- [Current Configuration](#current-configuration)
- [Log Output Analysis](#log-output-analysis)
- [Storage Projections](#storage-projections)
- [Changing Log Levels](#changing-log-levels)
- [Impact of Different Log Levels](#impact-of-different-log-levels)
- [Recommendations](#recommendations)

---

### Current Configuration

XRPL Monitor uses Docker's built-in log rotation to automatically manage container logs:

**Docker Log Driver Settings:**
```yaml
# Applied to all containers in docker-compose.yml
logging:
  driver: json-file
  options:
    max-size: "50m"     # Maximum size per log file
    max-file: "3"       # Number of rotated files to keep
```

**Effective Limits:**
- Maximum per log file: 50 MB
- Maximum rotated files: 3
- **Maximum per container: 150 MB** (50 MB × 3 files)
- System maximum: ~1.03 GB (7 containers × 150 MB)

**Log Level Configuration:**

Edit `.env` (project root):
```bash
LOG_LEVEL=INFO  # Default setting
```

### Log Output Analysis

Based on real-world measurements over 1 hour of operation:

**Verbosity by Container:**

| Container | Output Rate | % of Total | Time to 150MB Cap |
|-----------|-------------|------------|-------------------|
| **collector** | 152 KB/hour | 43.5% | ~42 days |
| **grafana** | 115 KB/hour | 32.8% | ~56 days |
| **uptime-exporter** | 80 KB/hour | 22.9% | ~80 days |
| **autoheal** | 3 KB/hour | 0.8% | ~6 years |
| **victoria-metrics** | 0 KB/hour | 0% | Never |
| **vmagent** | 0 KB/hour | 0% | Never |
| **node-exporter** | 0 KB/hour | 0% | Never |
| **TOTAL** | **350 KB/hour** | 100% | — |

**What's in the logs:**

- **Collector (43.5%):** httpx INFO messages for VictoriaMetrics writes (HTTP 204 responses every ~4 seconds), aiohttp access logs for health checks
- **Grafana (32.8%):** Dashboard query logs, user access logs, datasource health checks
- **Uptime-Exporter (22.9%):** HTTP health check responses from rippled
- **Autoheal (0.8%):** Container health monitoring events (minimal activity)
- **Other containers:** Produce no logs or very minimal output

### Storage Projections

**Without Log Rotation** (hypothetical unlimited growth):

| Time Period | Total Size | Notes |
|-------------|------------|-------|
| 1 hour | 0.34 MB | Baseline measurement |
| 1 day | 8.21 MB | 24 hours of accumulation |
| 1 week | 57.44 MB | Steady state growth |
| 30 days | 246.16 MB | ~0.24 GB |
| 90 days | 738.49 MB | ~0.72 GB |
| 1 year | 2.92 GB | Maximum without rotation |

**With Log Rotation** (actual behavior):

Docker automatically rotates logs when they reach 50 MB, keeping only the 3 most recent files per container.

| Container | Cap per Container | System Maximum |
|-----------|-------------------|----------------|
| Each container | 150 MB (3 × 50 MB) | — |
| **Total (7 containers)** | — | **1.03 GB** |

**Key Insight:** Once containers reach their 150 MB cap, log storage plateaus. The system will never exceed ~1.03 GB total, regardless of uptime.

**Time to reach cap:**
- **collector:** ~42 days (most verbose)
- **grafana:** ~56 days
- **uptime-exporter:** ~80 days
- **autoheal:** ~6+ years (minimal logs)
- **Other containers:** Never (no log output)

### Changing Log Levels

You can reduce log verbosity to minimize storage usage and logging overhead.

**1. Edit the environment file:**

```bash
# From the project root directory
nano .env
```

**2. Change LOG_LEVEL:**

```bash
# Current (recommended for production)
LOG_LEVEL=INFO

# Alternative options:
# LOG_LEVEL=DEBUG    # More verbose (troubleshooting)
# LOG_LEVEL=WARNING  # Less verbose (only warnings/errors)
# LOG_LEVEL=ERROR    # Minimal (only errors)
```

**3. Restart the collector:**

```bash
docker compose restart collector
```

### Impact of Different Log Levels

| Level | Verbosity | Use Case | Storage Impact | Troubleshooting Capability |
|-------|-----------|----------|----------------|----------------------------|
| **DEBUG** | Highest | Development, debugging issues | +50-100% size | Maximum detail |
| **INFO** | Standard | Production (recommended) | Baseline (350 KB/hour) | Good balance |
| **WARNING** | Reduced | Minimal logging preference | ~90% reduction | Limited context |
| **ERROR** | Minimal | Critical errors only | ~95% reduction | Minimal context |

**What changes at each level:**

**DEBUG:**
- Adds WebSocket message dumps
- Adds detailed metric calculation steps
- Adds connection state transitions
- **Not recommended for production** (excessive detail)

**INFO (Recommended):**
- HTTP request/response logging (VictoriaMetrics writes)
- Health check responses
- Connection status changes
- Metric collection confirmations
- **Provides good troubleshooting context without excessive noise**

**WARNING:**
- Only logs warnings and errors
- Eliminates routine operational messages
- **Reduces collector logs by ~90%** (httpx INFO messages eliminated)
- Makes it harder to diagnose performance issues

**ERROR:**
- Only logs critical failures
- Minimal output (only when things break)
- **Difficult to troubleshoot problems** without context

### Recommendations

**Production Deployment (Recommended):**
```bash
LOG_LEVEL=INFO
```

**Why INFO is recommended:**
- ✅ Total growth: ~350 KB/hour (~8.4 MB/day) is very reasonable
- ✅ System caps at 1.03 GB maximum with rotation
- ✅ Most containers reach cap in 40-100+ days
- ✅ Provides valuable troubleshooting context when issues occur
- ✅ Shows VictoriaMetrics write confirmations (proves data is flowing)
- ✅ Tracks WebSocket connection health
- ✅ Minimal CPU/memory overhead

**When to reduce to WARNING:**
- Extremely limited disk space (< 5 GB available)
- Running on very low-resource systems
- Logs are cluttering your log aggregation system
- You have external monitoring and don't need detailed logs

**When to increase to DEBUG:**
- Troubleshooting connectivity issues
- Investigating missing metrics
- Debugging collector behavior
- Working with support to diagnose problems
- **Always change back to INFO after troubleshooting**

**Storage is NOT a concern:**

With Docker log rotation configured:
- System maximum: 1.03 GB (enforced automatically)
- No manual cleanup required
- No runaway disk usage
- Logs automatically pruned when limits reached

**Bottom Line:** Keep `LOG_LEVEL=INFO` for production. The storage footprint is minimal (~350 KB/hour), the system caps at 1 GB total, and the troubleshooting value is significant.

---

# Disk I/O Optimization

Optimize disk performance for VictoriaMetrics data storage.

**In This Section:**
- [Use SSD Storage](#use-ssd-storage)
- [Volume Driver Options](#volume-driver-options)
- [Filesystem Tuning](#filesystem-tuning)

---

### Use SSD Storage

VictoriaMetrics benefits from fast disk I/O:

```yaml
victoria-metrics:
  volumes:
    - /mnt/ssd/victoria-data:/victoria-metrics-data  # Use SSD mount
```

**Performance Impact:**
- HDD: ~100 IOPS
- SSD: ~10,000+ IOPS
- NVMe: ~100,000+ IOPS

### Volume Driver Options

```yaml
volumes:
  victoria_data:
    name: xrpl-monitor-victoria-data
    driver_opts:
      type: none
      o: bind
      device: /mnt/fast-storage/victoria-data
```

### Filesystem Tuning

For dedicated VictoriaMetrics disk:

```bash
# Mount with noatime (reduce write operations)
sudo mount -o remount,noatime /mnt/victoria-data

# Add to /etc/fstab for persistence
/dev/sdX  /mnt/victoria-data  ext4  noatime,nodiratime  0  2
```

---

# Network Tuning

Optimize network performance for WebSocket and HTTP connections.

### rippled Connection Limits

If rippled is on the same host (recommended):

```yaml
collector:
  network_mode: "host"  # Already configured - uses localhost
```

**Benefit:** Lowest latency, no Docker network overhead

### Multiple Instances (Multi-Validator)

For multi-validator deployments, allocate unique ports for each instance (e.g., Grafana on 3000, 3001, 3002).

---

# rippled online_delete Tuning

The `online_delete` setting in rippled controls how many ledgers are retained before old ledgers are deleted. This setting has a significant impact on disk I/O patterns and can affect validator performance.

**Note:** This finding was identified by [shortthefomo](https://github.com/shortthefomo) as a result of using this XRPL Validator Dashboard, and documented in [rippled issue #6202](https://github.com/XRPLF/rippled/issues/6202). This section was added to help other validators benefit from this discovery.

**In This Section:**
- [The Problem: I/O Storms from Low online_delete](#the-problem-io-storms-from-low-online_delete)
- [How online_delete Affects Disk I/O](#how-online_delete-affects-disk-i-o)
- [Why NuDB Makes This Worse](#why-nudb-makes-this-worse)
- [Impact on Validator Performance](#impact-on-validator-performance)
- [Recommended Values](#recommended-values)
- [Trade-offs](#trade-offs)
- [How to Change online_delete](#how-to-change-online_delete)

---

### The Problem: I/O Storms from Low online_delete

A community member discovered that their validator was dropping ledgers despite running on high-spec hardware (150k IOPS NVMe, 80 cores, 128 GB RAM). The dashboard's Storage Disk panels revealed a sawtooth I/O pattern with IOPS spiking to 30,000+ every 30 minutes.

The root cause: the default `online_delete` value (512) triggers frequent garbage collection events that overwhelm the disk.

**Sawtooth Pattern (Low online_delete):**
```
IOPS
30k ┤        ╭─╮        ╭─╮        ╭─╮        ╭─╮
    │       ╱   ╲       ╱  ╲       ╱  ╲       ╱  ╲    ← Delete storms
15k ┤      ╱     ╲     ╱    ╲     ╱    ╲     ╱    ╲
    │     ╱       ╲   ╱      ╲   ╱      ╲   ╱      ╲
 0k ┼────╱─────────╲─╱────────╲─╱────────╲─╱────────╲──
    └────┴──────────┴──────────┴──────────┴──────────┴────► Time
         ~30min    ~30min    ~30min    ~30min
```

**Smooth Pattern (High online_delete):**
```
IOPS
30k ┤
    │
15k ┤
    │  ────────────────────────────────────────────  ← Steady state
 0k ┼
    └──────────────────────────────────────────────────► Time
```

### How online_delete Affects Disk I/O

| Factor | Low online_delete (512) | High online_delete (16384) |
|--------|-------------------------|----------------------------|
| Ledgers retained | ~512 (~30 min) | ~16384 (~14-18 hours) |
| Delete frequency | Every ~30 minutes | Every ~14-18 hours |
| Ledgers deleted per event | Small batches, frequently | Larger batches, rarely |
| I/O pattern | Sawtooth (spiky) | Smooth (steady-state) |
| Delete overhead | Constant context switching | Amortized over long periods |

### Why NuDB Makes This Worse

NuDB (the database type used by rippled for ledger storage) is optimized for append-mostly workloads:

- **Writes are fast:** Sequential appends are efficient
- **Deletes are expensive:** Requires compaction/reorganization
- **Frequent small deletes = worst case for NuDB**

By increasing `online_delete`, you allow NuDB to operate in its optimal mode (appending) for longer periods before incurring deletion overhead.

### Impact on Validator Performance

| Metric | During Delete Storm | Normal Operation |
|--------|---------------------|------------------|
| I/O latency | Spikes to 10-100+ ms | 1-2 ms |
| Consensus participation | May miss rounds | Full participation |
| Agreement % | Drops | Stable |
| server_state | May flicker | Steady proposing |

A validator can have perfect agreement scores most of the time but experience periodic drops during these I/O storms. The dashboard's Storage Disk panels make this pattern visible.

### Recommended Values

| Scenario | online_delete | Rationale |
|----------|---------------|-----------|
| Default (not recommended) | 512-2000 | Causes I/O storms |
| Minimum stable | 8192 | ~8 hours between deletes |
| **Recommended for validators** | **16384** | **~14-18 hours between deletes** |
| Conservative | 32768 | ~1.5 days between deletes |
| Maximum practical | 50000-100000 | Days between deletes, more disk used |

### Trade-offs

| online_delete Value | Disk Space | I/O Pattern | Delete Frequency |
|---------------------|------------|-------------|------------------|
| 512 | ~250 MB | Sawtooth (bad) | Every 30 min |
| 2000 | ~1 GB | Spiky | Every 2 hours |
| 16384 | ~8-12 GB | Smooth | Every 14-18 hours |
| 32768 | ~16-24 GB | Very smooth | Every 1.5 days |

**The trade-off is minimal:** Even at 16384, you're only using ~8-12 GB more disk space in exchange for dramatically smoother I/O and more stable validation.

### How to Change online_delete

**1. Edit your rippled.cfg:**

```bash
sudo nano /etc/opt/ripple/rippled.cfg
```

**2. Find or add the [node_db] section:**

```ini
[node_db]
type=NuDB
path=/var/lib/rippled/db/nudb
online_delete=16384
advisory_delete=0
```

**Note:** `advisory_delete=0` is optional and can be omitted as it is the default behavior. When set to 0, rippled automatically deletes old ledgers when the count exceeds `online_delete`. Setting it to 1 disables automatic deletion and requires an external `can_delete` API command to trigger cleanup, which is useful for backup coordination.

**3. Restart rippled:**

```bash
sudo systemctl restart rippled
```

**4. Verify the change:**

After rippled syncs, monitor the Storage Disk panels in the dashboard. The sawtooth pattern should disappear over the next several hours as the new retention period takes effect.

**Note:** The first delete cycle after increasing `online_delete` will still occur at the previous threshold. The smooth I/O pattern will be visible after the ledger count exceeds the new threshold.

---

# Monitoring Your Monitor

Track the performance of the monitoring stack itself.

**In This Section:**
- [Container Resource Usage](#container-resource-usage)
- [VictoriaMetrics Internal Metrics](#victoriametrics-internal-metrics)
- [Grafana Performance](#grafana-performance-1)
- [Check Logs](#check-logs)

---

### Container Resource Usage

```bash
# Real-time stats
docker stats

# Specific container
docker stats xrpl-monitor-grafana

# Save stats to file
docker stats --no-stream > monitor-stats.txt
```

### VictoriaMetrics Internal Metrics

```bash
# Query VM metrics endpoint
curl -s http://localhost:8428/metrics | grep vm_

# Key metrics to watch:
curl -s http://localhost:8428/metrics | grep -E "vm_cache|vm_rows|vm_blocks"
```

**Important Metrics:**
- `vm_cache_misses_total` - Cache effectiveness
- `vm_slow_queries_total` - Queries exceeding timeout
- `vm_rows` - Total data points stored

### Grafana Performance

Check Grafana's own metrics:

```bash
curl -s http://localhost:3000/metrics | grep grafana_
```

### Check Logs

```bash
# Grafana logs
docker logs xrpl-monitor-grafana --tail 100

# VictoriaMetrics logs
docker logs xrpl-monitor-victoria --tail 100

# Collector logs
docker logs xrpl-monitor-collector --tail 100

# All logs with timestamps
docker compose logs --tail=100 --timestamps
```

---

# Common Scenarios

**In This Section:**
- [Scenario 1: Dashboard is Slow to Load](#scenario-1-dashboard-is-slow-to-load)
- [Scenario 2: High Memory Usage](#scenario-2-high-memory-usage)
- [Scenario 3: Disk Filling Up](#scenario-3-disk-filling-up)
- [Scenario 4: Multiple Concurrent Viewers](#scenario-4-multiple-concurrent-viewers)
- [Scenario 5: Running on Low-Resource VPS](#scenario-5-running-on-low-resource-vps)

---

### Scenario 1: Dashboard is Slow to Load

**Symptoms:**
- Panels take 5+ seconds to load
- "Query timeout" errors
- Grafana using high CPU

**Solutions:**

1. **Increase Grafana resources:**
   ```yaml
   grafana:
     cpus: "4.0"
     mem_limit: "2g"
   ```

2. **Increase VictoriaMetrics cache:**
   ```yaml
   - '--storage.cacheSizeIndexDBIndexBlocks=64MB'
   - '--storage.cacheSizeIndexDBDataBlocks=64MB'
   ```

3. **Reduce dashboard refresh rate:**
   - Change from 1s to 5s or 10s

4. **Optimize time ranges:**
   - Use shorter time ranges when possible
   - Avoid querying full retention period frequently

### Scenario 2: High Memory Usage

**Symptoms:**
- Containers approaching memory limits
- OOM (Out of Memory) kills
- System swapping

**Solutions:**

1. **Check which container:**
   ```bash
   docker stats --no-stream | sort -k 4 -h
   ```

2. **If VictoriaMetrics:**
   - Reduce retention: `--retentionPeriod=7d`
   - Reduce cache sizes
   - Reduce `--memory.allowedBytes`

3. **If Grafana:**
   - Increase memory limit (if available)
   - Reduce concurrent viewers
   - Simplify dashboard queries

4. **If Collector:**
   - Check for memory leaks: `docker logs xrpl-monitor-collector`
   - Restart: `docker compose restart collector`

### Scenario 3: Disk Filling Up

**Symptoms:**
- VictoriaMetrics data growing rapidly
- Disk space warnings

**Solutions:**

1. **Check current usage:**
   ```bash
   docker exec xrpl-monitor-victoria du -sh /victoria-metrics-data
   ```

2. **Reduce retention:**
   ```yaml
   - '--retentionPeriod=7d'  # or 14d
   ```

3. **Force cleanup:**
   ```bash
   # This will remove old data immediately
   docker compose restart victoria-metrics
   ```

### Scenario 4: Multiple Concurrent Viewers

**Symptoms:**
- Dashboard slow when multiple people viewing
- High Grafana CPU

**Solutions:**

1. **Increase Grafana resources:**
   ```yaml
   grafana:
     cpus: "4.0"
     mem_limit: "4g"
   ```

2. **Increase connection limits:**
   ```yaml
   environment:
     - GF_DATAPROXY_MAX_CONNS_PER_HOST=512
     - GF_DATAPROXY_MAX_IDLE_CONNECTIONS=1024
   ```

3. **Increase VictoriaMetrics concurrency:**
   ```yaml
   - '--search.maxConcurrentRequests=32'
   ```

### Scenario 5: Running on Low-Resource VPS

**Symptoms:**
- Limited RAM (2-4 GB total)
- Shared CPU

**Solutions:**

Use minimal configuration:

```yaml
# docker-compose.yml
grafana:
  cpus: "1.0"
  mem_limit: "512m"

victoria-metrics:
  command:
    - '--retentionPeriod=7d'
    - '--memory.allowedBytes=128MB'
    - '--search.maxMemoryPerQuery=25MB'
    - '--storage.cacheSizeIndexDBIndexBlocks=16MB'
    - '--storage.cacheSizeIndexDBDataBlocks=16MB'
```

---

# Troubleshooting Performance Issues

**In This Section:**
- [Slow Queries](#slow-queries)
- [High CPU Usage](#high-cpu-usage)
- [Memory Leaks](#memory-leaks)
- [Connection Timeouts](#connection-timeouts)

---

### Slow Queries

**Diagnose:**
```bash
# Check VictoriaMetrics slow queries
curl -s http://localhost:8428/metrics | grep vm_slow_queries_total
```

**Fix:**
- Increase `--search.maxMemoryPerQuery`
- Increase `--search.maxQueueDuration`
- Reduce time range in dashboard
- Simplify query (less aggregation)

### High CPU Usage

**Diagnose:**
```bash
docker stats --no-stream | sort -k 3 -h
```

**Fix:**
- Identify culprit container
- Increase CPU limit if needed
- For Grafana: reduce refresh rate
- For Collector: check for excessive logging

### Memory Leaks

**Diagnose:**
```bash
# Watch memory over time
watch -n 5 'docker stats --no-stream | grep xrpl-monitor'
```

**Fix:**
- Restart affected container
- Check logs for errors
- Report issue if persistent

### Connection Timeouts

**Diagnose:**
```bash
# Check Grafana logs
docker logs xrpl-monitor-grafana | grep timeout

# Check rippled connectivity
curl http://localhost:5005
```

**Fix:**
- Increase `GF_DATAPROXY_TIMEOUT`
- Check rippled is running
- Verify network connectivity

---

# Performance Tuning Checklist

Use this checklist when tuning your deployment:

### Initial Setup
- [ ] Set appropriate retention period for your needs
- [ ] Configure resource limits based on available hardware
- [ ] Set dashboard refresh rate (1s/5s/10s)
- [ ] Choose appropriate log level

### After 24 Hours
- [ ] Check disk usage growth rate
- [ ] Monitor peak CPU usage
- [ ] Check peak memory usage
- [ ] Review slow query count

### Weekly Maintenance
- [ ] Review container logs for errors
- [ ] Check disk space trends
- [ ] Verify all health checks passing
- [ ] Monitor cache hit rates

### When Scaling Up
- [ ] Increase Grafana CPU/memory for more viewers
- [ ] Increase VictoriaMetrics cache for better performance
- [ ] Consider longer retention for historical analysis
- [ ] Add monitoring for the monitor (meta-monitoring)

---

# Configuration Templates

### Minimal (< 4 GB RAM)

```yaml
# docker-compose.yml snippet
grafana:
  cpus: "1.0"
  mem_limit: "512m"

victoria-metrics:
  command:
    - '--storageDataPath=/victoria-metrics-data'
    - '--retentionPeriod=7d'
    - '--httpListenAddr=:8428'
    - '--memory.allowedBytes=128MB'
    - '--search.maxMemoryPerQuery=25MB'
    - '--storage.cacheSizeIndexDBIndexBlocks=16MB'
    - '--storage.cacheSizeIndexDBDataBlocks=16MB'
    - '--storage.cacheSizeStorageTSID=16MB'

uptime-exporter:
  cpus: "0.1"
  mem_limit: "64m"

node-exporter:
  cpus: "0.1"
  mem_limit: "64m"
```

### Balanced (4-8 GB RAM) - Recommended ⭐

```yaml
# docker-compose.yml snippet
grafana:
  cpus: "2.0"
  mem_limit: "1g"

victoria-metrics:
  command:
    - '--storageDataPath=/victoria-metrics-data'
    - '--retentionPeriod=30d'
    - '--httpListenAddr=:8428'
    - '--memory.allowedBytes=512MB'       # OPTIMIZED: 2x baseline
    - '--search.maxMemoryPerQuery=100MB'  # OPTIMIZED: 2x baseline
    - '--storage.cacheSizeIndexDBIndexBlocks=64MB'  # OPTIMIZED: 2x baseline
    - '--storage.cacheSizeIndexDBDataBlocks=64MB'   # OPTIMIZED: 2x baseline
    - '--storage.cacheSizeStorageTSID=64MB'         # OPTIMIZED: 2x baseline

uptime-exporter:
  cpus: "0.1"
  mem_limit: "128m"

node-exporter:
  cpus: "0.2"
  mem_limit: "128m"
```

**Proven Performance (Real-World Measurements):**
- Cache hit rate: 98.6% (vs 95.4% with 256MB)
- CPU usage: 1.95% (vs 3.98% with 256MB) - 51% reduction!
- Memory: 353 MB (vs 326 MB) - Only +27 MB cost
- Query performance: 3.2% fewer disk reads

### High-Performance (16+ GB RAM)

```yaml
# docker-compose.yml snippet
grafana:
  cpus: "4.0"
  mem_limit: "4g"
  environment:
    - GF_DATAPROXY_MAX_CONNS_PER_HOST=512
    - GF_DATAPROXY_MAX_IDLE_CONNECTIONS=1024

victoria-metrics:
  command:
    - '--storageDataPath=/victoria-metrics-data'
    - '--retentionPeriod=90d'
    - '--httpListenAddr=:8428'
    - '--memory.allowedBytes=1GB'
    - '--search.maxMemoryPerQuery=200MB'
    - '--storage.cacheSizeIndexDBIndexBlocks=128MB'
    - '--storage.cacheSizeIndexDBDataBlocks=128MB'
    - '--storage.cacheSizeStorageTSID=128MB'
    - '--search.maxConcurrentRequests=32'
    - '--search.maxQueueDuration=30s'

uptime-exporter:
  cpus: "0.2"
  mem_limit: "128m"

node-exporter:
  cpus: "0.2"
  mem_limit: "128m"
```

---

# Getting Help

If you're experiencing performance issues:

1. **Check logs first:**
   ```bash
   docker compose logs --tail=100
   ```

2. **Collect diagnostics:**
   ```bash
   docker stats --no-stream > stats.txt
   docker compose logs > logs.txt
   docker exec xrpl-monitor-victoria du -sh /victoria-metrics-data
   ```

3. **Review this guide's Common Scenarios section**

4. **Check GitHub Issues:**
   - [XRPL Monitor Issues](https://github.com/realgrapedrop/xrpl-validator-dashboard/issues)

5. **Create an issue with:**
   - Your hardware specs
   - Docker stats output
   - Relevant logs
   - Configuration changes you've made

---

# Additional Resources

- [VictoriaMetrics Tuning Guide](https://docs.victoriametrics.com/#capacity-planning)
- [Grafana Performance Tips](https://grafana.com/docs/grafana/latest/administration/performance/)
- [Docker Resource Limits](https://docs.docker.com/config/containers/resource_constraints/)

---

**Last Updated:** January 11, 2026
**Tested With:** XRPL Validator Dashboard v3.0, VictoriaMetrics latest, Grafana 12.1.1
