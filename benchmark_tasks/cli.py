#!/usr/bin/env python3
"""
Benchmark Tasks CLI

Command-line interface for running and managing benchmark tasks.
"""

import argparse
import json
import sys
from pathlib import Path
from typing import List, Optional

from benchmark_tasks.task_loader import TaskLoader, BenchmarkTask
from benchmark_tasks.task_runner import TaskRunner, TaskResult


def list_tasks(loader: TaskLoader, category: Optional[str] = None, complexity: Optional[str] = None):
    """List available tasks"""
    tasks = loader.load_all_tasks()
    
    if category:
        tasks = [t for t in tasks if t.category == category]
    
    if complexity:
        tasks = [t for t in tasks if t.complexity == complexity]
    
    print(f"\nFound {len(tasks)} tasks:")
    print("-" * 80)
    
    for task in sorted(tasks, key=lambda t: (t.category, t.complexity, t.task_id)):
        print(f"{task.task_id:30} | {task.category:15} | {task.complexity:10} | {task.name}")


def run_single_task(loader: TaskLoader, runner: TaskRunner, task_id: str):
    """Run a single task by ID"""
    try:
        # Find task by ID
        all_tasks = loader.load_all_tasks()
        task = next((t for t in all_tasks if t.task_id == task_id), None)
        
        if not task:
            print(f"Error: Task '{task_id}' not found")
            return False
        
        print(f"\nRunning task: {task.name}")
        print(f"Description: {task.description}")
        print(f"Category: {task.category}, Complexity: {task.complexity}")
        print(f"Expected time: {task.human_baseline.median_time_seconds}s")
        print("-" * 60)
        
        result = runner.run_task(task)
        
        print_task_result(result, task)
        
        return result.success
        
    except Exception as e:
        print(f"Error running task: {e}")
        return False


def run_task_suite(loader: TaskLoader, runner: TaskRunner, category: Optional[str] = None, complexity: Optional[str] = None):
    """Run a suite of tasks"""
    tasks = loader.load_all_tasks()
    
    if category:
        tasks = [t for t in tasks if t.category == category]
    
    if complexity:
        tasks = [t for t in tasks if t.complexity == complexity]
    
    if not tasks:
        print("No tasks found matching criteria")
        return
    
    print(f"\nRunning {len(tasks)} tasks...")
    print("=" * 80)
    
    results = runner.run_task_suite(tasks)
    
    # Print summary
    print("\n" + "=" * 80)
    print("BENCHMARK RESULTS SUMMARY")
    print("=" * 80)
    
    successful = sum(1 for r in results if r.success)
    print(f"Tasks completed: {len(results)}")
    print(f"Successful: {successful}")
    print(f"Failed: {len(results) - successful}")
    print(f"Success rate: {successful / len(results) * 100:.1f}%")
    
    # Print detailed results
    print("\nDetailed Results:")
    print("-" * 80)
    
    for i, result in enumerate(results, 1):
        task = tasks[i-1]  # Corresponding task
        print(f"\n{i}. {task.name}")
        print_task_result(result, task)


def print_task_result(result: TaskResult, task: BenchmarkTask):
    """Print formatted task result"""
    status = "✅ PASS" if result.success else "❌ FAIL"
    
    print(f"   Status: {status}")
    print(f"   Execution time: {result.execution_time_seconds:.2f}s")
    
    if result.speed_vs_human_baseline:
        speed_indicator = "🚀" if result.speed_vs_human_baseline < 1.0 else "🐌" if result.speed_vs_human_baseline > 1.5 else "⚡"
        print(f"   Speed vs human: {result.speed_vs_human_baseline:.2f}x {speed_indicator}")
    
    if result.action_count_vs_baseline:
        efficiency_indicator = "🎯" if result.action_count_vs_baseline <= 1.1 else "📈"
        print(f"   Action efficiency: {result.action_count_vs_baseline:.2f}x {efficiency_indicator}")
    
    if result.overall_score:
        score_indicator = "🏆" if result.overall_score > 0.9 else "🥉" if result.overall_score > 0.7 else "📉"
        print(f"   Overall score: {result.overall_score:.2f} {score_indicator}")
    
    if result.error_message:
        print(f"   Error: {result.error_message}")


