#!/usr/bin/env python3
"""
Main entry point for the Agently planner.
Can be called from Swift or run standalone for testing.
"""

import argparse
import json
import logging
import os
import sys
from pathlib import Path

from .planner import AgentlyPlanner, PlanningContext


def setup_logging(verbose: bool = False):
    """Setup logging configuration."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )


def load_ui_graph(graph_path: str) -> dict:
    """Load UI graph from JSON file."""
    with open(graph_path, 'r') as f:
        return json.load(f)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Agently Planner')
    parser.add_argument('--task', required=True, help='Task description')
    parser.add_argument('--graph', required=True, help='Path to UI graph JSON file')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose logging')
    parser.add_argument('--recovery', action='store_true', help='Recovery planning mode')
    parser.add_argument('--failed-action', help='Failed action data (JSON, deprecated)')
    parser.add_argument('--failed-action-file', help='Path to JSON file containing the failed action')
    parser.add_argument('--error-message', help='Error message from failed action')
    parser.add_argument('--completed-actions', help='Completed actions data (JSON, deprecated)')
    parser.add_argument('--completed-actions-file', help='Path to JSON file containing completed actions')
    parser.add_argument('--log-dir', help='Directory to save LLM conversation logs')
    parser.add_argument('--enable-llm-logging', action='store_true', help='Enable detailed LLM conversation logging (may slow down execution)')
    
    args = parser.parse_args()
    
    setup_logging(args.verbose)
    logger = logging.getLogger(__name__)
    
    try:
        # Load UI graph
        ui_graph = load_ui_graph(args.graph)
        
        # Initialize planner
        api_key = os.getenv('OPENAI_API_KEY')
        if not api_key:
            logger.warning("OPENAI_API_KEY not set, planner may fail")
        
        planner = AgentlyPlanner(
            api_key=api_key, 
            log_dir=args.log_dir if args.enable_llm_logging else None
        )
        
        # Create planning context
        context = PlanningContext(
            task=args.task,
            ui_graph=ui_graph,
            active_application=ui_graph.get('activeApplication')
        )
        
        if args.recovery:
            # Recovery planning mode
            error_context = {}
            
            # Handle failed action (file takes precedence over direct argument)
            if args.failed_action_file:
                with open(args.failed_action_file, 'r') as f:
                    error_context['failed_action'] = json.load(f)
            elif args.failed_action:
                error_context['failed_action'] = json.loads(args.failed_action)
            
            if args.error_message:
                error_context['error_message'] = args.error_message
            
            # Handle completed actions (file takes precedence over direct argument)
            if args.completed_actions_file:
                with open(args.completed_actions_file, 'r') as f:
                    context.previous_actions = json.load(f)
            elif args.completed_actions:
                context.previous_actions = json.loads(args.completed_actions)
            
            context.error_context = error_context
            plan = planner.recover_from_error(context)
        else:
            # Normal planning mode
            plan = planner.generate_plan(context)
        
        # Output plan as JSON
        result = {
            'reasoning': plan.reasoning,
            'actions': plan.actions,
            'confidence': plan.confidence,
            'metadata': plan.metadata or {}
        }
        
        print(json.dumps(result, indent=2))
        
    except Exception as e:
        logger.error(f"Planning failed: {e}")
        # Output error in expected format
        error_result = {
            'reasoning': f"Planning failed: {str(e)}",
            'actions': [],
            'confidence': 0.0,
            'metadata': {'error': str(e)}
        }
        print(json.dumps(error_result, indent=2))
        sys.exit(1)


if __name__ == '__main__':
    main()
