"""
Task Runner for Benchmark Tasks

Handles execution of benchmark tasks and collection of performance metrics.
"""

import os
import sys
import time
import json
import subprocess
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
import logging

# Add parent directory to path to import planner modules
sys.path.append(str(Path(__file__).parent.parent))

from benchmark_tasks.task_loader import BenchmarkTask, TaskLoader


@dataclass
class TaskResult:
    """Result of executing a benchmark task"""
    task_id: str
    success: bool
    execution_time_seconds: float
    total_actions: int
    successful_actions: int
    failed_actions: int
    error_message: Optional[str] = None
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    
    # Performance metrics
    element_targeting_accuracy: Optional[float] = None
    ui_graph_build_time: Optional[float] = None
    llm_planning_time: Optional[float] = None
    memory_usage_mb: Optional[int] = None
    retry_count: int = 0
    context_switch_count: int = 0
    
    # Benchmark analysis
    speed_vs_human_baseline: Optional[float] = None  # ratio: agent_time / human_time
    action_count_vs_baseline: Optional[float] = None  # ratio: agent_actions / human_actions
    success_criteria_scores: Dict[str, float] = field(default_factory=dict)
    
    @property
    def success_rate(self) -> float:
        """Calculate action success rate"""
        if self.total_actions == 0:
            return 0.0
        return self.successful_actions / self.total_actions
    
    @property
    def overall_score(self) -> float:
        """Calculate overall task performance score (0.0 to 1.0)"""
        if not self.success:
            return 0.0
        
        # Base score from success criteria
        base_score = sum(self.success_criteria_scores.values()) / len(self.success_criteria_scores) if self.success_criteria_scores else 0.5
        
        # Apply efficiency penalties/bonuses
        efficiency_multiplier = 1.0
        
        if self.speed_vs_human_baseline:
            # Penalty for being slower than human, bonus for being faster
            if self.speed_vs_human_baseline > 1.5:  # More than 50% slower
                efficiency_multiplier *= 0.8
            elif self.speed_vs_human_baseline < 0.8:  # 20% faster
                efficiency_multiplier *= 1.1
        
        if self.action_count_vs_baseline:
            # Penalty for using too many actions
            if self.action_count_vs_baseline > 1.3:  # 30% more actions
                efficiency_multiplier *= 0.9
        
        return min(1.0, base_score * efficiency_multiplier)


