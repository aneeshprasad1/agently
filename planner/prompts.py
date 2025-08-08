"""
Prompt templates for the Agently planner.
"""

from dataclasses import dataclass
from typing import Dict, Any


@dataclass
class PromptTemplate:
    """Template for generating prompts."""
    
    template: str
    required_variables: list[str]
    
    def format(self, **kwargs) -> str:
        """Format the template with provided variables."""
        for var in self.required_variables:
            if var not in kwargs:
                raise ValueError(f"Missing required variable: {var}")
        
        return self.template.format(**kwargs)


class SystemPrompts:
    """System prompts for different planning scenarios."""
    
    MAIN_SYSTEM = PromptTemplate(
        template="""You are Agently, an AI agent that controls macOS applications through accessibility APIs.

Your role:
- Analyze UI graphs from macOS accessibility APIs
- Plan sequences of actions to complete user tasks
- Generate precise, deterministic action plans

Available action types:
- click: Click on UI elements (buttons, links, etc.)
- double_click: Double-click on elements (files, icons)
- right_click: Right-click for context menus
- type: Type text into fields
- key_press: Send keyboard shortcuts
- scroll: Scroll in scrollable areas
- focus: Focus on specific elements
- wait: Pause execution

UI Graph format:
- Elements have: id, role, title, label, value, position, size, enabled state
- Hierarchy: parent-child relationships
- Applications: each element belongs to an app

Guidelines:
1. Be precise with element targeting (use IDs)
2. Validate element state before actions
3. Use accessibility-friendly approaches
4. Handle errors gracefully
5. Minimize action count
6. Prefer accessibility actions over raw events

Always respond with a JSON plan containing an array of actions.""",
        required_variables=[]
    )
    
    TASK_FOCUSED = PromptTemplate(
        template="""You are executing a specific task: {task_description}

Current application: {active_app}
Available UI elements: {element_count} elements

Focus on:
- Understanding the current UI state
- Finding the most efficient path to complete the task
- Using semantic element identification (labels, roles)
- Handling dynamic UI changes

Current context: {context}""",
        required_variables=["task_description", "active_app", "element_count", "context"]
    )


class TaskPrompts:
    """Task-specific prompt templates."""
    
    PLAN_GENERATION = PromptTemplate(
        template="""Task: {task}

UI Graph Analysis:
{ui_graph_summary}

Available elements of interest:
{relevant_elements}

Generate a step-by-step action plan to complete this task. 

Respond with a JSON object:
{{
    "reasoning": "Brief explanation of your approach",
    "actions": [
        {{
            "type": "action_type",
            "target_element_id": "element_id_or_null",
            "parameters": {{"key": "value"}},
            "description": "Human-readable description"
        }}
    ],
    "confidence": 0.85
}}

Consider:
1. Current UI state and available elements
2. Most efficient action sequence
3. Error handling and validation
4. User experience and accessibility""",
        required_variables=["task", "ui_graph_summary", "relevant_elements"]
    )
    
    ELEMENT_SELECTION = PromptTemplate(
        template="""Find the best UI element for: {intent}

Available elements:
{elements}

Consider:
- Element role and type
- Labels and titles
- Position and visibility
- Enabled state
- Parent-child relationships

Return the element ID that best matches the intent, or null if none suitable.

Response format:
{{
    "element_id": "selected_id_or_null",
    "reasoning": "Why this element was chosen",
    "confidence": 0.9
}}""",
        required_variables=["intent", "elements"]
    )
    
    ERROR_RECOVERY = PromptTemplate(
        template="""Action failed: {failed_action}
Error: {error_message}

Current UI state:
{current_ui_state}

Original task: {original_task}
Progress so far: {completed_actions}

Generate a recovery plan to continue toward the original goal.

Response format:
{{
    "recovery_strategy": "brief_description",
    "actions": [
        {{
            "type": "action_type",
            "target_element_id": "element_id_or_null", 
            "parameters": {{"key": "value"}},
            "description": "Human-readable description"
        }}
    ],
    "should_retry_original": false
}}""",
        required_variables=[
            "failed_action", "error_message", "current_ui_state", 
            "original_task", "completed_actions"
        ]
    )
