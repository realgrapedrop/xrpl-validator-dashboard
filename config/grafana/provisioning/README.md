# Grafana Configuration

This directory contains the Grafana datasource and configuration files.

## Directory Structure

```
config/grafana/provisioning/
├── datasources/
│   └── victoriametrics.yaml                # VictoriaMetrics datasource
├── dashboards/
│   ├── dashboards.yaml                      # Provisioning config (disabled)
│   └── xrpl-validator-main.json.template    # Dashboard template (for fresh installs)
└── alerting/
    ├── alert-rules.yaml                     # Alert rules
    └── contact-points.yaml                  # Email notification settings
```

## Dashboard Management

### How the Dashboard Works

**During Installation:**
- The installer imports `xrpl-validator-main.json.template` via Grafana API
- Dashboard is created once in Grafana's database
- You have full control to edit and save changes in the UI
- NO provisioning after initial import

**After Installation:**
- Edit the dashboard directly in Grafana UI (http://localhost:3003)
- Your changes are saved automatically in Grafana's database
- NO provisioning interference - you have complete control

### Saving Your Dashboard Changes

When you want to save your customized dashboard as the new template:

1. Export from Grafana UI:
   - Click "Share" → "Export" → "Save to file"
2. Replace the template file:
   ```bash
   cp ~/Downloads/dashboard.json config/grafana/provisioning/dashboards/xrpl-validator-main.json.template
   ```
3. Commit to git so future installations use your version

### Alert Configuration

**Email Notifications:**
Edit `alerting/contact-points.yaml` to change the email address:
```yaml
settings:
  addresses: your-email@example.com
```

**Alert Thresholds:**
Edit `alerting/alert-rules.yaml` to modify alert conditions and thresholds.

## What Happens on Startup

When you run `docker compose up`, Grafana automatically:
1. Connects to VictoriaMetrics (metrics database via datasource provisioning)
2. Configures all alert rules (via alerting provisioning)
3. Sets up email notifications (via contact points provisioning)

**Note:** The dashboard is imported once during installation via the installer script, not through file-based provisioning.
