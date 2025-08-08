"""
SQLite-based episodic memory for Agently.
"""

import json
import sqlite3
import logging
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

logger = logging.getLogger(__name__)


@dataclass
class UISnapshot:
    """Represents a UI state snapshot."""
    
    timestamp: datetime
    ui_graph: Dict[str, Any]
    active_application: Optional[str]
    element_count: int
    checksum: str  # Hash of the UI state for deduplication
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            **asdict(self),
            'timestamp': self.timestamp.isoformat(),
            'ui_graph': json.dumps(self.ui_graph)
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'UISnapshot':
        """Create from dictionary."""
        return cls(
            timestamp=datetime.fromisoformat(data['timestamp']),
            ui_graph=json.loads(data['ui_graph']),
            active_application=data['active_application'],
            element_count=data['element_count'],
            checksum=data['checksum']
        )


@dataclass
class ExecutionRecord:
    """Records an action execution and its results."""
    
    timestamp: datetime
    task_description: str
    ui_snapshot_id: int
    action_plan: List[Dict[str, Any]]
    executed_actions: List[Dict[str, Any]]
    success_rate: float
    total_execution_time: float
    error_messages: List[str]
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            **asdict(self),
            'timestamp': self.timestamp.isoformat(),
            'action_plan': json.dumps(self.action_plan),
            'executed_actions': json.dumps(self.executed_actions),
            'error_messages': json.dumps(self.error_messages)
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'ExecutionRecord':
        """Create from dictionary."""
        return cls(
            timestamp=datetime.fromisoformat(data['timestamp']),
            task_description=data['task_description'],
            ui_snapshot_id=data['ui_snapshot_id'],
            action_plan=json.loads(data['action_plan']),
            executed_actions=json.loads(data['executed_actions']),
            success_rate=data['success_rate'],
            total_execution_time=data['total_execution_time'],
            error_messages=json.loads(data['error_messages'])
        )


