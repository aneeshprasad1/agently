"""
Task Loader for Benchmark Tasks

Handles loading, validation, and management of benchmark task definitions.
"""

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Any, Union
import jsonschema
from jsonschema import validate, ValidationError


@dataclass
class TaskSetup:
    """Task setup configuration"""
    required_apps: List[str] = field(default_factory=list)
    preconditions: List[str] = field(default_factory=list)
    cleanup: List[str] = field(default_factory=list)
    test_data: Dict[str, Any] = field(default_factory=dict)


@dataclass
class TaskStep:
    """Individual task execution step"""
    description: str
    expected_actions: List[str]
    success_indicators: List[str] = field(default_factory=list)


@dataclass
class SuccessCriterion:
    """Criterion for determining task success"""
    type: str
    weight: float
    description: str
    expected_value: Optional[str] = None
    app_name: Optional[str] = None
    element_role: Optional[str] = None


@dataclass
class RetryPolicy:
    """Retry policy configuration"""
    max_retries: int = 0
    retry_delay_seconds: int = 0


@dataclass
class HumanBaseline:
    """Human performance baseline"""
    median_time_seconds: float
    median_action_count: int
    success_rate: float
    notes: Optional[str] = None


@dataclass
class ValidationCheck:
    """Post-execution validation check"""
    type: str
    app_name: Optional[str] = None
    expected_value: Optional[str] = None
    path: Optional[str] = None


@dataclass
class TaskValidation:
    """Task validation configuration"""
    post_execution_checks: List[ValidationCheck] = field(default_factory=list)


@dataclass
class BenchmarkTask:
    """Complete benchmark task definition"""
    task_id: str
    name: str
    description: str
    category: str
    complexity: str
    success_criteria: List[SuccessCriterion]
    timeout_seconds: int
    human_baseline: HumanBaseline
    tags: List[str] = field(default_factory=list)
    setup: Optional[TaskSetup] = None
    task_steps: List[TaskStep] = field(default_factory=list)
    failure_modes: List[str] = field(default_factory=list)
    retry_policy: Optional[RetryPolicy] = None
    validation: Optional[TaskValidation] = None
    
    @property
    def file_path(self) -> Optional[str]:
        """Path to the task definition file"""
        return getattr(self, '_file_path', None)
    
    def get_test_data(self, key: str, default: Any = None) -> Any:
        """Get test data value by key"""
        if self.setup and self.setup.test_data:
            return self.setup.test_data.get(key, default)
        return default
    
    def get_expected_result(self) -> Optional[str]:
        """Get expected result from test data"""
        return self.get_test_data('expected_result')
    
    def is_complex(self) -> bool:
        """Check if task is considered complex"""
        return self.complexity in ['high', 'very_high']


