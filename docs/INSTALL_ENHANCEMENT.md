# Step-by-Step Guide: Enhancing install.sh

This guide shows exactly how to add Python monitoring installation to your existing `install.sh`.

## Overview

We're adding one new function and one function call to deploy the Python source code and create the systemd service.

---

## Step 1: Open install.sh in GitHub Editor

1. Navigate to your repo on GitHub
2. Click on `install.sh`
3. Click the **pencil icon** (Edit this file) in the top right

---

## Step 2: Find the Installation Functions Section

Scroll down in `install.sh` until you find the existing installation functions. You'll see functions like:

```bash
install_monitoring() {
    # ... existing code ...
}

install_docker() {
    # ... existing code ...
}
```

---

## Step 3: Add the New Function

**Right after the last installation function** (before the main script execution section), add this complete function:

```bash
#=============================================================================
# Install Python Monitor
#=============================================================================
install_python_monitor() {
    local install_dir="$1"
    local user="$2"
    
    echo ""
    echo "=========================================="
    echo "Installing Python Monitor"
    echo "=========================================="
    echo ""
    
    # Check if src/ directory exists in repo
    if [[ ! -d "./src" ]]; then
        echo "Error: Python source directory './src' not found"
        echo "Make sure you're running from the repo root with src/ present"
        exit 1
    fi
    
    # Install Python dependencies
    echo "[1/6] Installing Python dependencies..."
    if [[ -f "./requirements.txt" ]]; then
        pip3 install -r ./requirements.txt --user 2>&1 | grep -v "Requirement already satisfied" || true
        echo "  ✓ Python dependencies installed"
    else
        echo "  ⚠ No requirements.txt found, skipping"
    fi
    
    # Create src directory in installation
    echo ""
    echo "[2/6] Creating Python source directory..."
    mkdir -p "$install_dir/src"
    echo "  ✓ Created $install_dir/src"
    
    # Copy Python source files
    echo ""
    echo "[3/6] Copying Python source files..."
    
    # Copy entire src/ directory structure, excluding __pycache__
    rsync -av --exclude='__pycache__' --exclude='*.pyc' \
        ./src/ "$install_dir/src/" || cp -r ./src/* "$install_dir/src/"
    
    # Track each Python file in manifest
    find "$install_dir/src" -name "*.py" -type f | while read -r pyfile; do
        track_item "files" "$pyfile"
    done
    
    PYTHON_FILE_COUNT=$(find "$install_dir/src" -name "*.py" -type f | wc -l)
    echo "  ✓ Copied $PYTHON_FILE_COUNT Python files"
    
    # Replace ${INSTALL_DIR} placeholder with actual path
    echo ""
    echo "[4/6] Configuring installation paths..."
    find "$install_dir/src" -name "*.py" -type f -exec \
        sed -i "s|\${INSTALL_DIR}|$install_dir|g" {} \; 2>/dev/null || \
        find "$install_dir/src" -name "*.py" -type f -exec \
        sed -i '' "s|\${INSTALL_DIR}|$install_dir|g" {} \;
    echo "  ✓ Paths configured for $install_dir"
    
    # Set ownership
    chown -R "$user:$user" "$install_dir/src"
    echo "  ✓ Ownership set to $user"
    
    # Create systemd service
    echo ""
    echo "[5/6] Creating systemd service..."
    if [[ -f "./systemd/xrpl-monitor.service.template" ]]; then
        # Replace template variables
        sed -e "s|\${INSTALL_DIR}|$install_dir|g" \
            -e "s|\${USER}|$user|g" \
            ./systemd/xrpl-monitor.service.template \
            > /tmp/xrpl-monitor.service
        
        # Install service
        cp /tmp/xrpl-monitor.service /etc/systemd/system/
        track_item "systemd_services" "xrpl-monitor.service"
        
        # Reload systemd
        systemctl daemon-reload
        
        echo "  ✓ Service created: xrpl-monitor.service"
    else
        echo "  ⚠ Service template not found at ./systemd/xrpl-monitor.service.template"
        echo "  ⚠ Skipping service creation"
    fi
    
    # Enable and start service
    echo ""
    echo "[6/6] Starting monitor service..."
    
    if systemctl list-unit-files | grep -q "xrpl-monitor.service"; then
        systemctl enable xrpl-monitor.service
        systemctl start xrpl-monitor.service
        
        # Wait for service to start
        sleep 3
        
        if systemctl is-active --quiet xrpl-monitor.service; then
            echo "  ✓ Service started successfully"
            
            # Show quick status
            echo ""
            echo "Service status:"
            systemctl status xrpl-monitor.service --no-pager -l | head -10
            
            # Check Prometheus metrics
            echo ""
            echo "Checking Prometheus metrics..."
            sleep 2
            if curl -s http://localhost:9091/metrics 2>/dev/null | grep -q "xrpl_validator_state"; then
                echo "  ✓ Prometheus metrics available at http://localhost:9091/metrics"
            else
                echo "  ⚠ Prometheus metrics not yet available (may need more time)"
            fi
        else
            echo "  ⚠ Service failed to start"
            echo ""
            echo "Check logs with:"
            echo "  sudo journalctl -u xrpl-monitor.service -n 50"
            echo "  tail -f $install_dir/logs/error.log"
        fi
    else
        echo "  ⚠ Service file not found, skipping start"
    fi
    
    echo ""
    echo "=========================================="
    echo "Python Monitor Installation Complete"
    echo "=========================================="
    echo ""
}
```

