# Step-by-Step Guide: Enhancing uninstall.sh

This guide shows exactly how to add Python monitoring removal to your existing `uninstall.sh`.

## Overview

We're adding one new function and one function call to cleanly remove the Python monitoring service and tracked files.

---

## Step 1: Open uninstall.sh in GitHub Editor

1. Navigate to your repo on GitHub
2. Click on `uninstall.sh`
3. Click the **pencil icon** (Edit this file) in the top right

---

## Step 2: Find the Removal Functions Section

Scroll down in `uninstall.sh` until you find the existing removal functions. You'll see functions like:

```bash
remove_docker_containers() {
    # ... existing code ...
}

remove_directories() {
    # ... existing code ...
}
```

---

## Step 3: Add the New Removal Function

**Right after the existing removal functions** (but before the main execution section), add this complete function:

```bash
#=============================================================================
# Remove Python Monitor
#=============================================================================
remove_python_monitor() {
    echo ""
    echo "=========================================="
    echo "Removing Python Monitor"
    echo "=========================================="
    echo ""
    
    local service_removed=false
    local service_name="xrpl-monitor.service"
    
    # Check if service exists
    if systemctl list-unit-files | grep -q "$service_name"; then
        
        # Stop service if running
        if systemctl is-active --quiet "$service_name"; then
            echo "[1/4] Stopping service..."
            systemctl stop "$service_name"
            echo "  ✓ Service stopped"
        else
            echo "[1/4] Service not running"
        fi
        
        # Disable service if enabled
        if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
            echo "[2/4] Disabling service..."
            systemctl disable "$service_name"
            echo "  ✓ Service disabled"
        else
            echo "[2/4] Service not enabled"
        fi
        
        # Remove service file
        if [[ -f "/etc/systemd/system/$service_name" ]]; then
            echo "[3/4] Removing service file..."
            rm -f "/etc/systemd/system/$service_name"
            systemctl daemon-reload
            systemctl reset-failed 2>/dev/null || true
            echo "  ✓ Service file removed"
            service_removed=true
        else
            echo "[3/4] Service file not found"
        fi
        
    else
        echo "[1-3/4] Service not found, skipping..."
    fi
    
    # Python source files will be removed by main uninstall loop
    # (they're tracked in .install-tracker.json)
    echo "[4/4] Python source files..."
    echo "  ✓ Will be removed with tracked files"
    
    echo ""
    if [ "$service_removed" = true ]; then
        echo "✓ Python Monitor Service Removed"
    else
        echo "✓ Python Monitor Cleanup Complete"
    fi
    echo "=========================================="
    echo ""
}

#=============================================================================
# Remove Python Dependencies (Optional)
#=============================================================================
remove_python_dependencies() {
    echo ""
    echo "Checking Python dependencies..."
    
    # Only remove if user confirms
    if [[ "${REMOVE_PYTHON_DEPS:-no}" == "yes" ]]; then
        echo "Removing prometheus-client..."
        pip3 uninstall -y prometheus-client 2>/dev/null || true
        echo "  ✓ Python dependencies removed"
    else
        echo "  ℹ Python dependencies left intact (may be used by other tools)"
        echo "  ℹ To remove: pip3 uninstall prometheus-client"
    fi
    echo ""
}
```

---

## Step 4: Find the Main Uninstall Flow

Scroll down to find the main uninstall execution. Look for where removal functions are called, like:

```bash
# Main uninstall flow
remove_docker_containers
remove_directories
remove_files
```

---

## Step 5: Add the Function Call

**Add the call to `remove_python_monitor` BEFORE removing files/directories.**

