#!/usr/bin/env python3
"""
Switch between Grafana dashboard themes (transparent vs opaque).
Cross-platform theme switcher for XRPL Validator Dashboard.
"""

import getpass
import json
import shutil
import subprocess
import sys
from pathlib import Path


def main():
    # Define paths relative to project root
    project_root = Path(__file__).parent.parent
    transparent_template = project_root / "dashboards" / "xrpl-validator-dark-transparent.json"
    opaque_template = project_root / "dashboards" / "xrpl-validator-dark-opaque.json"
    active_dashboard = project_root / "config" / "grafana" / "provisioning" / "dashboards" / "xrpl-validator-main.json"

    # Verify templates exist
    if not transparent_template.exists():
        print(f"ERROR: Transparent template not found: {transparent_template}")
        sys.exit(1)
    if not opaque_template.exists():
        print(f"ERROR: Opaque template not found: {opaque_template}")
        sys.exit(1)

    print("=== XRPL Validator Dashboard Theme Switcher ===")
    print("")
    print("Available themes:")
    print("  1) Transparent - Panels with transparent backgrounds")
    print("  2) Opaque - Panels with solid dark backgrounds")
    print("  3) Exit - Cancel theme switch")
    print("")

    try:
        choice = input("Select theme (1, 2, or 3): ").strip()
    except (KeyboardInterrupt, EOFError):
        print("\nCancelled.")
        sys.exit(0)

    if choice == "3":
        print("\nExiting without changes.")
        sys.exit(0)
    elif choice == "1":
        print("")
        print("Switching to Transparent theme...")
        template_file = transparent_template
        theme_name = "Transparent"
    elif choice == "2":
        print("")
        print("Switching to Opaque theme...")
        template_file = opaque_template
        theme_name = "Opaque"
    else:
        print("ERROR: Invalid choice. Please select 1, 2, or 3.")
        sys.exit(1)

    # Prompt for Grafana credentials
    print("")
    print("For real-time dashboard updates, please provide Grafana admin credentials.")
    print("Note: Credentials are only used to push the dashboard change via API and are NOT saved.")
    print("")

    try:
        grafana_user = input("Grafana username (default: admin): ").strip() or "admin"
        grafana_password = getpass.getpass("Grafana password: ")

        if not grafana_password:
            print("ERROR: Password cannot be empty.")
            sys.exit(1)
    except (KeyboardInterrupt, EOFError):
        print("\nCancelled.")
        sys.exit(0)

    # Copy to active dashboard file
    shutil.copy2(template_file, active_dashboard)

    # Also push to Grafana via API (since allowUiUpdates: true)
    try:
        # Load the dashboard JSON
        with open(template_file, 'r') as f:
            dashboard_json = json.load(f)

        # Create the API payload
        payload = {
            "dashboard": dashboard_json,
            "overwrite": True,
            "message": f"Switched to {theme_name} theme"
        }

        # Write payload to temp file for curl
        temp_payload = "/tmp/grafana-dashboard-payload.json"
        with open(temp_payload, 'w') as f:
            json.dump(payload, f)

        # Push to Grafana API
        result = subprocess.run(
            [
                "curl", "-s", "-u", f"{grafana_user}:{grafana_password}",
                "-X", "POST",
                "-H", "Content-Type: application/json",
                "-d", f"@{temp_payload}",
                "http://localhost:3003/api/dashboards/db"
            ],
            capture_output=True,
            text=True
        )

        if result.returncode == 0:
            try:
                response = json.loads(result.stdout)
                if response.get("status") == "success":
                    print("")
                    print(f"✓ Successfully switched to {theme_name} theme")
                    print("")
                    print("IMPORTANT: Use HARD REFRESH to see changes:")
                    print("  - Windows/Linux: Ctrl+Shift+R")
                    print("  - Mac: Cmd+Shift+R")
                    print("")
                    print(f"Dashboard URL: http://localhost:3003{response.get('url', '/d/xrpl-validator-monitor-full')}")
                else:
                    print("")
                    print(f"⚠ API response: {result.stdout}")
                    print("Files updated, but Grafana API update may have failed.")
                    print("Try refreshing your browser in 10 seconds.")
            except json.JSONDecodeError:
                # Check if it's an auth error
                if "Invalid username or password" in result.stdout:
                    print("")
                    print("ERROR: Invalid Grafana credentials.")
                    print("Please verify your username and password have admin privileges.")
                    sys.exit(1)
                else:
                    print("")
                    print(f"⚠ Unexpected API response: {result.stdout}")
                    print("Files updated. Try refreshing your browser in 10 seconds.")
        else:
            print("")
            print("⚠ Failed to push to Grafana API")
            print("Files updated. Wait 10 seconds and refresh your browser.")

    except Exception as e:
        print("")
        print(f"⚠ Error pushing to Grafana API: {e}")
        print("Files updated. Wait 10 seconds and refresh your browser.")

    print("")


if __name__ == "__main__":
    main()
