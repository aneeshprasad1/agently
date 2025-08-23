# OSWorld Agent Interface Requirements

This document outlines the required interface for implementing agents to test against the OSWorld desktop environment evaluation framework.

## Overview

OSWorld is a desktop environment evaluation framework that tests agentic frameworks on various desktop automation tasks. To integrate your agent, you must implement a specific interface that allows OSWorld to control the evaluation loop.

## Required Interface

Your agent class must implement the following interface:

### Required Methods

#### 1. Constructor (`__init__`)
```python
def __init__(self, **kwargs):
    # Initialize your agent with configuration parameters
    # Common parameters include:
    # - model: The language model to use
    # - action_space: Type of actions (e.g., "pyautogui", "computer_13")
    # - observation_type: Type of observations (e.g., "screenshot", "a11y_tree", "screenshot_a11y_tree", "som")
    # - max_tokens: Maximum tokens for LLM responses
    # - temperature: LLM temperature setting
    # - top_p: LLM top_p setting
    # - client_password: Password for sudo operations
    pass
```

#### 2. Core Prediction Method (`predict`)
```python
def predict(self, instruction: str, obs: Dict) -> Tuple[str, List]:
    """
    Predict the next action(s) based on the current observation.
    
    This is the main method that OSWorld calls to get actions from your agent.
    
    Args:
        instruction: A string describing the task to complete
        obs: A dictionary containing observation data with keys like:
             - "screenshot": Base64 encoded screenshot image
             - "accessibility_tree": Accessibility tree data (if applicable)
             
    Returns:
        Tuple of (response, actions) where:
        - response: A string containing your agent's reasoning/response
        - actions: A list of actions to execute (can be strings, dicts, or other formats)
    
    Example:
        instruction = "Open the calculator application"
        obs = {"screenshot": "base64_image_data", "accessibility_tree": "tree_data"}
        return "I need to find and click on the calculator icon", ["click_calculator"]
    """
    pass
```

#### 3. Reset Method (`reset`)
```python
def reset(self, logger=None):
    """
    Reset the agent's state between tasks.
    
    This method is called by OSWorld before starting a new evaluation task.
    It should clear any internal state, history, or context that might
    interfere with the new task.
    
    Args:
        logger: Optional logger instance for debugging (can be ignored)
    """
    pass
```

## Example Implementation

Here's a minimal working example of an OSWorld-compatible agent:

```python
from typing import Dict, List, Tuple

class YourAgent:
    def __init__(self, 
                 model="your-model",
                 action_space="pyautogui",
                 observation_type="screenshot",
                 **kwargs):
        self.model = model
        self.action_space = action_space
        self.observation_type = observation_type
        
        # Internal state tracking
        self.thoughts = []
        self.actions = []
        self.observations = []
        
        # Store configuration
        self.config = kwargs
    
    def predict(self, instruction: str, obs: Dict) -> Tuple[str, List]:
        """
        Your agent's core logic goes here.
        """
        # Process the instruction and observation
        # This is where you'd implement your agent's reasoning
        
        # Example: Simple rule-based agent
        if "calculator" in instruction.lower():
            response = "I need to find and open the calculator application"
            actions = ["open_calculator"]
        elif "browser" in instruction.lower():
            response = "I need to open a web browser"
            actions = ["open_browser"]
        else:
            response = "I'm not sure how to handle this task"
            actions = []
        
        # Store history (optional but recommended)
        self.thoughts.append(response)
        self.actions.append(actions)
        self.observations.append(obs)
        
        return response, actions
    
    def reset(self, logger=None):
        """Clear agent state between tasks."""
        self.thoughts = []
        self.actions = []
        self.observations = []
```

## Integration with OSWorld

### 1. Replace Default Agent
In `run.py`, replace the `PromptAgent` instantiation:

```python
# Instead of:
# agent = PromptAgent(...)

# Use your agent:
agent = YourAgent(
    model=args.model,
    action_space=args.action_space,
    observation_type=args.observation_type,
    # ... other parameters
)
```

### 2. Create Custom Run Script
Alternatively, create a new run script that imports and uses your agent:

```python
from your_agent_module import YourAgent
from desktop_env.desktop_env import DesktopEnv
import lib_run_single

# Initialize your agent
agent = YourAgent(
    model="your-model",
    action_space="pyautogui",
    observation_type="screenshot"
)

# Initialize environment
env = DesktopEnv(
    provider_name="vmware",  # or other provider
    action_space=agent.action_space,
    screen_size=(1920, 1080),
    # ... other env config
)

# Run evaluation
# ... your evaluation loop using lib_run_single.run_single_example
```

## Key Design Principles

### 1. Reactive Architecture
- OSWorld controls the evaluation loop
- Your agent responds to observations with actions
- Don't implement internal planning loops - let OSWorld handle the step-by-step execution

### 2. State Management
- Store relevant history in your agent if needed
- Use the `reset()` method to clear state between tasks
- Don't rely on persistent state across different evaluation runs

### 3. Action Format
- Actions can be strings, dictionaries, or other formats
- OSWorld will pass these actions to the environment's `step()` method
- Ensure your actions are compatible with the environment's action space

### 4. Error Handling
- Handle cases where observations might be incomplete
- Return empty action lists if no valid action is possible
- Log errors appropriately for debugging

## Supported Observation Types

- **`screenshot`**: Just the visual screenshot
- **`a11y_tree`**: Only accessibility tree data
- **`screenshot_a11y_tree`**: Both screenshot and accessibility tree
- **`som`**: Set-of-marks with table metadata

## Supported Action Spaces

- **`pyautogui`**: Python code using pyautogui library
- **`computer_13`**: Enumerated action set

## Testing Your Agent

1. Implement the interface above
2. Test with a simple task first
3. Verify the `predict()` method returns the expected format
4. Check that `reset()` properly clears state
5. Run against OSWorld evaluation examples

## Common Pitfalls

- **Forgetting to implement `reset()`**: This can cause state to leak between tasks
- **Returning wrong format from `predict()`**: Must return `(response, actions)` tuple
- **Implementing internal loops**: Let OSWorld handle the step-by-step execution
- **Ignoring observation data**: Use the provided observations to make decisions

## Additional Resources

- Check the `mm_agents/` directory for existing agent implementations
- Review `lib_run_single.py` for how agents are integrated
- Look at evaluation examples in `evaluation_examples/` directory
- Check the `desktop_env/` module for environment capabilities
