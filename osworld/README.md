# OSWorld Integration for Agently

This package provides OSWorld integration for Agently, allowing you to use Agently's planning capabilities with the OSWorld desktop automation evaluation framework.

## 📍 Location & Usage

**This integration is located in the `osworld/` directory but can be used from anywhere in the project:**

- **Import**: `from osworld import AgentlyAgent`
- **Run tests**: `python osworld/test_osworld_agent.py`
- **Run demo**: `python osworld/run_osworld_agently.py --mode test`
- **Example usage**: `python example_osworld_usage.py` (from root directory)

## Overview

The integration provides an `AgentlyAgent` class that implements the required OSWorld interface:
- **Observation Type**: `a11y_tree` (accessibility tree)
- **Action Space**: `computer_13` (standardized action set)
- **Integration**: Uses Agently's LLM-based planning system for task execution

## 🚀 Quick Start from Root Directory

You can use the OSWorld integration directly from the project root:

```bash
# Test the integration
python example_osworld_usage.py

# Run tests
python osworld/test_osworld_agent.py

# Run demo
python osworld/run_osworld_agently.py --mode test
```

**Import the agent from anywhere:**
```python
from osworld import AgentlyAgent

agent = AgentlyAgent(
    model="gpt-4o-mini",
    action_space="computer_13",
    observation_type="a11y_tree"
)
```

## Files

- `osworld_agent.py` - Main `AgentlyAgent` class implementing the OSWorld interface
- `run_osworld_agently.py` - Custom run script demonstrating OSWorld integration
- `test_osworld_agent.py` - Test suite to verify the agent works correctly
- `__init__.py` - Package initialization file

## Package Structure

```
osworld/
├── __init__.py                    # Package initialization
├── osworld_agent.py              # Main agent implementation
├── run_osworld_agently.py        # Custom run script
├── test_osworld_agent.py         # Test suite
└── README.md                      # This documentation
```

## Quick Start

### 1. Prerequisites

- Python 3.8+
- OpenAI API key (set as `OPENAI_API_KEY` environment variable)
- Agently dependencies installed (`pip install -r requirements.txt`)

### 2. Test the Agent

Run the test suite to verify everything works:

```bash
# From the root directory
python osworld/test_osworld_agent.py

# Or from within the osworld directory
cd osworld && python test_osworld_agent.py
```

### 3. Run Standalone Demo

Test the agent with a simulated calculator interface:

```bash
# From the root directory
python osworld/run_osworld_agently.py --mode test --verbose

# Or from within the osworld directory
cd osworld && python run_osworld_agently.py --mode test --verbose
```

### 4. OSWorld Integration

For full OSWorld integration, you'll need to install OSWorld separately:

```bash
# Install OSWorld (follow their installation guide)
pip install osworld

# Run with OSWorld integration
python osworld/run_osworld_agently.py --mode osworld --provider vmware
```

## Usage

### Basic Agent Creation

```python
from osworld import AgentlyAgent

# Create agent with OSWorld requirements
agent = AgentlyAgent(
    model="gpt-4o-mini",
    action_space="computer_13",      # OSWorld requirement
    observation_type="a11y_tree",    # OSWorld requirement
    temperature=0.1,
    max_tokens=2000
)
```

### Using the Agent

```python
# Process an instruction with observation
instruction = "Click the number 1 button"
observation = {
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

# Get actions from the agent
response, actions = agent.predict(instruction, observation)
print(f"Response: {response}")
print(f"Actions: {actions}")  # e.g., ["click(button_1)"]

# Reset between tasks
agent.reset()
```

### OSWorld Integration Pattern

```python
# In your OSWorld run script
from osworld import AgentlyAgent
from desktop_env.desktop_env import DesktopEnv
import lib_run_single

# Initialize agent
agent = AgentlyAgent(
    model="gpt-4o-mini",
    action_space="computer_13",
    observation_type="a11y_tree"
)

# Initialize environment
env = DesktopEnv(
    provider_name="vmware",
    action_space=agent.action_space,
    screen_size=(1920, 1080)
)

# Run evaluation
# ... your evaluation loop using lib_run_single.run_single_example
```

## Action Format

The agent now uses computer_13 action format directly throughout the system:

| Action Type | Computer_13 Format |
|-------------|-------------------|
| Click | `click(element_id)` |
| Type | `type(element_id, "text")` |
| Key Press | `key_press("key")` |
| Wait | `wait("seconds")` |
| Scroll | `scroll("direction")` |
| Focus | `focus(element_id)` |
| Double Click | `double_click(element_id)` |
| Right Click | `right_click(element_id)` |
| Navigate | `navigate("direction")` |

**No conversion needed** - the planner generates computer_13 actions directly, and the SkillExecutor parses them natively.

## Configuration Options

### Agent Parameters

- `model`: Language model to use (default: "gpt-4o-mini")
- `action_space`: Must be "computer_13" for OSWorld
- `observation_type`: Must be "a11y_tree" for OSWorld
- `max_tokens`: Maximum tokens for LLM responses (default: 2000)
- `temperature`: LLM temperature setting (default: 0.1)
- `top_p`: LLM top_p setting (default: 1.0)
- `client_password`: Password for sudo operations (optional)

### Environment Variables

- `OPENAI_API_KEY`: Required for LLM API access

## Testing

### Run All Tests

```bash
python test_osworld_agent.py
```

### Test Specific Components

```bash
# Test agent initialization
python -c "
from osworld import AgentlyAgent
agent = AgentlyAgent()
print('Agent created successfully')
"

# Test action conversion
python -c "
from osworld import AgentlyAgent
agent = AgentlyAgent()
actions = agent._convert_to_computer_13([{'type': 'click', 'target_element_id': 'btn', 'parameters': {}}])
print(f'Converted actions: {actions}')
"
```

## Troubleshooting

### Common Issues

1. **Import Error**: Make sure you're in the correct directory and all dependencies are installed
2. **API Key Missing**: Set `OPENAI_API_KEY` environment variable
3. **Parameter Validation**: Ensure `action_space="computer_13"` and `observation_type="a11y_tree"`
4. **OSWorld Not Found**: Install OSWorld separately if you need full integration

### Debug Mode

Enable verbose logging for debugging:

```python
import logging
logging.basicConfig(level=logging.DEBUG)

agent = AgentlyAgent()
# ... your code
```

## Architecture

The `AgentlyAgent` integrates with OSWorld through:

1. **Interface Compliance**: Implements required `predict()` and `reset()` methods
2. **Direct computer_13 Actions**: Planner generates computer_13 actions directly, no conversion needed
3. **State Management**: Maintains task and action history for context
4. **Planning Integration**: Uses Agently's LLM-based planner for task reasoning

**Action Flow:**
1. Planner generates computer_13 actions (e.g., `["click(button_1)", "type(field, \"hello\")"]`)
2. Actions are returned directly to OSWorld
3. SkillExecutor parses computer_13 actions natively
4. No format conversion overhead

## Contributing

When modifying the agent:

1. Ensure OSWorld interface compliance is maintained
2. Update tests to cover new functionality
3. Verify action conversion still works correctly
4. Test with both standalone and OSWorld modes

## References

- [OSWorld Interface Requirements](docs/design/OSWORLD_INTERFACE.md)
- [Agently Planner Documentation](planner/)
- [OSWorld Framework](https://github.com/osworld-project/osworld)
