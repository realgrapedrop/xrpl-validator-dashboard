# **__ALERT CONFIGURATION GUIDE__**

*Complete guide to setting up email and webhook notifications for your XRPL Validator Monitor.*

---

# Table of Contents

- [Getting Started](#getting-started)
- [Email Alerts](#email-alerts)
- [Webhook Alerts](#webhook-alerts)
- [Testing & Validation](#testing--validation)
- [Operations](#operations)
- [Advanced Topics](#advanced-topics)
- [Reference](#reference)

---

# Getting Started

This section introduces alert concepts and helps you understand what's available.

**In This Section:**
- [Introduction](#introduction)
- [How Grafana Alerts Work](#how-grafana-alerts-work)
- [What Alerts Provide](#what-alerts-provide)
- [Alert Rules Overview](#alert-rules-overview)

---

# Introduction

Alerts are your validator's safety net - they notify you when something needs attention, so you don't have to constantly watch the dashboard.

**Think of alerts as your validator's way of tapping you on the shoulder and saying:**
- "Hey, I stopped proposing" (Critical - fix now!)
- "My peers are dropping" (Warning - check soon)
- "Load is trending up" (Info - be aware)

The XRPL Monitor comes with **18 pre-configured alert rules** that cover the most important validator health scenarios. You just need to tell the system **where** to send notifications.

| Category | Rules | Severity Levels |
|----------|-------|-----------------|
| **Critical Monitoring** | 8 | Validator not proposing, Agreement < 90%, Unhealthy state, WebSocket/HTTP down, Amendment blocked, UNL cert expiring, UNL inactive |
| **Network Monitoring** | 3 | Peer count dropping, critical peer loss, connectivity issues |
| **Performance Monitoring** | 7 | Memory exhaustion, high load, I/O latency, peer latency, disk space, CPU, upgrade recommended |

**Supported Alert Channels:**
- **Email** - SMTP (Gmail, SendGrid, Mailgun, AWS SES)
- **Chat Platforms** - Discord, Slack, Microsoft Teams, Telegram
- **On-Call Services** - PagerDuty (24/7 phone/SMS escalation)
- **Custom Webhooks** - Generic HTTP endpoints for automation

**Note:** Alerts are optional - the dashboard works perfectly without them. Configure notifications when you're ready for 24/7 peace of mind.

# How Grafana Alerts Work

Grafana alerting has three simple parts:

```
┌──────────────┐      ┌─────────────────┐      ┌──────────────────┐
│ Alert Rules  │ ───► │ Notification    │ ───► │ Contact Points   │
│ (14 pre-set) │      │ Policy (router) │      │ (you configure)  │
└──────────────┘      └─────────────────┘      └──────────────────┘
     WHEN                  ROUTING                  WHERE
```

| Component | What It Does | Your Action |
|-----------|--------------|-------------|
| **Alert Rules** | Define WHEN to alert (e.g., "peer count < 10 for 20 min") | Already configured - 16 rules included |
| **Notification Policy** | Routes alerts to contact points | Already configured - sends all to default |
| **Contact Points** | Define WHERE to send (email, Discord, Slack, etc.) | **You configure this** |

**The good news:** You only need to set up Contact Points. The alert rules and routing are already done.

### Multi-Channel Notifications

Want alerts on email AND Discord? You have two options:

**Option 1: Multiple receivers in one contact point** (recommended)
- All alerts go to ALL channels simultaneously
- Simple to set up in the config file

**Option 2: Route by severity**
- Critical alerts → PagerDuty (wake you up)
- Warnings → Slack (check when convenient)
- Requires editing notification policies

Most users just need Option 1 - set up email, optionally add Discord/Slack, done.

**No configuration required to use the dashboard** - alerts are optional. But once configured, they provide 24/7 peace of mind.

---

# What Alerts Provide

### Peace of Mind
- Sleep soundly knowing you'll be notified of issues
- No need to constantly check the dashboard
- Catch problems before they impact the network

### Proactive Monitoring
- Get notified when issues START, not after damage is done
- Early warning system for degrading performance
- Trends alert you to problems developing over time

### 24/7 Awareness
- Receive notifications on your phone (Discord, Telegram, email)
- Multi-channel support (email + Discord + Slack simultaneously)
- Different channels for different severity levels (if desired)

### Automatic Recovery Notifications
- Alerts fire when problems occur
- Alerts **resolve** when problems are fixed
- You'll know when your validator returns to healthy state

### Alert History
- View alert history in Grafana: **Alerting → Alert rules → [Click alert] → State history tab**
- See patterns: recurring issues, time-of-day patterns
- Data-driven decisions about infrastructure improvements

---

# Alert Rules Overview

XRPL Monitor includes **18 pre-configured alert rules** covering critical validator operations.

### Alert Severity Levels

- **🔴 Critical** - Requires immediate action (validator not functioning properly)
- **🟡 Warning** - Attention needed soon (performance degrading, potential issues)
- **🔵 Info** - Awareness only (useful trends, minor issues)

### Complete Alert Rules Table

| # | Alert Name | 🚨 | Severity | Condition | Duration | What It Means | Action Needed |
|---|------------|---|----------|-----------|----------|---------------|---------------|
| 1 | **Validator Not Proposing** | 🔴 | Critical | Server state ≠ proposing | 30s | Validator stopped participating in consensus | Check rippled logs, verify validator keys, check network connectivity |
| 2 | **Validator State Unhealthy** | 🔴 | Critical | Real-time state unhealthy | 30s | Validator in bad state | Check rippled status, restart if needed |
| 3 | **Validation Agreement Below 90%** | 🔴 | Critical | Agreements < 90% in 24h | 2 min | Validator missing too many validations | Check network, verify rippled health, review UNL |
| 4 | **WebSocket Unhealthy** | 🔴 | Critical | WebSocket connection down | 30s | Monitor lost connection to rippled | Check rippled is running, verify WebSocket port |
| 5 | **HTTP RPC Unhealthy** | 🔴 | Critical | HTTP RPC endpoint down | 30s | Monitor lost API access to rippled | Check rippled is running, verify HTTP port |
| 6 | **Peer Count Dropping** | 🟡 | Warning | > 10% peer loss in 30s | 30s | Network connectivity degrading | Check firewall, network stability, ISP issues |
| 7 | **Peer Count Critical Drop** | 🔴 | Critical | > 30% peer loss in 30s | 30s | Severe network connectivity loss | Immediate attention - check network, firewall, rippled logs |
| 8 | **Network Connectivity Issues** | 🔴 | Critical | Peers < 5 (critically low) | 1 min | Validator nearly isolated | Check network, firewall, ISP issues immediately |
| 9 | **High Load Factor** | 🟡 | Warning | Load factor > 1000 | 2 min | Server under heavy load | Check CPU, disk I/O, consider hardware upgrade |
| 10 | **High IO Latency (Trending Up)** | 🟡 | Warning | I/O latency > 50ms | 3 min | Disk performance degrading | Monitor disk health, consider SSD upgrade, check for failing disk |
| 11 | **Peer Latency Degradation** | 🟡 | Warning | P90 peer latency > 500ms | 2 min | Network performance decreasing | Check network quality, ISP issues, geographic routing |
| 12 | **Memory Usage Critical** | 🔴 | Critical | Memory usage > 90% | 2 min | System running out of RAM | Stop non-essential services, investigate memory leak, add RAM |
| 13 | **Disk Space Warning** | 🟡 | Warning | Disk usage > 85% | 2 min | Running low on disk space | Delete logs, clean up old data, expand disk |
| 14 | **Validator CPU High** | 🟡 | Warning | rippled CPU > 90% | 1 min | Validator CPU constrained | Check container limits, reduce load, add cores |
| 15 | **Amendment Blocked** | 🔴 | Critical | amendment_blocked = 1 | 1 min | Validator non-functional until upgraded | Upgrade rippled immediately - validator cannot participate in consensus |
| 16 | **Upgrade Recommended** | 🟡 | Warning | >60% peers on higher version | 30 min | Newer rippled version available | Plan upgrade soon - majority of network has upgraded |
| 17 | **UNL Publisher Certificate Expiring Soon** | 🟡 | Warning | Any UNL cert < 30 days | 1 hour | UNL publisher SSL cert expiring | Monitor renewal - rippled may not fetch UNL updates if cert expires |
| 18 | **UNL Status Inactive** | 🔴 | Critical | UNL status not active | 5 min | Validator list may be stale | Check UNL publisher connectivity, verify rippled can fetch UNL |

### Alert Categories

**Critical Monitoring (8 alerts):**
- Validator Not Proposing
- Validator State Unhealthy
- Validation Agreement Below 90%
- WebSocket Unhealthy
- HTTP RPC Unhealthy
- Amendment Blocked (validator non-functional)
- UNL Publisher Certificate Expiring Soon
- UNL Status Inactive

**Network Monitoring (3 alerts):**
- Peer Count Dropping (> 10% loss in 30s)
- Peer Count Critical Drop (> 30% loss in 30s)
- Network Connectivity Issues (< 5 peers)

**Performance Monitoring (7 alerts):**
- High Load Factor
- High IO Latency (Trending Up)
- Peer Latency Degradation
- Memory Usage Critical
- Disk Space Warning
- Validator CPU High
- Upgrade Recommended (>60% peers ahead)

### How Alerts Work (Flow Diagram)

```
┌────────────────────────────────────────────────┐
│            ─ Alert Evaluation Flow             │
└────────────────────────────────────────────────┘

  Metric Collection (every 5-60s)
           ↓
  Store in VictoriaMetrics
           ↓
  Alert Evaluation (every 1 minute) ──────────────┐
           ↓                                      │
  Check Condition                                 │
   • Query: xrpl_peers_connected < 10             │
           ↓                                      │
  Threshold Met?                                  │
   • YES: Start timer                             │
   • NO: Reset timer ─────────────────────────────┘
           ↓
  Duration Elapsed? (e.g., 20 minutes)
   • YES: Fire Alert
   • NO: Keep waiting ────────────────────────────┐
           ↓                                      │
  Send to Contact Points                          │
   • Email                                        │
   • Discord                                      │
   • Slack                                        │
   • etc.                                         │
           ↓                                      │
  Notifications Delivered                         │
           ↓                                      │
  Condition Resolved?                             │
   • YES: Send "Resolved" notification            │
   • NO: Keep firing ─────────────────────────────┘
```

**Key Points:**
- **Evaluation Interval:** Every 1 minute (configurable)
- **Duration Requirement:** Condition must be met for specified time before firing (prevents false alarms)
- **Auto-Resolution:** Alerts automatically resolve when condition clears
- **Multi-Channel:** All enabled contact points receive notifications

---

# Email Alerts

Email is the most universal notification method - works everywhere, no third-party accounts needed (besides email itself).

**In This Section:**
- [Prerequisites](#prerequisites)
- [Step 1: Get SMTP Credentials](#step-1-get-smtp-credentials)
- [Step 2: Configure SMTP in .env File](#step-2-configure-smtp-in-env-file)
- [Step 3: Configure Email Contact Point](#step-3-configure-email-contact-point)
- [Step 4: Recreate Grafana Container](#step-4-recreate-grafana-container)
- [Step 5: Test Email Delivery](#step-5-test-email-delivery)

---

# Prerequisites

You need access to an SMTP server. Options:

**Free Options:**
- **Gmail** (free, 2FA + app passwords required)
- **Yahoo Mail** (free, app passwords)
- **Outlook.com** (free, app passwords)

**Paid/Developer Options:**
- **SendGrid** (free tier: 100 emails/day)
- **Mailgun** (free tier: 5,000 emails/month)
- **AWS SES** (62,000 free emails/month if on AWS)
- **Custom SMTP** (if you run your own mail server)

# Step 1: Get SMTP Credentials

### Using Gmail (Most Common)

1. **Enable 2-Factor Authentication** (required for app passwords)
   - Go to https://myaccount.google.com/security
   - Enable 2-Step Verification if not already enabled

2. **Create App Password**
   - Go to https://myaccount.google.com/apppasswords
   - Select app: "Mail"
   - Select device: "Other" → enter "XRPL Monitor"
   - Click "Generate"
   - **Copy the 16-character password** (you won't see it again)

**Gmail SMTP Settings:**
```
Host: smtp.gmail.com
Port: 587
Username: your-email@gmail.com
Password: xxxx xxxx xxxx xxxx (16-character app password)
From: your-email@gmail.com
```

### Using SendGrid

1. Sign up at https://sendgrid.com
2. Create API Key: Settings → API Keys → Create API Key
3. Choose "Restricted Access" → Mail Send: Full Access
4. Copy API key (starts with `SG.`)

**SendGrid SMTP Settings:**
```
Host: smtp.sendgrid.net
Port: 587
Username: apikey (literally the word "apikey")
Password: SG.your-actual-api-key-here
From: YOUR_EMAIL_HERE
```

### Using Mailgun

1. Sign up at https://mailgun.com
2. Add and verify your domain (or use sandbox domain for testing)
3. Get SMTP credentials from Dashboard → Sending → Domain Settings → SMTP

**Mailgun SMTP Settings:**
```
Host: smtp.mailgun.org
Port: 587
Username: postmaster@your-domain.mailgun.org
Password: (from Mailgun dashboard)
From: YOUR_EMAIL_HERE
```

# Step 2: Configure SMTP in .env File

Add your SMTP settings to the `.env` file in the project root:

```bash
nano .env
```

Add these lines at the end of the file:

```bash
# Email Alert Configuration
GF_SMTP_ENABLED=true
GF_SMTP_HOST=smtp.gmail.com:587
GF_SMTP_USER=your-email@gmail.com
GF_SMTP_PASSWORD=your-16-char-app-password
GF_SMTP_FROM_ADDRESS=your-email@gmail.com
```

**Common SMTP Servers:**
| Provider | SMTP Host |
|----------|-----------|
| Gmail | smtp.gmail.com:587 |
| Outlook/O365 | smtp.office365.com:587 |
| Yahoo | smtp.mail.yahoo.com:587 |
| AWS SES | email-smtp.us-east-1.amazonaws.com:587 |
| SendGrid | smtp.sendgrid.net:587 |
| Mailgun | smtp.mailgun.org:587 |

**Tips:**
- Use port 587 (STARTTLS) - most compatible
- `FROM_ADDRESS` should match your SMTP username
- **Settings are preserved** during updates (`git pull` + `./manage.sh`)

**Example for Gmail:**
```bash
GF_SMTP_ENABLED=true
GF_SMTP_HOST=smtp.gmail.com:587
GF_SMTP_USER=validator@gmail.com
GF_SMTP_PASSWORD=abcd efgh ijkl mnop
GF_SMTP_FROM_ADDRESS=validator@gmail.com
```

# Step 3: Configure Email Contact Point

Edit `config/grafana/provisioning/alerting/contact-points.yaml`:

```bash
sudo nano config/grafana/provisioning/alerting/contact-points.yaml
```

Find the email section (around line 27) and update the email address from `ALERT_EMAIL_ADDRESS` to your email:

```yaml
contactPoints:
  - orgId: 1
    name: xrpl-monitor-email
    receivers:
      - uid: xrpl-email
        type: email
        settings:
          addresses: your-email@gmail.com  # ← Change this to your email
          singleEmail: false
        disableResolveMessage: false
```

**Note:** The contact point is named `xrpl-monitor-email` (not `grafana-default-email`). This avoids conflicts with Grafana's built-in default receiver.

**For multiple recipients:**
```yaml
addresses: admin@example.com;ops@example.com;alerts@example.com
```

**Note:** Semicolon-separated, no spaces between emails.

# Step 4: Recreate Grafana Container

**Important:** Use `--force-recreate` to pick up the new environment variables (a simple restart won't work):

```bash
cd /path/to/xrpl-validator-dashboard
docker compose up -d grafana --force-recreate
```

**Expected output:**
```
[+] Running 2/2
 ✔ Container xrpl-monitor-victoria  Running
 ✔ Container xrpl-monitor-grafana   Started
```

Wait ~15 seconds for Grafana to fully start.

# Step 5: Test Email Delivery

1. Open Grafana: http://localhost:3000
2. Login (default: admin/admin, change password when prompted)
3. Go to **Alerting** → **Contact points** (in left sidebar)
4. Find **"xrpl-monitor-email"**
5. Click **"Test"** button → **"Send test notification"**
6. Check your email inbox

**Expected result:** Email with subject "[FIRING:1] TestAlert..." arrives within 1-2 minutes.

**Optional Cleanup - Orphaned Contact Point:**

If you see a second contact point called `grafana-default-email` marked as "Unused":
- This is Grafana's built-in default that appears when SMTP is enabled
- It's harmless and won't affect your alerts (not connected to any notification policy)
- You can optionally delete it: Click **More** → **Delete**

**If email doesn't arrive:**
- Check spam/junk folder
- Verify SMTP credentials are correct
- Check Grafana logs: `docker compose logs grafana | grep -i smtp`
- See [Troubleshooting](#troubleshooting) section

---

# Webhook Alerts

Webhooks send real-time notifications to chat platforms (Discord, Slack, Teams) or custom endpoints. They're instant, rich-formatted, and mobile-friendly.

**Advantages over email:**
- ⚡ Instant delivery (no email delays)
- 📱 Mobile push notifications
- 🎨 Rich formatting (colors, embeds, buttons)
- 💬 Team collaboration (shared channels)
- 🔗 Clickable links and actions

**In This Section:**
- [Quick Start: Test Webhooks First](#quick-start-test-webhooks-first)
- [Discord Webhooks](#discord-webhooks-recommended-for-xrpl-community)
- [Slack Webhooks](#slack-webhooks)
- [Microsoft Teams Webhooks](#microsoft-teams-webhooks)
- [Telegram Webhooks](#telegram-webhooks)
- [PagerDuty (24/7 On-Call)](#pagerduty-247-on-call)
- [SMS Alerts (TextBee)](#sms-alerts-textbee---free-option)
- [Generic Webhook](#generic-webhook-custom-integrations)
- [Enabling Multiple Channels](#enabling-multiple-channels-simultaneously)

---

# Quick Start: Test Webhooks First

**New to webhooks?** Start here! This tutorial uses a free service to help you understand how webhooks work before configuring Discord, Slack, or other platforms.

Once you're comfortable with this test, move on to the platform-specific sections below.

### Free Webhook Testing Services

| Service | URL | Signup Required | Features |
|---------|-----|-----------------|----------|
| **Pipedream** | https://pipedream.com | Yes (free) | Real-time payload viewer, request history |
| **webhook.site** | https://webhook.site | No | Instant unique URL, no signup |
| **RequestBin** | https://requestbin.com | No | Simple payload inspection |
| **Beeceptor** | https://beeceptor.com | No | Mock API responses |

### Tutorial: Testing with Pipedream

Pipedream provides a clean interface to inspect webhook payloads in real-time. This is a great way to understand how Grafana sends alert data.

#### Step 1: Get Your Test Webhook URL

1. Go to https://pipedream.com and create a free account
2. Click **New** → **HTTP / Webhook** → **New Requests**
3. Copy the unique URL provided (e.g., `https://xxxxxx.m.pipedream.net`)

#### Step 2: Create Webhook Contact Point in Grafana

1. Open Grafana: http://localhost:3000
2. Go to **Alerting** → **Contact points** (left sidebar)
3. Click **"+ Create contact point"** button (top right)
4. Fill in the details:
   - **Name:** `webhook-test`
   - **Integration:** Select **Webhook** from dropdown
5. In the Webhook settings:
   - **URL:** Paste your Pipedream URL
6. Expand **Optional Webhook settings**
7. Set **HTTP Method** dropdown to **POST**
8. Click **"Test"** button → Click **"Send test notification"**
9. Check your Pipedream page - you should see the payload arrive instantly!
10. Click the blue **"Save contact point"** button at the bottom

#### Step 3: Verify the Payload

In Pipedream, you'll see a JSON payload like this:

```json
{
  "receiver": "test",
  "status": "firing",
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "TestAlert",
        "grafana_folder": "Test Folder",
        "instance": "Grafana"
      },
      "annotations": {
        "summary": "Notification test"
      },
      "startsAt": "2025-12-04T05:18:09.535339473Z",
      "endsAt": "0001-01-01T00:00:00Z",
      "fingerprint": "326ea703b01f6100"
    }
  ],
  "groupLabels": { ... },
  "commonLabels": { ... },
  "commonAnnotations": { "summary": "Notification test" },
  "externalURL": "http://localhost:3000/",
  "version": "1"
}
```

**If you see this payload:** ✅ Webhook functionality is working! You now understand how webhooks work and can configure real webhooks (Discord, Slack, etc.) with confidence.

### Why Test with These Services?

- **Verify Grafana can send webhooks** before configuring production endpoints
- **Inspect the exact payload format** to understand what data is sent
- **Debug issues** - if webhook.site receives data but Discord doesn't, the problem is with your Discord webhook URL
- **No cost** - test without setting up Discord servers or Slack workspaces

### After Testing

Once you've confirmed webhooks work:

1. Delete the test contact point (optional)
2. Configure your real webhook (Discord, Slack, etc.) using the sections below
3. The payload format is identical - if the test worked, your real webhook will work too

---

# Discord Webhooks (Recommended for XRPL Community)

Discord is popular in the XRPL community and provides excellent webhook support.

### Step 1: Create Discord Webhook

1. **Open Discord** and navigate to your server
2. **Right-click your server name** → Server Settings
3. Click **Integrations** (left sidebar)
4. Click **Webhooks** → **New Webhook** (or edit existing)
5. **Name it:** "XRPL Validator Alerts"
6. **Choose channel:** Select where alerts should appear (e.g., #validator-alerts)
7. **Optional:** Upload an icon/avatar
8. Click **Copy Webhook URL**

**Example Discord webhook format** (not a real webhook - for reference only):
```
https://discord.com/api/webhooks/1234567890123456789/AbCdEfGhIjKlMnOpQrStUvWxYz1234567890AbCdEfGhIjKlMnOpQrStUvWxYz
```

**Format breakdown:**
- `1234567890123456789` = Webhook ID (18-19 digits)
- `AbCdEfGhIj...` = Webhook Token (68+ alphanumeric characters)

### Step 2: Configure Discord Contact Point

Edit `config/grafana/provisioning/alerting/contact-points.yaml`:

Find the Discord section (around line 50) and **uncomment it**:

```yaml
  # BEFORE (commented out = disabled):
  # - orgId: 1
  #   name: discord-alerts
  #   receivers:
  #     - uid: discord-receiver

  # AFTER (uncommented = enabled):
  - orgId: 1
    name: discord-alerts
    receivers:
      - uid: discord-receiver
        type: discord
        settings:
          url: https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN
          title: "🔔 {{ .GroupLabels.alertname }}"
          message: |-
            **Status:** {{ .Status }}
            **Summary:** {{ .CommonAnnotations.summary }}
            **Description:** {{ .CommonAnnotations.description }}
            **Severity:** {{ .CommonLabels.severity }}
          use_discord_username: true
        disableResolveMessage: false
```

**Replace the webhook URL** with the one you copied from Discord.

### Step 3: Restart Grafana

```bash
docker compose restart grafana
```

### Step 4: Test Discord Webhook

1. Open Grafana → Alerting → Contact points
2. Find "discord-alerts"
3. Click **"Test"** button
4. Check your Discord channel

**Expected result:** Message appears in Discord with:
- 🔔 Icon and alert name
- Color-coded embed (red/yellow/blue based on severity)
- Status, summary, description, severity fields
- Mobile push notification

---

# Slack Webhooks

Slack is popular for team collaboration and has excellent webhook support.

### Step 1: Create Slack Webhook

1. Go to https://api.slack.com/messaging/webhooks
2. Click **"Create your Slack app"** → **"From scratch"**
3. **App Name:** "XRPL Monitor"
4. **Workspace:** Select your Slack workspace
5. Click **"Incoming Webhooks"** (left sidebar)
6. **Toggle "Activate Incoming Webhooks"** to ON
7. Click **"Add New Webhook to Workspace"**
8. **Choose channel** where alerts should appear (e.g., #validator-alerts)
9. Click **"Allow"**
10. **Copy Webhook URL**

**Example Slack webhook format** (not a real webhook - for reference only):
```
https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX
```

**Format breakdown:**
- `T00000000` = Team/Workspace ID
- `B00000000` = Bot/App ID
- `XXXXXXXXXXXXXXXXXXXX` = Secret token (24 characters)

### Step 2: Configure Slack Contact Point

Edit `config/grafana/provisioning/alerting/contact-points.yaml`:

Find the Slack section (around line 81) and **uncomment it**:

```yaml
  - orgId: 1
    name: slack-alerts
    receivers:
      - uid: slack-receiver
        type: slack
        settings:
          url: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
          title: "{{ .GroupLabels.alertname }}"
          text: |-
            *Status:* {{ .Status }}
            *Summary:* {{ .CommonAnnotations.summary }}
            *Description:* {{ .CommonAnnotations.description }}
            *Severity:* {{ .CommonLabels.severity }}
        disableResolveMessage: false
```

### Step 3: Restart and Test

```bash
docker compose restart grafana
```

Test via Grafana UI (Alerting → Contact points → Test button).

---

# Microsoft Teams Webhooks

Teams is popular in enterprise environments.

### Step 1: Create Teams Webhook

1. Open **Microsoft Teams**
2. Navigate to your channel (e.g., "Validator Alerts")
3. Click **⋯** (three dots) next to channel name
4. Select **Connectors**
5. Search for **"Incoming Webhook"**
6. Click **"Add"** or **"Configure"**
7. **Name:** "XRPL Monitor"
8. **Upload image** (optional)
9. Click **"Create"**
10. **Copy webhook URL**

**Example Teams webhook format** (not a real webhook - for reference only):
```
https://outlook.office.com/webhook/a1b2c3d4@e5f6-g7h8/IncomingWebhook/i9j0k1l2/m3n4o5p6
```

### Step 2: Configure Teams Contact Point

Edit `config/grafana/provisioning/alerting/contact-points.yaml`:

Find the Teams section (around line 110) and **uncomment it**:

```yaml
  - orgId: 1
    name: teams-alerts
    receivers:
      - uid: teams-receiver
        type: webhook
        settings:
          url: https://outlook.office.com/webhook/YOUR_WEBHOOK_URL
          httpMethod: POST
          maxAlerts: 10
        disableResolveMessage: false
```

**Note:** Teams uses generic webhook type in Grafana (not dedicated Teams type).

---

# Telegram Webhooks

Telegram provides instant mobile notifications with simple bot setup.

### Step 1: Create Telegram Bot

1. Open **Telegram** app
2. Search for **@BotFather** (official bot for creating bots)
3. Send `/newbot`
4. **Bot name:** "XRPL Monitor" (display name)
5. **Bot username:** "xrpl_monitor_yourname_bot" (must end with "bot")
6. **Copy bot token** (looks like: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

### Step 2: Get Chat ID

**Option A: Create Channel**
1. Create a new Telegram channel (e.g., "Validator Alerts")
2. Add your bot as administrator
3. Send a test message to the channel
4. Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
5. Look for `"chat":{"id":` in the response (e.g., `-1001234567890`)

**Option B: Direct Messages**
1. Start a chat with your bot in Telegram
2. Send any message (e.g., "/start")
3. Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
4. Look for `"chat":{"id":` in the response (e.g., `987654321`)

### Step 3: Configure Telegram Contact Point

Edit `config/grafana/provisioning/alerting/contact-points.yaml`:

Find the Telegram section (around line 190) and **uncomment it**:

```yaml
  - orgId: 1
    name: telegram-alerts
    receivers:
      - uid: telegram-receiver
        type: telegram
        settings:
          bottoken: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz
          chatid: -1001234567890
          message: |-
            🔔 *{{ .GroupLabels.alertname }}*

            *Status:* {{ .Status }}
            *Summary:* {{ .CommonAnnotations.summary }}
            *Severity:* {{ .CommonLabels.severity }}
          parse_mode: Markdown
        disableResolveMessage: false
```

**Replace:**
- `bottoken` with your actual bot token
- `chatid` with your chat/channel ID (include the minus sign if present)

---

# PagerDuty (24/7 On-Call)

PagerDuty is designed for critical alerts requiring immediate response with phone/SMS escalation.

### Step 1: Create PagerDuty Integration

1. Log in to **PagerDuty**
2. Go to **Services** → **Add New Service**
3. **Name:** "XRPL Validator Monitor"
4. **Escalation Policy:** Choose or create policy
5. **Integration Type:** "Use our API directly" → **Events API v2**
6. Click **"Add Service"**
7. **Copy Integration Key** (32-character hex string)

### Step 2: Configure PagerDuty Contact Point

Edit `config/grafana/provisioning/alerting/contact-points.yaml`:

Find the PagerDuty section (around line 163) and **uncomment it**:

```yaml
  - orgId: 1
    name: pagerduty-alerts
    receivers:
      - uid: pagerduty-receiver
        type: pagerduty
        settings:
          integrationKey: a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
          severity: critical
          class: validator
          component: xrpl-monitor
        disableResolveMessage: false
```

**PagerDuty is best used for CRITICAL alerts only.** Consider creating a separate notification policy (advanced topic).

---

# SMS Alerts (TextBee - Free Option)

For direct SMS alerts without paid services like Twilio, [TextBee](https://textbee.dev) offers a free tier that converts an Android phone into an SMS gateway.

### Why TextBee?

- **Free tier:** 50 messages/day, 300/month (plenty for validator alerts)
- **No carrier costs:** Uses your existing phone/plan
- **Simple REST API:** Works with Grafana webhooks
- **Self-hosted:** Your data stays on your device

### Free Tier Limits

| Limit | Free | Pro ($6.99/mo) |
|-------|------|----------------|
| Messages/day | 50 | Unlimited |
| Messages/month | 300 | 5,000 |
| Devices | 1 | 5 |

### Requirements

- Android phone (can be an old spare phone)
- TextBee app installed
- Phone connected to WiFi or mobile data

### Step 1: Set Up TextBee

1. Create account at [textbee.dev](https://textbee.dev)
2. Download TextBee app from [Google Play](https://play.google.com/store/apps/details?id=com.textbee.android)
3. Open the app and sign in
4. Your device will appear in the TextBee dashboard
5. Copy your **API Key** and **Device ID** from the dashboard

### Step 2: Test the API

```bash
# Test sending an SMS (replace with your values)
curl -X POST "https://api.textbee.dev/api/v1/gateway/devices/YOUR_DEVICE_ID/send-sms" \
  -H "x-api-key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "receivers": ["+1234567890"],
    "smsBody": "Test alert from XRPL Monitor"
  }'
```

### Step 3: Configure Grafana Webhook

Edit `config/grafana/provisioning/alerting/contact-points.yaml` and add a new contact point:

```yaml
  - orgId: 1
    name: textbee-sms
    receivers:
      - uid: textbee-receiver
        type: webhook
        settings:
          url: https://api.textbee.dev/api/v1/gateway/devices/YOUR_DEVICE_ID/send-sms
          httpMethod: POST
        disableResolveMessage: false
```

**Note:** TextBee uses `x-api-key` header for authentication. You may need to use a webhook proxy or n8n/Pipedream to transform the request and add the API key header.

### Alternative: Use Pipedream as Webhook Proxy

Since Grafana's webhook doesn't support custom headers like `x-api-key`, use Pipedream as a proxy:

1. Create a Pipedream workflow with HTTP trigger
2. Add a step to forward to TextBee API with your API key
3. Use the Pipedream webhook URL in Grafana

Example Pipedream code step:

```javascript
export default defineComponent({
  async run({ steps, $ }) {
    const response = await fetch(
      `https://api.textbee.dev/api/v1/gateway/devices/${process.env.TEXTBEE_DEVICE_ID}/send-sms`,
      {
        method: 'POST',
        headers: {
          'x-api-key': process.env.TEXTBEE_API_KEY,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          receivers: ['+1234567890'],  // Your phone number
          smsBody: `🚨 ${steps.trigger.event.body.status}: ${steps.trigger.event.body.alerts[0]?.labels?.alertname || 'Alert'}`
        })
      }
    );
    return response.json();
  }
});
```

### Tips

- **Use a spare Android phone** dedicated to SMS alerts
- **Keep it plugged in** and connected to WiFi
- **Test monthly** to ensure the phone is still working
- **Monitor TextBee dashboard** for delivery status

---

# Generic Webhook (Custom Integrations)

Send JSON alerts to any HTTP endpoint - perfect for custom scripts, IFTTT, Zapier, n8n, or custom applications.

### Example Use Cases:
- Trigger custom bash scripts
- Log alerts to custom database
- Forward to IFTTT/Zapier workflows
- Integrate with home automation
- Send to custom monitoring tools

### Configure Generic Webhook

Edit `config/grafana/provisioning/alerting/contact-points.yaml`:

Find the generic webhook section (around line 136) and **uncomment it**:

```yaml
  - orgId: 1
    name: custom-webhook
    receivers:
      - uid: custom-receiver
        type: webhook
        settings:
          url: https://your-custom-endpoint.com/webhook
          httpMethod: POST
          maxAlerts: 10
          # Optional: Add authentication
          # authorization_scheme: Bearer
          # authorization_credentials: YOUR_API_TOKEN
        disableResolveMessage: false
```

**JSON payload sent to your endpoint:**
```json
{
  "receiver": "custom-webhook",
  "status": "firing",
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "ValidatorNotProposing",
        "severity": "critical"
      },
      "annotations": {
        "summary": "Validator has stopped proposing",
        "description": "The validator server state is not 'proposing'. Current state: full"
      },
      "startsAt": "2025-11-19T10:30:00Z",
      "endsAt": "0001-01-01T00:00:00Z",
      "fingerprint": "a1b2c3d4e5f6g7h8"
    }
  ],
  "groupLabels": {
    "alertname": "ValidatorNotProposing"
  },
  "commonLabels": {
    "alertname": "ValidatorNotProposing",
    "severity": "critical"
  },
  "commonAnnotations": {
    "summary": "Validator has stopped proposing",
    "description": "The validator server state is not 'proposing'. Current state: full"
  }
}
```

See [Integration Examples](#integration-examples) for custom webhook scripts.

---

# Enabling Multiple Channels Simultaneously

**You can enable ALL channels at once!** Alerts will be sent to every uncommented contact point.

**Example: Email + Discord + Slack:**

```yaml
contactPoints:
  # Email (enabled)
  - orgId: 1
    name: xrpl-monitor-email
    receivers:
      - uid: xrpl-email
        type: email
        settings:
          addresses: YOUR_EMAIL_HERE

  # Discord (enabled)
  - orgId: 1
    name: discord-alerts
    receivers:
      - uid: discord-receiver
        type: discord
        settings:
          url: https://discord.com/api/webhooks/...

  # Slack (enabled)
  - orgId: 1
    name: slack-alerts
    receivers:
      - uid: slack-receiver
        type: slack
        settings:
          url: https://hooks.slack.com/...

  # Telegram (disabled - commented out)
  # - orgId: 1
  #   name: telegram-alerts
```

**Result:** When an alert fires, you'll receive:
- ✅ Email notification
- ✅ Discord message
- ✅ Slack message
- ❌ NO Telegram message (commented out)

**Recommended combinations:**
- **Solo operator:** Email + Discord (redundancy)
- **Team:** Slack + PagerDuty (collaboration + on-call)
- **Mobile-first:** Telegram + Discord (instant notifications)

---

# Testing & Validation

This section covers testing your alert setup and understanding notifications.

**In This Section:**
- [Understanding contact-points.yaml](#understanding-contact-pointsyaml)
- [Testing Your Alert Setup](#testing-your-alert-setup)
- [Understanding Alert Notifications](#understanding-alert-notifications)

---

# Understanding contact-points.yaml

**File location:** `config/grafana/provisioning/alerting/contact-points.yaml`

This file defines **where** alert notifications are sent. Think of it as your notification routing table.

### File Structure

```yaml
contactPoints:
  - orgId: 1                    # Organization ID (always 1 for single-org)
    name: discord-alerts        # Contact point name (shows in Grafana UI)
    receivers:                  # List of receivers (usually one per contact point)
      - uid: discord-receiver   # Unique ID for this receiver
        type: discord           # Notification type (discord, email, slack, etc.)
        settings:               # Type-specific configuration
          url: https://...      # Discord webhook URL
        disableResolveMessage: false  # Send notification when alert resolves?
```

### How It Works

1. **Provisioning on startup**: Grafana reads this file when it starts
2. **Auto-registration**: Contact points are created/updated automatically
3. **Default routing**: All alerts send to ALL enabled contact points
4. **Enable/disable**: Uncomment to enable, comment to disable

### Enabling a Contact Point

**Before (disabled):**
```yaml
  # - orgId: 1
  #   name: discord-alerts
  #   receivers:
  #     - uid: discord-receiver
  #       type: discord
  #       settings:
  #         url: https://discord.com/api/webhooks/...
```

**After (enabled):**
```yaml
  - orgId: 1
    name: discord-alerts
    receivers:
      - uid: discord-receiver
        type: discord
        settings:
          url: https://discord.com/api/webhooks/...
```

**Key change:** Remove the `#` comment character from the beginning of each line.

### When to Edit This File

**✅ Edit contact-points.yaml when:**
- Adding your first notification channel
- Enabling/disabling specific channels
- Changing webhook URLs or email addresses
- Adding custom notification endpoints

**❌ Do NOT edit this file for:**
- Adjusting alert thresholds (use `alert-rules.yaml`)
- Changing which metrics trigger alerts (use `alert-rules.yaml`)
- Modifying alert evaluation frequency (use `alert-rules.yaml`)

### After Editing

**Always restart Grafana to apply changes:**
```bash
docker compose restart grafana
```

**Verify in Grafana UI:**
1. Open Grafana → Alerting → Contact points
2. Confirm your enabled contact points appear in the list
3. Use "Test" button to verify delivery

### Common Settings Explained

**disableResolveMessage:**
```yaml
disableResolveMessage: false  # Send notification when alert resolves (default)
disableResolveMessage: true   # Only send when alert fires, not when it resolves
```

**Why you might disable resolve messages:**
- Using PagerDuty (incidents auto-resolve)
- Only care about problems, not fixes
- Reducing notification volume

**Recommendation:** Keep `false` (default) - it's helpful to know when problems are fixed!

---

# Testing Your Alert Setup

After configuring contact points, always test before relying on them in production.

### Method 1: Grafana UI Test Button (Recommended)

This is the easiest and fastest way to test.

**Steps:**
1. Open Grafana: http://localhost:3000
2. Go to **Alerting** → **Contact points** (left sidebar)
3. Find your contact point (e.g., "discord-alerts")
4. Click **"Test"** button (on the right)
5. Modal appears: "Send test notification"
6. Click **"Send test notification"**
7. Check your notification channel (email, Discord, Slack, etc.)

**Expected result:** Test notification arrives within 10-30 seconds with:
- Title: "Test notification"
- Message: "Someone is testing the alert notification within Grafana"

**If test succeeds:** ✅ Your contact point is configured correctly!

**If test fails:** See [Troubleshooting](#troubleshooting) section.

### Method 2: Force an Alert to Fire

For more realistic testing, trigger an actual alert condition.

**Example: Force "Peer Count Low" alert**

**Temporary threshold adjustment:**

1. Edit `config/grafana/provisioning/alerting/alert-rules.yaml`
2. Find "Peer Count Low" rule (around line 8)
3. Change threshold from `< 10` to `< 999` (will always trigger):
   ```yaml
   expr: xrpl_peers_connected < 999  # Temporarily lowered
   ```
4. Restart Grafana: `docker compose restart grafana`
5. Wait 20 minutes (duration in rule)
6. Check notifications arrive
7. **Revert change** back to `< 10`
8. Restart Grafana again

**Warning:** Don't leave test thresholds in place - you'll get constant alerts!

### Method 3: View Alert History

Check if alerts have fired in the past (useful after initial setup).

**Steps:**
1. Grafana → **Alerting** (left sidebar) → **Alert rules**
2. Look for alert state indicators:
   - 🟢 **Normal** - No active alert
   - 🔴 **Firing** - Alert currently active
   - 🟡 **Pending** - Condition met, waiting for duration
3. **Click on any alert name** to open the detail view
4. Click the **"State history"** tab (at the top)
5. Review past firing/resolution times with timestamps

**What you'll see:**
- Timeline of when alert fired and resolved
- Duration of each alert instance
- Annotations with alert details

### Method 4: Check Grafana Logs

Verify notifications are being sent successfully.

```bash
# Watch for notification logs in real-time
docker compose logs -f grafana | grep -i "alert\|notification"

# Check recent notification attempts
docker compose logs grafana --tail 100 | grep -i notification

# Look for errors
docker compose logs grafana | grep -i "error.*notification"
```

**Successful notification log example:**
```
logger=alerting.notifier.discord uid=discord-receiver t=2025-11-19T10:30:00+00:00 level=info msg="Notification sent successfully"
```

**Failed notification log example:**
```
logger=alerting.notifier.discord uid=discord-receiver t=2025-11-19T10:30:00+00:00 level=error msg="Failed to send notification" error="webhook returned 404"
```

### Test Checklist

Before relying on alerts in production, verify:

- [ ] Test notification received via Grafana UI test button
- [ ] Correct email address / webhook URL configured
- [ ] Notifications include alert name, status, summary
- [ ] Mobile notifications work (if using Discord/Telegram/Slack)
- [ ] Resolve messages arrive when alert clears
- [ ] Multiple channels work simultaneously (if configured)
- [ ] Alert history visible in Grafana UI
- [ ] No errors in Grafana logs

---

# Understanding Alert Notifications

When an alert fires, you'll receive a notification with details about what's wrong.

### Notification Anatomy

All notifications include:

**Core Fields:**
- **Alert Name** - Which alert fired (e.g., "Validator Not Proposing")
- **Status** - "Firing" (problem exists) or "Resolved" (problem fixed)
- **Severity** - "critical", "warning", or "info"
- **Summary** - One-line description of the issue
- **Description** - Detailed explanation and recommended actions

**Metadata:**
- **Timestamp** - When alert was triggered
- **Fingerprint** - Unique ID for this alert instance

### Example Notifications

#### Email Notification

**Subject:**
```
[FIRING] Validator Not Proposing
```

**Body:**
```
Alert: Validator Not Proposing
Status: FIRING
Severity: critical

Summary: Validator has stopped proposing

Description: The validator server state is not 'proposing'.
Current state: full. This means your validator is not
participating in consensus.

Recommended Actions:
- Check rippled logs: docker logs rippled | tail -100
- Verify validator keys are configured
- Check network connectivity to peers

Time: 2025-11-19 10:30:00 UTC
```

#### Discord Notification

**Discord Rich Embed:**
```
┌─────────────────────────────────────────┐
│ 🔔 Validator Not Proposing              │ RED
├─────────────────────────────────────────┤
│ Status:       FIRING                    │
│ Severity:     critical                  │
│ Summary:      Validator has stopped     │
│               proposing                 │
│ Description:  The validator server      │
│               state is not 'proposing'  │
│                                         │
│ 2025-11-19 10:30:00 UTC                 │
└─────────────────────────────────────────┘
```

**Color coding:**
- 🔴 Red embed: Critical alerts
- 🟡 Yellow embed: Warning alerts
- 🔵 Blue embed: Info alerts

#### Slack Notification

```
🔔 Validator Not Proposing

Status: FIRING
Severity: critical
Summary: Validator has stopped proposing
Description: The validator server state is not 'proposing'. Current state: full

2025-11-19 10:30:00 UTC
```

#### Telegram Notification

```
🔔 *Validator Not Proposing*

*Status:* FIRING
*Severity:* critical
*Summary:* Validator has stopped proposing

2025-11-19 10:30:00 UTC
```

### Alert States

**🟢 Normal** - No issues detected
- Condition not met
- No notification sent

**🟡 Pending** - Condition met, waiting for duration
- Threshold crossed, but duration not elapsed yet
- Example: Peers < 10, waiting for 20 minutes
- No notification sent yet (prevents false alarms)

**🔴 Firing** - Alert active
- Condition met AND duration elapsed
- Notification sent to all contact points
- Will continue firing until resolved

**✅ Resolved** - Alert cleared
- Condition no longer met
- "Resolved" notification sent to all contact points
- Returns to Normal state

### Reading Alert Messages

**Critical alerts require immediate action:**
```
🔴 FIRING: Validator Not Proposing
→ Check your validator immediately
→ Review rippled logs
→ Verify configuration
```

**Warning alerts need attention soon:**
```
🟡 FIRING: Peer Count Low
→ Investigate network issues
→ Check firewall rules
→ Monitor for improvement
```

**Info alerts are for awareness:**
```
🔵 FIRING: High IO Latency (Trending Up)
→ Note the trend
→ Plan infrastructure review
→ Monitor disk health
```

---

# Operations

This section covers day-to-day management of alerts.

**In This Section:**
- [Managing Alert Fatigue](#managing-alert-fatigue)
- [Troubleshooting](#troubleshooting)

---

# Managing Alert Fatigue

Too many alerts = alert fatigue = ignoring important alerts. Here's how to tune your alerts effectively.

### Understanding Alert Fatigue

**Symptoms:**
- Receiving alerts constantly
- Ignoring alerts because they're "always firing"
- Missing critical alerts buried in noise
- Disabling alerts entirely out of frustration

**Root causes:**
- Thresholds too sensitive for your environment
- No duration requirement (alerts fire immediately)
- Alerts for non-actionable issues

### Adjusting Alert Thresholds

Alerts come with sensible defaults, but your environment may differ.

**Example: Peer Count Low**

**Default:** `< 10 peers for 20 minutes`

**Your situation:** You run a private validator with 8 trusted peers only.

**Fix:** Lower threshold to match your setup:

Edit `config/grafana/provisioning/alerting/alert-rules.yaml`:

```yaml
- title: Peer Count Low
  condition: C
  data:
  - refId: A
    model:
      expr: xrpl_peers_connected < 5  # Changed from 10 to 5
```

Restart Grafana:
```bash
docker compose restart grafana
```

### Adjusting Alert Duration

Duration prevents false alarms from temporary blips.

**Example: High Load Factor**

**Default:** `> 100 for 15 minutes`

**Your situation:** Your server often spikes to 150 briefly during ledger closes, but recovers.

**Fix:** Increase duration to ignore brief spikes:

```yaml
- title: High Load Factor
  for: 30m  # Changed from 15m to 30m - must be sustained
```

**Guideline:**
- **Short duration (5-10m):** Critical issues requiring immediate action
- **Medium duration (15-30m):** Performance issues needing investigation
- **Long duration (30m+):** Trends and informational alerts

### Silencing Alerts During Maintenance

Performing maintenance? Don't get spammed with alerts!

**Create a Silence:**

1. Grafana → Alerting → Silences
2. Click **"Add Silence"**
3. **Matcher:** `alertname =~ .*` (matches all alerts)
4. **Duration:** 2 hours (or your maintenance window)
5. **Comment:** "Scheduled maintenance: rippled upgrade"
6. Click **"Create"**

**Result:** No alerts will fire during the silence period.

**Silence specific alerts only:**
```
Matcher: alertname = ValidatorNotProposing
```

### Best Practices for Alert Tuning

**1. Start with defaults, tune based on real data**
- Run for 1 week with defaults
- Review alert history
- Identify false positives
- Adjust thresholds

**2. Make thresholds environment-specific**
- High-performance server? Increase load factor threshold
- Limited peers? Lower peer count threshold
- NVMe storage? Lower I/O latency threshold

**3. Use appropriate duration for severity**
- Critical alerts: Short duration (5-10m)
- Warning alerts: Medium duration (15-30m)
- Info alerts: Long duration (30m+)

**4. Document your changes**
```yaml
# Custom threshold for our 8-peer private validator setup
expr: xrpl_peers_connected < 5  # Default was 10
```

### When to Disable an Alert Entirely

**Disable if:**
- Alert fires constantly with no action possible
- Alert is not relevant to your setup (e.g., peer latency on localhost-only setup)
- You have better monitoring elsewhere

**How to disable:**
Comment out the entire rule in `alert-rules.yaml` or delete via Grafana UI.

**Warning:** Don't disable critical alerts! If "Validator Not Proposing" fires constantly, fix the root cause, don't silence the symptom.

---

# Troubleshooting

Common issues and solutions when alerts don't work as expected.

### Email Notifications Not Arriving

**Symptom:** Test notification says "sent" but email never arrives.

**Diagnosis:**

1. **Check spam/junk folder**
   - Gmail often flags automated emails as spam
   - Mark as "Not Spam" to whitelist future emails

2. **Verify SMTP credentials**
   ```bash
   # Check Grafana logs for SMTP errors
   docker compose logs grafana | grep -i smtp
   ```

   **Common errors:**
   - `535 Authentication failed` - Wrong username/password
   - `554 Sender address rejected` - FROM address doesn't match SMTP username
   - `Connection refused` - Wrong port or firewall blocking

3. **Test SMTP manually**
   ```bash
   # Test SMTP connection (replace with your settings)
   docker run --rm -it alpine/curl curl -v \
     --url 'smtp://smtp.gmail.com:587' \
     --ssl-reqd \
     --mail-from 'YOUR_EMAIL_HERE' \
     --mail-rcpt 'YOUR_EMAIL_HERE' \
     --user 'YOUR_EMAIL_HERE:your-app-password' \
     -T - <<EOF
   Subject: Test from XRPL Monitor

   This is a test email.
   EOF
   ```

4. **Verify docker-compose.yml**
   ```yaml
   # Common mistakes:
   - GF_SMTP_HOST=smtp.gmail.com:587  # ✅ Correct
   - GF_SMTP_HOST=smtp.gmail.com      # ❌ Missing port
   - GF_SMTP_USER=your-email@gmail.com # ✅ Correct
   - GF_SMTP_PASSWORD=your app password # ✅ Correct (spaces OK for app passwords)
   ```

5. **Check email provider limits**
   - Gmail free: 500 emails/day
   - SendGrid free tier: 100 emails/day
   - If over limit, emails will be rejected

**Solutions:**
- Use app password, not account password (Gmail, Yahoo)
- Ensure FROM address matches SMTP username
- Check firewall isn't blocking port 587
- Try different SMTP provider (SendGrid, Mailgun)

### Webhook Notifications Not Arriving

**Symptom:** Test notification fails or webhook never receives messages.

**Diagnosis:**

1. **Check webhook URL is valid**
   ```bash
   # Test Discord webhook manually
   curl -X POST "YOUR_DISCORD_WEBHOOK_URL" \
     -H "Content-Type: application/json" \
     -d '{"content":"Test from command line"}'

   # Should return HTTP 204 (success) or create message in Discord
   ```

2. **Verify webhook URL format**
   - Discord: `https://discord.com/api/webhooks/{ID}/{TOKEN}`
   - Slack: `https://hooks.slack.com/services/{T}/{B}/{TOKEN}`
   - Teams: `https://outlook.office.com/webhook/...`

3. **Check Grafana logs**
   ```bash
   docker compose logs grafana | grep -i "discord\|slack\|webhook"
   ```

   **Common errors:**
   - `404 Not Found` - Webhook URL is incorrect or deleted
   - `401 Unauthorized` - Webhook token is wrong
   - `429 Too Many Requests` - Rate limited (too many notifications)

4. **Verify contact point is uncommented**
   ```yaml
   # ❌ Wrong - commented out (disabled)
   # - orgId: 1
   #   name: discord-alerts

   # ✅ Correct - uncommented (enabled)
   - orgId: 1
     name: discord-alerts
   ```

5. **Restart Grafana after changes**
   ```bash
   docker compose restart grafana
   ```

**Solutions:**
- Regenerate webhook URL (webhook may have been deleted)
- Ensure webhook URL has no extra spaces or line breaks
- Check webhook isn't rate limited (wait 5 minutes and retry)
- Verify bot has permissions in Discord/Slack channel

### Alerts Not Firing When Expected

**Symptom:** Condition is met but alert doesn't fire.

**Diagnosis:**

1. **Check alert state in Grafana UI**
   - Grafana → Alerting → Alert rules
   - Find your alert
   - Look at state: Normal, Pending, Firing?

2. **Verify query returns data**
   - Click on alert rule
   - Click "Query" tab
   - Check if query returns results
   - If empty, metric might not exist

3. **Check duration requirement**
   ```yaml
   for: 20m  # Condition must be met for 20 minutes before firing
   ```

   If condition just started, wait for duration to elapse.

4. **Check evaluation interval**
   ```yaml
   interval: 1m  # Alert checked every 1 minute
   ```

   Alert won't fire instantly - waits for next evaluation.

5. **Verify datasource is working**
   - Grafana → Configuration → Data Sources
   - Click "VictoriaMetrics"
   - Click "Test" button
   - Should show "Data source is working"

**Solutions:**
- Wait for duration to elapse (check "Pending" state)
- Verify metric exists: `curl http://localhost:8428/api/v1/query?query=xrpl_peers_connected`
- Check collector is running: `docker compose ps`
- Review alert rule query syntax

### Alerts Firing Too Frequently

**Symptom:** Same alert fires every few minutes (alert flapping).

**Cause:** Metric oscillates around threshold (e.g., peers = 9, 11, 9, 11...)

**Solutions:**

1. **Increase duration**
   ```yaml
   for: 30m  # Increased from 15m - reduces flapping
   ```

2. **Adjust threshold with buffer**
   ```yaml
   # Before: Fires at exactly 10
   expr: xrpl_peers_connected < 10

   # After: Fires at 8 (gives 2-peer buffer)
   expr: xrpl_peers_connected < 8
   ```

3. **Use time-based aggregation**
   ```yaml
   # Average over 5 minutes instead of instant value
   expr: avg_over_time(xrpl_peers_connected[5m]) < 10
   ```

### Grafana Logs Show Errors

**Check logs:**
```bash
docker compose logs grafana --tail 100
```

**Common errors:**

**Error:** `failed to provision alert rules`
- **Cause:** Syntax error in alert-rules.yaml
- **Solution:** Validate YAML syntax, check for tabs vs spaces

**Error:** `failed to send notification: context deadline exceeded`
- **Cause:** Webhook endpoint timeout
- **Solution:** Check webhook URL is reachable, increase timeout in settings

**Error:** `unauthorized`
- **Cause:** Wrong credentials (SMTP, webhook token)
- **Solution:** Regenerate credentials, update configuration

---

# Advanced Topics

This section covers customization and advanced configurations.

**In This Section:**
- [Advanced Configuration](#advanced-configuration)
- [Notification Channel Comparison](#notification-channel-comparison)
- [Security Best Practices](#security-best-practices)
- [Integration Examples](#integration-examples)

---

# Advanced Configuration

### Creating Custom Alert Rules

Want to monitor something specific to your setup? Create custom alert rules.

#### Example: Alert When Ledger Age Exceeds 10 Seconds

**Option A: Via Grafana UI** (Easiest)

1. **Open Grafana** → Alerting → Alert rules
2. Click **"New alert rule"**
3. **Enter details:**
   - **Alert name:** Ledger Age High
   - **Folder:** XRPL Validator Network Alerts
4. **Define query:**
   - **Query A:** `xrpl_ledger_age_seconds > 10`
   - **Datasource:** VictoriaMetrics
5. **Set condition:**
   - **Type:** Threshold
   - **When:** Last value
   - **Is above:** 10
6. **Configure evaluation:**
   - **Evaluate every:** 1m
   - **For:** 5m (wait 5 minutes before firing)
7. **Add annotations:**
   - **Summary:** Ledger age exceeds 10 seconds
   - **Description:** Node may be falling behind the network
8. **Save** (top right)

**Option B: Via YAML File** (Reproducible, Version Controlled)

Edit `config/grafana/provisioning/alerting/alert-rules.yaml`:

Add a new rule under `groups[].rules[]`:

```yaml
groups:
- name: Network Monitoring
  folder: XRPL Validator Network Alerts
  interval: 1m
  rules:
  # ... existing rules ...

  # Your custom rule (add at the end)
  - uid: custom-ledger-age-high
    title: Ledger Age High
    condition: C
    data:
    - refId: A
      queryType: ''
      relativeTimeRange:
        from: 600
        to: 0
      datasourceUid: victoria
      model:
        editorMode: code
        expr: xrpl_ledger_age_seconds > 10
        instant: true
        refId: A
    - refId: C
      queryType: ''
      datasourceUid: __expr__
      model:
        conditions:
        - evaluator:
            params: [10]
            type: gt
          operator:
            type: and
          query:
            params: [C]
          reducer:
            params: []
            type: last
          type: query
        expression: A
        refId: C
        type: threshold
    for: 5m
    annotations:
      summary: Ledger age exceeds 10 seconds
      description: Node may be falling behind the network. Check rippled sync status.
    labels:
      severity: warning
```

**Restart Grafana:**
```bash
docker compose restart grafana
```

### Available Metrics for Custom Alerts

See [METRICS.md](METRICS.md) for the complete list. Common ones for alerts:

**Validator Metrics:**
- `xrpl_ledger_age_seconds` - How old the current ledger is
- `xrpl_validations_agreements_1h` - Validations in last hour
- `xrpl_validations_agreements_24h` - Validations in last 24 hours
- `xrpl_server_state` - Current server state (0-6)
- `xrpl_server_load_factor` - Server load
- `xrpl_peers_connected` - Number of connected peers

**System Metrics:**
- `node_memory_MemAvailable_bytes` - Available RAM
- `node_cpu_seconds_total` - CPU usage
- `node_disk_io_time_seconds_total` - Disk I/O time
- `node_filesystem_avail_bytes` - Free disk space

**Example PromQL Queries:**

```promql
# Alert if validator hasn't agreed in 10 minutes
rate(xrpl_validations_agreements_1h[10m]) == 0

# Alert if disk space < 10 GB
node_filesystem_avail_bytes{mountpoint="/"} < 10 * 1024 * 1024 * 1024

# Alert if CPU usage > 90% for 10 minutes
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90

# Alert if memory usage > 90%
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
```

### Advanced Alert Routing

**Scenario:** Send critical alerts to PagerDuty, warnings to Slack, info to email.

This requires Grafana's **notification policies** (advanced feature).

**Quick setup:**

1. Grafana → Alerting → Notification policies
2. Click **"New nested policy"**
3. **Matcher:** `severity = critical`
4. **Contact point:** PagerDuty
5. Repeat for `severity = warning` → Slack
6. Default policy: Email

**Result:**
- 🔴 Critical alerts → PagerDuty (phone/SMS)
- 🟡 Warning alerts → Slack (team channel)
- 🔵 Info alerts → Email (reference)

**Learn more:** [Grafana Notification Policies Documentation](https://grafana.com/docs/grafana/latest/alerting/manage-notifications/create-notification-policy/)

### Customizing Alert Messages

Want different message templates for different channels?

Edit `config/grafana/provisioning/alerting/contact-points.yaml`:

```yaml
- orgId: 1
  name: discord-alerts
  receivers:
    - uid: discord-receiver
      type: discord
      settings:
        url: YOUR_WEBHOOK_URL
        # Custom message template
        title: "🚨 {{ .GroupLabels.alertname }}"
        message: |-
          **{{ .Status | toUpper }}**

          📊 **Summary:** {{ .CommonAnnotations.summary }}
          📝 **Details:** {{ .CommonAnnotations.description }}
          ⚠️ **Severity:** {{ .CommonLabels.severity }}
          ⏰ **Time:** {{ .StartsAt.Format "2006-01-02 15:04:05 MST" }}

          [View Dashboard](http://localhost:3000)
```

**Template variables available:**
- `{{ .Status }}` - "firing" or "resolved"
- `{{ .GroupLabels.alertname }}` - Alert name
- `{{ .CommonAnnotations.summary }}` - Alert summary
- `{{ .CommonAnnotations.description }}` - Alert description
- `{{ .CommonLabels.severity }}` - Alert severity
- `{{ .StartsAt }}` - When alert started

**Learn more:** [Grafana Template Variables](https://grafana.com/docs/grafana/latest/alerting/manage-notifications/template-notifications/)

---

# Notification Channel Comparison

Choosing the right notification channel(s) for your needs.

| Feature | Email | Discord | Slack | Teams | Telegram | PagerDuty |
|---------|-------|---------|-------|-------|----------|-----------|
| **Setup Time** | 5-10 min | 2 min | 5 min | 5 min | 3 min | 10 min |
| **Cost** | Free* | Free | Free† | Free† | Free | Paid‡ |
| **Mobile Push** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |
| **Rich Formatting** | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes | ⚠️ Limited | ✅ Yes |
| **Color Coding** | ❌ No | ✅ Yes | ⚠️ Limited | ✅ Yes | ❌ No | ✅ Yes |
| **Instant Delivery** | ⚠️ 1-5 min | ✅ < 1 sec | ✅ < 1 sec | ✅ < 1 sec | ✅ < 1 sec | ✅ < 1 sec |
| **Team Collaboration** | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes | ⚠️ Limited | ✅ Yes |
| **Phone/SMS Escalation** | ❌ No | ❌ No | ❌ No | ❌ No | ❌ No | ✅ Yes |
| **24/7 On-Call** | ❌ No | ❌ No | ❌ No | ❌ No | ❌ No | ✅ Yes |

**Notes:**
- *Email: Free with existing email account, may have send limits (Gmail: 500/day)
- †Slack/Teams: Free tier has limitations, paid plans for larger teams
- ‡PagerDuty: Starts at $19/user/month, essential for 24/7 operations

### Recommended Combinations

**Solo Validator Operator:**
```
Email + Discord
```
- Email for permanent record
- Discord for instant mobile alerts
- Redundancy (if one fails, other works)

**Small Team (2-5 people):**
```
Slack + Email
```
- Slack for team collaboration
- Email for individual awareness
- All team members get alerts

**Large Team / Enterprise:**
```
Slack + PagerDuty + Email
```
- Slack for team awareness
- PagerDuty for on-call rotation
- Email for audit trail

**Mission-Critical Mainnet Validator:**
```
PagerDuty + Discord + Email
```
- PagerDuty for critical alerts (phone/SMS)
- Discord for team chat
- Email for records

**Budget-Conscious / Hobby:**
```
Discord only
```
- Free, instant, mobile notifications
- Rich formatting
- No complex setup

---

# Security Best Practices

Protecting your notification credentials and preventing alert spam.

### Protecting Webhook URLs

**Webhook URLs are secrets** - they allow anyone who has them to send messages to your channel.

**❌ Don't:**
- Commit webhook URLs to public git repositories
- Share webhook URLs in public chat/forums
- Include webhook URLs in screenshots
- Store webhook URLs in plaintext files

**✅ Do:**
- Keep webhook URLs in `contact-points.yaml` (not committed to git if in `.gitignore`)
- Use environment variables for webhook URLs (advanced)
- Regenerate webhook if accidentally exposed
- Use private git repositories only

**If webhook URL is leaked:**
1. Delete the webhook in Discord/Slack/etc.
2. Create a new webhook
3. Update `contact-points.yaml` with new URL
4. Restart Grafana

### SMTP Password Security

**SMTP passwords are account credentials** - protect them carefully.

**✅ Use app passwords, not account passwords:**
- Gmail: Generate app password (16 characters, spaces OK)
- Outlook: Generate app password
- **Never use your actual email password**

**Benefits of app passwords:**
- Can be revoked independently
- Don't compromise your main email account if leaked
- Work even with 2FA enabled

**If SMTP password is leaked:**
1. Revoke app password in email provider settings
2. Generate new app password
3. Update `.env`
4. Restart Grafana

### Avoid Committing Secrets to Git

**Problem:** Accidentally committing secrets to a public GitHub repository.

**Solution: Use .env file (Already Configured)**

XRPL Monitor is already configured to use `.env` for secrets. The `.env` file is gitignored by default.

```bash
# .env (gitignored - never committed)
GF_SMTP_ENABLED=true
GF_SMTP_HOST=smtp.gmail.com:587
GF_SMTP_USER=your-email@gmail.com
GF_SMTP_PASSWORD=your-app-password
GF_SMTP_FROM_ADDRESS=your-email@gmail.com
```

**Benefits:**
- Secrets stay out of git history
- Settings are preserved during updates (`git pull` + `./manage.sh`)
- Easy to backup separately from code

**Note:** The `docker-compose.yml` references these via `${GF_SMTP_USER:-}` syntax - you don't need to edit it

### Network Security

**Grafana admin interface** should not be publicly accessible.

**✅ Secure access:**
- Use SSH tunnel: `ssh -L 3000:localhost:3000 user@validator-server`
- Use VPN for remote access
- Restrict to specific IPs with firewall

**❌ Don't:**
- Expose Grafana port 3000 to the public internet without authentication
- Use default `admin`/`admin` password (change immediately)
- Disable HTTPS for public access

---

# Integration Examples

Real-world examples of using webhooks with external services.

### Example 1: Trigger Bash Script on Alert

Send alert to custom webhook that triggers local bash script.

**1. Create webhook receiver script:**

`/usr/local/bin/alert-handler.sh`:
```bash
#!/bin/bash
# Alert webhook receiver
# Triggered by generic webhook from Grafana

# Parse JSON from stdin
read -r payload

# Extract alert details
status=$(echo "$payload" | jq -r '.status')
alertname=$(echo "$payload" | jq -r '.alerts[0].labels.alertname')
severity=$(echo "$payload" | jq -r '.alerts[0].labels.severity')

# Log to file
echo "$(date): $status - $alertname ($severity)" >> /var/log/xrpl-alerts.log

# Take action based on severity
if [ "$severity" = "critical" ]; then
  # Send SMS via Twilio (example)
  curl -X POST "https://api.twilio.com/2010-04-01/Accounts/$TWILIO_SID/Messages.json" \
    -u "$TWILIO_SID:$TWILIO_TOKEN" \
    -d "From=+1234567890" \
    -d "To=+1987654321" \
    -d "Body=CRITICAL: $alertname"

  # Or trigger server health check
  /usr/local/bin/check-rippled-health.sh
fi
```

**2. Set up webhook endpoint:**

Use a simple HTTP server to receive webhooks:
```bash
# Install webhook listener
sudo apt-get install webhook

# Configure webhook
# /etc/webhook.conf
[
  {
    "id": "grafana-alert",
    "execute-command": "/usr/local/bin/alert-handler.sh",
    "command-working-directory": "/tmp",
    "response-message": "Alert received"
  }
]

# Start webhook listener
webhook -hooks /etc/webhook.conf -verbose -port 9000
```

**3. Configure Grafana to send to webhook:**

`contact-points.yaml`:
```yaml
- orgId: 1
  name: custom-bash-script
  receivers:
    - uid: custom-receiver
      type: webhook
      settings:
        url: http://localhost:9000/hooks/grafana-alert
        httpMethod: POST
```

### Example 2: Forward Alerts to IFTTT

**1. Create IFTTT applet:**
- Go to https://ifttt.com
- Create new applet
- **If:** Webhooks → Receive web request
- **Event name:** "xrpl_alert"
- **Then:** Choose action (SMS, notification, Google Sheets log, etc.)
- Copy webhook URL

**2. Configure Grafana:**

`contact-points.yaml`:
```yaml
- orgId: 1
  name: ifttt-alerts
  receivers:
    - uid: ifttt-receiver
      type: webhook
      settings:
        url: https://maker.ifttt.com/trigger/xrpl_alert/with/key/YOUR_IFTTT_KEY
        httpMethod: POST
```

**Use cases:**
- Log alerts to Google Sheets
- Send SMS via IFTTT
- Flash smart lights red on critical alerts
- Post to Twitter/X (automated status updates)

### Example 3: Alert Database Logging

Log all alerts to SQLite database for analysis.

**Python webhook receiver with SQLite:**

`alert-logger.py`:
```python
import sqlite3
import json
from flask import Flask, request

app = Flask(__name__)

# Initialize database
conn = sqlite3.connect('alerts.db', check_same_thread=False)
c = conn.cursor()
c.execute('''CREATE TABLE IF NOT EXISTS alerts
             (timestamp TEXT, status TEXT, alertname TEXT,
              severity TEXT, summary TEXT, description TEXT)''')
conn.commit()

@app.route('/webhook', methods=['POST'])
def webhook():
    data = request.json
    alert = data['alerts'][0]

    c.execute('''INSERT INTO alerts VALUES (?, ?, ?, ?, ?, ?)''',
              (alert.get('startsAt'),
               data.get('status'),
               alert['labels'].get('alertname'),
               alert['labels'].get('severity'),
               data['commonAnnotations'].get('summary'),
               data['commonAnnotations'].get('description')))
    conn.commit()

    return 'OK', 200

if __name__ == '__main__':
    app.run(port=9000)
```

**Query alerts:**
```bash
sqlite3 alerts.db "SELECT * FROM alerts WHERE severity='critical' ORDER BY timestamp DESC LIMIT 10"
```

---

# Reference

Quick reference materials and frequently asked questions.

**In This Section:**
- [FAQ](#faq)
- [Additional Resources](#additional-resources)

---

# FAQ

### General Questions

**Q: Do I need to configure alerts to use the dashboard?**

A: No! The dashboard works perfectly fine without alerts. Alerts are optional - they just notify you when issues occur so you don't have to watch the dashboard constantly.

**Q: Can I use multiple notification channels at once?**

A: Yes! You can enable email, Discord, Slack, and any other channels simultaneously. When an alert fires, it will send to ALL enabled contact points.

**Q: Will my alerts work if Grafana restarts?**

A: Yes. Alert rules and contact points are auto-provisioned from YAML files on every Grafana startup. Your configuration persists across restarts.

**Q: How do I temporarily disable all alerts?**

A: **Option 1:** Create a silence (Alerting → Silences → Add Silence → Match all alerts)
**Option 2:** Comment out all contact points in `contact-points.yaml` (alerts will evaluate but not send notifications)
**Option 3:** Stop Grafana entirely (alerts won't evaluate)

**Q: What's the difference between email and webhooks?**

A:
- **Email:** Slower (1-5 min delivery), universal, permanent record, works offline
- **Webhooks:** Instant (< 1 sec), rich formatting, mobile push, requires third-party service

### Alert Configuration

**Q: How do I change alert thresholds?**

A: Edit `config/grafana/provisioning/alerting/alert-rules.yaml`, find the rule, change the `expr:` threshold value, restart Grafana.

**Q: Can I create alerts based on custom metrics?**

A: Yes! See [Advanced Configuration](#advanced-configuration) section for creating custom alert rules. You can alert on any metric in VictoriaMetrics.

**Q: How do I make alerts less sensitive?**

A: Two approaches:
1. Increase threshold (e.g., peers < 5 instead of < 10)
2. Increase duration (e.g., 30m instead of 15m)

See [Managing Alert Fatigue](#managing-alert-fatigue).

**Q: Can I send different alerts to different channels?**

A: Yes, using Grafana's notification policies (advanced). For example: critical alerts to PagerDuty, warnings to Slack, info to email.

See [Advanced Alert Routing](#advanced-alert-routing).

### Notification Channels

**Q: Which notification channel is best?**

A: Depends on your needs:
- **Solo operator:** Email + Discord (redundancy)
- **Team:** Slack + PagerDuty (collaboration + on-call)
- **Budget-conscious:** Discord only (free, instant, rich formatting)
- **Mission-critical:** PagerDuty (phone/SMS escalation)

See [Notification Channel Comparison](#notification-channel-comparison).

**Q: Do I need a paid PagerDuty account?**

A: PagerDuty is paid-only (starts at $19/user/month). It's designed for 24/7 on-call scenarios with phone/SMS escalation. Not necessary for personal validators.

**Q: Can I use Gmail without enabling 2FA?**

A: No. Gmail requires 2-Factor Authentication to generate app passwords (which are required for SMTP). This is a security feature by Google.

**Q: What if my Discord webhook stops working?**

A: Webhooks can be deleted or regenerated. If webhook returns 404, create a new webhook in Discord and update `contact-points.yaml`.

### Troubleshooting

**Q: Test notification says "sent" but I don't receive anything. Why?**

A: Common causes:
- **Email:** Check spam folder, verify SMTP credentials, check FROM address matches SMTP username
- **Webhook:** Verify webhook URL is correct, check Grafana logs for errors, test webhook manually with curl

See [Troubleshooting](#troubleshooting) section.

**Q: My alerts fire constantly. How do I stop alert spam?**

A: Alert flapping (rapid fire/resolve cycles) indicates oscillating metrics. Solutions:
- Increase `for:` duration (30m instead of 15m)
- Adjust threshold with buffer (< 8 instead of < 10)
- Use time-based aggregation (`avg_over_time`)

See [Managing Alert Fatigue](#managing-alert-fatigue).

**Q: Can I test alerts without waiting for real issues?**

A: Yes! Two methods:
1. Use Grafana UI "Test" button (sends test notification instantly)
2. Temporarily adjust alert threshold to force firing (then revert)

See [Testing Your Alert Setup](#testing-your-alert-setup).

### Security

**Q: Is it safe to put webhook URLs in YAML files?**

A: **If your repository is private:** Yes, relatively safe (but use `.gitignore` for extra protection)
**If your repository is public:** NO! Use environment variables or .env files.

See [Security Best Practices](#security-best-practices).

**Q: What happens if someone gets my Discord webhook URL?**

A: They can send messages to your Discord channel. **Immediately:**
1. Delete the webhook in Discord
2. Create new webhook
3. Update `contact-points.yaml`
4. Restart Grafana

**Q: Should I commit SMTP passwords to git?**

A: NO! XRPL Monitor uses `.env` for secrets (already gitignored). Your SMTP settings in `.env` are preserved during updates.

### Advanced

**Q: Can I write alert notifications to a database?**

A: Yes! Use generic webhook to send to custom endpoint that writes to database. See [Integration Examples](#integration-examples) for Python SQLite example.

**Q: How do I send alerts to multiple emails?**

A: In `contact-points.yaml`, use semicolon-separated list:
```yaml
addresses: admin@example.com;ops@example.com;alerts@example.com
```

**Q: Can I customize the alert message format?**

A: Yes! Edit message templates in `contact-points.yaml` using Grafana template variables. See [Customizing Alert Messages](#customizing-alert-messages).

**Q: How do I view alert history?**

A: Grafana → **Alerting** (left sidebar) → **Alert rules** → Click on any alert name → **"State history"** tab shows past firing/resolution times with timestamps.

---

# Additional Resources

**Official Documentation:**
- [Grafana Alerting Overview](https://grafana.com/docs/grafana/latest/alerting/)
- [Grafana Contact Points](https://grafana.com/docs/grafana/latest/alerting/manage-notifications/create-contact-point/)
- [Grafana Alert Rules](https://grafana.com/docs/grafana/latest/alerting/alerting-rules/)
- [PromQL Query Guide](https://prometheus.io/docs/prometheus/latest/querying/basics/)

**XRPL Monitor Documentation:**
- [METRICS.md](METRICS.md) - Complete list of available metrics
- [TUNING.md](TUNING.md) - Performance tuning and optimization
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture and design
- [FAQ.md](FAQ.md) - General frequently asked questions

**Community Support:**
- [GitHub Issues](https://github.com/realgrapedrop/xrpl-validator-dashboard/issues)
- [XRPL Discord](https://discord.gg/xrpl) - #validators channel

---

**Last Updated:** December 4, 2025
**XRPL Monitor Version:** 3.0
