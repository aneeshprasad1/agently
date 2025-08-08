"""
Tests for the Agently planner module.
"""

import json
import pytest
from unittest.mock import Mock, patch

from planner.planner import AgentlyPlanner, PlanningContext, ActionPlan
from planner.prompts import SystemPrompts, TaskPrompts


class TestAgentlyPlanner:
    """Test the main planner functionality."""
    
    def setup_method(self):
        """Set up test fixtures."""
        self.planner = AgentlyPlanner(api_key="test_key")
        
        self.sample_ui_graph = {
            "elements": {
                "button_1": {
                    "id": "button_1",
                    "role": "AXButton",
                    "title": "Submit",
                    "label": "Submit Button",
                    "position": {"x": 100, "y": 200},
                    "size": {"width": 80, "height": 30},
                    "isEnabled": True,
                    "isFocused": False,
                    "applicationName": "TestApp"
                },
                "text_1": {
                    "id": "text_1", 
                    "role": "AXTextField",
                    "label": "Name Field",
                    "position": {"x": 100, "y": 150},
                    "size": {"width": 200, "height": 25},
                    "isEnabled": True,
                    "isFocused": False,
                    "applicationName": "TestApp"
                }
            },
            "rootElements": ["button_1", "text_1"],
            "activeApplication": "TestApp"
        }
    
    def test_planning_context_creation(self):
        """Test creating a planning context."""
        context = PlanningContext(
            task="Click the submit button",
            ui_graph=self.sample_ui_graph,
            active_application="TestApp"
        )
        
        assert context.task == "Click the submit button"
        assert context.ui_graph == self.sample_ui_graph
        assert context.active_application == "TestApp"
        assert context.previous_actions == []
        assert context.error_context is None
    
    def test_ui_graph_summarization(self):
        """Test UI graph summarization."""
        summary = self.planner._summarize_ui_graph(self.sample_ui_graph)
        
        assert "TestApp" in summary
        assert "2" in summary  # element count
        assert "AXButton" in summary
        assert "AXTextField" in summary
    
    def test_relevant_elements_finding(self):
        """Test finding relevant elements for a task."""
        relevant = self.planner._find_relevant_elements(
            self.sample_ui_graph, 
            "submit the form"
        )
        
        # Should find elements related to "submit"
        relevant_data = json.loads(relevant)
        assert len(relevant_data) > 0
        
        # Should include the submit button
        submit_elements = [e for e in relevant_data if "submit" in str(e).lower()]
        assert len(submit_elements) > 0
    
    @patch('planner.planner.OpenAI')
    def test_generate_plan_success(self, mock_openai):
        """Test successful plan generation."""
        # Mock OpenAI response
        mock_response = Mock()
        mock_response.choices = [Mock()]
        mock_response.choices[0].message.content = json.dumps({
            "reasoning": "Click the submit button to complete the form",
            "actions": [
                {
                    "type": "click",
                    "target_element_id": "button_1",
                    "parameters": {},
                    "description": "Click submit button"
                }
            ],
            "confidence": 0.9
        })
        
        mock_client = Mock()
        mock_client.chat.completions.create.return_value = mock_response
        mock_openai.return_value = mock_client
        
        context = PlanningContext(
            task="Submit the form",
            ui_graph=self.sample_ui_graph
        )
        
        plan = self.planner.generate_plan(context)
        
        assert isinstance(plan, ActionPlan)
        assert plan.confidence == 0.9
        assert len(plan.actions) == 1
        assert plan.actions[0]["type"] == "click"
        assert plan.actions[0]["target_element_id"] == "button_1"
    
    @patch('planner.planner.OpenAI')
    def test_generate_plan_failure(self, mock_openai):
        """Test plan generation failure handling."""
        # Mock OpenAI to raise an exception
        mock_client = Mock()
        mock_client.chat.completions.create.side_effect = Exception("API Error")
        mock_openai.return_value = mock_client
        
        context = PlanningContext(
            task="Submit the form",
            ui_graph=self.sample_ui_graph
        )
        
        plan = self.planner.generate_plan(context)
        
        # Should return fallback plan
        assert isinstance(plan, ActionPlan)
        assert plan.confidence == 0.0
        assert len(plan.actions) == 0
        assert "Error in planning" in plan.reasoning
    
    def test_element_formatting(self):
        """Test element formatting for selection."""
        elements = [
            {
                "id": "button_1",
                "role": "AXButton",
                "title": "Submit",
                "isEnabled": True
            }
        ]
        
        formatted = self.planner._format_elements_for_selection(elements)
        formatted_data = json.loads(formatted)
        
        assert len(formatted_data) == 1
        assert formatted_data[0]["id"] == "button_1"
        assert formatted_data[0]["role"] == "AXButton"
        assert formatted_data[0]["title"] == "Submit"


class TestPromptTemplates:
    """Test prompt template functionality."""
    
    def test_system_prompt_formatting(self):
        """Test system prompt formatting."""
        prompt = SystemPrompts.MAIN_SYSTEM.format()
        assert "Agently" in prompt
        assert "accessibility" in prompt
        assert "JSON" in prompt
    
    def test_task_prompt_formatting(self):
        """Test task prompt formatting with required variables."""
        prompt = TaskPrompts.PLAN_GENERATION.format(
            task="Click button",
            ui_graph_summary="Test summary",
            relevant_elements="[]"
        )
        
        assert "Click button" in prompt
        assert "Test summary" in prompt
        assert "JSON" in prompt
    
    def test_missing_variable_error(self):
        """Test that missing variables raise an error."""
        with pytest.raises(ValueError, match="Missing required variable"):
            TaskPrompts.PLAN_GENERATION.format(
                task="Click button"
                # Missing ui_graph_summary and relevant_elements
            )
    
    def test_element_selection_prompt(self):
        """Test element selection prompt."""
        prompt = TaskPrompts.ELEMENT_SELECTION.format(
            intent="click submit button",
            elements='[{"id": "btn1", "title": "Submit"}]'
        )
        
        assert "click submit button" in prompt
        assert "Submit" in prompt
        assert "element_id" in prompt
    
    def test_error_recovery_prompt(self):
        """Test error recovery prompt."""
        prompt = TaskPrompts.ERROR_RECOVERY.format(
            failed_action='{"type": "click"}',
            error_message="Element not found",
            current_ui_state="Current state",
            original_task="Submit form", 
            completed_actions="[]"
        )
        
        assert "Element not found" in prompt
        assert "Submit form" in prompt
        assert "recovery_strategy" in prompt


if __name__ == "__main__":
    pytest.main([__file__])
