#!/usr/bin/env python3
"""
OSWorld Agent Implementation for Agently

This module provides an AgentlyAgent class that implements the required OSWorld interface
for desktop automation evaluation. The agent uses accessibility tree observations and
computer_13 action space for task execution.
"""

import json
import logging
import os
from typing import Dict, List, Tuple, Optional, Any
from pathlib import Path

import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))
from planner.planner import AgentlyPlanner, PlanningContext


class AgentlyAgent:
    """
    OSWorld-compatible agent that uses Agently's planning capabilities.
    
    This agent implements the required interface for OSWorld evaluation:
    - Uses a11y_tree observation type for accessibility tree data
    - Uses computer_13 action space for standardized actions
    - Integrates with Agently's LLM-based planning system
    """
    
    def __init__(self, 
                 model: str = "gpt-4o-mini",
                 action_space: str = "computer_13",
                 observation_type: str = "a11y_tree",
                 max_tokens: int = 2000,
                 temperature: float = 0.1,
                 top_p: float = 1.0,
                 client_password: Optional[str] = None,
                 **kwargs):
        
        # Validate OSWorld requirements
        if action_space != "computer_13":
            raise ValueError("OSWorld requires action_space='computer_13'")
        if observation_type != "a11y_tree":
            raise ValueError("OSWorld requires observation_type='a11y_tree'")
        
        self.model = model
        self.action_space = action_space
        self.observation_type = observation_type
        self.max_tokens = max_tokens
        self.temperature = temperature
        self.top_p = top_p
        self.client_password = client_password
        
        # Initialize planner
        self.planner = AgentlyPlanner(
            model=model,
            temperature=temperature,
            max_tokens=max_tokens
        )
        
        # Initialize state
        self.current_task = "No task set"
        self.action_history = []
        self.task_history = []
        self.observation_history = []
        
        # Initialize logger
        self.logger = logging.getLogger(__name__)
        
        logging.info(f"Initialized AgentlyAgent with model: {model}")
    
    def predict(self, instruction: str, obs: Dict) -> Tuple[str, List[str]]:
        """
        Generate action predictions based on instruction and observation.
        
        Args:
            instruction: A string describing the task to complete
            obs: A dictionary containing observation data with accessibility tree
            
        Returns:
            Tuple of (response_text, action_list)
        """
        try:
            # Store current task and observation
            self.current_task = instruction
            self.observation_history.append(obs)
            
            # Extract accessibility tree from observation
            if "accessibility_tree" not in obs:
                raise ValueError("Observation must contain 'accessibility_tree'")
            
            accessibility_tree = obs["accessibility_tree"]
            
            # Create planning context
            context = PlanningContext(
                task=instruction,
                ui_graph=accessibility_tree,
                active_application=accessibility_tree.get("activeApplication"),
                previous_actions=self.action_history
            )
            
            # Generate action plan
            plan = self.planner.generate_plan(context)
            
            # Extract actions from plan
            actions = plan.actions
            
            # Log the planning result
            self.logger.info(f"Generated plan with {len(actions)} actions, confidence: {plan.confidence}")
            self.logger.info(f"Plan reasoning: {plan.reasoning}")
            
            # Update action history
            self.action_history.extend(actions)
            
            # Return response and actions
            response = f"Generated plan: {plan.reasoning}"
            return response, actions
            
        except Exception as e:
            self.logger.error(f"Error in predict: {e}")
            return f"Error: {str(e)}", []
    
    def reset(self, logger=None):
        """
        Reset the agent's state between tasks.
        
        This method is called by OSWorld before starting a new evaluation task.
        It clears all internal state, history, and context.
        
        Args:
            logger: Optional logger instance for debugging (can be ignored)
        """
        logging.info("Resetting AgentlyAgent state")
        
        # Clear all history
        self.task_history = []
        self.action_history = []
        self.observation_history = []
        self.current_task = None
        
        # Reset planner state if needed
        if hasattr(self.planner, 'reset'):
            self.planner.reset()
        
        logging.info("Agent state reset complete")
    
    def get_state_summary(self) -> Dict[str, Any]:
        """
        Get a summary of the agent's current state for debugging.
        
        Returns:
            Dictionary containing state information
        """
        return {
            'model': self.model,
            'action_space': self.action_space,
            'observation_type': self.observation_type,
            'current_task': self.current_task,
            'task_history_count': len(self.task_history),
            'action_history_count': len(self.action_history),
            'observation_history_count': len(self.observation_history),
            'config': {
                'max_tokens': self.max_tokens,
                'temperature': self.temperature,
                'top_p': self.top_p
            }
        }


# Example usage and testing
if __name__ == "__main__":
    # Setup logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Example of how to use the agent
    try:
        # Initialize agent
        agent = AgentlyAgent(
            model="gpt-4o-mini",
            action_space="computer_13",
            observation_type="a11y_tree"
        )
        
        # Example observation (simplified)
        example_obs = {
            "accessibility_tree": {
                "activeApplication": "Calculator",
                "elements": {
                    "button_1": {
                        "role": "AXButton",
                        "label": "1",
                        "isEnabled": True
                    }
                }
            }
        }
        
        # Test prediction
        response, actions = agent.predict("Click the number 1 button", example_obs)
        print(f"Response: {response}")
        print(f"Actions: {actions}")
        
        # Test reset
        agent.reset()
        print("Agent reset complete")
        
    except Exception as e:
        print(f"Error: {e}")
