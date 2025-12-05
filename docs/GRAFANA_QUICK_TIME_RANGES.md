# **__QUICK TIME RANGE PRESETS CONFIGURATION__**

*Configure quick time range presets in Grafana 12.1 for streamlined validator monitoring.*

---

# Table of Contents

- [Overview](#overview)
- [Recommended Presets for XRPL Validator Monitoring](#recommended-presets-for-xrpl-validator-monitoring)
- [Configuration Methods](#configuration-methods)
- [Implementation for XRPL Monitor v3](#implementation-for-xrpl-monitor-v3)
- [Time Range Format Reference](#time-range-format-reference)
- [Validator Monitoring Workflows](#validator-monitoring-workflows)
- [Testing the Configuration](#testing-the-configuration)
- [Troubleshooting](#troubleshooting)
- [Phase 1 Implementation Status](#phase-1-implementation-status)
- [Next Steps](#next-steps)

---

# Overview

Grafana 12.1.1 introduces configurable quick time range presets that appear in the time picker dropdown. These replace the previous hardcoded defaults and can be customized per user or organization-wide.

**Benefits for Validator Monitoring:**
- Fast access to relevant time windows (1h, 6h, 24h, 7d)
- Reduced clicks for common investigative workflows
- Consistent time range usage across team members
- Optimized for validator operational needs

---

# Recommended Presets for XRPL Validator Monitoring

Based on validator monitoring best practices, here are the recommended time range presets:

| Preset | Use Case | Priority |
|--------|----------|----------|
| **Last 1 hour** | Real-time monitoring, incident detection | Critical |
| **Last 6 hours** | Short-term trend analysis, recent issue investigation | High |
| **Last 24 hours** | Daily performance review, validation agreement tracking | High |
| **Last 7 days** | Weekly performance assessment, long-term trend analysis | Medium |
| **Last 30 days** | Monthly reports, baseline performance comparison | Low |

**Special Presets:**
- **Today so far** - For daily operational checks (00:00 to now)
- **Yesterday** - For reviewing previous day's performance
- **This week so far** - For weekly performance tracking

---

# Configuration Methods

### Method 1: User Preferences (Individual)

**Steps:**
1. Log into Grafana (http://localhost:3000)
2. Click your profile icon (bottom left)
3. Select **Preferences**
4. Scroll to **Quick time ranges**
5. Configure your presets:

```
Last 1 hour
Last 6 hours
Last 24 hours
Last 7 days
Last 30 days
Today so far
Yesterday
```

6. Click **Save**

**Scope:** Applies only to your user account

---

### Method 2: Organization Preferences (Team-wide)

**Steps:**
1. Log into Grafana as Admin
2. Go to **Administration** → **Settings** → **Preferences**
3. Scroll to **Quick time ranges**
4. Configure organization-wide presets (same as above)
5. Click **Save**

**Scope:** Applies to all users in the organization (can be overridden by user preferences)

---

### Method 3: Configuration File (System-wide)

**For Docker deployments, add to grafana.ini:**

```ini
[dashboards]
# Configure quick time range presets
quick_time_ranges = Last 1 hour,Last 6 hours,Last 24 hours,Last 7 days,Last 30 days,Today so far,Yesterday

[defaults.preferences]
# Set default theme and quick ranges
theme = dark
quick_time_ranges = Last 1 hour,Last 6 hours,Last 24 hours,Last 7 days,Last 30 days
```

**For our Docker Compose setup:**

Add to `docker-compose.yml` under Grafana service environment variables:

```yaml
grafana:
  environment:
    - GF_DASHBOARDS_QUICK_TIME_RANGES=Last 1 hour,Last 6 hours,Last 24 hours,Last 7 days,Last 30 days,Today so far,Yesterday
```

**Scope:** Applies to all users system-wide

---

# Implementation for XRPL Monitor v3

### Recommended Approach: Organization Preferences

Since XRPL Monitor is typically deployed for a single validator operation, configure organization-wide presets so all team members have consistent quick ranges.

**Steps to implement:**

1. Access Grafana v3 dashboard (port 3000):
   ```bash
   open http://localhost:3000
   ```

2. Login with admin credentials (default: admin/admin)

3. Navigate to **Administration** → **Settings** → **Preferences**

4. Configure the following Quick Time Ranges:
   ```
   Last 1 hour
   Last 6 hours
   Last 24 hours
   Last 7 days
   Last 30 days
   Today so far
   ```

5. Click **Save**

6. Test by opening any dashboard and clicking the time picker - your presets should appear at the top

---

# Time Range Format Reference

Grafana accepts these formats for quick ranges:

### Relative Ranges
- `Last 5 minutes` - Last 5m
- `Last 15 minutes` - Last 15m
- `Last 30 minutes` - Last 30m
- `Last 1 hour` - Last 1h
- `Last 3 hours` - Last 3h
- `Last 6 hours` - Last 6h
- `Last 12 hours` - Last 12h
- `Last 24 hours` - Last 24h
- `Last 2 days` - Last 2d
- `Last 7 days` - Last 7d
- `Last 30 days` - Last 30d
- `Last 90 days` - Last 90d

### Fixed Ranges
- `Today` - Today (00:00 to now)
- `Today so far` - Today (00:00 to now)
- `Yesterday` - Yesterday (full day)
- `This week` - Current week (Monday to now)
- `This week so far` - Current week (Monday to now)
- `This month` - Current month (1st to now)
- `This month so far` - Current month (1st to now)
- `Previous week` - Last week (Monday to Sunday)
- `Previous month` - Last month (full month)

---

# Validator Monitoring Workflows

### Incident Response (Use: Last 1 hour)
When alerts fire, quickly switch to "Last 1 hour" to see recent metrics:
- Server state changes
- Load factor spikes
- IO latency increases
- Peer disconnects

### Performance Investigation (Use: Last 6 hours)
For degradation analysis, use "Last 6 hours" with trendlines enabled:
- IO Latency trend
- Load Factor trend
- Peer Latency trend
- Agreement % trend

### Daily Review (Use: Today so far or Last 24 hours)
Morning operational checks:
- Validation agreement rate over 24h
- State transitions overnight
- Peer stability
- Transaction rate patterns

### Weekly Assessment (Use: Last 7 days)
Weekly performance review:
- Agreement % trend over 7 days
- Uptime percentage
- Average load factor
- Peer count stability

---

# Testing the Configuration

After configuring quick ranges, test them:

1. Open the XRPL Validator Main dashboard
2. Click the time picker (top right, shows current time range)
3. Verify your configured presets appear at the top of the dropdown
4. Click each preset to ensure it correctly adjusts the dashboard time range
5. Verify trendline panels update correctly with each time range

**Expected behavior:**
- Quick ranges appear above the calendar picker
- Clicking a preset immediately updates all panels
- Trendlines recalculate for the new time range
- URL updates with the new time range (for sharing)

---

# Troubleshooting

### Presets Not Appearing

**Problem:** Quick ranges don't show in time picker

**Solutions:**
1. Clear browser cache and hard reload (Ctrl+Shift+R)
2. Verify Grafana version is 12.1.1 or later: `docker-compose exec grafana grafana-cli --version`
3. Check organization preferences were saved
4. Try logging out and back in

### Wrong Time Ranges

**Problem:** Preset shows different time range than expected

**Solutions:**
1. Check format matches Grafana syntax (see reference above)
2. Verify no typos in configuration
3. Test with simple ranges first (e.g., "Last 1 hour")

### User Override Not Working

**Problem:** User preferences don't override organization settings

**Solutions:**
1. Ensure user has permission to modify preferences
2. Clear organization-level presets if needed
3. User preferences take precedence when set

---

# Phase 1 Implementation Status

- ✅ Trendline transformations added to key panels:
  - IO Latency (panel ID: 392)
  - Load Factor (panel ID: 356)
  - Peer Latency (panel ID: 349)
  - Agreement % Trend (panel ID: 388)

- ⏳ Quick Time Range Presets:
  - Documentation complete
  - **Action Required:** Configure in Grafana UI (see "Implementation" section above)
  - Estimated time: 2 minutes

---

# Next Steps

After configuring quick time ranges:

1. **Verify:** Test all presets work correctly
2. **Train:** Brief team members on the new quick ranges
3. **Monitor:** Collect feedback on which ranges are most useful
4. **Iterate:** Adjust presets based on actual usage patterns

---

**Document Version:** 1.0
**Created:** 2025-11-11
**Status:** Ready for implementation
