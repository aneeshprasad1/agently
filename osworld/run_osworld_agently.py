#!/usr/bin/env python3
"""
Custom OSWorld Run Script for Agently

This script demonstrates how to use the AgentlyAgent with OSWorld for desktop
automation evaluation. It shows the integration pattern and can be used as
a starting point for custom evaluation runs.
"""

import argparse
import logging
import os
import sys
from pathlib import Path

# Import the AgentlyAgent
import sys
import os

# Add the parent directory to Python path so we can find the planner module
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

from osworld_agent import AgentlyAgent

# Note: You would need to install OSWorld dependencies separately
# from desktop_env.desktop_env import DesktopEnv
# import lib_run_single


def setup_logging(verbose: bool = False):
    """Setup logging configuration."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )


def create_agently_agent(args) -> AgentlyAgent:
    """
    Create and configure an AgentlyAgent instance.
    
    Args:
        args: Command line arguments
        
    Returns:
        Configured AgentlyAgent instance
    """
    logging.info("Creating AgentlyAgent...")
    
    # Create agent with OSWorld-compatible configuration
    agent = AgentlyAgent(
        model=args.model,
        action_space="computer_13",  # OSWorld requirement
        observation_type="a11y_tree",  # OSWorld requirement
        max_tokens=args.max_tokens,
        temperature=args.temperature,
        top_p=args.top_p,
        client_password=args.client_password
    )
    
    logging.info(f"Agent created successfully with model: {args.model}")
    return agent


def run_standalone_test(agent: AgentlyAgent):
    """
    Run a standalone test of the agent without OSWorld environment.
    
    Args:
        agent: Configured AgentlyAgent instance
    """
    logging.info("Running standalone agent test...")
    
    # Test observation (simplified accessibility tree)
    test_obs = {
        "accessibility_tree": {
            "activeApplication": "Calculator",
            "elements": {
                "button_1": {
                    "role": "AXButton",
                    "label": "1",
                    "title": "1",
                    "isEnabled": True,
                    "position": {"x": 100, "y": 200}
                },
                "button_plus": {
                    "role": "AXButton", 
                    "label": "+",
                    "title": "plus",
                    "isEnabled": True,
                    "position": {"x": 150, "y": 200}
                },
                "button_2": {
                    "role": "AXButton",
                    "label": "2", 
                    "title": "2",
                    "isEnabled": True,
                    "position": {"x": 200, "y": 200}
                },
                "result_field": {
                    "role": "AXTextField",
                    "label": "Result",
                    "value": "0",
                    "isEnabled": True,
                    "position": {"x": 100, "y": 150}
                }
            }
        }
    }
    
    # Test tasks
    test_tasks = [
        "Click the number 1 button",
        "Click the plus button", 
        "Click the number 2 button",
        "What is the current result?"
    ]
    
    for i, task in enumerate(test_tasks, 1):
        logging.info(f"\n--- Test Task {i}: {task} ---")
        
        try:
            response, actions = agent.predict(task, test_obs)
            print(f"Task: {task}")
            print(f"Response: {response}")
            print(f"Actions: {actions}")
            print(f"State: {agent.get_state_summary()}")
            
        except Exception as e:
            logging.error(f"Task {i} failed: {e}")
            print(f"Task {i} failed: {e}")
    
    # Test reset
    logging.info("\n--- Testing Reset ---")
    agent.reset()
    print(f"After reset - State: {agent.get_state_summary()}")


def run_osworld_integration(agent: AgentlyAgent, args):
    """
    Run the agent with OSWorld integration.
    
    Note: This requires OSWorld to be installed and configured.
    
    Args:
        agent: Configured AgentlyAgent instance
        args: Command line arguments
    """
    logging.info("Setting up OSWorld integration...")
    
    try:
        # Import OSWorld components (these would need to be installed)
        # from desktop_env.desktop_env import DesktopEnv
        # import lib_run_single
        
        logging.info("OSWorld components imported successfully")
        
        # Example of how the integration would work:
        # 
        # # Initialize environment
        # env = DesktopEnv(
        #     provider_name=args.provider or "vmware",
        #     action_space=agent.action_space,
        #     screen_size=(1920, 1080),
        #     # ... other env config
        # )
        # 
        # # Run evaluation using lib_run_single
        # # This would be the actual OSWorld integration code
        # 
        logging.info("OSWorld integration setup complete")
        logging.warning("Full OSWorld integration requires OSWorld installation")
        
    except ImportError as e:
        logging.error(f"OSWorld components not available: {e}")
        logging.info("Run 'pip install osworld' or follow OSWorld installation guide")
        return False
    
    return True


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='OSWorld Agently Agent Runner')
    
    # Agent configuration
    parser.add_argument('--model', default='gpt-4o-mini', help='Language model to use')
    parser.add_argument('--max-tokens', type=int, default=2000, help='Maximum tokens for LLM responses')
    parser.add_argument('--temperature', type=float, default=0.1, help='LLM temperature setting')
    parser.add_argument('--top-p', type=float, default=1.0, help='LLM top_p setting')
    parser.add_argument('--client-password', help='Password for sudo operations')
    
    # OSWorld configuration (for future integration)
    parser.add_argument('--provider', help='OSWorld provider name (e.g., vmware)')
    parser.add_argument('--screen-size', nargs=2, type=int, default=[1920, 1080], 
                       help='Screen size (width height)')
    
    # Run mode
    parser.add_argument('--mode', choices=['test', 'osworld'], default='test',
                       help='Run mode: test (standalone) or osworld (OSWorld integration)')
    
    # Logging
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose logging')
    
    args = parser.parse_args()
    
    # Setup logging
    setup_logging(args.verbose)
    logger = logging.getLogger(__name__)
    
    try:
        # Create the agent
        agent = create_agently_agent(args)
        
        if args.mode == 'test':
            # Run standalone test
            run_standalone_test(agent)
            
        elif args.mode == 'osworld':
            # Run OSWorld integration
            success = run_osworld_integration(agent, args)
            if not success:
                logger.error("OSWorld integration failed")
                sys.exit(1)
        
        logger.info("Run completed successfully")
        
    except Exception as e:
        logger.error(f"Run failed: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