class TaskRunner:
    """Executes benchmark tasks and collects performance metrics"""
    
    def __init__(self, tasks_directory: Optional[Path] = None):
        """
        Initialize task runner
        
        Args:
            tasks_directory: Path to directory containing task definitions
        """
        self.task_loader = TaskLoader(tasks_directory)
        self.logger = logging.getLogger(__name__)
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
    
    def run_task(self, task: BenchmarkTask, timeout_override: Optional[int] = None) -> TaskResult:
        """
        Execute a single benchmark task
        
        Args:
            task: BenchmarkTask to execute
            timeout_override: Override the task's default timeout
            
        Returns:
            TaskResult with execution metrics
        """
        start_time = datetime.now()
        timeout = timeout_override or task.timeout_seconds
        
        self.logger.info(f"Starting task: {task.task_id} - {task.name}")
        
        try:
            # Execute the task using the existing planner
            result = self._execute_with_planner(task, timeout)
            
            end_time = datetime.now()
            execution_time = (end_time - start_time).total_seconds()
            
            # Calculate performance metrics
            result.start_time = start_time
            result.end_time = end_time
            result.execution_time_seconds = execution_time
            
            # Calculate baseline comparisons
            if task.human_baseline:
                result.speed_vs_human_baseline = execution_time / task.human_baseline.median_time_seconds
                result.action_count_vs_baseline = result.total_actions / task.human_baseline.median_action_count
            
            self.logger.info(f"Task completed: {task.task_id} - Success: {result.success}, Time: {execution_time:.2f}s")
            
            return result
            
        except Exception as e:
            end_time = datetime.now()
            execution_time = (end_time - start_time).total_seconds()
            
            self.logger.error(f"Task failed with exception: {task.task_id} - {str(e)}")
            
            return TaskResult(
                task_id=task.task_id,
                success=False,
                execution_time_seconds=execution_time,
                total_actions=0,
                successful_actions=0,
                failed_actions=1,
                error_message=str(e),
                start_time=start_time,
                end_time=end_time
            )
    
    def run_task_suite(self, tasks: List[BenchmarkTask]) -> List[TaskResult]:
        """
        Execute a suite of benchmark tasks
        
        Args:
            tasks: List of BenchmarkTask instances to execute
            
        Returns:
            List of TaskResult instances
        """
        results = []
        
        for i, task in enumerate(tasks, 1):
            self.logger.info(f"Running task {i}/{len(tasks)}: {task.name}")
            
            try:
                result = self.run_task(task)
                results.append(result)
                
                # Brief pause between tasks
                time.sleep(2)
                
            except KeyboardInterrupt:
                self.logger.info("Task suite interrupted by user")
                break
            except Exception as e:
                self.logger.error(f"Unexpected error running task {task.task_id}: {e}")
                # Create error result
                error_result = TaskResult(
                    task_id=task.task_id,
                    success=False,
                    execution_time_seconds=0,
                    total_actions=0,
                    successful_actions=0,
                    failed_actions=1,
                    error_message=str(e)
                )
                results.append(error_result)
                continue
        
        return results
    
    def _execute_with_planner(self, task: BenchmarkTask, timeout: int) -> TaskResult:
        """
        Execute task using the real Swift AgentlyRunner system
        
        Args:
            task: BenchmarkTask to execute
            timeout: Maximum execution time in seconds
            
        Returns:
            TaskResult with execution details
        """
        # Use the real Swift AgentlyRunner instead of fake planning-only execution
        project_root = Path(__file__).parent.parent
        
        try:
            # Build the Swift project first
            build_cmd = ["swift", "build"]
            build_process = subprocess.run(
                build_cmd,
                cwd=project_root,
                capture_output=True,
                text=True,
                timeout=60  # Build timeout
            )
            
            if build_process.returncode != 0:
                raise subprocess.CalledProcessError(build_process.returncode, build_cmd, build_process.stderr)
            
            # Execute the task using the real Swift AgentlyRunner
            cmd = [
                "swift", "run", "agently-runner",
                "--task", task.description,
                "--format", "json"
            ]
            
            # Add test data as environment variables if available
            env = os.environ.copy()
            if task.setup and task.setup.test_data:
                for key, value in task.setup.test_data.items():
                    env[f"AGENTLY_TEST_{key.upper()}"] = str(value)
            
            # Execute the real Swift AgentlyRunner
            process = subprocess.run(
                cmd,
                cwd=project_root,
                capture_output=True,
                text=True,
                timeout=timeout,
                env=env
            )
            
            # Parse the output to extract metrics from real execution
            return self._parse_agently_runner_output(task, process)
            
        except subprocess.TimeoutExpired:
            return TaskResult(
                task_id=task.task_id,
                success=False,
                execution_time_seconds=timeout,
                total_actions=0,
                successful_actions=0,
                failed_actions=1,
                error_message=f"Task timed out after {timeout} seconds"
            )
        except subprocess.CalledProcessError as e:
            return TaskResult(
                task_id=task.task_id,
                success=False,
                execution_time_seconds=0,
                total_actions=0,
                successful_actions=0,
                failed_actions=1,
                error_message=f"Planner execution failed: {e}"
            )
        except Exception as e:
            return TaskResult(
                task_id=task.task_id,
                success=False,
                execution_time_seconds=0,
                total_actions=0,
                successful_actions=0,
                failed_actions=1,
                error_message=f"Swift AgentlyRunner execution failed: {e}"
            )
    
    def _parse_agently_runner_output(self, task: BenchmarkTask, process: subprocess.CompletedProcess) -> TaskResult:
        """
        Parse Swift AgentlyRunner output and extract metrics from real execution
        
        Args:
            task: The executed task
            process: Completed subprocess result from Swift AgentlyRunner
            
        Returns:
            TaskResult with parsed metrics from real execution
        """
        # Basic success determination
        success = process.returncode == 0
        
        # Try to parse JSON output from AgentlyRunner
        total_actions = 0
        successful_actions = 0
        failed_actions = 0
        
        try:
            if success and process.stdout:
                # Parse the JSON output from Swift AgentlyRunner
                output_data = json.loads(process.stdout)
                total_actions = output_data.get('total_actions', 0)
                successful_actions = output_data.get('successful_actions', 0)
                failed_actions = total_actions - successful_actions
            else:
                # If no JSON output or failure, mark as failed
                failed_actions = 1 if not success else 0
        except json.JSONDecodeError:
            # If we can't parse JSON, fall back to basic success/failure
            total_actions = 1
            successful_actions = 1 if success else 0
            failed_actions = 0 if success else 1
        
        # Initialize result with real execution data
        result = TaskResult(
            task_id=task.task_id,
            success=success,
            execution_time_seconds=0.0,  # Will be set by caller
            total_actions=total_actions,
            successful_actions=successful_actions,
            failed_actions=failed_actions
        )
        
        # Extract any error messages
        if not success and process.stderr:
            result.error_message = process.stderr.strip()
        
        # Evaluate success criteria against real execution
        result.success_criteria_scores = self._evaluate_success_criteria(task, result)
        
        return result

    def _parse_planner_output(self, task: BenchmarkTask, process: subprocess.CompletedProcess) -> TaskResult:
        """
        Parse planner output and extract metrics
        
        Args:
            task: The executed task
            process: Completed subprocess result
            
        Returns:
            TaskResult with parsed metrics
        """
        # Basic success determination
        success = process.returncode == 0
        
        # Initialize result
        result = TaskResult(
            task_id=task.task_id,
            success=success,
            execution_time_seconds=0.0,  # Will be set by caller
            total_actions=0,
            successful_actions=0,
            failed_actions=0 if success else 1
        )
        
        # Try to find the latest run log directory to extract detailed metrics
        logs_dir = Path(__file__).parent.parent / "logs" / "runs"
        if logs_dir.exists():
            # Find the most recent run directory
            run_dirs = [d for d in logs_dir.iterdir() if d.is_dir()]
            if run_dirs:
                latest_run = max(run_dirs, key=lambda d: d.stat().st_mtime)
                result = self._extract_metrics_from_run_log(result, latest_run)
        
        # Extract any error messages
        if not success and process.stderr:
            result.error_message = process.stderr.strip()
        
        # Evaluate success criteria
        result.success_criteria_scores = self._evaluate_success_criteria(task, result)
        
        return result
    
    def _extract_metrics_from_run_log(self, result: TaskResult, run_dir: Path) -> TaskResult:
        """
        Extract detailed metrics from run log directory
        
        Args:
            result: TaskResult to populate
            run_dir: Path to run log directory
            
        Returns:
            Updated TaskResult
        """
        try:
            # Look for metadata file
            metadata_file = run_dir / "run_metadata.json"
            if metadata_file.exists():
                with open(metadata_file, 'r') as f:
                    metadata = json.load(f)
                    # Extract any available metrics from metadata
                    # This would need to be updated based on your actual log format
            
            # Look for action logs or other metric files
            # This is a placeholder - you'd implement based on your actual logging structure
            
        except Exception as e:
            self.logger.debug(f"Failed to extract metrics from run log: {e}")
        
        return result
    
    def _evaluate_success_criteria(self, task: BenchmarkTask, result: TaskResult) -> Dict[str, float]:
        """
        Evaluate task success criteria
        
        Args:
            task: The executed task
            result: TaskResult with execution details
            
        Returns:
            Dictionary mapping criterion type to score (0.0-1.0)
        """
        scores = {}
        
        for criterion in task.success_criteria:
            # Basic scoring based on overall success
            # This is a simplified implementation - you'd want more sophisticated validation
            if criterion.type == "application_running":
                scores[criterion.type] = 1.0 if result.success else 0.0
            elif criterion.type == "computation_completed":
                scores[criterion.type] = 1.0 if result.success else 0.0
            elif criterion.type == "message_sent":
                scores[criterion.type] = 1.0 if result.success else 0.0
            elif criterion.type == "page_loaded":
                scores[criterion.type] = 1.0 if result.success else 0.0
            elif criterion.type == "folder_exists":
                scores[criterion.type] = 1.0 if result.success else 0.0
            else:
                # Default scoring
                scores[criterion.type] = 1.0 if result.success else 0.0
        
        return scores
    
    def generate_report(self, results: List[TaskResult]) -> Dict[str, Any]:
        """
        Generate performance report from task results
        
        Args:
            results: List of TaskResult instances
            
        Returns:
            Dictionary containing performance analysis
        """
        if not results:
            return {"error": "No results to analyze"}
        
        total_tasks = len(results)
        successful_tasks = sum(1 for r in results if r.success)
        success_rate = successful_tasks / total_tasks
        
        # Calculate timing statistics
        execution_times = [r.execution_time_seconds for r in results if r.execution_time_seconds > 0]
        avg_execution_time = sum(execution_times) / len(execution_times) if execution_times else 0
        
        # Calculate baseline comparisons
        speed_ratios = [r.speed_vs_human_baseline for r in results if r.speed_vs_human_baseline]
        avg_speed_ratio = sum(speed_ratios) / len(speed_ratios) if speed_ratios else None
        
        action_ratios = [r.action_count_vs_baseline for r in results if r.action_count_vs_baseline]
        avg_action_ratio = sum(action_ratios) / len(action_ratios) if action_ratios else None
        
        # Group by category
        category_stats = {}
        for result in results:
            # You'd need to match result back to task for category info
            # This is simplified for now
            pass
        
        return {
            "summary": {
                "total_tasks": total_tasks,
                "successful_tasks": successful_tasks,
                "success_rate": success_rate,
                "average_execution_time": avg_execution_time,
                "average_speed_vs_human": avg_speed_ratio,
                "average_action_efficiency": avg_action_ratio
            },
            "failed_tasks": [
                {
                    "task_id": r.task_id,
                    "error": r.error_message,
                    "execution_time": r.execution_time_seconds
                }
                for r in results if not r.success
            ],
            "performance_details": [
                {
                    "task_id": r.task_id,
                    "success": r.success,
                    "execution_time": r.execution_time_seconds,
                    "overall_score": r.overall_score,
                    "speed_vs_human": r.speed_vs_human_baseline,
                    "action_efficiency": r.action_count_vs_baseline
                }
                for r in results
            ]
        }
