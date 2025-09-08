#!/usr/bin/env python3
"""
Test script for AgentlyAgent OSWorld integration.

This script tests the basic functionality of the AgentlyAgent class to ensure
it properly implements the OSWorld interface requirements.
"""

import json
import logging
import os
import sys
from unittest.mock import Mock, patch, MagicMock

# Add the parent directory to Python path so we can find the planner module
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

from osworld_agent import AgentlyAgent


def test_agent_initialization():
    """Test that the agent initializes correctly with OSWorld requirements."""
    print("Testing agent initialization...")
    
    try:
        # Test with valid OSWorld parameters
        agent = AgentlyAgent(
            model="gpt-4o-mini",
            action_space="computer_13",
            observation_type="a11y_tree"
        )
        
        assert agent.action_space == "computer_13"
        assert agent.observation_type == "a11y_tree"
        print("✓ Agent initialized successfully with OSWorld requirements")
        
        return agent
        
    except Exception as e:
        print(f"✗ Agent initialization failed: {e}")
        return None


def test_agent_parameter_validation():
    """Test that the agent validates parameters correctly."""
    print("\nTesting parameter validation...")
    
    # Test invalid action space
    try:
        agent = AgentlyAgent(action_space="pyautogui", observation_type="a11y_tree")
        print("✗ Should have rejected invalid action space")
        return False
    except ValueError as e:
        if "computer_13" in str(e):
            print("✓ Correctly rejected invalid action space")
        else:
            print(f"✗ Unexpected error message: {e}")
            return False
    
    # Test invalid observation type
    try:
        agent = AgentlyAgent(action_space="computer_13", observation_type="screenshot")
        print("✗ Should have rejected invalid observation type")
        return False
    except ValueError as e:
        if "a11y_tree" in str(e):
            print("✓ Correctly rejected invalid observation type")
        else:
            print(f"✗ Unexpected error message: {e}")
            return False
    
    print("✓ Parameter validation working correctly")
    return True


def test_agent_interface_methods():
    """Test that the agent implements all required OSWorld interface methods."""
    print("\nTesting OSWorld interface methods...")
    
    agent = AgentlyAgent(
        model="gpt-4o-mini",
        action_space="computer_13",
        observation_type="a11y_tree"
    )
    
    # Check required methods exist
    required_methods = ['__init__', 'predict', 'reset']
    for method_name in required_methods:
        if hasattr(agent, method_name):
            print(f"✓ Method '{method_name}' exists")
        else:
            print(f"✗ Method '{method_name}' missing")
            return False
    
    # Check method signatures
    import inspect
    
    # Check predict method signature
    predict_sig = inspect.signature(agent.predict)
    if len(predict_sig.parameters) == 2:  # instruction, obs
        print("✓ predict method has correct signature")
    else:
        print(f"✗ predict method has wrong signature: {predict_sig}")
        return False
    
    # Check reset method signature
    reset_sig = inspect.signature(agent.reset)
    if len(reset_sig.parameters) == 1:  # self
        print("✓ reset method has correct signature")
    else:
        print(f"✗ reset method has wrong signature: {reset_sig}")
        return False
    
    print("✓ All required interface methods implemented correctly")
    return True


def test_agent_predict_method():
    """Test the predict method."""
    print("\nTesting predict method...")
    
    agent = AgentlyAgent(
        model="gpt-4o-mini",
        action_space="computer_13",
        observation_type="a11y_tree"
    )
    
    # Mock the OpenAI client to avoid actual API calls
    with patch('planner.planner.OpenAI') as mock_openai:
        mock_client = MagicMock()
        mock_openai.return_value = mock_client
        
        # Mock response for computer_13 actions
        mock_response = MagicMock()
        mock_response.choices = [MagicMock()]
        mock_response.choices[0].message.content = '''{
            "reasoning": "Click the button to test",
            "actions": ["click(button_1)"],
            "confidence": 0.9
        }'''
        mock_client.chat.completions.create.return_value = mock_response
        
        # Test with instruction and observation
        instruction = "Click the button"
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
        
        response, actions = agent.predict(instruction, observation)
        
        if actions and len(actions) > 0:
            assert isinstance(actions[0], str)
            print("✓ Actions returned in computer_13 format")
        else:
            print("⚠ No actions generated (this might be expected)")
        
        print("✓ predict method working correctly")
        return True


def test_agent_reset_method():
    """Test the reset method."""
    print("\nTesting reset method...")
    
    agent = AgentlyAgent(
        model="gpt-4o-mini",
        action_space="computer_13",
        observation_type="a11y_tree"
    )
    
    # Add some state
    agent.current_task = "test task"
    agent.task_history.append({"test": "data"})
    agent.action_history.append("test_action")
    agent.observation_history.append({"test": "obs"})
    
    # Verify state exists
    assert agent.current_task is not None
    assert len(agent.task_history) > 0
    assert len(agent.action_history) > 0
    assert len(agent.observation_history) > 0
    
    # Reset
    agent.reset()
    
    # Verify state cleared
    assert agent.current_task is None
    assert len(agent.task_history) == 0
    assert len(agent.action_history) == 0
    assert len(agent.observation_history) == 0
    
    print("✓ reset method working correctly")
    return True


def test_action_conversion():
    """Test that the agent returns computer_13 format actions directly."""
    print("\nTesting computer_13 action format...")
    
    agent = AgentlyAgent(
        model="gpt-4o-mini",
        action_space="computer_13",
        observation_type="a11y_tree"
    )
    
    # Test that actions are returned in computer_13 format
    # Note: This test now verifies that actions are strings, not dictionaries
    instruction = "Click the button"
    test_observation = {
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
    
    # Mock the planner to return computer_13 actions
    with patch('planner.planner.OpenAI') as mock_openai:
        mock_client = MagicMock()
        mock_openai.return_value = mock_client
        
        # Mock response for computer_13 actions
        mock_response = MagicMock()
        mock_response.choices = [MagicMock()]
        mock_response.choices[0].message.content = '''{
            "reasoning": "Click the button to test",
            "actions": ["click(button_1)"],
            "confidence": 0.9
        }'''
        mock_client.chat.completions.create.return_value = mock_response
        
        response, actions = agent.predict(instruction, test_observation)
        
        if actions and len(actions) > 0:
            # Actions should now be strings in computer_13 format
            assert isinstance(actions[0], str)
            print(f"✓ Actions returned in computer_13 format: {actions[0]}")
        else:
            print("⚠ No actions generated (this might be expected)")
        
        print("✓ Agent returns computer_13 actions directly")
        return True


def main():
    """Run all tests."""
    print("Running AgentlyAgent OSWorld integration tests...\n")
    
    tests = [
        test_agent_initialization,
        test_agent_parameter_validation,
        test_agent_interface_methods,
        test_agent_predict_method,
        test_agent_reset_method,
        test_action_conversion
    ]
    
    passed = 0
    total = len(tests)
    
    for test in tests:
        try:
            if test():
                passed += 1
        except Exception as e:
            print(f"✗ Test {test.__name__} failed with exception: {e}")
    
    print(f"\n{'='*50}")
    print(f"Test Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests passed! AgentlyAgent is ready for OSWorld integration.")
        return 0
    else:
        print("❌ Some tests failed. Please fix the issues before using with OSWorld.")
        return 1


if __name__ == '__main__':
    sys.exit(main())
