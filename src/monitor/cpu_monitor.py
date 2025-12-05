#!/usr/bin/env python3
"""
CPU Monitor for rippled Process

Monitors CPU usage of rippled process using psutil.
Supports both Docker and native deployments.
"""

import logging
import subprocess
import psutil
from typing import Optional

logger = logging.getLogger(__name__)


class RippledCPUMonitor:
    """Monitor CPU usage of rippled process"""

    def __init__(self, docker_container: Optional[str] = None):
        """
        Initialize CPU monitor

        Args:
            docker_container: Docker container name if rippled runs in Docker
        """
        self.docker_container = docker_container
        self._rippled_pid: Optional[int] = None
        self._process: Optional[psutil.Process] = None
        self._last_cpu_percent: float = 0.0

        logger.info(f"CPU Monitor initialized (docker_container={docker_container or 'native'})")

    def _find_rippled_pid(self) -> Optional[int]:
        """
        Find rippled process PID

        Returns:
            PID of rippled process, or None if not found
        """
        try:
            if self.docker_container:
                # Docker: Get PID from container
                result = subprocess.run(
                    ['docker', 'inspect', '-f', '{{.State.Pid}}', self.docker_container],
                    capture_output=True,
                    text=True,
                    check=True,
                    timeout=5
                )
                pid = int(result.stdout.strip())

                if pid > 0:
                    logger.info(f"Found rippled PID: {pid} (Docker container: {self.docker_container})")
                    return pid
                else:
                    logger.warning(f"Docker container '{self.docker_container}' returned invalid PID: {pid}")
                    return None

            else:
                # Native: Try multiple methods to find rippled

                # Method 1: Try psutil first (works if collector is running natively)
                for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
                    try:
                        # Match 'rippled' or '/usr/bin/rippled'
                        if 'rippled' in proc.info['name'].lower():
                            pid = proc.info['pid']
                            logger.info(f"Found rippled PID: {pid} (native process via psutil)")
                            return pid

                        # Match by cmdline
                        cmdline = proc.info.get('cmdline')
                        if cmdline and any('rippled' in arg for arg in cmdline):
                            pid = proc.info['pid']
                            logger.info(f"Found rippled PID: {pid} (native process via cmdline)")
                            return pid

                    except (psutil.NoSuchProcess, psutil.AccessDenied):
                        continue

                # Method 2: If collector runs in container, use pidof or pgrep via /proc
                # This works when /proc is mounted from host
                try:
                    result = subprocess.run(
                        ['pidof', 'rippled'],
                        capture_output=True,
                        text=True,
                        timeout=2
                    )
                    if result.returncode == 0:
                        pid = int(result.stdout.strip().split()[0])  # Get first PID if multiple
                        logger.info(f"Found rippled PID: {pid} (native process via pidof)")
                        return pid
                except (subprocess.TimeoutExpired, subprocess.CalledProcessError, ValueError):
                    pass

                # Method 3: Try pgrep as final fallback
                try:
                    result = subprocess.run(
                        ['pgrep', '-x', 'rippled'],
                        capture_output=True,
                        text=True,
                        timeout=2
                    )
                    if result.returncode == 0:
                        pid = int(result.stdout.strip().split('\n')[0])  # Get first PID
                        logger.info(f"Found rippled PID: {pid} (native process via pgrep)")
                        return pid
                except (subprocess.TimeoutExpired, subprocess.CalledProcessError, ValueError):
                    pass

                # Method 4: Search /host/proc directly (when running in container with /proc mounted)
                # This is needed when collector runs in container with network_mode:host
                try:
                    import glob
                    for comm_file in glob.glob('/host/proc/[0-9]*/comm'):
                        try:
                            with open(comm_file, 'r') as f:
                                if f.read().strip() == 'rippled':
                                    pid = int(comm_file.split('/')[3])
                                    logger.info(f"Found rippled PID: {pid} (native process via /host/proc)")
                                    return pid
                        except (IOError, ValueError):
                            continue
                except Exception:
                    pass

                logger.warning("rippled process not found (native) - tried psutil, pidof, pgrep, and /host/proc")
                return None

        except subprocess.TimeoutExpired:
            logger.error(f"Timeout finding rippled PID (docker: {self.docker_container})")
            return None
        except subprocess.CalledProcessError as e:
            logger.error(f"Error finding rippled PID: {e}")
            return None
        except Exception as e:
            logger.error(f"Unexpected error finding rippled PID: {e}", exc_info=True)
            return None

    def get_cpu_percent(self) -> Optional[float]:
        """
        Get current CPU usage percentage

        Returns:
            CPU usage percentage (0-100+), or None if unavailable
        """
        try:
            # Use docker stats for Docker containers (more accurate than psutil for containers)
            if self.docker_container:
                return self._get_cpu_docker()

            # Use psutil for native deployments
            return self._get_cpu_psutil()

        except Exception as e:
            logger.error(f"Error getting CPU usage: {e}", exc_info=True)
            return None

    def _get_cpu_docker(self) -> Optional[float]:
        """
        Get CPU usage via docker stats (for Docker deployments)

        Returns:
            CPU usage percentage, or None if unavailable
        """
        try:
            result = subprocess.run(
                ['docker', 'stats', self.docker_container, '--no-stream', '--format', '{{.CPUPerc}}'],
                capture_output=True,
                text=True,
                check=True,
                timeout=5
            )

            # Output is like "30.57%" - strip % and convert to float
            cpu_str = result.stdout.strip().rstrip('%')
            cpu_percent = float(cpu_str)

            self._last_cpu_percent = cpu_percent
            return cpu_percent

        except subprocess.TimeoutExpired:
            logger.error(f"Timeout getting CPU for container: {self.docker_container}")
            return None
        except subprocess.CalledProcessError as e:
            logger.error(f"Error getting CPU for container: {e}")
            return None
        except (ValueError, IndexError) as e:
            logger.error(f"Error parsing docker stats output: {e}")
            return None

    def _get_cpu_psutil(self) -> Optional[float]:
        """
        Get CPU usage via psutil (for native deployments)

        Returns:
            CPU usage percentage, or None if unavailable
        """
        try:
            # Find PID if not cached
            if self._rippled_pid is None:
                self._rippled_pid = self._find_rippled_pid()

                if self._rippled_pid is None:
                    return None

            # Try using psutil first (works if /proc is not remapped)
            try:
                # Create Process object if not cached
                if self._process is None:
                    self._process = psutil.Process(self._rippled_pid)

                # Verify process still exists
                if not self._process.is_running():
                    logger.warning(f"rippled process (PID {self._rippled_pid}) is no longer running")
                    self._rippled_pid = None
                    self._process = None
                    return None

                # Get CPU percent (non-blocking, uses cached value)
                # First call returns 0.0, subsequent calls return accurate value
                cpu_percent = self._process.cpu_percent(interval=None)

                # Store for next iteration
                self._last_cpu_percent = cpu_percent

                return cpu_percent

            except (psutil.NoSuchProcess, psutil.AccessDenied):
                # psutil can't find the process (likely /proc remapped to /host/proc)
                # Fall back to manual calculation using /host/proc
                logger.debug(f"psutil failed for PID {self._rippled_pid}, trying /host/proc")
                return self._get_cpu_from_proc_files()

        except Exception as e:
            logger.error(f"Error in _get_cpu_psutil: {e}", exc_info=True)
            return None

    def _get_cpu_from_proc_files(self) -> Optional[float]:
        """
        Calculate CPU usage by reading /host/proc files directly

        This is used when psutil can't access the process (e.g., when running
        in a container with /proc mounted as /host/proc)

        Returns:
            CPU usage percentage, or None if unavailable
        """
        import time

        try:
            if self._rippled_pid is None:
                return None

            # Read CPU times from /host/proc/<pid>/stat
            stat_file = f'/host/proc/{self._rippled_pid}/stat'
            try:
                with open(stat_file, 'r') as f:
                    stat = f.read().split()

                # CPU times are at positions 13-16 (utime, stime, cutime, cstime)
                # All in clock ticks
                utime = int(stat[13])
                stime = int(stat[14])
                cutime = int(stat[15])
                cstime = int(stat[16])

                process_time = utime + stime + cutime + cstime

                # Get current time
                current_time = time.time()

                # Calculate CPU percent if we have a previous measurement
                if hasattr(self, '_last_process_time') and hasattr(self, '_last_measurement_time'):
                    time_delta = current_time - self._last_measurement_time
                    process_delta = process_time - self._last_process_time

                    # Get clock ticks per second
                    clock_ticks = 100  # Standard value, could also use os.sysconf('SC_CLK_TCK')

                    # Calculate CPU percentage
                    # process_delta is in clock ticks, convert to seconds
                    cpu_seconds = process_delta / clock_ticks
                    cpu_percent = (cpu_seconds / time_delta) * 100.0

                    self._last_cpu_percent = cpu_percent
                else:
                    # First measurement, return 0
                    cpu_percent = 0.0

                # Store current values for next iteration
                self._last_process_time = process_time
                self._last_measurement_time = current_time

                return cpu_percent

            except (IOError, IndexError, ValueError) as e:
                logger.warning(f"Error reading /host/proc/{self._rippled_pid}/stat: {e}")
                # Process might have terminated
                self._rippled_pid = None
                self._process = None
                return None

        except Exception as e:
            logger.error(f"Error calculating CPU from proc files: {e}", exc_info=True)
            return None

    def get_cpu_cores(self) -> int:
        """
        Get the number of CPU cores available to rippled.

        For Docker: Returns container CPU limit (or system cores if unlimited)
        For Native: Returns system cores

        Returns:
            Number of CPU cores available to rippled
        """
        try:
            if self.docker_container:
                # Docker: Query NanoCpus from container config
                result = subprocess.run(
                    ['docker', 'inspect', '-f', '{{.HostConfig.NanoCpus}}', self.docker_container],
                    capture_output=True,
                    text=True,
                    check=True,
                    timeout=5
                )
                nanocpus = int(result.stdout.strip())

                if nanocpus > 0:
                    # Container has CPU limit set
                    cores = nanocpus // 1_000_000_000
                    logger.debug(f"Docker container CPU limit: {cores} cores")
                    return cores
                else:
                    # No limit - container can use all system cores
                    import os
                    cores = os.cpu_count() or 1
                    logger.debug(f"Docker container unlimited - using system cores: {cores}")
                    return cores

            else:
                # Native: Use system cores
                import os
                cores = os.cpu_count() or 1
                logger.debug(f"Native rippled - system cores: {cores}")
                return cores

        except subprocess.TimeoutExpired:
            logger.error(f"Timeout getting CPU cores for container: {self.docker_container}")
        except subprocess.CalledProcessError as e:
            logger.error(f"Error getting CPU cores: {e}")
        except Exception as e:
            logger.error(f"Unexpected error getting CPU cores: {e}", exc_info=True)

        # Fallback to system cores
        import os
        return os.cpu_count() or 1

    def __repr__(self) -> str:
        return (
            f"RippledCPUMonitor(pid={self._rippled_pid}, "
            f"cpu={self._last_cpu_percent:.1f}%)"
        )
