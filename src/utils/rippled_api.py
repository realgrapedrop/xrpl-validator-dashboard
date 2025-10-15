#!/usr/bin/env python3
"""
RippledAPI - Interface to rippled validator via Docker
"""

import subprocess
import json
import os
from typing import Dict, Any, Optional, List


class RippledAPIError(Exception):
    """Raised when rippled API calls fail"""
    pass


class RippledAPI:
    """
    Interface to rippled running in Docker container
    """
    
    def __init__(self, container_name: str = 'rippledvalidator'):
        """
        Initialize API client
        
        Args:
            container_name: Name of Docker container running rippled
        """
        self.container_name = container_name
    
    def _call(self, command: str, params: Optional[Dict] = None) -> Dict[str, Any]:
        """
        Call rippled API via docker exec
        
        Args:
            command: rippled command to execute
            params: Optional parameters dict
            
        Returns:
            Result dictionary from rippled
            
        Raises:
            RippledAPIError: If command fails
        """
        try:
            # Build command
            cmd = ['docker', 'exec', self.container_name, 'rippled', command]
            
            # Add JSON params if provided
            if params:
                cmd.append(json.dumps(params))
            
            # Execute
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode != 0:
                raise RippledAPIError(f"Command failed: {result.stderr}")
            
            # Parse JSON response
            try:
                data = json.loads(result.stdout)
                return data.get('result', {})
            except json.JSONDecodeError as e:
                raise RippledAPIError(f"Invalid JSON response: {e}")
        
        except subprocess.TimeoutExpired:
            raise RippledAPIError("Command timed out")
        except Exception as e:
            raise RippledAPIError(f"Command failed: {e}")
    
    def get_server_state(self) -> Dict[str, Any]:
        """
        Get comprehensive server information including state, validation_quorum, proposers, etc.
        
        Returns:
            Dictionary with server info (from server_info command)
        """
        result = self._call('server_info')
        return result.get('info', {})
    
    def get_server_info(self) -> Dict[str, Any]:
        """
        Alias for get_server_state() for backward compatibility
        
        Returns:
            Dictionary with server info
        """
        return self.get_server_state()
    
    def get_peers(self) -> List[Dict[str, Any]]:
        """
        Get list of connected peers with details
        
        Returns:
            List of peer dictionaries
        """
        result = self._call('peers')
        return result.get('peers', [])
    
    def get_ledger(self, ledger_index: Optional[int] = None, 
                   transactions: bool = False) -> Dict[str, Any]:
        """
        Get ledger information
        
        Args:
            ledger_index: Specific ledger to retrieve (default: validated)
            transactions: Include full transaction data
            
        Returns:
            Ledger information dict
        """
        params = {
            'ledger_index': ledger_index if ledger_index else 'validated',
            'transactions': transactions
        }
        result = self._call('ledger', params)
        return result.get('ledger', {})
    
    def get_validator_list_sites(self) -> Dict[str, Any]:
        """
        Get validator list sites information
        
        Returns:
            Validator list sites dict
        """
        return self._call('validator_list_sites')
    
    def get_validations(self, ledger_index: Optional[int] = None) -> list:
        """
        Get validations for a ledger
        
        Args:
            ledger_index: Ledger to get validations for
            
        Returns:
            List of validations
        """
        params = {}
        if ledger_index:
            params['ledger_index'] = ledger_index
        
        result = self._call('validations', params)
        return result.get('validations', [])
    
    def get_validator_info(self) -> Dict[str, Any]:
        """
        Get validator configuration and keys
        
        Returns:
            Validator info dict
        """
        return self._call('validator_info')
    
    def get_database_sizes(self, data_dir: str = '/home/grapedrop/rippled/data') -> Dict[str, int]:
        """
        Get database sizes from filesystem
        
        Args:
            data_dir: Path to rippled data directory
            
        Returns:
            Dictionary with database sizes in bytes
        """
        sizes = {
            'ledger_db': 0,
            'nudb': 0
        }
        
        try:
            # Check main database directory
            db_path = os.path.join(data_dir, 'db')
            if os.path.exists(db_path):
                sizes['ledger_db'] = self._get_directory_size(db_path)
            
            # Check NuDB directory
            nudb_path = os.path.join(data_dir, 'nudb')
            if os.path.exists(nudb_path):
                sizes['nudb'] = self._get_directory_size(nudb_path)
        except Exception as e:
            # If we can't access the directory, return zeros
            pass
        
        return sizes
    
    def _get_directory_size(self, path: str) -> int:
        """
        Get total size of directory
        
        Args:
            path: Directory path
            
        Returns:
            Size in bytes
        """
        total = 0
        try:
            for dirpath, dirnames, filenames in os.walk(path):
                for filename in filenames:
                    filepath = os.path.join(dirpath, filename)
                    if os.path.exists(filepath):
                        total += os.path.getsize(filepath)
        except Exception:
            pass
        return total
    
    def get_tx_history(self, start: int = 0) -> Dict[str, Any]:
        """
        Get recent transaction history
        
        Args:
            start: Starting index (0 = most recent)
            
        Returns:
            Transaction history dict with txs list
        """
        params = {'start': start}
        return self._call('tx_history', params)
    
    def get_fee(self) -> Dict[str, Any]:
        """
        Get current fee information and ledger size
        
        Returns:
            Fee information including current_ledger_size
        """
        return self._call('fee')
