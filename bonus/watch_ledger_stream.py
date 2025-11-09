#!/usr/bin/env python3
"""
Watch XRPL Ledger Stream - Real-time ledger close notifications
Usage: python3 watch_ledger_stream.py
"""

import sys
import subprocess
import os

# Check for required dependencies
try:
    import websockets
except ImportError:
    print("\n⚠️  Missing required library: websockets")
    print("\nThis script requires the 'websockets' library to connect to rippled.")
    response = input("\nWould you like to install it now? [Y/n]: ").strip().lower()

    if response in ['', 'y', 'yes']:
        print("\nInstalling websockets...")
        try:
            subprocess.check_call([
                sys.executable, '-m', 'pip', 'install', '--break-system-packages', 'websockets'
            ])
            print("\n✓ Installation complete! Please run the script again.\n")
        except subprocess.CalledProcessError:
            print("\n✗ Installation failed. Try manually:")
            print("  pip3 install --break-system-packages websockets\n")
        sys.exit(0)
    else:
        print("\nCancelled. To install manually, run:")
        print("  pip3 install --break-system-packages websockets\n")
        sys.exit(1)

import asyncio
import json
from datetime import datetime

# ANSI color codes (optimized for white background)
GREEN = '\033[32m'      # Dark green
BLUE = '\033[34m'       # Dark blue
YELLOW = '\033[33m'     # Dark yellow/orange
CYAN = '\033[36m'       # Dark cyan
MAGENTA = '\033[35m'    # Dark magenta
RED = '\033[31m'        # Dark red
BOLD = '\033[1m'
RESET = '\033[0m'

# Configuration file for storing detected port
CONFIG_FILE = os.path.expanduser('~/.xrpl_ledger_stream_port')

# Common rippled WebSocket ports
COMMON_PORTS = [6006, 6005, 5005]


async def test_websocket_connection(port):
    """Test if WebSocket is accessible on given port"""
    try:
        ws_url = f'ws://localhost:{port}'
        async with websockets.connect(ws_url, close_timeout=2) as ws:
            # Try to send a simple ping
            await ws.send(json.dumps({"command": "ping"}))
            response = await asyncio.wait_for(ws.recv(), timeout=2)
            return True
    except Exception:
        return False


async def detect_websocket_port():
    """Auto-detect rippled WebSocket port"""

    # Check if we have a saved port
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                saved_port = int(f.read().strip())
                print(f"{CYAN}Testing saved port {saved_port}...{RESET}")
                if await test_websocket_connection(saved_port):
                    print(f"{GREEN}✓ Connected on port {saved_port}{RESET}\n")
                    return saved_port
                else:
                    print(f"{YELLOW}⚠ Saved port {saved_port} not responding{RESET}\n")
        except Exception:
            pass

    # Try common ports
    print(f"{CYAN}Auto-detecting rippled WebSocket port...{RESET}")
    for port in COMMON_PORTS:
        print(f"  Trying port {port}...", end=' ')
        if await test_websocket_connection(port):
            print(f"{GREEN}✓{RESET}")
            # Save detected port
            with open(CONFIG_FILE, 'w') as f:
                f.write(str(port))
            print(f"{GREEN}Port {port} detected and saved!{RESET}\n")
            return port
        else:
            print(f"{YELLOW}✗{RESET}")

    # None worked, prompt user
    print(f"\n{YELLOW}⚠ Could not auto-detect WebSocket port{RESET}")
    print(f"\n{CYAN}rippled WebSocket Information:{RESET}")
    print("The WebSocket API must be enabled in rippled.cfg:")
    print()
    print("  [port_ws_public]")
    print("  port = 6006")
    print("  ip = 0.0.0.0")
    print("  protocol = ws")
    print()
    print("Common ports: 6006 (default), 6005, 5005")
    print()

    while True:
        try:
            port_input = input(f"{CYAN}Enter your rippled WebSocket port [6006]: {RESET}").strip()
            port = int(port_input) if port_input else 6006

            if port < 1 or port > 65535:
                print(f"{RED}Invalid port number. Please enter 1-65535{RESET}")
                continue

            print(f"\nTesting port {port}...", end=' ')
            if await test_websocket_connection(port):
                print(f"{GREEN}✓{RESET}")
                # Save detected port
                with open(CONFIG_FILE, 'w') as f:
                    f.write(str(port))
                print(f"{GREEN}Port {port} saved!{RESET}\n")
                return port
            else:
                print(f"{RED}✗{RESET}")
                print(f"{YELLOW}Cannot connect to port {port}{RESET}")
                retry = input("Try another port? [Y/n]: ").strip().lower()
                if retry in ['n', 'no']:
                    print(f"\n{RED}Cannot proceed without WebSocket connection{RESET}")
                    sys.exit(1)
        except ValueError:
            print(f"{RED}Please enter a valid number{RESET}")
        except KeyboardInterrupt:
            print(f"\n\n{CYAN}Cancelled{RESET}\n")
            sys.exit(0)


