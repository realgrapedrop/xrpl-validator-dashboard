# Tips & Best Practices

Advanced tips for optimizing your XRPL Validator Monitor Dashboard.

## Table of Contents

- [Grafana Dashboard Optimization](#grafana-dashboard-optimization)
- [Prometheus Configuration](#prometheus-configuration)
- [State Monitoring Best Practices](#state-monitoring-best-practices)
- [Alert Configuration](#alert-configuration)
- [Performance Tuning](#performance-tuning)
- [Query Optimization](#query-optimization)
- [Security Tips](#security-tips)
- [Backup Strategies](#backup-strategies)

## Grafana Dashboard Optimization

### Enable Real-Time Monitoring (Recommended)

For the best monitoring experience, configure your dashboard for 5-second updates:

**Step 1: Set Auto-Refresh Interval**

1. Open your Grafana dashboard
2. Look at the top-right corner
3. Click the **refresh dropdown** (🔄 icon)
4. Select **5s** from the list
5. The dashboard will now automatically refresh every 5 seconds

**Step 2: Enable Refresh Live Dashboards**

1. Click the **dashboard settings** icon (⚙️ gear icon at top)
2. Navigate to **Settings** → **General**
3. Scroll to **Time options** section
4. Check ✅ **"Refresh live dashboards"**
5. Click **Save dashboard** (💾 icon at top)

**Step 3: Verify Settings**

- You should see the refresh countdown at the top (e.g., "Next refresh in 4s")
- The dashboard should feel "live" with metrics updating smoothly
- State changes should appear within seconds

**Why This Configuration Matters:**

| Without Fast Refresh | With 5s Refresh |
|---------------------|-----------------|
| Miss fast state transitions | Catch all state changes |
| 15-30s lag in alerts | Near real-time alerts |
| Hard to correlate events | Precise event timing |
| Miss brief issues | See everything |

### Dashboard Organization Tips

**Panel Layout Best Practices:**

1. **Top Row: Critical Status**
   - Validator state (large, prominent)
   - Ledger sync status
   - Peer count
   - Validation agreement %

2. **Middle Rows: Performance Metrics**
   - Consensus time
   - Transaction rate
   - I/O latency
   - Load factor

3. **Bottom Rows: System Resources**
   - CPU usage
   - Memory usage
   - Disk usage
   - Network traffic

**Color Coding:**

- 🔴 **Red**: Critical issues (disconnected, validation failed)
- 🟡 **Yellow**: Warning states (connected but not syncing)
- 🟠 **Orange**: Transitional (syncing, tracking)
- 🔵 **Blue**: Operational (full)
- 🟢 **Green**: Optimal (proposing, high validation %)

### Time Range Recommendations

**For Different Use Cases:**

- **Real-time monitoring**: Last 15 minutes
- **Recent troubleshooting**: Last 1 hour
- **Daily review**: Last 24 hours
- **Weekly analysis**: Last 7 days
- **Historical trends**: Last 30 days

**Pro Tip:** Create multiple dashboards:
- `Validator - Live` (15min, 5s refresh)
- `Validator - Daily` (24h, 1m refresh)
- `Validator - Weekly` (7d, 5m refresh)

## Prometheus Configuration

### Optimal Scrape Intervals

Different jobs need different scrape rates:

```yaml
scrape_configs:
  # Fast - Validator State Monitoring
  - job_name: 'xrpl-monitor'
    scrape_interval: 5s      # Catch fast state transitions
    scrape_timeout: 4s
    static_configs:
      - targets: ['localhost:9091']

  # Medium - System Metrics
  - job_name: 'node_exporter'
    scrape_interval: 15s     # Balance between detail and load
    scrape_timeout: 10s
    static_configs:
      - targets: ['node_exporter:9100']

  # Slow - Container Metrics
  - job_name: 'cadvisor'
    scrape_interval: 30s     # Less critical, reduce overhead
    scrape_timeout: 10s
    static_configs:
      - targets: ['cadvisor:8080']
```

**Why Different Intervals?**

| Metric Type | Interval | Reason |
|------------|----------|---------|
| Validator state | 5s | Changes happen in seconds |
| System resources | 15s | Good balance for trends |
| Container stats | 30s | Slower changing, less critical |
| Prometheus self | 30s | Rarely needs real-time |

### Data Retention

Balance storage vs. historical data:

```yaml
# In docker-compose.yml for Prometheus
command:
  - '--storage.tsdb.retention.time=30d'    # Keep 30 days
  - '--storage.tsdb.retention.size=50GB'   # Or max 50GB
```

**Recommended Retention:**

- **Validators**: 30-90 days (critical for trend analysis)
- **Test/Dev**: 7-15 days (less critical)
- **High-volume**: Use recording rules to downsample

### Recording Rules for Performance

Create aggregated metrics to reduce query load:

```yaml
# In prometheus.yml
rule_files:
  - 'rules.yml'
```

**Example rules.yml:**

```yaml
groups:
  - name: xrpl_aggregations
    interval: 30s
    rules:
      # Ledger close rate (5 min average)
      - record: xrpl:ledger_close_rate:5m
        expr: rate(xrpl_ledger_sequence[5m])
      
      # Average consensus time (5 min)
      - record: xrpl:consensus_time_avg:5m
        expr: avg_over_time(xrpl_consensus_converge_time_seconds[5m])
      
      # Validation agreement rate (1 hour)
      - record: xrpl:validation_agreement:1h
        expr: xrpl_validation_agreement_pct_1h
      
      # Peer stability (disconnects per hour)
      - record: xrpl:peer_disconnects_rate:1h
        expr: rate(xrpl_peer_disconnects_total[1h]) * 3600
```

**Benefits:**
- Faster dashboard loading
- Less CPU usage on queries
- Pre-computed metrics for alerts

## State Monitoring Best Practices

### Understanding State Values

**Numeric State Mapping:**

```
0 = disconnected    🔴 Critical - No network connection
1 = connected       🟡 Warning - Connected but not syncing
2 = syncing         🟠 Normal - Downloading ledger history
3 = tracking        🔵 Normal - Following network
4 = full            🔵 Good - Fully synced, not validating
6 = proposing       🟢 Optimal - Actively validating
```

**Note:** Value 5 and 7 may exist but are rarely seen in practice.

### Best Queries for State Monitoring

**Current State (for Stat panel):**
```promql
xrpl_validator_state_value{job="xrpl-monitor"}
```

**State Over Time (for Timeline panel):**
```promql
xrpl_validator_state_value{job="xrpl-monitor"}
```

**Time in Each State (for Table):**
```promql
xrpl_state_accounting_duration_seconds
```

**State Transition Count:**
```promql
xrpl_state_accounting_transitions
```

### Grafana Value Mappings

**In your State panel settings:**

1. Go to **Panel** → **Value mappings**
2. Add mappings:

```
Value → Display Text → Color
0     → Disconnected  → Red
1     → Connected     → Yellow
2     → Syncing       → Orange
3     → Tracking      → Light Blue
4     → Full          → Blue
6     → Proposing     → Green
```

**For State Timeline panels:**
- These mappings automatically create colored bands
- Easy to see state history at a glance
- Quickly identify when issues occurred

### Catching Fast State Transitions

**Problem:** Validator syncs in 5-10 seconds, but you never see it

**Solution:**

1. **Set Prometheus scrape to 5s** (as shown above)
2. **Use state accounting metrics:**
   ```promql
   # Shows ALL state transitions, even if brief
   xrpl_state_accounting_transitions
   
   # Shows total time spent in each state
   xrpl_state_accounting_duration_seconds
   ```

3. **Alert on unexpected states:**
   ```promql
   # Alert if NOT proposing for >5 minutes
   xrpl_validator_state_value != 6
   ```

## Alert Configuration

### Critical Alerts

**Validator Not Proposing:**

```yaml
- alert: ValidatorNotProposing
  expr: xrpl_validator_state_value{job="xrpl-monitor"} != 6
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Validator not in proposing state"
    description: "Validator has been in state {{ $value }} for >5 minutes"
```

**Low Validation Agreement:**

```yaml
- alert: LowValidationAgreement
  expr: xrpl_validation_agreement_pct_1h < 95
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Low validation agreement"
    description: "Agreement at {{ $value }}% (threshold: 95%)"
```

**Peer Count Low:**

```yaml
- alert: LowPeerCount
  expr: xrpl_peer_count < 10
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Low peer count"
    description: "Only {{ $value }} peers connected (threshold: 10)"
```

**Ledger Age High:**

```yaml
- alert: LedgerStale
  expr: xrpl_ledger_age_seconds > 60
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "Ledger not updating"
    description: "Last ledger is {{ $value }}s old (threshold: 60s)"
```

### Recommended Alert Thresholds

| Metric | Warning | Critical | Duration |
|--------|---------|----------|----------|
| State | != proposing | != proposing | 5m / 10m |
| Validation % | <95% | <90% | 10m / 5m |
| Peer count | <15 | <10 | 5m / 2m |
| Ledger age | >30s | >60s | 5m / 2m |
| Memory usage | >80% | >90% | 10m / 5m |
| Disk usage | >80% | >90% | 30m / 10m |

### Alert Notification Channels

**Configure in Grafana:**

1. **Settings** → **Alerting** → **Contact points**
2. Add channels:
   - **Email** (for all alerts)
   - **Slack/Discord** (for critical only)
   - **PagerDuty** (for production validators)
   - **Webhook** (for custom integrations)

**Best Practice:**
- Send warnings to email/Slack
- Send critical to PagerDuty/phone
- Group alerts to avoid spam
- Use alert rules to define severity

## Performance Tuning

### Prometheus Performance

**If Prometheus uses too much CPU/memory:**

1. **Increase scrape intervals** (except for critical metrics)
2. **Use recording rules** to pre-compute metrics
3. **Limit metric cardinality:**
   ```yaml
   metric_relabel_configs:
     # Only keep metrics you actually use
     - source_labels: [__name__]
       regex: 'xrpl_(validator_state|ledger_sequence|peer_count|validation_agreement).*'
       action: keep
   ```
4. **Reduce retention time** if disk is full
5. **Enable compression** (already in our config)

### Grafana Performance

**Dashboard Loading Slow?**

1. **Limit time range** - Don't query months of data
2. **Use recording rules** - Pre-aggregate metrics
3. **Reduce panel count** - Split into multiple dashboards
4. **Optimize queries:**
   - Avoid `rate()` on large ranges
   - Use `increase()` instead of `rate() * time`
   - Cache common sub-queries

**Example Optimization:**

```promql
# Slow - calculates for every data point
rate(xrpl_ledger_sequence[5m])

# Fast - pre-computed via recording rule
xrpl:ledger_close_rate:5m
```

### System Resource Management

**For the Validator Host:**

```bash
# Check what's using resources
docker stats

# If Prometheus using too much memory
# Reduce retention or increase container limit

# If disk filling up
# Clean old Docker resources
docker system prune -a --volumes
```

**Recommended Container Limits:**

```yaml
# In docker-compose.yml
services:
  prometheus:
    mem_limit: "4g"      # 4GB for 30-day retention
    cpus: "2.0"          # 2 CPU cores
  
  grafana:
    mem_limit: "1g"      # 1GB sufficient
    cpus: "1.0"          # 1 CPU core
```

## Query Optimization

### Efficient PromQL Queries

**Do This ✅:**

```promql
# Use specific job labels
xrpl_validator_state_value{job="xrpl-monitor"}

# Use recording rules for complex calculations
xrpl:validation_agreement:1h

# Aggregate before rate calculations
avg(rate(xrpl_peer_disconnects_total[5m]))
```

**Don't Do This ❌:**

```promql
# Avoid wildcards without labels
xrpl_validator_state_value

# Don't calculate rate on every point
rate(xrpl_peer_disconnects_total[1d])

# Avoid multiple aggregations
avg(rate(avg(xrpl_consensus_converge_time_seconds[5m])[10m:]))
```

### Common Query Patterns

**Percentage Calculation:**
```promql
(xrpl_validation_agreements_1h / (xrpl_validation_agreements_1h + xrpl_validation_missed_1h)) * 100
```

**Rate of Change:**
```promql
rate(xrpl_ledger_sequence[5m]) * 60  # Ledgers per minute
```

**Uptime Percentage:**
```promql
(xrpl_validator_uptime_seconds / (xrpl_validator_uptime_seconds + xrpl_server_state_duration_seconds{state="disconnected"})) * 100
```

## Security Tips

### Secure Your Monitoring Stack

**1. Don't Expose Grafana Publicly**

Use Cloudflare Tunnel or VPN instead of opening ports:

```yaml
# In docker-compose.yml - bind to localhost only
ports:
  - "127.0.0.1:3000:3000"  # ✅ Good
  # NOT:
  # - "3000:3000"          # ❌ Bad - public access
```

**2. Change Default Passwords**

```bash
# First login to Grafana
# Username: admin
# Password: admin
# IMMEDIATELY change the password!
```

**3. Enable HTTPS**

Either:
- Use Cloudflare Tunnel (handles SSL)
- Use reverse proxy (nginx/traefik) with Let's Encrypt
- Configure Grafana SSL directly

**4. Restrict Prometheus Access**

```yaml
# Only accessible from localhost
ports:
  - "127.0.0.1:9090:9090"
```

**5. Protect Validator Keys**

```bash
# Ensure correct permissions
chmod 600 ${INSTALL_DIR}/rippled/config/validator-keys.json

# Back up securely (encrypted)
gpg -c validator-keys.json
```

### Firewall Configuration

```bash
# Only allow necessary ports
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp        # SSH
sudo ufw allow 51235/tcp     # XRPL peer
sudo ufw allow 51235/udp     # XRPL peer
sudo ufw enable

# Do NOT open:
# - 3000 (Grafana)
# - 9090 (Prometheus)
# - 5005 (rippled admin)
# Use Cloudflare Tunnel or VPN instead
```

## Backup Strategies

### What to Back Up

**Critical (daily):**
- Validator keys: `validator-keys.json`
- Rippled config: `rippled.cfg`
- Validators list: `validators.txt`

**Important (weekly):**
- Grafana dashboards: Export as JSON
- Prometheus configuration: `prometheus.yml`
- Alert rules: `rules.yml`

**Optional:**
- Grafana database (contains dashboard history)
- Prometheus data (can regenerate from validator)

### Automated Backup Script

```bash
#!/bin/bash
# backup-validator.sh

BACKUP_DIR="/backups/xrpl-validator"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

mkdir -p "$BACKUP_PATH"

# Backup critical files
cp ${INSTALL_DIR}/rippled/config/validator-keys.json "$BACKUP_PATH/"
cp ${INSTALL_DIR}/rippled/config/rippled.cfg "$BACKUP_PATH/"
cp ${INSTALL_DIR}/rippled/config/validators.txt "$BACKUP_PATH/"
cp ${INSTALL_DIR}/monitoring/prometheus/prometheus.yml "$BACKUP_PATH/"

# Encrypt backup
tar czf "${BACKUP_PATH}.tar.gz" "$BACKUP_PATH"
gpg -c "${BACKUP_PATH}.tar.gz"
rm -rf "$BACKUP_PATH" "${BACKUP_PATH}.tar.gz"

# Keep only last 30 days
find "$BACKUP_DIR" -name "*.tar.gz.gpg" -mtime +30 -delete

echo "Backup completed: ${BACKUP_PATH}.tar.gz.gpg"
```

**Set up cron:**
```bash
# Run daily at 2 AM
crontab -e
# Add:
0 2 * * * /path/to/backup-validator.sh
```

### Off-Site Backup

**Options:**
1. **rsync to remote server**
2. **AWS S3 / Backblaze B2**
3. **Encrypted cloud storage** (Dropbox, Google Drive with gpg)
4. **GitHub private repo** (for configs only, not keys!)

## Additional Resources

**Official Documentation:**
- XRPL: https://xrpl.org/docs.html
- Prometheus: https://prometheus.io/docs/
- Grafana: https://grafana.com/docs/

**Community:**
- XRPL Forum: https://forum.xrpl.org
- Discord: https://discord.gg/xrpl

**This Project:**
- GitHub: https://github.com/realGrapedrop/xrpl-validator-monitor-dashboard
- Issues: https://github.com/realGrapedrop/xrpl-validator-monitor-dashboard/issues

---

**Questions or suggestions?** Open an issue or contribute improvements!

Created by [Grapedrop](https://xrp-validator.grapedrop.xyz) | [@realGrapedrop](https://x.com/realGrapedrop)
