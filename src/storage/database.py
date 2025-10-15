import time
#!/usr/bin/env python3
"""
Database module for XRPL Monitor
Simple SQLite database for storing validator metrics
"""

import sqlite3
import os
from typing import Dict, Any, Optional, List, Tuple
from contextlib import contextmanager


class Database:
    """
    Simple SQLite database wrapper
    """
    
    def __init__(self, db_path: str):
        """
        Initialize database
        
        Args:
            db_path: Path to SQLite database file
        """
        self.db_path = db_path
        
        # Ensure directory exists
        db_dir = os.path.dirname(db_path)
        if db_dir and not os.path.exists(db_dir):
            os.makedirs(db_dir)
        
        # Initialize database
        self._init_db()
    
    @contextmanager
    def get_connection(self):
        """
        Context manager for database connections
        """
        conn = sqlite3.connect(self.db_path)
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()
    
    def _init_db(self):
        """
        Initialize database schema
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            
            # Simple metrics table - just the basics for now
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS validator_metrics (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    server_state TEXT NOT NULL,
                    ledger_seq INTEGER NOT NULL,
                    peers INTEGER,
                    load_factor REAL
                )
            ''')
            
            # Index for fast time-based queries
            cursor.execute('''
                CREATE INDEX IF NOT EXISTS idx_timestamp 
                ON validator_metrics(timestamp)
            ''')
            
            # Index for ledger sequence queries
            cursor.execute('''
                CREATE INDEX IF NOT EXISTS idx_ledger_seq 
                ON validator_metrics(ledger_seq)
            ''')
            
            # State transitions table - tracks every state change
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS state_transitions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    old_state TEXT NOT NULL,
                    new_state TEXT NOT NULL,
                    duration_in_old_state REAL,
                    ledger_seq INTEGER,
                    peers INTEGER,
                    load_factor REAL
                )
            ''')
            
            # Index for time-based queries
            cursor.execute('''
                CREATE INDEX IF NOT EXISTS idx_transitions_timestamp 
                ON state_transitions(timestamp)
            ''')
            
            # Index for finding specific state changes
            cursor.execute('''
                CREATE INDEX IF NOT EXISTS idx_transitions_states 
                ON state_transitions(old_state, new_state)
            ''')
            
            # Validation tracking table - tracks ledger-by-ledger validation
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS ledger_validations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp REAL NOT NULL,
                    ledger_seq INTEGER NOT NULL UNIQUE,
                    server_state TEXT NOT NULL,
                    was_proposing BOOLEAN NOT NULL,
                    should_validate BOOLEAN NOT NULL,
                    did_validate BOOLEAN,
                    agreed BOOLEAN,
                    peers INTEGER,
                    load_factor REAL
                )
            ''')
            
            # Indexes for validation queries
            cursor.execute('''
                CREATE INDEX IF NOT EXISTS idx_validations_timestamp 
                ON ledger_validations(timestamp)
            ''')
            
            cursor.execute('''
                CREATE INDEX IF NOT EXISTS idx_validations_ledger 
                ON ledger_validations(ledger_seq)
            ''')
            
            cursor.execute('''
                CREATE INDEX IF NOT EXISTS idx_validations_should 
                ON ledger_validations(should_validate, did_validate)
            ''')
    
    def write_metrics(self, timestamp: float, server_state: str, 
                     ledger_seq: int, peers: int, load_factor: float):
        """
        Write validator metrics to database
        
        Args:
            timestamp: Unix timestamp
            server_state: Server state (proposing, full, etc.)
            ledger_seq: Ledger sequence number
            peers: Number of peers
            load_factor: Load factor
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute('''
                INSERT INTO validator_metrics 
                (timestamp, server_state, ledger_seq, peers, load_factor)
                VALUES (?, ?, ?, ?, ?)
            ''', (timestamp, server_state, ledger_seq, peers, load_factor))
    
    def get_latest_metrics(self, limit: int = 10):
        """
        Get latest metrics from database
        
        Args:
            limit: Number of records to retrieve
            
        Returns:
            List of tuples (timestamp, state, ledger_seq, peers, load_factor)
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute('''
                SELECT timestamp, server_state, ledger_seq, peers, load_factor
                FROM validator_metrics
                ORDER BY timestamp DESC
                LIMIT ?
            ''', (limit,))
            return cursor.fetchall()
    
    def get_record_count(self) -> int:
        """
        Get total number of records in database
        
        Returns:
            Number of records
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute('SELECT COUNT(*) FROM validator_metrics')
            return cursor.fetchone()[0]
    
    def write_state_transition(self, timestamp: float, old_state: str, 
                              new_state: str, duration: float,
                              ledger_seq: int, peers: int, load_factor: float):
        """
        Write state transition to database
        
        Args:
            timestamp: Unix timestamp of transition
            old_state: Previous state
            new_state: New state
            duration: Time spent in old state (seconds)
            ledger_seq: Current ledger sequence
            peers: Number of peers
            load_factor: Load factor
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute('''
                INSERT INTO state_transitions 
                (timestamp, old_state, new_state, duration_in_old_state, 
                 ledger_seq, peers, load_factor)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (timestamp, old_state, new_state, duration, 
                  ledger_seq, peers, load_factor))
    
    def get_latest_transitions(self, limit: int = 10):
        """
        Get latest state transitions
        
        Args:
            limit: Number of transitions to retrieve
            
        Returns:
            List of tuples (timestamp, old_state, new_state, duration)
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute('''
                SELECT timestamp, old_state, new_state, duration_in_old_state
                FROM state_transitions
                ORDER BY timestamp DESC
                LIMIT ?
            ''', (limit,))
            return cursor.fetchall()
    
    def write_ledger_validation(self, timestamp: float, ledger_seq: int,
                                server_state: str, was_proposing: bool,
                                should_validate: bool, did_validate: Optional[bool],
                                agreed: Optional[bool], peers: int, load_factor: float):
        """
        Write ledger validation record
        
        Args:
            timestamp: Unix timestamp
            ledger_seq: Ledger sequence number
            server_state: Current server state
            was_proposing: Was validator in proposing state
            should_validate: Should validator have validated this ledger
            did_validate: Did validator actually validate (None if unknown)
            agreed: Did validation agree with network (None if didn't validate)
            peers: Number of peers
            load_factor: Load factor
        """
        with self.get_connection() as conn:
            cursor = conn.cursor()
            # Use INSERT OR REPLACE to handle duplicate ledger sequences
            cursor.execute('''
                INSERT OR REPLACE INTO ledger_validations
                (timestamp, ledger_seq, server_state, was_proposing,
                 should_validate, did_validate, agreed, peers, load_factor)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (timestamp, ledger_seq, server_state, was_proposing,
                  should_validate, did_validate, agreed, peers, load_factor))
    
    def get_validation_stats(self, hours: int = 24) -> Dict[str, Any]:
        """
        Get validation statistics for the last N hours
        
        Args:
            hours: Number of hours to look back
            
        Returns:
            Dictionary with validation statistics
        """
        import time
        cutoff = time.time() - (hours * 3600)
        
        with self.get_connection() as conn:
            cursor = conn.cursor()
            
            # Get counts
            cursor.execute('''
                SELECT 
                    COUNT(*) as total_ledgers,
                    SUM(CASE WHEN should_validate THEN 1 ELSE 0 END) as expected,
                    SUM(CASE WHEN did_validate THEN 1 ELSE 0 END) as validated,
                    SUM(CASE WHEN agreed THEN 1 ELSE 0 END) as agreed,
                    SUM(CASE WHEN should_validate AND NOT did_validate THEN 1 ELSE 0 END) as missed,
                    SUM(CASE WHEN did_validate AND NOT agreed THEN 1 ELSE 0 END) as disagreed
                FROM ledger_validations
                WHERE timestamp >= ?
            ''', (cutoff,))
            
            row = cursor.fetchone()
            
            total = row[0] or 0
            expected = row[1] or 0
            validated = row[2] or 0
            agreed = row[3] or 0
            missed = row[4] or 0
            disagreed = row[5] or 0
            
            # Calculate rates
            agreement_rate = (agreed / validated * 100) if validated > 0 else 0
            validation_rate = (validated / expected * 100) if expected > 0 else 0
            
            return {
                'total_ledgers': total,
                'expected_validations': expected,
                'actual_validations': validated,
                'agreements': agreed,
                'disagreements': disagreed,
                'missed': missed,
                'agreement_rate': agreement_rate,
                'validation_rate': validation_rate
            }



    def get_validation_stats_period(self, hours: int = 1):
        """
        Get validation statistics for a specific time period
        
        Args:
            hours: Number of hours to look back
            
        Returns:
            Dictionary with validation statistics
        """
        cutoff = time.time() - (hours * 3600)
        
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT 
                    COUNT(*) as total_checked,
                    SUM(CASE WHEN did_validate = 1 AND agreed = 1 THEN 1 ELSE 0 END) as validated_count,
                    SUM(CASE WHEN should_validate = 1 AND did_validate = 0 THEN 1 ELSE 0 END) as missed_count
                FROM ledger_validations
                WHERE timestamp >= ?
            """, (cutoff,))
            
            row = cursor.fetchone()
            
            if row and row[0] > 0:
                total = row[0]
                validated = row[1] or 0
                missed = row[2] or 0
                agreement_rate = (validated / total * 100) if total > 0 else 0
                
                return {
                    'total_checked': total,
                    'validated_count': validated,
                    'missed_count': missed,
                    'agreement_rate': agreement_rate,
                    'hours': hours
                }
            
            return {
                'total_checked': 0,
                'validated_count': 0,
                'missed_count': 0,
                'agreement_rate': 0,
                'hours': hours
            }