async def watch_ledgers(port):
    """Connect to rippled WebSocket and watch ledger stream"""

    ws_url = f'ws://localhost:{port}'

    print(f"{CYAN}{BOLD}╔══════════════════════════════════════════════════════════════════════════════╗{RESET}")
    print(f"{CYAN}{BOLD}║                      XRPL Ledger Stream Viewer                               ║{RESET}")
    print(f"{CYAN}{BOLD}╚══════════════════════════════════════════════════════════════════════════════╝{RESET}\n")

    print(f"{YELLOW}Connecting to rippled WebSocket at {ws_url}...{RESET}\n")

    try:
        async with websockets.connect(ws_url) as ws:
            # Subscribe to ledger stream
            subscribe_msg = {
                "command": "subscribe",
                "streams": ["ledger"]
            }

            await ws.send(json.dumps(subscribe_msg))
            print(f"{GREEN}✓ Connected and subscribed to ledger stream{RESET}")
            print(f"{GREEN}✓ Waiting for ledger closes...{RESET}\n")
            print("=" * 80 + "\n")

            # Listen for messages
            async for msg in ws:
                data = json.loads(msg)

                # Handle subscription confirmation
                if data.get('status') == 'success':
                    print(f"{GREEN}✓ Subscription confirmed{RESET}\n")

                # Handle ledger close events
                elif data.get('type') == 'ledgerClosed':
                    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

                    print(f"{MAGENTA}{BOLD}[{timestamp}] LEDGER CLOSED{RESET}")
                    print(f"{BLUE}├─ Ledger Index:{RESET}      {data['ledger_index']:,}")
                    print(f"{BLUE}├─ Ledger Hash:{RESET}       {data['ledger_hash']}")
                    print(f"{BLUE}├─ Parent Hash:{RESET}       {data.get('parent_ledger_hash', 'N/A')}")
                    print(f"{BLUE}├─ Transactions:{RESET}      {data.get('txn_count', 0)}")
                    print(f"{BLUE}├─ Ledger Time:{RESET}       {data.get('ledger_time', 'N/A')}")
                    print(f"{BLUE}├─ Fee Base:{RESET}          {data.get('fee_base', 'N/A')} drops")
                    print(f"{BLUE}├─ Fee Ref:{RESET}           {data.get('fee_ref', 'N/A')} drops")
                    print(f"{BLUE}├─ Reserve Base:{RESET}      {data.get('reserve_base', 'N/A')} drops")
                    print(f"{BLUE}├─ Reserve Inc:{RESET}       {data.get('reserve_inc', 'N/A')} drops")
                    print(f"{BLUE}└─ Validated Range:{RESET}   {data.get('validated_ledgers', 'N/A')}")

                    # Show raw JSON for debugging (all available fields)
                    print(f"\n{CYAN}Raw data (all fields):{RESET}")
                    print(json.dumps(data, indent=2, sort_keys=True))
                    print("\n" + "─" * 80 + "\n")

                # Handle other message types
                else:
                    msg_type = data.get('type', 'unknown')
                    print(f"{YELLOW}Other message type: {msg_type}{RESET}")

    except websockets.exceptions.WebSocketException as e:
        print(f"\n{YELLOW}⚠ WebSocket Error:{RESET} {e}")
        print(f"{YELLOW}Make sure rippled is running and WebSocket port {port} is accessible{RESET}")
        print(f"\n{CYAN}To change port, delete: {CONFIG_FILE}{RESET}\n")
    except KeyboardInterrupt:
        print(f"\n\n{CYAN}Stream stopped by user{RESET}")
    except Exception as e:
        print(f"\n{YELLOW}⚠ Error:{RESET} {e}")


async def main():
    """Main entry point"""
    print(f"\n{CYAN}Press Ctrl+C to stop{RESET}\n")

    # Detect or ask for WebSocket port
    port = await detect_websocket_port()

    # Watch ledger stream
    await watch_ledgers(port)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print(f"\n{CYAN}Goodbye!{RESET}\n")
