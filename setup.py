#!/usr/bin/env python3
"""
XRPL Validator Dashboard - Interactive Setup Wizard
Validates environment and configures the dashboard for Docker-based rippled deployments
"""

import sys
import os
import subprocess
import json
import socket
import shutil
from typing import Optional, Tuple, List
from pathlib import Path

# Color codes for terminal output
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[34m'  # Darker blue for better visibility
    OKCYAN = '\033[36m'  # Darker cyan for better visibility
    OKGREEN = '\033[32m'  # Darker green for better visibility
    WARNING = '\033[97m'  # White for warnings
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def print_header(text: str):
    """Print a section header"""
    print(f"\n{Colors.HEADER}{Colors.BOLD}{'=' * 80}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{text}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{'=' * 80}{Colors.ENDC}\n")

def print_success(text: str):
    """Print success message"""
    print(f"{Colors.OKGREEN}✓ {text}{Colors.ENDC}")

def print_error(text: str):
    """Print error message"""
    print(f"{Colors.FAIL}✗ {text}{Colors.ENDC}")

def print_warning(text: str):
    """Print warning message"""
    print(f"{Colors.WARNING}⚠ {text}{Colors.ENDC}")

def print_info(text: str):
    """Print info message"""
    print(f"{Colors.OKCYAN}ℹ {text}{Colors.ENDC}")

def ask_yes_no(question: str, default: bool = True) -> bool:
    """Ask a yes/no question"""
    default_str = "Y/n" if default else "y/N"
    while True:
        response = input(f"{Colors.OKBLUE}? {question} [{default_str}]: {Colors.ENDC}").strip().lower()
        if response == '':
            return default
        if response in ['y', 'yes']:
            return True
        if response in ['n', 'no']:
            return False
        print_warning("Please answer 'y' or 'n'")

def ask_input(question: str, default: str = "") -> str:
    """Ask for text input"""
    if default:
        prompt = f"{Colors.OKBLUE}? {question} [{default}]: {Colors.ENDC}"
    else:
        prompt = f"{Colors.OKBLUE}? {question}: {Colors.ENDC}"

    response = input(prompt).strip()
    return response if response else default

def check_command_exists(command: str) -> bool:
    """Check if a command exists in PATH"""
    return shutil.which(command) is not None

def check_docker() -> bool:
    """Check if Docker is installed and running"""
    # Check if docker command exists
    if not check_command_exists('docker'):
        print_error("Docker is not installed")
        return False

    print_success("Docker command found")

    # Check if Docker daemon is running
    try:
        result = subprocess.run(
            ['docker', 'ps'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode != 0:
            print_error("Docker daemon is not running")
            return False

        print_success("Docker daemon is running")
        return True

    except subprocess.TimeoutExpired:
        print_error("Docker command timed out")
        return False
    except Exception as e:
        print_error(f"Failed to check Docker: {e}")
        return False

def check_python() -> bool:
    """Check Python version"""
    version = sys.version_info
    if version.major < 3 or (version.major == 3 and version.minor < 6):
        print_error(f"Python 3.6+ required, found {version.major}.{version.minor}")
        return False

    print_success(f"Python {version.major}.{version.minor}.{version.micro}")
    return True

def check_pip() -> bool:
    """Check if pip is available"""
    if not check_command_exists('pip3'):
        print_error("pip3 is not installed")
        return False

    print_success("pip3 found")
    return True

def check_docker_compose() -> bool:
    """Check if docker-compose is available"""
    # Try docker compose (v2)
    try:
        result = subprocess.run(
            ['docker', 'compose', 'version'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            print_success("docker compose (v2) found")
            return True
    except:
        pass

    # Try docker-compose (v1)
    if check_command_exists('docker-compose'):
        print_success("docker-compose (v1) found")
        return True

    print_error("docker-compose not found")
    return False

def find_rippled_containers() -> List[str]:
    """Find running containers that might be rippled"""
    try:
        result = subprocess.run(
            ['docker', 'ps', '--format', '{{.Names}}'],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode != 0:
            return []

        all_containers = result.stdout.strip().split('\n')

        # Filter for containers that might be rippled
        # Exclude dashboard monitoring containers (grafana, prometheus, node-exporter)
        exclude_keywords = ['grafana', 'prometheus', 'node-exporter', 'node_exporter']
        rippled_containers = [
            c for c in all_containers
            if ('rippled' in c.lower() or 'xrpl' in c.lower())
            and not any(keyword in c.lower() for keyword in exclude_keywords)
        ]

        return rippled_containers

    except Exception as e:
        print_warning(f"Could not list containers: {e}")
        return []

def test_rippled_connection(container_name: str) -> Tuple[bool, Optional[dict]]:
    """Test connection to rippled via docker exec"""
    try:
        result = subprocess.run(
            ['docker', 'exec', container_name, 'rippled', 'server_info'],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            return False, None

        # Parse JSON response
        try:
            data = json.loads(result.stdout)
            info = data.get('result', {}).get('info', {})
            return True, info
        except json.JSONDecodeError:
            return False, None

    except subprocess.TimeoutExpired:
        print_warning("rippled command timed out")
        return False, None
    except Exception as e:
        print_warning(f"Failed to connect: {e}")
        return False, None

def detect_native_rippled() -> Optional[dict]:
    """Detect native rippled installation and extract configuration"""
    # Check if rippled binary exists
    rippled_paths = [
        '/opt/ripple/bin/rippled',
        '/usr/bin/rippled',
        '/usr/local/bin/rippled'
    ]

    rippled_bin = None
    for path in rippled_paths:
        if os.path.exists(path):
            rippled_bin = path
            break

    if not rippled_bin:
        return None

    # Check if rippled service is running
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', 'rippled'],
            capture_output=True,
            text=True,
            timeout=5
        )
        is_running = result.returncode == 0
    except:
        is_running = False

    # Try to get version
    version = "unknown"
    try:
        result = subprocess.run(
            [rippled_bin, '--version'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            version = result.stdout.strip().split('\n')[0]
    except:
        pass

    return {
        'binary': rippled_bin,
        'running': is_running,
        'version': version
    }

def parse_rippled_config_ports() -> Optional[dict]:
    """Parse rippled config to find ports"""
    config_paths = [
        '/opt/ripple/etc/rippled.cfg',
        '/etc/rippled.cfg',
        '/etc/opt/ripple/rippled.cfg'
    ]

    config_file = None
    for path in config_paths:
        if os.path.exists(path):
            config_file = path
            break

    if not config_file:
        return None

    ports = {
        'rpc': None,
        'ws': None,
        'peer': None
    }

    try:
        with open(config_file, 'r') as f:
            lines = f.readlines()

        current_section = None
        for line in lines:
            line = line.strip()

            # Skip comments and empty lines
            if not line or line.startswith('#'):
                continue

            # Check for section headers
            if line.startswith('[') and line.endswith(']'):
                current_section = line[1:-1]
                continue

            # Parse port from current section
            if current_section and line.startswith('port'):
                try:
                    port_value = line.split('=')[1].strip()
                    port_num = int(port_value)

                    if 'rpc_admin' in current_section:
                        ports['rpc'] = port_num
                    elif 'ws_admin' in current_section or 'ws_public' in current_section:
                        if ports['ws'] is None:  # Use first WS port found
                            ports['ws'] = port_num
                    elif 'peer' in current_section:
                        ports['peer'] = port_num
                except:
                    continue

        return ports if any(ports.values()) else None

    except Exception as e:
        print_warning(f"Could not parse config file: {e}")
        return None

def test_native_rippled_connection(host: str, port: int) -> Tuple[bool, Optional[dict]]:
    """Test connection to native rippled via HTTP API"""
    import http.client
    import socket

    try:
        # First check if port is reachable
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(3)
        result = sock.connect_ex((host, port))
        sock.close()

        if result != 0:
            print_warning(f"Port {port} is not reachable (connection refused)")
            return False, None

        conn = http.client.HTTPConnection(host, port, timeout=5)

        # Send server_info request using JSON-RPC 2.0 format
        body = json.dumps({
            "method": "server_info",
            "params": [{}]
        })
        headers = {'Content-Type': 'application/json'}

        conn.request('POST', '/', body, headers)
        response = conn.getresponse()
        data = response.read().decode()
        conn.close()

        if response.status != 200:
            print_warning(f"HTTP error {response.status}: {response.reason}")
            print_warning(f"Response: {data[:200]}")
            return False, None

        # Parse JSON response
        try:
            result = json.loads(data)

            # Check for error in response
            if 'error' in result:
                print_warning(f"rippled returned error: {result.get('error')}")
                return False, None

            info = result.get('result', {}).get('info', {})
            return True, info
        except json.JSONDecodeError as e:
            print_warning(f"Invalid JSON response: {e}")
            print_warning(f"Response: {data[:200]}")
            return False, None

    except socket.timeout:
        print_warning(f"Connection timeout to {host}:{port}")
        return False, None
    except ConnectionRefusedError:
        print_warning(f"Connection refused to {host}:{port}")
        return False, None
    except Exception as e:
        print_warning(f"Connection error: {type(e).__name__}: {e}")
        return False, None

def detect_rippled_container() -> Optional[str]:
    """Detect and validate rippled container"""
    print_header("Step 2: Detecting rippled Container")

    # Find potential rippled containers
    containers = find_rippled_containers()

    if not containers:
        print_warning("No rippled containers detected")
        container_name = ask_input("Enter rippled container name", "rippledvalidator")
    elif len(containers) == 1:
        container_name = containers[0]
        print_info(f"Found rippled container: {container_name}")
        if not ask_yes_no(f"Use this container?", True):
            container_name = ask_input("Enter rippled container name", "rippledvalidator")
    else:
        print_info(f"Found {len(containers)} potential rippled containers:")
        for i, c in enumerate(containers, 1):
            print(f"  {i}. {c}")

        choice = ask_input(f"Select container (1-{len(containers)}) or enter custom name", "1")

        try:
            idx = int(choice) - 1
            if 0 <= idx < len(containers):
                container_name = containers[idx]
            else:
                container_name = choice
        except ValueError:
            container_name = choice

    # Test connection
    print_info(f"Testing connection to {container_name}...")
    success, info = test_rippled_connection(container_name)

    if not success:
        print_error(f"Failed to connect to container '{container_name}'")
        print_info("Make sure the container is running and rippled is accessible")

        if ask_yes_no("Try a different container name?", True):
            return detect_rippled_container()
        return None

    # Display validator info
    print_success(f"Connected to rippled in container '{container_name}'")

    if info:
        print_info(f"  Server State: {info.get('server_state', 'unknown')}")
        print_info(f"  Build Version: {info.get('build_version', 'unknown')}")
        print_info(f"  Network: {info.get('network_id', 'unknown')}")

        pubkey = info.get('pubkey_validator', '')
        if pubkey:
            print_info(f"  Validator Key: {pubkey[:30]}...")

        ledger_seq = info.get('validated_ledger', {}).get('seq', 'unknown')
        print_info(f"  Ledger Seq: {ledger_seq}")

    # Explain how the monitor communicates with rippled
    print("\n" + Colors.BOLD + "Communication Method:" + Colors.ENDC)
    print_info("  Monitor → rippled: Docker exec (no network ports needed)")
    print_info("  No rippled ports (5005, 6006, 51234, etc.) need to be exposed")
    print("")

    print(Colors.BOLD + "rippled APIs Called via Docker Exec:" + Colors.ENDC)
    print(f"  {Colors.OKGREEN}✓{Colors.ENDC} server_info  - State, ledger, peers, validation data (every 3s)")
    print(f"  {Colors.OKGREEN}✓{Colors.ENDC} peers        - Detailed peer information (every 30s)")
    print(f"  {Colors.OKGREEN}✓{Colors.ENDC} fee          - Transaction rate calculation (every 3s)")
    print(f"  {Colors.OKGREEN}✓{Colors.ENDC} ledger       - Ledger validation tracking (as needed)")
    print("")

    print(Colors.BOLD + "Ports Used by Dashboard Components:" + Colors.ENDC)
    print(f"  {Colors.OKCYAN}→{Colors.ENDC} Monitor (fast_poller):  Port 9094 - Exports Prometheus metrics")
    print(f"  {Colors.OKCYAN}→{Colors.ENDC} Node Exporter:          Port 9102 - Exports system metrics (CPU, RAM, Disk)")
    print(f"  {Colors.OKCYAN}→{Colors.ENDC} Prometheus:             Port 9092 - Stores & queries metrics")
    print(f"  {Colors.OKCYAN}→{Colors.ENDC} Grafana:                Port 3001 - Web dashboard UI")
    print_info("  (Ports will be configured in Step 3)")
    print("")

    print(Colors.BOLD + "Data Flow:" + Colors.ENDC)
    print(f"  System → {Colors.OKCYAN}Node Exporter:9102{Colors.ENDC} ┐")
    print(f"  rippled ← {Colors.OKGREEN}docker exec{Colors.ENDC} ← Monitor:{Colors.OKCYAN}9094{Colors.ENDC} ├→ Prometheus:{Colors.OKCYAN}9092{Colors.ENDC} → Grafana:{Colors.OKCYAN}3001{Colors.ENDC}")
    print(f"                                            ┘")
    print("")

    print(Colors.BOLD + "These APIs and ports will be tested in Step 6" + Colors.ENDC)

    return container_name

def is_port_available(port: int, retries: int = 3, delay: float = 2.0) -> bool:
    """Check if a port is available, with retries to handle TIME_WAIT state"""
    import time

    for attempt in range(retries):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)
        # Set SO_REUSEADDR to detect actual availability vs TIME_WAIT
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(('0.0.0.0', port))
            sock.close()
            return True
        except OSError as e:
            sock.close()
            # If port is in TIME_WAIT and this isn't the last retry, wait and retry
            if attempt < retries - 1:
                time.sleep(delay)
            continue
        except:
            sock.close()
            return False

    return False

def find_next_available_port(start_port: int, max_attempts: int = 100) -> Optional[int]:
    """Find the next available port starting from start_port"""
    for port in range(start_port, start_port + max_attempts):
        if is_port_available(port):
            return port
    return None

def get_container_ports(name_pattern: str) -> List[int]:
    """Get ports used by containers matching a name pattern"""
    try:
        # Get all containers with their port mappings
        result = subprocess.run(
            ['docker', 'ps', '--format', '{{.Names}}\t{{.Ports}}'],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode != 0:
            return []

        ports = []
        for line in result.stdout.strip().split('\n'):
            if not line:
                continue

            parts = line.split('\t')
            if len(parts) < 2:
                continue

            container_name = parts[0]
            port_mappings = parts[1]

            # Check if container name matches pattern
            if name_pattern.lower() in container_name.lower():
                # Extract host ports from mappings like "0.0.0.0:3000->3000/tcp"
                import re
                port_matches = re.findall(r'0\.0\.0\.0:(\d+)->', port_mappings)
                ports.extend([int(p) for p in port_matches])

        return ports

    except Exception as e:
        return []

def detect_rippled_unified() -> Optional[dict]:
    """Unified rippled detection - supports both Docker and native modes"""
    print_header("Step 2: Detecting rippled Installation")

    # Detect both modes
    native_info = detect_native_rippled()
    docker_containers = find_rippled_containers()

    # Determine what was found
    has_native = native_info is not None
    has_docker = len(docker_containers) > 0

    if not has_native and not has_docker:
        print_warning("No rippled installations detected")
        print_info("Could not find:")
        print_info("  • Native rippled binary (/opt/ripple/bin/rippled)")
        print_info("  • Docker containers with 'rippled' or 'xrpl' in name")
        print("")

        # Ask user what to do
        if ask_yes_no("Do you have a rippled installation to configure?", True):
            mode_choice = ask_input("Enter mode (docker/native)", "docker").lower()
            if mode_choice == "native":
                return configure_native_mode_manual()
            else:
                return configure_docker_mode_manual()
        return None

    # Display what was found
    print_info("Found rippled installation(s):\n")

    modes = []
    if has_native:
        running_status = "running" if native_info['running'] else "stopped"
        print_success(f"Native rippled: {native_info['binary']}")
        print_info(f"  Status: {running_status}")
        print_info(f"  Version: {native_info['version']}")

        # Try to detect ports
        ports = parse_rippled_config_ports()
        if ports and ports['rpc']:
            print_info(f"  RPC Port: {ports['rpc']}")
        modes.append(('native', native_info, ports))
        print("")

    if has_docker:
        print_success(f"Docker rippled: {len(docker_containers)} container(s) found")
        for container in docker_containers:
            print_info(f"  • {container}")
        modes.append(('docker', docker_containers, None))
        print("")

    # If both modes exist, ask user to choose
    if len(modes) == 2:
        print_info("Multiple rippled installations detected!")
        print("")
        choice = ask_input("Which would you like to monitor? (native/docker)", "native").lower()

        if choice == "native":
            return configure_native_mode(modes[0][1], modes[0][2])
        else:
            return configure_docker_mode(modes[1][1])

    # Only one mode found - use it
    if modes[0][0] == 'native':
        if ask_yes_no("Monitor native rippled installation?", True):
            return configure_native_mode(modes[0][1], modes[0][2])
        return None
    else:
        if ask_yes_no("Monitor Docker rippled installation?", True):
            return configure_docker_mode(modes[0][1])
        return None

def configure_native_mode(native_info: dict, detected_ports: Optional[dict]) -> Optional[dict]:
    """Configure monitoring for native rippled"""
    if not native_info['running']:
        print_warning("Native rippled service is not running")
        if not ask_yes_no("Continue anyway? (you'll need to start it later)", False):
            return None

    # Get or confirm RPC port
    if detected_ports and detected_ports['rpc']:
        default_port = str(detected_ports['rpc'])
        port_str = ask_input(f"RPC API Port (detected: {default_port})", default_port)
    else:
        port_str = ask_input("RPC API Port", "5005")

    try:
        rpc_port = int(port_str)
    except ValueError:
        print_error(f"Invalid port: {port_str}")
        return None

    # Get host (usually localhost for native)
    host = ask_input("RPC API Host", "localhost")

    # Test connection
    print_info(f"Testing connection to {host}:{rpc_port}...")
    success, info = test_native_rippled_connection(host, rpc_port)

    if not success:
        print_error(f"Failed to connect to rippled at {host}:{rpc_port}")
        print_info("Please verify:")
        print_info("  • rippled service is running: systemctl status rippled")
        print_info("  • RPC port is correct in /opt/ripple/etc/rippled.cfg")
        print_info("  • RPC API is accessible on localhost")
        print("")
        print_info("Note: Connection test may fail even if rippled is running.")
        print_info("The dashboard will attempt to connect when the service starts.")

        if not ask_yes_no("Continue anyway?", True):
            return None
        info = None

    # Display validator info if connected
    if info:
        print_success(f"Connected to native rippled")
        print_info(f"  Server State: {info.get('server_state', 'unknown')}")
        print_info(f"  Build Version: {info.get('build_version', 'unknown')}")

        pubkey = info.get('pubkey_validator', '')
        if pubkey and pubkey != 'none':
            print_info(f"  Validator Key: {pubkey[:30]}...")
        else:
            print_info(f"  Mode: Standalone node (non-validator)")

        ledger_seq = info.get('validated_ledger', {}).get('seq') or \
                     info.get('closed_ledger', {}).get('seq', 'unknown')
        print_info(f"  Ledger Seq: {ledger_seq}")
        print("")

    return {
        'mode': 'native',
        'host': host,
        'port': rpc_port,
        'version': native_info['version'],
        'info': info
    }

def configure_docker_mode(containers: List[str]) -> Optional[dict]:
    """Configure monitoring for Docker rippled"""
    # Select container
    if len(containers) == 1:
        container_name = containers[0]
        print_info(f"Using container: {container_name}")
        if not ask_yes_no("Use this container?", True):
            container_name = ask_input("Enter container name", "rippledvalidator")
    else:
        print_info(f"Found {len(containers)} containers:")
        for i, c in enumerate(containers, 1):
            print(f"  {i}. {c}")

        choice = ask_input(f"Select container (1-{len(containers)}) or enter custom name", "1")

        try:
            idx = int(choice) - 1
            if 0 <= idx < len(containers):
                container_name = containers[idx]
            else:
                container_name = choice
        except ValueError:
            container_name = choice

    # Test connection
    print_info(f"Testing connection to {container_name}...")
    success, info = test_rippled_connection(container_name)

    if not success:
        print_error(f"Failed to connect to container '{container_name}'")
        print_info("Please verify:")
        print_info("  • Container is running: docker ps")
        print_info("  • rippled is accessible via: docker exec {container_name} rippled server_info")

        if ask_yes_no("Try a different container?", True):
            new_name = ask_input("Enter container name", "rippledvalidator")
            return configure_docker_mode([new_name])

        if not ask_yes_no("Continue anyway?", False):
            return None
        info = None

    # Display validator info if connected
    if info:
        print_success(f"Connected to rippled in container '{container_name}'")
        print_info(f"  Server State: {info.get('server_state', 'unknown')}")
        print_info(f"  Build Version: {info.get('build_version', 'unknown')}")

        pubkey = info.get('pubkey_validator', '')
        if pubkey and pubkey != 'none':
            print_info(f"  Validator Key: {pubkey[:30]}...")

        ledger_seq = info.get('validated_ledger', {}).get('seq') or \
                     info.get('closed_ledger', {}).get('seq', 'unknown')
        print_info(f"  Ledger Seq: {ledger_seq}")
        print("")

    return {
        'mode': 'docker',
        'container': container_name,
        'info': info
    }

def configure_native_mode_manual() -> Optional[dict]:
    """Manual configuration for native rippled"""
    print_info("Configuring native rippled manually...")

    host = ask_input("RPC API Host", "localhost")
    port_str = ask_input("RPC API Port", "5005")

    try:
        port = int(port_str)
    except ValueError:
        print_error(f"Invalid port: {port_str}")
        return None

    return {
        'mode': 'native',
        'host': host,
        'port': port,
        'version': 'unknown',
        'info': None
    }

def configure_docker_mode_manual() -> Optional[dict]:
    """Manual configuration for Docker rippled"""
    print_info("Configuring Docker rippled manually...")

    container_name = ask_input("Container name", "rippledvalidator")

    return {
        'mode': 'docker',
        'container': container_name,
        'info': None
    }

def check_ports() -> Tuple[int, int, int, int]:
    """Check and configure ports"""
    print_header("Step 3: Checking Port Availability")

    ports = {
        'grafana': 3001,
        'prometheus': 9092,
        'node_exporter': 9102,
        'monitor': 9094
    }

    # Detect existing container ports and processes
    container_patterns = {
        'grafana': 'grafana',
        'prometheus': 'prometheus',
        'node_exporter': 'node-exporter',
        'monitor': 'xrpl'  # Catch xrpl-monitor, xrpl-dashboard, etc.
    }

    for service, port in ports.items():
        if is_port_available(port):
            print_success(f"{service.capitalize()}: port {port} is available")
        else:
            print_warning(f"{service.capitalize()}: port {port} is in use")

            # Show what's using related ports
            if service in container_patterns:
                used_ports = get_container_ports(container_patterns[service])
                if used_ports:
                    if service == 'monitor':
                        print_info(f"  Existing XRPL monitor instances using ports: {', '.join(map(str, used_ports))}")
                    else:
                        print_info(f"  Existing {service} containers using ports: {', '.join(map(str, used_ports))}")

            # Find next available port
            suggested_port = find_next_available_port(port + 1)

            if suggested_port:
                print_info(f"  Suggested next available port: {suggested_port}")

                while True:
                    new_port = ask_input(
                        f"Enter port for {service} (or press Enter for {suggested_port})",
                        str(suggested_port)
                    )

                    try:
                        new_port = int(new_port)
                        if is_port_available(new_port):
                            print_success(f"Port {new_port} is available")
                            ports[service] = new_port
                            break
                        else:
                            print_warning(f"Port {new_port} is in use. Try another port.")
                    except ValueError:
                        print_warning("Please enter a valid port number")
            else:
                print_error(f"Could not find available port. Please specify manually:")
                while True:
                    new_port = ask_input(f"Enter port for {service}", "")
                    try:
                        new_port = int(new_port)
                        if is_port_available(new_port):
                            print_success(f"Port {new_port} is available")
                            ports[service] = new_port
                            break
                        else:
                            print_warning(f"Port {new_port} is in use")
                    except ValueError:
                        print_warning("Please enter a valid port number")

    return ports['grafana'], ports['prometheus'], ports['node_exporter'], ports['monitor']

def check_python_package(package_name: str) -> bool:
    """Check if a Python package is already installed"""
    try:
        if package_name == 'pyyaml':
            import yaml
            return True
        elif package_name == 'prometheus-client':
            import prometheus_client
            return True
        return False
    except ImportError:
        return False

def install_python_dependencies() -> bool:
    """Install required Python packages"""
    print_header("Step 4: Installing Python Dependencies")

    packages = ['prometheus-client', 'pyyaml']
    package_map = {
        'prometheus-client': 'prometheus_client',
        'pyyaml': 'yaml'
    }

    # Check which packages are already installed
    missing_packages = []
    for pkg in packages:
        if not check_python_package(pkg):
            missing_packages.append(pkg)
        else:
            print_success(f"{pkg} is already installed")

    if not missing_packages:
        print_success("All required packages are already installed")
        return True

    print_info(f"Missing packages: {', '.join(missing_packages)}")

    if not ask_yes_no("Install missing Python dependencies?", True):
        print_warning("Skipping dependency installation")
        print_info("You can install manually with: pip3 install --user " + " ".join(missing_packages))
        return False

    # Try installing with --user flag (works on externally-managed systems)
    print_info("Installing packages to user directory (~/.local/)...")
    try:
        result = subprocess.run(
            ['pip3', 'install', '--user'] + missing_packages,
            capture_output=True,
            text=True,
            timeout=120
        )

        if result.returncode == 0:
            print_success("Python dependencies installed successfully")
            print_info("Packages installed to: ~/.local/lib/python*/site-packages/")
            print_warning("Note: You may need to re-run setup.py for import tests to work")
            return 'installed'  # Signal that packages were just installed

        # If --user install failed, check if it's externally-managed error
        if 'externally-managed-environment' in result.stderr:
            print_warning("System Python is externally managed")
            print_info("Trying system package installation...")

            # Try apt install as fallback
            apt_packages = {
                'prometheus-client': 'python3-prometheus-client',
                'pyyaml': 'python3-yaml'
            }

            apt_pkgs = [apt_packages[pkg] for pkg in missing_packages if pkg in apt_packages]

            if apt_pkgs:
                print_info(f"Attempting: sudo apt install {' '.join(apt_pkgs)}")
                result = subprocess.run(
                    ['sudo', 'apt', 'install', '-y'] + apt_pkgs,
                    capture_output=True,
                    text=True,
                    timeout=120
                )

                if result.returncode == 0:
                    print_success("Packages installed via apt")
                    return True

        # All methods failed
        print_error("Could not install dependencies automatically")
        print("\nPlease install manually using ONE of these methods:")
        print(f"  1. User install:   pip3 install --user {' '.join(missing_packages)}")
        print(f"  2. System install: sudo apt install python3-prometheus-client python3-yaml")
        print(f"  3. Virtual env:    python3 -m venv venv && source venv/bin/activate && pip install {' '.join(missing_packages)}")
        return False

    except Exception as e:
        print_error(f"Installation failed: {e}")
        return False

def generate_config(rippled_config: dict, monitor_port: int) -> bool:
    """Generate config.yaml for Docker or native rippled"""
    print_header("Step 5: Generating Configuration")

    project_dir = Path(__file__).parent.absolute()
    config_path = project_dir / 'config.yaml'

    # Build monitoring section based on mode
    if rippled_config['mode'] == 'docker':
        monitoring_config = f"""monitoring:
  poll_interval: 3  # seconds between polls
  rippled_mode: docker
  container_name: {rippled_config['container']}
"""
    else:  # native mode
        monitoring_config = f"""monitoring:
  poll_interval: 3  # seconds between polls
  rippled_mode: native
  rippled_host: {rippled_config['host']}
  rippled_port: {rippled_config['port']}
"""

    config_content = f"""# XRPL Monitor Configuration

# Monitoring settings
{monitoring_config}
# Prometheus exporter settings
prometheus:
  enabled: true
  port: {monitor_port}
  host: 0.0.0.0  # Listen on all interfaces

# Alert settings
alerts:
  # File-based alerts (always enabled)
  file_enabled: true

  # Email alerts - DISABLED (using Grafana alerts instead)
  email_enabled: false
  # Note: Email alerts are handled by Grafana
  # Configure email in Grafana Settings -> Alerting -> Contact Points

# Database settings
database:
  path: {project_dir}/data/monitor.db

# Logging
logging:
  level: INFO
  file: {project_dir}/logs/monitor.log
"""

    # Backup existing config if it exists
    if config_path.exists():
        backup_path = config_path.with_suffix('.yaml.backup')
        print_info(f"Backing up existing config to {backup_path.name}")
        shutil.copy(config_path, backup_path)

    # Write new config
    try:
        with open(config_path, 'w') as f:
            f.write(config_content)

        print_success(f"Configuration written to {config_path}")

        # Also update config/config.yaml
        config_dir_path = project_dir / 'config' / 'config.yaml'
        if config_dir_path.parent.exists():
            with open(config_dir_path, 'w') as f:
                f.write(config_content)
            print_success(f"Also updated {config_dir_path}")

        return True

    except Exception as e:
        print_error(f"Failed to write config: {e}")
        return False

def update_prometheus_config(monitor_port: int) -> bool:
    """Update Prometheus scrape configuration"""
    project_dir = Path(__file__).parent.absolute()
    prom_config_path = project_dir / 'compose' / 'prometheus' / 'prometheus.yml'

    if not prom_config_path.exists():
        print_warning(f"Prometheus config not found at {prom_config_path}")
        return False

    # Update the target port in prometheus.yml
    try:
        with open(prom_config_path, 'r') as f:
            content = f.read()

        # Replace the target port
        import re
        content = re.sub(
            r'host\.docker\.internal:\d+',
            f'host.docker.internal:{monitor_port}',
            content
        )

        with open(prom_config_path, 'w') as f:
            f.write(content)

        print_success("Updated Prometheus scrape target")
        return True

    except Exception as e:
        print_error(f"Failed to update Prometheus config: {e}")
        return False

def update_docker_compose(grafana_port: int, prometheus_port: int, node_exporter_port: int) -> bool:
    """Update docker-compose.yml port mappings"""
    project_dir = Path(__file__).parent.absolute()
    compose_path = project_dir / 'docker-compose.yml'

    if not compose_path.exists():
        print_warning(f"docker-compose.yml not found")
        return False

    try:
        with open(compose_path, 'r') as f:
            content = f.read()

        # Update port mappings
        import re
        content = re.sub(r'"9092:9090"', f'"{prometheus_port}:9090"', content)
        content = re.sub(r'"9102:9100"', f'"{node_exporter_port}:9100"', content)
        content = re.sub(r'"3001:3000"', f'"{grafana_port}:3000"', content)

        with open(compose_path, 'w') as f:
            f.write(content)

        print_success("Updated docker-compose.yml port mappings")
        return True

    except Exception as e:
        print_error(f"Failed to update docker-compose.yml: {e}")
        return False

def create_directories() -> bool:
    """Create necessary directories"""
    project_dir = Path(__file__).parent.absolute()

    dirs = [
        project_dir / 'data',
        project_dir / 'logs'
    ]

    for dir_path in dirs:
        try:
            dir_path.mkdir(exist_ok=True)
            print_success(f"Directory ready: {dir_path.name}/")
        except Exception as e:
            print_error(f"Failed to create {dir_path}: {e}")
            return False

    return True

def test_rippled_api_calls(container_name: str) -> Tuple[bool, List[str]]:
    """Test the rippled API calls that the monitor will use"""
    failed_calls = []

    # Test server_info (most critical)
    try:
        result = subprocess.run(
            ['docker', 'exec', container_name, 'rippled', 'server_info'],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode != 0:
            failed_calls.append("server_info")
        else:
            data = json.loads(result.stdout)
            if 'result' not in data or 'info' not in data.get('result', {}):
                failed_calls.append("server_info (invalid response)")
    except Exception as e:
        failed_calls.append(f"server_info ({str(e)})")

    # Test peers (used for peer details)
    try:
        result = subprocess.run(
            ['docker', 'exec', container_name, 'rippled', 'peers'],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode != 0:
            failed_calls.append("peers")
    except Exception as e:
        failed_calls.append(f"peers ({str(e)})")

    # Test fee (used for transaction rate)
    try:
        result = subprocess.run(
            ['docker', 'exec', container_name, 'rippled', 'fee'],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode != 0:
            failed_calls.append("fee")
    except Exception as e:
        failed_calls.append(f"fee ({str(e)})")

    return len(failed_calls) == 0, failed_calls

def run_preflight_checks(rippled_config: dict, monitor_port: int, skip_import_tests: bool = False) -> bool:
    """Run pre-flight checks for Docker or native rippled"""
    print_header("Step 6: Running Pre-Flight Checks")

    all_passed = True
    mode = rippled_config['mode']

    # Check rippled connection
    print_info(f"Testing rippled connection ({mode} mode)...")

    if mode == 'docker':
        container_name = rippled_config['container']
        success, info = test_rippled_connection(container_name)
        connection_desc = f"container '{container_name}'"
    else:  # native mode
        host = rippled_config['host']
        port = rippled_config['port']
        success, info = test_native_rippled_connection(host, port)
        connection_desc = f"{host}:{port}"

    if success:
        print_success(f"rippled is accessible ({connection_desc})")
    else:
        print_error(f"Cannot connect to rippled ({connection_desc})")
        all_passed = False
        return all_passed  # No point continuing if rippled isn't accessible

    # Test rippled API calls (only for Docker mode)
    if mode == 'docker':
        container_name = rippled_config['container']
        print_info(f"Testing rippled API calls (via docker exec {container_name})...")
        api_success, failed_calls = test_rippled_api_calls(container_name)
        if api_success:
            print_success("All rippled API calls working (server_info, peers, fee)")
        else:
            print_error(f"Some rippled API calls failed: {', '.join(failed_calls)}")
            print_warning("The monitor may not work correctly")
            all_passed = False
    else:
        print_info("Native mode: API calls will be tested via HTTP")
        print_success("Connection successful (detailed API tests will run during monitoring)")

    # Check monitor port availability
    print_info(f"Checking monitor port {monitor_port}...")
    if is_port_available(monitor_port):
        print_success(f"Port {monitor_port} is available for metrics export")
    else:
        print_error(f"Port {monitor_port} is in use - monitor cannot start")
        all_passed = False

    # Check Python imports (skip if packages were just installed)
    if skip_import_tests:
        print_info("Skipping import tests (packages just installed - re-run setup.py to verify)")
    else:
        print_info("Testing Python imports...")
        try:
            import prometheus_client
            import yaml
            print_success("Required Python packages are installed")
        except ImportError as e:
            print_error(f"Missing Python package: {e}")
            all_passed = False

        # Test Prometheus exporter initialization
        print_info("Testing Prometheus exporter...")
        try:
            from prometheus_client import Gauge, Counter
            test_gauge = Gauge('test_metric', 'Test metric')
            test_gauge.set(1)
            print_success("Prometheus exporter can initialize")
        except Exception as e:
            print_error(f"Prometheus exporter test failed: {e}")
            all_passed = False

    # Check config file
    project_dir = Path(__file__).parent.absolute()
    config_path = project_dir / 'config.yaml'
    if config_path.exists():
        print_success("Configuration file exists")

        # Validate config content
        try:
            import yaml
            with open(config_path, 'r') as f:
                config = yaml.safe_load(f)

            # Check essential config values based on mode
            config_mode = config.get('monitoring', {}).get('rippled_mode')
            if config_mode == mode:
                print_success(f"Config mode matches: {mode}")

                # Validate mode-specific settings
                if mode == 'docker':
                    container_name = rippled_config['container']
                    if config.get('monitoring', {}).get('container_name') == container_name:
                        print_success(f"Config container name matches: {container_name}")
                    else:
                        print_warning(f"Config container name mismatch")
                else:  # native mode
                    config_host = config.get('monitoring', {}).get('rippled_host')
                    config_port = config.get('monitoring', {}).get('rippled_port')
                    if config_host == rippled_config['host'] and config_port == rippled_config['port']:
                        print_success(f"Config rippled connection matches: {config_host}:{config_port}")
                    else:
                        print_warning(f"Config rippled connection mismatch")
            else:
                print_warning(f"Config mode mismatch (expected {mode}, got {config_mode})")

            if config.get('prometheus', {}).get('port') == monitor_port:
                print_success(f"Config monitor port matches: {monitor_port}")
            else:
                print_warning(f"Config monitor port mismatch")

        except Exception as e:
            print_warning(f"Could not validate config content: {e}")
    else:
        print_error("Configuration file missing")
        all_passed = False

    # Check docker-compose
    compose_path = project_dir / 'docker-compose.yml'
    if compose_path.exists():
        print_success("docker-compose.yml exists")
    else:
        print_error("docker-compose.yml missing")
        all_passed = False

    # Check database directory
    data_dir = project_dir / 'data'
    if data_dir.exists():
        print_success("Data directory exists")
    else:
        print_warning("Data directory missing (will be created)")

    # Check logs directory
    logs_dir = project_dir / 'logs'
    if logs_dir.exists():
        print_success("Logs directory exists")
    else:
        print_warning("Logs directory missing (will be created)")

    return all_passed

def set_grafana_home_dashboard(grafana_port: int, dashboard_uid: str) -> bool:
    """Set a dashboard as the home dashboard for the default org"""
    import urllib.request
    import urllib.error
    import base64

    try:
        # Update org preferences to set home dashboard
        url = f'http://127.0.0.1:{grafana_port}/api/org/preferences'

        payload = {
            "homeDashboardUID": dashboard_uid
        }

        data = json.dumps(payload).encode('utf-8')

        credentials = base64.b64encode(b'admin:admin').decode('ascii')
        headers = {
            'Content-Type': 'application/json',
            'Authorization': f'Basic {credentials}'
        }

        request = urllib.request.Request(url, data=data, headers=headers, method='PUT')
        urllib.request.urlopen(request, timeout=10)

        return True
    except Exception as e:
        return False

def get_nodename_from_prometheus(prometheus_port: int) -> str:
    """Query Prometheus to get the actual nodename from node_exporter"""
    import urllib.request
    import urllib.error

    try:
        # Query node_uname_info to get nodename label
        url = f'http://127.0.0.1:{prometheus_port}/api/v1/query?query=node_uname_info'

        request = urllib.request.Request(url)
        response = urllib.request.urlopen(request, timeout=5)

        if response.status == 200:
            data = json.loads(response.read().decode('utf-8'))
            results = data.get('data', {}).get('result', [])

            if results:
                # Get nodename from the first result's labels
                nodename = results[0].get('metric', {}).get('nodename', '')
                if nodename:
                    return nodename

        return ''
    except Exception as e:
        return ''

def import_grafana_dashboard(grafana_port: int, dashboard_path: str, node_exporter_port: int, prometheus_port: int) -> Tuple[bool, str, str, str]:
    """Import a dashboard into Grafana via API with dynamic variable defaults"""
    import time
    import urllib.request
    import urllib.error
    import base64

    # Wait for Grafana and Prometheus to be fully ready
    time.sleep(5)

    # Get the actual nodename from Prometheus
    nodename = get_nodename_from_prometheus(prometheus_port)
    if not nodename:
        # Fallback to the fixed hostname set in docker-compose.yml
        nodename = 'xrpl-validator'

    try:
        # Read dashboard JSON
        with open(dashboard_path, 'r') as f:
            dashboard_json = json.load(f)

        # Remove UID and ID to avoid conflicts with existing dashboards
        # Grafana will generate new ones on import
        if 'uid' in dashboard_json:
            del dashboard_json['uid']
        if 'id' in dashboard_json:
            del dashboard_json['id']

        # Update template variable defaults to match the setup configuration
        if 'templating' in dashboard_json and 'list' in dashboard_json['templating']:
            for template_var in dashboard_json['templating']['list']:
                var_name = template_var.get('name', '')

                # Set default for 'job' variable
                if var_name == 'job' or var_name.lower() == 'job':
                    template_var['current'] = {
                        'selected': True,
                        'text': 'xrpl-validator',
                        'value': 'xrpl-validator'
                    }
                    if 'options' not in template_var:
                        template_var['options'] = []

                # Set default for 'instance' or 'node' variable
                elif var_name in ['instance', 'node']:
                    instance_value = f'127.0.0.1:{node_exporter_port}'
                    template_var['current'] = {
                        'selected': True,
                        'text': instance_value,
                        'value': instance_value
                    }
                    if 'options' not in template_var:
                        template_var['options'] = []

                # Set default for 'nodename' - use actual nodename from Prometheus
                elif var_name == 'nodename':
                    template_var['multi'] = False
                    template_var['current'] = {
                        'selected': True,
                        'text': nodename,
                        'value': nodename
                    }
                    if 'options' not in template_var:
                        template_var['options'] = []

                # Set defaults for other variables to All
                elif var_name in ['containergroup', 'server', 'diskdevices']:
                    template_var['current'] = {
                        'selected': False,
                        'text': 'All',
                        'value': '$__all'
                    }
                    if var_name != 'diskdevices':  # diskdevices is a regex, not a query
                        template_var['includeAll'] = True
                        template_var['allValue'] = '.*'

        # Prepare the import payload
        payload = {
            "dashboard": dashboard_json,
            "overwrite": True,
            "message": "Imported by setup wizard"
        }

        # Create request with basic auth
        url = f'http://127.0.0.1:{grafana_port}/api/dashboards/db'
        data = json.dumps(payload).encode('utf-8')

        # Add basic auth header
        credentials = base64.b64encode(b'admin:admin').decode('ascii')
        headers = {
            'Content-Type': 'application/json',
            'Authorization': f'Basic {credentials}'
        }

        request = urllib.request.Request(url, data=data, headers=headers, method='POST')

        response = urllib.request.urlopen(request, timeout=10)

        if response.status == 200:
            # Parse response to get dashboard UID
            response_data = json.loads(response.read().decode('utf-8'))
            dashboard_uid = response_data.get('uid', '')
            dashboard_name = dashboard_json.get('title', 'Dashboard')
            return True, dashboard_name, dashboard_uid, nodename
        else:
            return False, f"HTTP {response.status}", "", ""

    except urllib.error.HTTPError as e:
        return False, f"HTTP {e.code}: {e.read().decode()}", "", ""
    except Exception as e:
        return False, str(e), "", ""

def install_systemd_service() -> bool:
    """Install the monitor as a systemd service"""
    service_name = "xrpl-validator-dashboard"
    service_file = f"/etc/systemd/system/{service_name}.service"
    project_dir = os.getcwd()

    print_info("Installing monitor as a background service (systemd)")
    print_info("This requires sudo access to create the service file")
    print("")

    # Create service file content
    service_content = f"""[Unit]
Description=XRPL Validator Dashboard Monitor
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User={os.getenv('USER', 'grapedrop')}
Group={os.getenv('USER', 'grapedrop')}
WorkingDirectory={project_dir}
ExecStart=/usr/bin/python3 -u {project_dir}/src/collectors/fast_poller.py
Restart=always
RestartSec=10
StandardOutput=append:{project_dir}/logs/monitor.log
StandardError=append:{project_dir}/logs/error.log
NoNewPrivileges=true
MemoryMax=512M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
"""

    try:
        # Write service file
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write(service_content)
            temp_file = f.name

        # Copy to systemd directory
        result = subprocess.run(
            ['sudo', 'cp', temp_file, service_file],
            capture_output=True,
            text=True
        )
        os.unlink(temp_file)

        if result.returncode != 0:
            print_error("Failed to create service file")
            return False

        print_success("Service file created")

        # Reload systemd
        subprocess.run(['sudo', 'systemctl', 'daemon-reload'], check=True, capture_output=True)
        print_success("Systemd reloaded")

        # Enable service
        subprocess.run(['sudo', 'systemctl', 'enable', service_name], check=True, capture_output=True)
        print_success("Service enabled (will start on boot)")

        # Start service
        subprocess.run(['sudo', 'systemctl', 'start', service_name], check=True, capture_output=True)
        print_success("Service started")

        # Brief pause to let service start
        import time
        time.sleep(2)

        # Check status
        result = subprocess.run(
            ['systemctl', 'is-active', service_name],
            capture_output=True,
            text=True
        )

        if result.stdout.strip() == 'active':
            print_success(f"Monitor is running as '{service_name}' service")
            return True
        else:
            print_warning("Service may not have started correctly")
            return False

    except subprocess.CalledProcessError as e:
        print_error(f"Failed to install service: {e}")
        return False
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        return False

def print_next_steps(grafana_port: int, prometheus_port: int, monitor_port: int):
    """Print next steps for the user"""
    print_header("Setup Complete!")

    print(f"{Colors.OKGREEN}{Colors.BOLD}Next Steps:{Colors.ENDC}\n")

    print(f"{Colors.BOLD}1. Start the monitoring stack:{Colors.ENDC}")
    print(f"   docker compose up -d\n")

    print(f"{Colors.BOLD}2. Start the validator monitor:{Colors.ENDC}")
    print(f"   python3 src/collectors/fast_poller.py\n")

    print(f"{Colors.BOLD}3. Access your dashboards:{Colors.ENDC}")
    print(f"   Grafana:    http://localhost:{grafana_port}")
    print(f"               Username: admin / Password: admin")
    print(f"   Prometheus: http://localhost:{prometheus_port}")
    print(f"   Metrics:    http://localhost:{monitor_port}/metrics\n")

    print(f"{Colors.BOLD}4. Import Grafana dashboards:{Colors.ENDC}")
    print(f"   - Go to http://localhost:{grafana_port}")
    print(f"   - Navigate to Dashboards → New → Import")
    print(f"   - Click 'Upload dashboard JSON file'")
    print(f"   - Browse to dashboards/categories/ and select 1-overview-status.json")
    print(f"   - Select Prometheus as data source → Import")
    print(f"   - Repeat for the other 5 dashboard files\n")

    print(f"{Colors.OKBLUE}For detailed instructions, see SETUP.md{Colors.ENDC}\n")

def main():
    """Main setup wizard"""
    print_header("XRPL Validator Dashboard - Setup Wizard")
    print("This wizard will guide you through setting up the dashboard")
    print("for rippled deployments (Docker or native).\n")

    # Step 1: Check prerequisites - Check ALL first before continuing
    print_header("Step 1: Checking Prerequisites")

    prereqs_met = {
        'python': check_python(),
        'pip': check_pip(),
        'docker': check_docker(),
        'docker_compose': check_docker_compose()
    }

    # If any prerequisite failed, show summary
    if not all(prereqs_met.values()):
        print_error("\nPrerequisite checks failed!")
        print("\nMissing requirements:")

        if not prereqs_met['python']:
            print(f"  ✗ Python 3.6+ is required")
        if not prereqs_met['pip']:
            print(f"  ✗ pip3 is required")
        if not prereqs_met['docker']:
            print(f"  ✗ Docker is required")
        if not prereqs_met['docker_compose']:
            print(f"  ✗ docker-compose is required")

        # Check if only Docker/pip are missing (we can auto-install these)
        can_auto_install = (
            prereqs_met['python'] and  # Python must be present
            (not prereqs_met['pip'] or not prereqs_met['docker'] or not prereqs_met['docker_compose'])
        )

        if can_auto_install:
            print("")
            print_info("I can automatically install the missing prerequisites for you.")

            if ask_yes_no("Install missing prerequisites now?", True):
                # Run the install-prerequisites.sh script
                install_script = Path(__file__).parent / 'install-prerequisites.sh'

                if install_script.exists():
                    print("")
                    print_info("Running installation script...")
                    print_info("You may be prompted for your sudo password.")
                    print("")

                    try:
                        result = subprocess.run(
                            ['bash', str(install_script)],
                            cwd=Path(__file__).parent,
                            timeout=600  # 10 minute timeout
                        )

                        if result.returncode == 0:
                            print("")
                            print_success("Prerequisites installed successfully!")
                            print("")
                            print_header("IMPORTANT: Logout Required")
                            print("")
                            print_info("Docker group permissions require a fresh login session.")
                            print("")
                            print_info("Next steps:")
                            print(f"  {Colors.BOLD}1.{Colors.ENDC} Log out of this session:")
                            print(f"     {Colors.BOLD}exit{Colors.ENDC}")
                            print("")
                            print(f"  {Colors.BOLD}2.{Colors.ENDC} Log back in via SSH")
                            print("")
                            print(f"  {Colors.BOLD}3.{Colors.ENDC} Run setup again:")
                            print(f"     {Colors.BOLD}cd ~/rippled/xrpl-validator-dashboard{Colors.ENDC}")
                            print(f"     {Colors.BOLD}python3 setup.py{Colors.ENDC}")
                            print("")
                            return 0
                        else:
                            print_error("Installation script failed")
                            return 1

                    except subprocess.TimeoutExpired:
                        print_error("Installation timed out")
                        return 1
                    except Exception as e:
                        print_error(f"Installation failed: {e}")
                        return 1
                else:
                    print_warning("Installation script not found at: install-prerequisites.sh")
                    print_info("Please install the missing prerequisites manually.")
                    print_info("See README.md for detailed installation instructions.")
                    return 1
            else:
                print(f"\n{Colors.OKBLUE}Please install the missing prerequisites and try again.{Colors.ENDC}")
                print(f"{Colors.OKBLUE}See README.md for detailed installation instructions.{Colors.ENDC}\n")
                return 1
        else:
            print(f"\n{Colors.OKBLUE}Please install the missing prerequisites and try again.{Colors.ENDC}")
            print(f"{Colors.OKBLUE}See README.md for detailed installation instructions.{Colors.ENDC}\n")
            return 1

    print_success("All prerequisites met!")

    # Step 2: Detect rippled installation (Docker or native)
    rippled_config = detect_rippled_unified()
    if not rippled_config:
        print_error("Cannot proceed without a valid rippled installation")
        return 1

    # Step 3: Check ports
    grafana_port, prometheus_port, node_exporter_port, monitor_port = check_ports()

    # Step 4: Install dependencies
    deps_result = install_python_dependencies()
    packages_just_installed = (deps_result == 'installed')

    if not deps_result:
        print_warning("Some dependencies may be missing")
        if not ask_yes_no("Continue anyway?", False):
            return 1

    # Step 5: Generate configuration
    if not create_directories():
        return 1

    if not generate_config(rippled_config, monitor_port):
        return 1

    if not update_prometheus_config(monitor_port):
        print_warning("Could not update Prometheus config")

    if not update_docker_compose(grafana_port, prometheus_port, node_exporter_port):
        print_warning("Could not update docker-compose.yml")

    # Step 6: Pre-flight checks
    if not run_preflight_checks(rippled_config, monitor_port, packages_just_installed):
        print_warning("Some pre-flight checks failed")
        if not ask_yes_no("Continue anyway?", True):
            return 1

    # Done with configuration!
    print_header("Setup Complete!")
    print_success("Configuration files generated successfully")
    print("")

    # Ask if user wants automatic or manual setup
    if ask_yes_no("Automatically start services and import dashboard?", True):
        # AUTOMATIC FLOW
        print("")
        print_info("Starting automated setup...")
        print("")

        # Step 1: Start Docker services
        docker_started = False
        print_info("Step 1/3: Starting Docker services (Grafana, Prometheus, Node Exporter)...")
        try:
            subprocess.run(['docker', 'compose', 'up', '-d'], check=True, capture_output=True)
            print_success("Docker services started")
            docker_started = True
        except (subprocess.CalledProcessError, FileNotFoundError):
            try:
                subprocess.run(['docker-compose', 'up', '-d'], check=True, capture_output=True)
                print_success("Docker services started")
                docker_started = True
            except:
                print_error("Failed to start Docker services")
                print_info("Try manually: docker compose up -d")

        # Step 2: Install monitor as systemd service
        service_installed = False
        if docker_started:
            print("")
            if ask_yes_no("Install monitor as a systemd service? (recommended)", True):
                print_info("Step 2/3: Installing monitor as systemd service...")
                print_info("(You will be prompted for sudo password)")
                print("")

                service_installed = install_systemd_service()

                if not service_installed:
                    print_warning("Service installation failed, but continuing with dashboard setup")
                    print_info("You can manually start the monitor later with:")
                    print_info("  python3 fast_poller.py &")
                    print_info("Or install the service with: ./install-service.sh")
            else:
                print_info("Skipping systemd service installation")
                print_info("You can install it later with: ./install-service.sh")

        # Step 3: Import dashboard (always proceed if docker started)
        if docker_started:
            # Step 3: Import dashboard
            print("")
            print_info("Step 3/3: Importing dashboard...")
            dashboard_file = Path(__file__).parent / 'dashboards' / 'categories' / 'xrpl-monitor-dashboard.json'

            if dashboard_file.exists():
                print_info("Querying Prometheus for node hostname...")
                success, result, dashboard_uid, detected_nodename = import_grafana_dashboard(grafana_port, str(dashboard_file), node_exporter_port, prometheus_port)

                if success:
                    print_success(f"Dashboard imported: {result}")
                    print_info(f"Configured defaults: Job=xrpl-validator, Instance=127.0.0.1:{node_exporter_port}, Nodename={detected_nodename}")

                    # Set as home dashboard so it opens automatically on login
                    if dashboard_uid and set_grafana_home_dashboard(grafana_port, dashboard_uid):
                        print_success("Dashboard set as home page (opens automatically on login)")

                    print("")
                    print_header("All Done! Everything is Running")
                    print("")
                    print_success(f"Services running:")
                    print(f"  Grafana:    http://localhost:{grafana_port}")
                    print(f"  Prometheus: http://localhost:{prometheus_port}")
                    print(f"  Metrics:    http://localhost:{monitor_port}/metrics")
                    print("")
                    print_info(f"{Colors.BOLD}You are ready to view your dashboard:{Colors.ENDC}")
                    print(f"  {Colors.BOLD}1.{Colors.ENDC} Go to {Colors.BOLD}http://localhost:{grafana_port}{Colors.ENDC}")
                    print(f"  {Colors.BOLD}2.{Colors.ENDC} Login with username: {Colors.BOLD}admin{Colors.ENDC} / password: {Colors.BOLD}admin{Colors.ENDC}")
                    print(f"  {Colors.BOLD}3.{Colors.ENDC} You will be prompted to change the password")
                    print(f"  {Colors.BOLD}4.{Colors.ENDC} Dashboard opens automatically with all metrics ready!")
                    print("")
                    print_info("⏳ Note: 24-hour metrics panels (Agreements %, Agreements, Missed) will")
                    print_info("        populate after 5-10 minutes as historical data is collected.")
                    print("")
                    print_info("Useful commands:")
                    print(f"  View live logs:     {Colors.BOLD}sudo journalctl -u xrpl-validator-dashboard -f{Colors.ENDC}")
                    print(f"  Check status:       {Colors.BOLD}sudo systemctl status xrpl-validator-dashboard{Colors.ENDC}")
                    print(f"  Restart service:    {Colors.BOLD}sudo systemctl restart xrpl-validator-dashboard{Colors.ENDC}")
                else:
                    print_warning(f"Auto-import failed: {result}")
                    print_info("Dashboard import steps:")
                    print(f"  1. Go to http://localhost:{grafana_port}")
                    print(f"  2. Dashboards → New → Import → Upload JSON file")
                    print(f"  3. Select: dashboards/categories/xrpl-monitor-dashboard.json")

    else:
        # MANUAL FLOW
        print("")
        print_info("Manual setup steps:")
        print("")
        print(f"{Colors.BOLD}1. Start Docker services:{Colors.ENDC}")
        print(f"   cd /home/grapedrop/projects/xrpl-validator-dashboard")
        print(f"   docker compose up -d")
        print("")
        print(f"{Colors.BOLD}2. Install monitor as systemd service:{Colors.ENDC}")
        print(f"   ./install-service.sh")
        print("")
        print(f"{Colors.BOLD}3. Import dashboard:{Colors.ENDC}")
        print(f"   - Go to http://localhost:{grafana_port} (admin/admin)")
        print(f"   - Dashboards → New → Import → Upload JSON file")
        print(f"   - Select: dashboards/categories/xrpl-monitor-dashboard.json")
        print("")
        print_info("Or run the monitor manually:")
        print(f"   python3 src/collectors/fast_poller.py")

    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print(f"\n\n{Colors.WARNING}Setup cancelled by user{Colors.ENDC}")
        sys.exit(1)
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