def validate_tasks(loader: TaskLoader):
    """Validate all task definitions"""
    tasks_dir = loader.tasks_directory
    json_files = list(tasks_dir.rglob("*.json"))
    json_files = [f for f in json_files if f.name != "task_schema.json"]
    
    print(f"\nValidating {len(json_files)} task files...")
    print("-" * 60)
    
    valid_count = 0
    invalid_count = 0
    
    for task_file in json_files:
        try:
            task = loader.load_task(task_file)
            print(f"✅ {task_file.relative_to(tasks_dir)}: {task.name}")
            valid_count += 1
        except Exception as e:
            print(f"❌ {task_file.relative_to(tasks_dir)}: {str(e)}")
            invalid_count += 1
    
    print(f"\nValidation complete: {valid_count} valid, {invalid_count} invalid")
    return invalid_count == 0


def main():
    """Main CLI entry point"""
    parser = argparse.ArgumentParser(description="Benchmark Tasks CLI")
    
    # Global options
    parser.add_argument("--tasks-dir", type=Path, help="Path to tasks directory")
    
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # List command
    list_parser = subparsers.add_parser("list", help="List available tasks")
    list_parser.add_argument("--category", help="Filter by category")
    list_parser.add_argument("--complexity", help="Filter by complexity")
    
    # Run command
    run_parser = subparsers.add_parser("run", help="Run benchmark tasks")
    run_parser.add_argument("--task", help="Run specific task by ID")
    run_parser.add_argument("--category", help="Run all tasks in category")
    run_parser.add_argument("--complexity", help="Run all tasks with complexity level")
    run_parser.add_argument("--all", action="store_true", help="Run all tasks")
    
    # Validate command
    validate_parser = subparsers.add_parser("validate", help="Validate task definitions")
    
    # Info command
    info_parser = subparsers.add_parser("info", help="Show task information")
    info_parser.add_argument("task_id", help="Task ID to show info for")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    # Initialize loader and runner
    try:
        loader = TaskLoader(args.tasks_dir)
        runner = TaskRunner(args.tasks_dir)
    except Exception as e:
        print(f"Error initializing: {e}")
        return
    
    # Execute command
    try:
        if args.command == "list":
            list_tasks(loader, args.category, args.complexity)
        
        elif args.command == "run":
            if args.task:
                success = run_single_task(loader, runner, args.task)
                sys.exit(0 if success else 1)
            elif args.category or args.complexity or args.all:
                run_task_suite(loader, runner, args.category, args.complexity)
            else:
                print("Error: Must specify --task, --category, --complexity, or --all")
        
        elif args.command == "validate":
            success = validate_tasks(loader)
            sys.exit(0 if success else 1)
        
        elif args.command == "info":
            all_tasks = loader.load_all_tasks()
            task = next((t for t in all_tasks if t.task_id == args.task_id), None)
            if task:
                print(f"\nTask: {task.name}")
                print(f"ID: {task.task_id}")
                print(f"Category: {task.category}")
                print(f"Complexity: {task.complexity}")
                print(f"Description: {task.description}")
                print(f"Tags: {', '.join(task.tags)}")
                print(f"Timeout: {task.timeout_seconds}s")
                print(f"Human baseline: {task.human_baseline.median_time_seconds}s, {task.human_baseline.median_action_count} actions, {task.human_baseline.success_rate:.0%} success")
                
                if task.task_steps:
                    print(f"\nTask Steps ({len(task.task_steps)}):")
                    for i, step in enumerate(task.task_steps, 1):
                        print(f"  {i}. {step.description}")
                
                print(f"\nSuccess Criteria:")
                for criterion in task.success_criteria:
                    print(f"  - {criterion.description} (weight: {criterion.weight})")
            else:
                print(f"Task '{args.task_id}' not found")
    
    except KeyboardInterrupt:
        print("\nInterrupted by user")
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
