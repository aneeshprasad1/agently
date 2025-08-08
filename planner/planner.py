"""
Main planner implementation for Agently.
"""

import json
import logging
from dataclasses import dataclass
from typing import Dict, List, Optional, Any

import openai
from openai import OpenAI

from .prompts import SystemPrompts, TaskPrompts


logger = logging.getLogger(__name__)


@dataclass
class PlanningContext:
    """Context information for planning."""
    
    task: str
    ui_graph: Dict[str, Any]
    active_application: Optional[str] = None
    previous_actions: List[Dict[str, Any]] = None
    error_context: Optional[Dict[str, Any]] = None
    
    def __post_init__(self):
        if self.previous_actions is None:
            self.previous_actions = []


@dataclass 
class ActionPlan:
    """Generated action plan."""
    
    reasoning: str
    actions: List[Dict[str, Any]]
    confidence: float
    metadata: Optional[Dict[str, Any]] = None


class AgentlyPlanner:
    """LLM-based planner for generating action sequences."""
    
    def __init__(
        self, 
        model: str = "gpt-4o-mini",
        api_key: Optional[str] = None,
        temperature: float = 0.1,
        max_tokens: int = 2000
    ):
        self.model = model
        self.temperature = temperature
        self.max_tokens = max_tokens
        
        self.client = OpenAI(api_key=api_key)
        logger.info(f"Initialized planner with model: {model}")
    
    def generate_plan(self, context: PlanningContext) -> ActionPlan:
        """Generate an action plan for the given context."""
        logger.info(f"Generating plan for task: {context.task}")
        
        try:
            # Analyze UI graph and extract relevant information
            ui_summary = self._summarize_ui_graph(context.ui_graph)
            relevant_elements = self._find_relevant_elements(context.ui_graph, context.task)
            
            # Build the planning prompt
            user_prompt = TaskPrompts.PLAN_GENERATION.format(
                task=context.task,
                ui_graph_summary=ui_summary,
                relevant_elements=relevant_elements
            )
            
            # Generate plan using LLM
            response = self._call_llm(
                system_prompt=SystemPrompts.MAIN_SYSTEM.format(),
                user_prompt=user_prompt
            )
            
            # Parse and validate response
            if not response or not response.strip():
                raise ValueError("Empty response from LLM")
            
            try:
                # Strip markdown code blocks if present
                clean_response = response.strip()
                if clean_response.startswith('```json'):
                    clean_response = clean_response[7:]  # Remove '```json'
                if clean_response.startswith('```'):
                    clean_response = clean_response[3:]   # Remove '```'
                if clean_response.endswith('```'):
                    clean_response = clean_response[:-3]  # Remove trailing '```'
                clean_response = clean_response.strip()
                
                # Remove JavaScript-style comments that break JSON parsing
                clean_response = self._remove_json_comments(clean_response)
                
                plan_data = json.loads(clean_response)
            except json.JSONDecodeError as e:
                logger.error(f"JSON decode error: {e}")
                logger.error(f"Response that failed to parse: {repr(response)}")
                raise ValueError(f"Invalid JSON response: {e}")
            plan = ActionPlan(
                reasoning=plan_data.get("reasoning", ""),
                actions=plan_data.get("actions", []),
                confidence=plan_data.get("confidence", 0.5)
            )
            
            logger.info(f"Generated plan with {len(plan.actions)} actions, confidence: {plan.confidence}")
            return plan
            
        except Exception as e:
            logger.error(f"Failed to generate plan: {e}")
            # Return fallback plan
            return ActionPlan(
                reasoning=f"Error in planning: {str(e)}",
                actions=[],
                confidence=0.0
            )
    
    def recover_from_error(self, context: PlanningContext) -> ActionPlan:
        """Generate a recovery plan when an action fails."""
        logger.info("Generating error recovery plan")
        
        if not context.error_context:
            logger.warning("No error context provided for recovery")
            return self.generate_plan(context)
        
        try:
            current_ui_summary = self._summarize_ui_graph(context.ui_graph)
            
            user_prompt = TaskPrompts.ERROR_RECOVERY.format(
                failed_action=context.error_context.get("failed_action", "unknown"),
                error_message=context.error_context.get("error_message", "unknown error"),
                current_ui_state=current_ui_summary,
                original_task=context.task,
                completed_actions=context.previous_actions
            )
            
            response = self._call_llm(
                system_prompt=SystemPrompts.MAIN_SYSTEM.format(),
                user_prompt=user_prompt
            )
            
            if not response or not response.strip():
                raise ValueError("Empty response from LLM")
            
            # Strip markdown code blocks if present
            clean_response = response.strip()
            if clean_response.startswith('```json'):
                clean_response = clean_response[7:]
            if clean_response.startswith('```'):
                clean_response = clean_response[3:]
            if clean_response.endswith('```'):
                clean_response = clean_response[:-3]
            clean_response = clean_response.strip()
            
            # Remove JavaScript-style comments that break JSON parsing
            clean_response = self._remove_json_comments(clean_response)
            
            recovery_data = json.loads(clean_response)
            
            return ActionPlan(
                reasoning=recovery_data.get("recovery_strategy", ""),
                actions=recovery_data.get("actions", []),
                confidence=0.7,  # Lower confidence for recovery plans
                metadata={"is_recovery": True}
            )
            
        except Exception as e:
            logger.error(f"Failed to generate recovery plan: {e}")
            return ActionPlan(
                reasoning=f"Recovery planning failed: {str(e)}",
                actions=[],
                confidence=0.0
            )
    
    def select_element(self, intent: str, elements: List[Dict[str, Any]]) -> Optional[str]:
        """Select the best element for a given intent."""
        logger.debug(f"Selecting element for intent: {intent}")
        
        try:
            elements_summary = self._format_elements_for_selection(elements)
            
            user_prompt = TaskPrompts.ELEMENT_SELECTION.format(
                intent=intent,
                elements=elements_summary
            )
            
            response = self._call_llm(
                system_prompt=SystemPrompts.MAIN_SYSTEM.format(),
                user_prompt=user_prompt
            )
            
            if not response or not response.strip():
                raise ValueError("Empty response from LLM")
            
            # Strip markdown code blocks if present
            clean_response = response.strip()
            if clean_response.startswith('```json'):
                clean_response = clean_response[7:]
            if clean_response.startswith('```'):
                clean_response = clean_response[3:]
            if clean_response.endswith('```'):
                clean_response = clean_response[:-3]
            clean_response = clean_response.strip()
            
            # Remove JavaScript-style comments that break JSON parsing
            clean_response = self._remove_json_comments(clean_response)
            
            selection_data = json.loads(clean_response)
            element_id = selection_data.get("element_id")
            
            logger.debug(f"Selected element: {element_id}, reasoning: {selection_data.get('reasoning')}")
            return element_id
            
        except Exception as e:
            logger.error(f"Failed to select element: {e}")
            return None
    
    def _call_llm(self, system_prompt: str, user_prompt: str) -> str:
        """Make a call to the LLM API."""
        try:
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                temperature=self.temperature,
                max_tokens=self.max_tokens
            )
            
            content = response.choices[0].message.content
            logger.debug(f"LLM response: {content}")
            return content
            
        except Exception as e:
            logger.error(f"LLM API call failed: {e}")
            raise
    
    def _summarize_ui_graph(self, ui_graph: Dict[str, Any]) -> str:
        """Create a concise summary of the UI graph."""
        elements = ui_graph.get("elements", {})
        active_app = ui_graph.get("activeApplication")
        
        # Count elements by role
        role_counts = {}
        for element in elements.values():
            role = element.get("role", "unknown")
            role_counts[role] = role_counts.get(role, 0) + 1
        
        # Find notable elements
        notable_elements = []
        for element in elements.values():
            if element.get("role") in ["AXButton", "AXTextField", "AXMenuButton"]:
                label = element.get("label") or element.get("title") or "unlabeled"
                notable_elements.append(f"{element.get('role')} '{label}'")
        
        summary = f"Application: {active_app or 'Unknown'}\\n"
        summary += f"Total elements: {len(elements)}\\n"
        summary += f"Element types: {dict(role_counts)}\\n"
        
        if notable_elements:
            summary += f"Key interactive elements: {notable_elements[:10]}"  # Limit to first 10
        
        return summary
    
    def _find_relevant_elements(self, ui_graph: Dict[str, Any], task: str) -> str:
        """Find elements relevant to the current task."""
        elements = ui_graph.get("elements", {})
        task_lower = task.lower()
        
        relevant = []
        
        for element_id, element in elements.items():
            # Check if element might be relevant based on labels/text
            text_fields = [
                element.get("label", ""),
                element.get("title", ""), 
                element.get("value", "")
            ]
            
            element_text = " ".join(filter(None, text_fields)).lower()
            
            # Simple keyword matching - could be improved with semantic similarity
            if any(word in element_text for word in task_lower.split() if len(word) > 2):
                relevant.append({
                    "id": element_id,
                    "role": element.get("role"),
                    "label": element.get("label"),
                    "title": element.get("title"),
                    "enabled": element.get("isEnabled", False)
                })
        
        # Limit to most relevant elements
        return json.dumps(relevant[:20], indent=2)
    
    def _format_elements_for_selection(self, elements: List[Dict[str, Any]]) -> str:
        """Format elements for element selection prompt."""
        formatted = []
        
        for element in elements:
            formatted.append({
                "id": element.get("id"),
                "role": element.get("role"),
                "label": element.get("label"),
                "title": element.get("title"),
                "enabled": element.get("isEnabled", False),
                "position": element.get("position")
            })
        
        return json.dumps(formatted, indent=2)
    
    def _remove_json_comments(self, json_string: str) -> str:
        """Remove JavaScript-style comments from JSON string."""
        import re
        
        # Remove single-line comments (// comment)
        # This regex matches // followed by anything up to end of line
        # but avoids removing // inside quoted strings
        lines = json_string.split('\n')
        cleaned_lines = []
        
        for line in lines:
            # Simple approach: if line contains //, check if it's inside quotes
            if '//' in line:
                # Find all quote positions
                quote_positions = []
                in_quotes = False
                escape_next = False
                
                for i, char in enumerate(line):
                    if escape_next:
                        escape_next = False
                        continue
                    if char == '\\':
                        escape_next = True
                        continue
                    if char == '"':
                        quote_positions.append(i)
                        in_quotes = not in_quotes
                
                # Find // that's not inside quotes
                comment_start = -1
                i = 0
                while i < len(line) - 1:
                    if line[i:i+2] == '//':
                        # Check if this // is inside quotes
                        inside_quotes = False
                        quote_count = 0
                        for quote_pos in quote_positions:
                            if quote_pos < i:
                                quote_count += 1
                        inside_quotes = quote_count % 2 == 1
                        
                        if not inside_quotes:
                            comment_start = i
                            break
                    i += 1
                
                if comment_start >= 0:
                    line = line[:comment_start].rstrip()
            
            cleaned_lines.append(line)
        
        return '\n'.join(cleaned_lines)