class TaskLoader:
    """Loads and validates benchmark task definitions"""
    
    def __init__(self, tasks_directory: Union[str, Path] = None):
        """
        Initialize task loader
        
        Args:
            tasks_directory: Path to directory containing task definitions
        """
        if tasks_directory is None:
            # Default to benchmark_tasks directory relative to this file
            tasks_directory = Path(__file__).parent
        
        self.tasks_directory = Path(tasks_directory)
        self.schema = self._load_schema()
        self._task_cache: Dict[str, BenchmarkTask] = {}
    
    def _load_schema(self) -> Dict[str, Any]:
        """Load the task definition JSON schema"""
        schema_path = self.tasks_directory / 'task_schema.json'
        try:
            with open(schema_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            raise FileNotFoundError(f"Task schema not found at {schema_path}")
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in task schema: {e}")
    
    def load_task(self, task_file: Union[str, Path]) -> BenchmarkTask:
        """
        Load a single task definition from file
        
        Args:
            task_file: Path to task definition JSON file
            
        Returns:
            BenchmarkTask instance
            
        Raises:
            FileNotFoundError: If task file doesn't exist
            ValidationError: If task definition is invalid
            ValueError: If JSON is malformed
        """
        task_path = Path(task_file)
        if not task_path.is_absolute():
            task_path = self.tasks_directory / task_path
        
        # Check cache first
        cache_key = str(task_path)
        if cache_key in self._task_cache:
            return self._task_cache[cache_key]
        
        try:
            with open(task_path, 'r') as f:
                task_data = json.load(f)
        except FileNotFoundError:
            raise FileNotFoundError(f"Task file not found: {task_path}")
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in task file {task_path}: {e}")
        
        # Validate against schema
        try:
            validate(instance=task_data, schema=self.schema)
        except ValidationError as e:
            raise ValidationError(f"Task validation failed for {task_path}: {e.message}")
        
        # Convert to BenchmarkTask object
        task = self._dict_to_task(task_data)
        task._file_path = str(task_path)
        
        # Cache the task
        self._task_cache[cache_key] = task
        
        return task
    
    def load_all_tasks(self) -> List[BenchmarkTask]:
        """
        Load all task definitions from the tasks directory
        
        Returns:
            List of BenchmarkTask instances
        """
        tasks = []
        
        # Recursively find all .json files (except schema)
        for json_file in self.tasks_directory.rglob('*.json'):
            if json_file.name == 'task_schema.json':
                continue
                
            try:
                task = self.load_task(json_file)
                tasks.append(task)
            except (ValidationError, ValueError, FileNotFoundError) as e:
                print(f"Warning: Failed to load task from {json_file}: {e}")
                continue
        
        return tasks
    
    def get_tasks_by_category(self, category: str) -> List[BenchmarkTask]:
        """Get all tasks in a specific category"""
        all_tasks = self.load_all_tasks()
        return [task for task in all_tasks if task.category == category]
    
    def get_tasks_by_complexity(self, complexity: str) -> List[BenchmarkTask]:
        """Get all tasks with specific complexity level"""
        all_tasks = self.load_all_tasks()
        return [task for task in all_tasks if task.complexity == complexity]
    
    def get_tasks_by_tag(self, tag: str) -> List[BenchmarkTask]:
        """Get all tasks with a specific tag"""
        all_tasks = self.load_all_tasks()
        return [task for task in all_tasks if tag in task.tags]
    
    def _dict_to_task(self, task_data: Dict[str, Any]) -> BenchmarkTask:
        """Convert dictionary to BenchmarkTask object"""
        
        # Parse setup
        setup = None
        if 'setup' in task_data:
            setup_data = task_data['setup']
            setup = TaskSetup(
                required_apps=setup_data.get('required_apps', []),
                preconditions=setup_data.get('preconditions', []),
                cleanup=setup_data.get('cleanup', []),
                test_data=setup_data.get('test_data', {})
            )
        
        # Parse task steps
        task_steps = []
        if 'task_steps' in task_data:
            for step_data in task_data['task_steps']:
                step = TaskStep(
                    description=step_data['description'],
                    expected_actions=step_data['expected_actions'],
                    success_indicators=step_data.get('success_indicators', [])
                )
                task_steps.append(step)
        
        # Parse success criteria
        success_criteria = []
        for criterion_data in task_data['success_criteria']:
            criterion = SuccessCriterion(
                type=criterion_data['type'],
                weight=criterion_data['weight'],
                description=criterion_data['description'],
                expected_value=criterion_data.get('expected_value'),
                app_name=criterion_data.get('app_name'),
                element_role=criterion_data.get('element_role')
            )
            success_criteria.append(criterion)
        
        # Parse retry policy
        retry_policy = None
        if 'retry_policy' in task_data:
            retry_data = task_data['retry_policy']
            retry_policy = RetryPolicy(
                max_retries=retry_data.get('max_retries', 0),
                retry_delay_seconds=retry_data.get('retry_delay_seconds', 0)
            )
        
        # Parse human baseline
        baseline_data = task_data['human_baseline']
        human_baseline = HumanBaseline(
            median_time_seconds=baseline_data['median_time_seconds'],
            median_action_count=baseline_data['median_action_count'],
            success_rate=baseline_data['success_rate'],
            notes=baseline_data.get('notes')
        )
        
        # Parse validation
        validation = None
        if 'validation' in task_data:
            val_data = task_data['validation']
            checks = []
            for check_data in val_data.get('post_execution_checks', []):
                check = ValidationCheck(
                    type=check_data['type'],
                    app_name=check_data.get('app_name'),
                    expected_value=check_data.get('expected_value'),
                    path=check_data.get('path')
                )
                checks.append(check)
            validation = TaskValidation(post_execution_checks=checks)
        
        return BenchmarkTask(
            task_id=task_data['task_id'],
            name=task_data['name'],
            description=task_data['description'],
            category=task_data['category'],
            complexity=task_data['complexity'],
            success_criteria=success_criteria,
            timeout_seconds=task_data['timeout_seconds'],
            human_baseline=human_baseline,
            tags=task_data.get('tags', []),
            setup=setup,
            task_steps=task_steps,
            failure_modes=task_data.get('failure_modes', []),
            retry_policy=retry_policy,
            validation=validation
        )
    
    def validate_task_file(self, task_file: Union[str, Path]) -> bool:
        """
        Validate a task file without loading it into memory
        
        Args:
            task_file: Path to task definition JSON file
            
        Returns:
            True if valid, False otherwise
        """
        try:
            self.load_task(task_file)
            return True
        except (ValidationError, ValueError, FileNotFoundError):
            return False
    
    def clear_cache(self):
        """Clear the task cache"""
        self._task_cache.clear()
