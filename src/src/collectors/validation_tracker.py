#!/usr/bin/env python3
"""
Validation Tracker - State-based validation tracking (lightweight)
"""

import sys
import os
from typing import Dict, Any, Optional

# Add project root to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from src.utils.rippled_api import RippledAPI, RippledAPIError
from src.storage.database import Database


class ValidationTracker:
    """
    Tracks validator's participation in consensus based on state
    
    Simple logic:
    - If in 'proposing' state -> validator is validating (agreed=True)
    - If not proposing but should be -> missed validation (agreed=False)
    """
    
    def __init__(self, api: RippledAPI, db: Database, 
                 validator_pubkey: Optional[str] = None):
        """
        Initialize validation tracker
        
        Args:
            api: RippledAPI instance
            db: Database instance
            validator_pubkey: Your validator's public key (optional, will auto-detect)
        """
        self.api = api
        self.db = db
        self.validator_pubkey = validator_pubkey
        
        # Auto-detect validator public key if not provided
        if not self.validator_pubkey:
            self.validator_pubkey = self._get_validator_pubkey()
    
    def _get_validator_pubkey(self) -> Optional[str]:
        """
        Get validator public key from server_info
        
        Returns:
            Validator public key or None
        """
        try:
            info = self.api.get_server_info()
            pubkey = info.get('pubkey_validator')
            if pubkey:
                print(f"Auto-detected validator pubkey: {pubkey}")
            return pubkey
        except Exception as e:
            print(f"Warning: Could not auto-detect validator pubkey: {e}")
            return None
    
    def check_ledger_validation(self, ledger_seq: int, server_state: str,
                                peers: int, load_factor: float) -> Dict[str, Any]:
        """
        Check if validator validated a specific ledger (state-based)
        
        Args:
            ledger_seq: Ledger sequence number to check
            server_state: Current server state
            peers: Number of peers
            load_factor: Load factor
            
        Returns:
            Dictionary with validation info
        """
        import time
        
        # Determine validation based on state
        was_proposing = (server_state == 'proposing')
        
        # If we're on the UNL and proposing, we ARE validating
        should_validate = was_proposing
        did_validate = was_proposing
        agreed = was_proposing
        
        # Record the validation
        self.db.write_ledger_validation(
            timestamp=time.time(),
            ledger_seq=ledger_seq,
            server_state=server_state,
            was_proposing=was_proposing,
            should_validate=should_validate,
            did_validate=did_validate,
            agreed=agreed,
            peers=peers,
            load_factor=load_factor
        )
        
        return {
            'ledger_seq': ledger_seq,
            'was_proposing': was_proposing,
            'should_validate': should_validate,
            'did_validate': did_validate,
            'agreed': agreed
        }