The order matters:
1. Stop services first (so they don't access files)
2. Then remove files
3. Then remove directories

Find this section and modify it:

```bash
# Main uninstall flow
echo "Starting uninstall process..."

# Stop Docker containers
remove_docker_containers

# ADD THIS LINE - Remove Python monitor service
remove_python_monitor

# Remove files (includes Python source - already tracked)
remove_files

# Remove directories
remove_directories

# Optional: Remove Python dependencies
# Uncomment if you want to remove pip packages too
# remove_python_dependencies

echo "Uninstall complete!"
```

**Exact addition:**
- Add `remove_python_monitor` after `remove_docker_containers`
- Add before `remove_files`

---

## Step 6: Add Verification Function (Optional but Recommended)

Right after the `remove_python_monitor` function, add this verification:

```bash
#=============================================================================
# Verify Python Monitor Removal
#=============================================================================
verify_python_monitor_removal() {
    echo ""
    echo "=========================================="
    echo "Verifying Python Monitor Removal"
    echo "=========================================="
    echo ""
    
    local all_clean=true
    
    # Check service removed
    if systemctl list-unit-files 2>/dev/null | grep -q "xrpl-monitor.service"; then
        echo "  ✗ Service still exists"
        all_clean=false
    else
        echo "  ✓ Service removed"
    fi
    
    # Check service file removed
    if [[ -f "/etc/systemd/system/xrpl-monitor.service" ]]; then
        echo "  ✗ Service file still exists"
        all_clean=false
    else
        echo "  ✓ Service file removed"
    fi
    
    # Check if service is running
    if systemctl is-active --quiet xrpl-monitor.service 2>/dev/null; then
        echo "  ✗ Service still running"
        all_clean=false
    else
        echo "  ✓ Service not running"
    fi
    
    # Check Prometheus metrics endpoint
    if curl -s http://localhost:9091/metrics 2>/dev/null | grep -q "xrpl_validator_state"; then
        echo "  ⚠ Metrics endpoint still responding (service may be running)"
        all_clean=false
    else
        echo "  ✓ Metrics endpoint not responding"
    fi
    
    echo ""
    if [ "$all_clean" = true ]; then
        echo "✓ Verification Complete - Python Monitor Fully Removed"
    else
        echo "⚠ Verification Complete - Some Components May Remain"
        echo "  Manual cleanup may be required"
    fi
    echo "=========================================="
    echo ""
}
```

Then add a call after removal:
```bash
# After remove_python_monitor in main flow:
remove_python_monitor
verify_python_monitor_removal  # ADD THIS
```

---

## Step 7: Handle Edge Cases

Add error handling for when things aren't found:

```bash
# At the top of remove_python_monitor, add safety checks:
remove_python_monitor() {
    echo ""
    echo "=========================================="
    echo "Removing Python Monitor"
    echo "=========================================="
    echo ""
    
    # Safety check - don't fail if service doesn't exist
    set +e  # Allow commands to fail without exiting
    
    # ... rest of function ...
    
    set -e  # Re-enable exit on error
}
```

---

## Step 8: Add User Confirmation (Optional)

If you want to ask before removing the service:

```bash
# Add at the start of remove_python_monitor:
if [[ "${SKIP_PYTHON_MONITOR:-no}" == "yes" ]]; then
    echo "Skipping Python monitor removal (SKIP_PYTHON_MONITOR=yes)"
    return 0
fi

# Or add interactive prompt:
read -p "Remove Python monitoring service? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
    echo "Skipping Python monitor removal"
    return 0
fi
```

---

## Step 9: Save and Commit

1. **Scroll to bottom** of GitHub editor
2. **Commit message:** "Add Python monitor removal to uninstall.sh"
3. **Commit description (optional):**
   ```
   - Add remove_python_monitor() function
   - Stop and disable xrpl-monitor service
   - Remove systemd service file
   - Add verification function
   - Preserve Python dependencies by default
   ```
4. Click **"Commit changes"**

---

## What This Does

The enhanced `uninstall.sh` now:
1. ✅ Stops xrpl-monitor service gracefully
2. ✅ Disables service from auto-start
3. ✅ Removes systemd service file
4. ✅ Reloads systemd daemon
5. ✅ Python files removed by existing tracked file cleanup
6. ✅ Verifies complete removal
7. ✅ Leaves Python dependencies intact (they're small and may be used elsewhere)

---

## Testing After Changes

After committing, test on your server:

```bash
# Pull the updated uninstall.sh
cd ~/xrpl-validator-monitor-dashboard
git pull

# Backup first! (in case you want to keep data)
sudo systemctl stop xrpl-monitor
sudo cp -r /path/to/installation /path/to/installation.backup

# Run uninstall
sudo ./uninstall.sh

# Verify removal
systemctl status xrpl-monitor  # Should show "could not be found"
curl http://localhost:9091/metrics  # Should fail or timeout
ls /etc/systemd/system/xrpl-monitor.service  # Should not exist
```

---

## Troubleshooting

**If service won't stop:**
```bash
# Force stop
sudo systemctl kill xrpl-monitor.service

# Check what's holding it
sudo systemctl status xrpl-monitor.service
sudo journalctl -u xrpl-monitor.service -n 50
```

**If service file won't delete:**
```bash
# Check permissions
ls -la /etc/systemd/system/xrpl-monitor.service

# Force remove
sudo rm -f /etc/systemd/system/xrpl-monitor.service
sudo systemctl daemon-reload
```

**If metrics endpoint still responds:**
```bash
# Check if process is still running
ps aux | grep fast_poller

# Kill any orphaned processes
sudo pkill -f fast_poller.py
```

---

## Complete Uninstall (Including Python Dependencies)

If you want to also remove Python dependencies:

```bash
# Run uninstall with dependency removal
REMOVE_PYTHON_DEPS=yes sudo ./uninstall.sh

# Or manually after uninstall:
pip3 uninstall -y prometheus-client
```

---

## Summary

You've successfully enhanced `uninstall.sh` to:
- Stop and remove xrpl-monitor service cleanly
- Clean up systemd files properly
- Verify complete removal
- Handle edge cases gracefully
- Preserve Python dependencies by default

The uninstaller now completely reverses what the installer does - clean surgical removal! ✅

---

## Next Steps

1. Test install → uninstall → reinstall cycle
2. Verify no orphaned files remain
3. Check service doesn't restart on reboot
4. Document any manual cleanup steps needed

Both install.sh and uninstall.sh are now complete!
