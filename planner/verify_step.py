#!/usr/bin/env python3
"""
Standalone step verification script for Agently.
Called from Swift to verify individual steps.
"""

import argparse
import json
import logging
import os
import sys
from pathlib import Path

# Add the planner directory to the path
sys.path.insert(0, str(Path(__file__).parent))

from verifier import StepVerifier


def setup_logging(verbose: bool = False):
    """Setup logging configuration."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        stream=sys.stderr  # Log to stderr so stdout only contains JSON
    )


def main():
    """Main entry point for step verification."""
    parser = argparse.ArgumentParser(description='Agently Step Verifier')
    parser.add_argument('--step-description', help='Description of what the step should accomplish')
    parser.add_argument('--step-description-file', help='Path to file containing step description')
    parser.add_argument('--action-type', help='Type of action performed')
    parser.add_argument('--action-type-file', help='Path to file containing action type')
    parser.add_argument('--action-description', help='Description of the action performed')
    parser.add_argument('--action-description-file', help='Path to file containing action description')
    parser.add_argument('--run-dir', required=True, help='Directory to save verification artifacts')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose logging')
    parser.add_argument('--log-dir', help='Directory to save LLM conversation logs')
    
    args = parser.parse_args()
    
    # Get arguments from either direct parameters or files
    step_description = None
    if args.step_description:
        step_description = args.step_description
    elif args.step_description_file:
        try:
            with open(args.step_description_file, 'r') as f:
                step_description = f.read().strip()
        except Exception as e:
            print(f"Error reading step description file: {e}")
            sys.exit(1)
    else:
        print("Error: Either --step-description or --step-description-file must be provided")
        sys.exit(1)
    
    action_type = None
    if args.action_type:
        action_type = args.action_type
    elif args.action_type_file:
        try:
            with open(args.action_type_file, 'r') as f:
                action_type = f.read().strip()
        except Exception as e:
            print(f"Error reading action type file: {e}")
            sys.exit(1)
    else:
        print("Error: Either --action-type or --action-type-file must be provided")
        sys.exit(1)
    
    action_description = None
    if args.action_description:
        action_description = args.action_description
    elif args.action_description_file:
        try:
            with open(args.action_description_file, 'r') as f:
                action_description = f.read().strip()
        except Exception as e:
            print(f"Error reading action description file: {e}")
            sys.exit(1)
    else:
        print("Error: Either --action-description or --action-description-file must be provided")
        sys.exit(1)
    
    setup_logging(args.verbose)
    logger = logging.getLogger(__name__)
    
    try:
        # Get API key
        api_key = os.getenv('OPENAI_API_KEY')
        if not api_key:
            logger.error("OPENAI_API_KEY not set")
            sys.exit(1)
        
        # Initialize verifier
        verifier = StepVerifier(
            api_key=api_key,
            log_dir=args.log_dir
        )
        
        # Perform verification
        result = verifier.verify_step(
            step_description=step_description,
            action_type=action_type,
            action_description=action_description,
            run_dir=args.run_dir
        )
        
        # Determine if step should be retried
        should_retry, retry_reason = verifier.should_retry_step(result)
        
        # Output result as JSON
        output = {
            "success": result.success,
            "confidence": result.confidence,
            "reasoning": result.reasoning,
            "screenshot_path": result.screenshot_path,
            "ui_graph_path": result.ui_graph_path,
            "validation_prompt": result.validation_prompt,
            "should_retry": should_retry,
            "retry_reason": retry_reason,
            "llm_response": result.llm_response
        }
        
        # Output only the JSON to stdout, log everything else to stderr
        print(json.dumps(output, indent=2), flush=True)
        
        # Exit with appropriate code
        if result.success:
            sys.exit(0)
        else:
            sys.exit(1)
            
    except Exception as e:
        logger.error(f"Verification failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()

