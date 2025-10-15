#!/usr/bin/env python3
"""
Alerter - Sends alerts for important validator events
"""

import os
import time
from datetime import datetime
from typing import Optional


class Alerter:
    """
    Simple alerter that writes to file and stdout
    Can be extended for email, Slack, Discord, etc.
    """
    
    def __init__(self, alerts_file: Optional[str] = None):
        """
        Initialize alerter
        
        Args:
            alerts_file: Path to alerts log file (default: data/alerts.log)
        """
        if alerts_file is None:
            alerts_file = os.path.join(
                os.path.dirname(__file__),
                '../../data/alerts.log'
            )
        
        self.alerts_file = alerts_file
        
        # Ensure directory exists
        alerts_dir = os.path.dirname(alerts_file)
        if alerts_dir and not os.path.exists(alerts_dir):
            os.makedirs(alerts_dir)
    
    def alert(self, level: str, title: str, message: str):
        """
        Send an alert
        
        Args:
            level: Alert level (INFO, WARNING, CRITICAL)
            title: Alert title
            message: Alert message
        """
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        # Format alert
        alert_text = f"[{timestamp}] [{level}] {title}\n{message}\n"
        
        # Write to file
        try:
            with open(self.alerts_file, 'a') as f:
                f.write(alert_text + '\n')
        except Exception as e:
            print(f"Failed to write alert to file: {e}")
        
        # Print to stdout with color
        self._print_alert(level, timestamp, title, message)
    
    def _print_alert(self, level: str, timestamp: str, title: str, message: str):
        """Print colored alert to stdout"""
        
        # Color codes
        colors = {
            'INFO': '\033[94m',      # Blue
            'WARNING': '\033[93m',   # Yellow
            'CRITICAL': '\033[91m',  # Red
            'RESET': '\033[0m'
        }
        
        # Emoji
        emoji = {
            'INFO': 'ℹ️ ',
            'WARNING': '⚠️ ',
            'CRITICAL': '🚨'
        }
        
        color = colors.get(level, colors['RESET'])
        icon = emoji.get(level, '•')
        
        print(f"\n{color}{'='*60}")
        print(f"{icon}  ALERT: {title}")
        print(f"{'='*60}{colors['RESET']}")
        print(f"Level: {level}")
        print(f"Time: {timestamp}")
        print(f"{message}")
        print(f"{color}{'='*60}{colors['RESET']}\n")
    
    def state_change(self, old_state: str, new_state: str, 
                    duration: float, ledger_seq: int):
        """
        Alert for state changes
        
        Args:
            old_state: Previous state
            new_state: New state
            duration: Time in old state (seconds)
            ledger_seq: Current ledger sequence
        """
        # Determine severity
        if new_state in ['disconnected', 'syncing']:
            level = 'CRITICAL'
        elif new_state == 'tracking':
            level = 'WARNING'
        elif new_state == 'proposing':
            level = 'INFO'
        else:
            level = 'WARNING'
        
        title = f"State Change: {old_state} → {new_state}"
        
        message = (
            f"Validator state changed from '{old_state}' to '{new_state}'\n"
            f"Duration in {old_state}: {duration:.1f}s ({duration/60:.1f}m)\n"
            f"Ledger: {ledger_seq}"
        )
        
        self.alert(level, title, message)
    
    def validation_issue(self, issue_type: str, ledger_seq: int, details: str):
        """
        Alert for validation issues
        
        Args:
            issue_type: Type of issue (missed, disagreement)
            ledger_seq: Ledger sequence
            details: Additional details
        """
        if issue_type == 'disagreement':
            level = 'CRITICAL'
            title = f"Validation Disagreement on Ledger {ledger_seq}"
        else:
            level = 'WARNING'
            title = f"Missed Validation on Ledger {ledger_seq}"
        
        message = f"{details}"
        
        self.alert(level, title, message)
    
    def get_recent_alerts(self, count: int = 10) -> list:
        """
        Get recent alerts from file
        
        Args:
            count: Number of recent alerts to retrieve
            
        Returns:
            List of alert strings
        """
        try:
            if not os.path.exists(self.alerts_file):
                return []
            
            with open(self.alerts_file, 'r') as f:
                lines = f.readlines()
            
            # Get last N non-empty lines
            alerts = [line.strip() for line in lines if line.strip()]
            return alerts[-count:] if len(alerts) > count else alerts
        
        except Exception as e:
            print(f"Failed to read alerts: {e}")
            return []