class MemoryStore:
    """SQLite-based memory store for Agently."""
    
    def __init__(self, db_path: Optional[str] = None):
        """Initialize memory store."""
        if db_path is None:
            # Default to user's cache directory
            cache_dir = Path.home() / ".cache" / "agently"
            cache_dir.mkdir(parents=True, exist_ok=True)
            db_path = str(cache_dir / "memory.db")
        
        self.db_path = db_path
        self._init_database()
        logger.info(f"Initialized memory store at {db_path}")
    
    def _init_database(self):
        """Initialize database schema."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS ui_snapshots (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    ui_graph TEXT NOT NULL,
                    active_application TEXT,
                    element_count INTEGER NOT NULL,
                    checksum TEXT NOT NULL UNIQUE,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            conn.execute("""
                CREATE TABLE IF NOT EXISTS execution_records (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    task_description TEXT NOT NULL,
                    ui_snapshot_id INTEGER NOT NULL,
                    action_plan TEXT NOT NULL,
                    executed_actions TEXT NOT NULL,
                    success_rate REAL NOT NULL,
                    total_execution_time REAL NOT NULL,
                    error_messages TEXT NOT NULL,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (ui_snapshot_id) REFERENCES ui_snapshots (id)
                )
            """)
            
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_snapshots_checksum 
                ON ui_snapshots (checksum)
            """)
            
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_snapshots_timestamp 
                ON ui_snapshots (timestamp)
            """)
            
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_execution_task 
                ON execution_records (task_description)
            """)
            
            conn.commit()
    
    def store_ui_snapshot(self, snapshot: UISnapshot) -> int:
        """Store a UI snapshot, return the ID."""
        with sqlite3.connect(self.db_path) as conn:
            try:
                cursor = conn.execute("""
                    INSERT INTO ui_snapshots 
                    (timestamp, ui_graph, active_application, element_count, checksum)
                    VALUES (?, ?, ?, ?, ?)
                """, (
                    snapshot.timestamp.isoformat(),
                    json.dumps(snapshot.ui_graph),
                    snapshot.active_application,
                    snapshot.element_count,
                    snapshot.checksum
                ))
                
                snapshot_id = cursor.lastrowid
                conn.commit()
                logger.debug(f"Stored UI snapshot with ID {snapshot_id}")
                return snapshot_id
                
            except sqlite3.IntegrityError:
                # Snapshot with this checksum already exists
                cursor = conn.execute(
                    "SELECT id FROM ui_snapshots WHERE checksum = ?",
                    (snapshot.checksum,)
                )
                result = cursor.fetchone()
                if result:
                    logger.debug(f"UI snapshot already exists with ID {result[0]}")
                    return result[0]
                else:
                    raise
    
    def store_execution_record(self, record: ExecutionRecord) -> int:
        """Store an execution record, return the ID."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute("""
                INSERT INTO execution_records 
                (timestamp, task_description, ui_snapshot_id, action_plan, 
                 executed_actions, success_rate, total_execution_time, error_messages)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                record.timestamp.isoformat(),
                record.task_description,
                record.ui_snapshot_id,
                json.dumps(record.action_plan),
                json.dumps(record.executed_actions),
                record.success_rate,
                record.total_execution_time,
                json.dumps(record.error_messages)
            ))
            
            record_id = cursor.lastrowid
            conn.commit()
            logger.debug(f"Stored execution record with ID {record_id}")
            return record_id
    
    def get_similar_executions(
        self, 
        task_description: str, 
        limit: int = 5
    ) -> List[ExecutionRecord]:
        """Get execution records for similar tasks."""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            
            # Simple text matching - could be enhanced with semantic similarity
            cursor = conn.execute("""
                SELECT * FROM execution_records 
                WHERE task_description LIKE ? 
                ORDER BY success_rate DESC, timestamp DESC
                LIMIT ?
            """, (f"%{task_description}%", limit))
            
            records = []
            for row in cursor.fetchall():
                record_data = dict(row)
                records.append(ExecutionRecord.from_dict(record_data))
            
            return records
    
    def get_successful_plans_for_task(self, task_description: str) -> List[Dict[str, Any]]:
        """Get successful action plans for a similar task."""
        records = self.get_similar_executions(task_description)
        
        successful_plans = []
        for record in records:
            if record.success_rate > 0.8:  # 80% success threshold
                successful_plans.append(record.action_plan)
        
        return successful_plans
    
    def get_ui_snapshot(self, snapshot_id: int) -> Optional[UISnapshot]:
        """Get a UI snapshot by ID."""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute(
                "SELECT * FROM ui_snapshots WHERE id = ?",
                (snapshot_id,)
            )
            
            row = cursor.fetchone()
            if row:
                snapshot_data = dict(row)
                return UISnapshot.from_dict(snapshot_data)
            
            return None
    
    def get_stats(self) -> Dict[str, Any]:
        """Get memory store statistics."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute("SELECT COUNT(*) FROM ui_snapshots")
            snapshot_count = cursor.fetchone()[0]
            
            cursor = conn.execute("SELECT COUNT(*) FROM execution_records")
            execution_count = cursor.fetchone()[0]
            
            cursor = conn.execute("""
                SELECT AVG(success_rate) FROM execution_records 
                WHERE timestamp > datetime('now', '-7 days')
            """)
            recent_success_rate = cursor.fetchone()[0] or 0.0
            
            cursor = conn.execute("""
                SELECT COUNT(DISTINCT task_description) FROM execution_records
            """)
            unique_tasks = cursor.fetchone()[0]
            
            return {
                "total_ui_snapshots": snapshot_count,
                "total_executions": execution_count,
                "unique_tasks": unique_tasks,
                "recent_success_rate": recent_success_rate,
                "db_path": self.db_path
            }
    
    def cleanup_old_records(self, days_to_keep: int = 30):
        """Clean up old records to manage database size."""
        with sqlite3.connect(self.db_path) as conn:
            # Delete old execution records
            cursor = conn.execute("""
                DELETE FROM execution_records 
                WHERE timestamp < datetime('now', '-{} days')
            """.format(days_to_keep))
            
            deleted_executions = cursor.rowcount
            
            # Delete orphaned UI snapshots
            cursor = conn.execute("""
                DELETE FROM ui_snapshots 
                WHERE id NOT IN (
                    SELECT DISTINCT ui_snapshot_id FROM execution_records
                ) AND timestamp < datetime('now', '-{} days')
            """.format(days_to_keep))
            
            deleted_snapshots = cursor.rowcount
            conn.commit()
            
            logger.info(f"Cleaned up {deleted_executions} execution records and {deleted_snapshots} UI snapshots")
            
            # Vacuum database to reclaim space
            conn.execute("VACUUM")
            
            return {
                "deleted_executions": deleted_executions,
                "deleted_snapshots": deleted_snapshots
            }
