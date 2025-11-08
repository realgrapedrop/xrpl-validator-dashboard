# Path templating applied - INSTALL_DIR will be set during installation
#!/usr/bin/env python3
"""
Configuration loader for XRPL Monitor
"""

import yaml
import os


class Config:
    """
    Load and provide access to configuration
    """
    
    def __init__(self, config_path: str = None):
        """
        Initialize configuration
        
        Args:
            config_path: Path to config.yaml file
        """
        if config_path is None:
            # Default to config.yaml in project root
            config_path = os.path.join(
                os.path.dirname(__file__),
                '../../config.yaml'
            )
        
        self.config_path = config_path
        self._load_config()
    
    def _load_config(self):
        """Load configuration from YAML file"""
        try:
            with open(self.config_path, 'r') as f:
                self.config = yaml.safe_load(f)
        except FileNotFoundError:
            print(f"Warning: Config file not found at {self.config_path}")
            self.config = self._default_config()
        except Exception as e:
            print(f"Error loading config: {e}")
            self.config = self._default_config()
    
    def _default_config(self):
        """Return default configuration"""
        return {
            'monitoring': {
                'poll_interval': 3,
                'container_name': 'rippledvalidator'
            },
            'prometheus': {
                'enabled': True,
                'port': 9091,
                'host': '0.0.0.0'
            },
            'alerts': {
                'file_enabled': True,
                'email_enabled': False,
                'email_to': '',
                'email_from': 'xrpl-monitor@localhost',
                'smtp_host': 'localhost',
                'smtp_port': 25,
                'smtp_use_tls': False
            },
            'database': {
                'path': '${INSTALL_DIR}/data/monitor.db'
            }
        }
    
    def get(self, key_path: str, default=None):
        """
        Get configuration value by dot-separated path

        Environment variables can override config values.
        For example, 'monitoring.rippled_host' can be overridden with
        XRPL_MONITORING_RIPPLED_HOST environment variable.

        Args:
            key_path: Dot-separated path (e.g., 'prometheus.port')
            default: Default value if key not found

        Returns:
            Configuration value
        """
        # Check for environment variable override
        env_key = 'XRPL_' + key_path.replace('.', '_').upper()
        env_value = os.getenv(env_key)
        if env_value is not None:
            # Try to convert to appropriate type
            if env_value.lower() in ('true', 'false'):
                return env_value.lower() == 'true'
            try:
                # Try integer
                return int(env_value)
            except ValueError:
                try:
                    # Try float
                    return float(env_value)
                except ValueError:
                    # Return as string
                    return env_value

        # Otherwise, get from config file
        keys = key_path.split('.')
        value = self.config

        for key in keys:
            if isinstance(value, dict) and key in value:
                value = value[key]
            else:
                return default

        return value