---

## Step 4: Find the Main Installation Flow

Scroll down to find the main installation logic. Look for a section that handles different installation modes, like:

```bash
# Main installation flow
case "$mode" in
    --full)
        install_docker
        install_monitoring
        ;;
    --monitoring)
        install_monitoring
        ;;
```

---

## Step 5: Add the Function Call

**Add the call to `install_python_monitor` in the appropriate cases.** Here's what to add:

Find this section:
```bash
case "$mode" in
    --full)
        install_docker
        install_monitoring
        # ADD THIS LINE:
        install_python_monitor "$INSTALL_DIR" "$USER"
        ;;
        
    --monitoring)
        install_monitoring
        # ADD THIS LINE:
        install_python_monitor "$INSTALL_DIR" "$USER"
        ;;
        
    --dashboard-only)
        # Don't add here - dashboard-only mode doesn't need Python
        ;;
esac
```

**Exact additions:**
- After `install_monitoring` in both `--full` and `--monitoring` cases
- Add: `install_python_monitor "$INSTALL_DIR" "$USER"`

---

## Step 6: Add Verification Function (Optional but Recommended)

Right after the `install_python_monitor` function, add this verification function:

```bash
#=============================================================================
# Verify Python Monitor Installation
#=============================================================================
verify_python_monitor() {
    local install_dir="$1"
    
    echo ""
    echo "=========================================="
    echo "Verifying Python Monitor Installation"
    echo "=========================================="
    echo ""
    
    local all_good=true
    
    # Check files
    if [[ ! -f "$install_dir/src/collectors/fast_poller.py" ]]; then
        echo "  ✗ Python source files missing"
        all_good=false
    else
        echo "  ✓ Python source files present"
    fi
    
    # Check service
    if ! systemctl is-enabled --quiet xrpl-monitor.service 2>/dev/null; then
        echo "  ✗ Service not enabled"
        all_good=false
    else
        echo "  ✓ Service enabled"
    fi
    
    if ! systemctl is-active --quiet xrpl-monitor.service 2>/dev/null; then
        echo "  ✗ Service not running"
        all_good=false
    else
        echo "  ✓ Service running"
    fi
    
    # Check Prometheus metrics
    if curl -s http://localhost:9091/metrics 2>/dev/null | grep -q "xrpl_validator_state"; then
        echo "  ✓ Prometheus metrics available"
    else
        echo "  ⚠ Prometheus metrics not yet available (may need time to start)"
    fi
    
    # Check database
    if [[ -f "$install_dir/data/monitor.db" ]]; then
        if command -v sqlite3 >/dev/null 2>&1; then
            RECORD_COUNT=$(sqlite3 "$install_dir/data/monitor.db" \
                "SELECT COUNT(*) FROM validator_metrics;" 2>/dev/null || echo "0")
            echo "  ✓ Database created ($RECORD_COUNT records)"
        else
            echo "  ✓ Database file exists"
        fi
    else
        echo "  ⚠ Database not yet created (will be created on first poll)"
    fi
    
    echo ""
    if [ "$all_good" = true ]; then
        echo "✓ Verification Complete - All Checks Passed"
    else
        echo "⚠ Verification Complete - Some Issues Found"
        echo "  Check logs: sudo journalctl -u xrpl-monitor.service -n 50"
    fi
    echo "=========================================="
    echo ""
}
```

Then add a call to verify after installation:
```bash
# In the main flow, after install_python_monitor:
install_python_monitor "$INSTALL_DIR" "$USER"
verify_python_monitor "$INSTALL_DIR"  # ADD THIS
```

---

## Step 7: Save and Commit

1. **Scroll to bottom** of GitHub editor
2. **Commit message:** "Add Python monitor installation to install.sh"
3. **Commit description (optional):**
   ```
   - Add install_python_monitor() function
   - Deploy Python source code from src/
   - Create and start xrpl-monitor systemd service
   - Add verification function
   ```
4. Click **"Commit changes"**

---

## What This Does

The enhanced `install.sh` now:
1. ✅ Installs Python dependencies (`prometheus-client`)
2. ✅ Copies `src/` directory to installation location
3. ✅ Replaces `${INSTALL_DIR}` variables with actual path
4. ✅ Creates systemd service from template
5. ✅ Starts and enables the service
6. ✅ Verifies installation worked
7. ✅ Tracks everything for clean uninstall

---

## Testing After Changes

After committing, test on your server:

```bash
# Pull the updated install.sh
cd ~/xrpl-validator-monitor-dashboard
git pull

# Test installation in a new directory
sudo ./install.sh --monitoring --rippled-type docker

# Verify service running
systemctl status xrpl-monitor

# Check metrics
curl http://localhost:9091/metrics | grep xrpl_validator
```

---

## Troubleshooting

**If service fails to start:**
```bash
# Check logs
sudo journalctl -u xrpl-monitor.service -n 50 --no-pager

# Check error log
tail -50 /path/to/install/logs/error.log

# Check Python dependencies
pip3 list | grep prometheus-client
```

**If metrics not available:**
- Wait 10-15 seconds for first poll cycle
- Check service is running: `systemctl status xrpl-monitor`
- Verify rippled is accessible: `docker exec rippledvalidator rippled server_info`

---

## Summary

You've successfully enhanced `install.sh` to:
- Deploy Python monitoring code
- Create systemd service automatically
- Verify installation success
- Track all changes for clean removal

Next step: Enhance `uninstall.sh` to remove these components cleanly.
