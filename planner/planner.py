"""
Main planner implementation for Agently.
"""

import json
import logging
import os
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

import openai
from openai import OpenAI

from planner.prompts import SystemPrompts, TaskPrompts
from planner.conversation_logger import ConversationLogger


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
        max_tokens: int = 2000,
        log_dir: Optional[str] = None
    ):
        self.model = model
        self.temperature = temperature
        self.max_tokens = max_tokens
        
        # Initialize conversation logger
        self.conversation_logger = ConversationLogger(
            log_dir=log_dir,
            model=model,
            temperature=temperature,
            max_tokens=max_tokens
        )
        
        self.client = OpenAI(api_key=api_key)
        logger.info(f"Initialized planner with model: {model}")
    
    def _clean_json_response(self, response: str) -> str:
        """Clean and prepare JSON response for parsing."""
        if not response or not response.strip():
            raise ValueError("Empty response from LLM")
        
        # Strip markdown code blocks if present
        clean_response = response.strip()
        if clean_response.startswith('```json'):
            clean_response = clean_response[7:]  # Remove '```json'
        if clean_response.startswith('```'):
            clean_response = clean_response[3:]   # Remove '```'
        if clean_response.endswith('```'):
            clean_response = clean_response[:-3]  # Remove trailing '```'
        clean_response = clean_response.strip()
        
        # Remove any JavaScript-style comments that might have been generated
        import re
        clean_response = re.sub(r'//.*$', '', clean_response, flags=re.MULTILINE)
        clean_response = re.sub(r'/\*.*?\*/', '', clean_response, flags=re.DOTALL)
        
        # Remove trailing commas before closing brackets/braces
        clean_response = re.sub(r',(\s*[}\]])', r'\1', clean_response)
        
        # Try to find JSON content if the response contains extra text
        # Look for content between { and } that looks like JSON
        json_match = re.search(r'\{.*\}', clean_response, flags=re.DOTALL)
        if json_match:
            clean_response = json_match.group(0)
        
        return clean_response

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
                user_prompt=user_prompt,
                conversation_type="initial_planning"
            )
            
            # Parse and validate response
            try:
                clean_response = self._clean_json_response(response)
                logger.debug(f"Cleaned response: {repr(clean_response)}")
                plan_data = json.loads(clean_response)
            except json.JSONDecodeError as e:
                logger.error(f"JSON decode error: {e}")
                logger.error(f"Original response: {repr(response)}")
                logger.error(f"Cleaned response: {repr(clean_response)}")
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
            available_elements = self._extract_interactive_elements(context.ui_graph)
            
            user_prompt = TaskPrompts.ERROR_RECOVERY.format(
                failed_action=context.error_context.get("failed_action", "unknown"),
                error_message=context.error_context.get("error_message", "unknown error"),
                current_ui_state=current_ui_summary,
                original_task=context.task,
                completed_actions=context.previous_actions,
                available_elements=available_elements
            )
            
            response = self._call_llm(
                system_prompt=SystemPrompts.MAIN_SYSTEM.format(),
                user_prompt=user_prompt,
                conversation_type="error_recovery"
            )
            
            try:
                clean_response = self._clean_json_response(response)
                recovery_data = json.loads(clean_response)
            except Exception as e:
                logger.error(f"Failed to parse recovery response: {e}")
                return ActionPlan(
                    reasoning=f"Recovery planning failed: {str(e)}",
                    actions=[],
                    confidence=0.0
                )
            
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
                user_prompt=user_prompt,
                conversation_type="element_selection"
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
            
            selection_data = json.loads(clean_response)
            element_id = selection_data.get("element_id")
            
            logger.debug(f"Selected element: {element_id}, reasoning: {selection_data.get('reasoning')}")
            return element_id
            
        except Exception as e:
            logger.error(f"Failed to select element: {e}")
            return None
    
    def _call_llm(self, system_prompt: str, user_prompt: str, conversation_type: str = "planning") -> str:
        """Make a call to the LLM API with detailed logging."""
        try:
            # Increment conversation counter
            self.conversation_logger.increment_counter()
            
            # Prepare messages
            messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ]
            
            # Log the conversation before making the API call
            self.conversation_logger.log_conversation(
                conversation_type=conversation_type,
                messages=messages,
                stage="request"
            )
            
            # Make API call
            response = self.client.chat.completions.create(
                model=self.model,
                messages=messages,
                temperature=self.temperature,
                max_tokens=self.max_tokens
            )
            
            content = response.choices[0].message.content
            
            # Log the response
            self.conversation_logger.log_conversation(
                conversation_type=conversation_type,
                messages=messages,
                response=content,
                response_metadata={
                    "model": response.model,
                    "usage": {
                        "prompt_tokens": response.usage.prompt_tokens,
                        "completion_tokens": response.usage.completion_tokens,
                        "total_tokens": response.usage.total_tokens
                    } if response.usage else None,
                    "finish_reason": response.choices[0].finish_reason
                },
                stage="response"
            )
            
            logger.debug(f"LLM response: {content}")
            return content
            
        except Exception as e:
            # Log the error
            self.conversation_logger.log_conversation(
                conversation_type=conversation_type,
                messages=messages if 'messages' in locals() else [],
                error=str(e),
                stage="error"
            )
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
    
    def _extract_interactive_elements(self, ui_graph: Dict[str, Any]) -> str:
        """Extract interactive elements for recovery planning (generic across all apps)."""
        elements = ui_graph.get("elements", {})
        
        interactive_elements = []
        interactive_roles = {"AXButton", "AXTextField", "AXMenuButton", "AXLink", "AXTab", "AXMenuItem"}
        
        for element_id, element in elements.items():
            role = element.get("role", "")
            if (role in interactive_roles and 
                element.get("isEnabled", False)):
                
                label = element.get("label", "")
                title = element.get("title", "")
                value = element.get("value", "")
                app_name = element.get("applicationName", "")
                
                # Create display text prioritizing most informative attribute
                display_parts = []
                if label:
                    display_parts.append(f"label:'{label}'")
                if title and title != label:
                    display_parts.append(f"title:'{title}'")
                if value and value not in [label, title]:
                    display_parts.append(f"value:'{value}'")
                
                display_text = " ".join(display_parts) if display_parts else "unlabeled"
                
                interactive_elements.append({
                    "id": element_id,
                    "role": role,
                    "app": app_name,
                    "display_text": display_text,
                    "label": label,
                    "title": title,
                    "value": value
                })
        
        if not interactive_elements:
            return "No interactive elements found"
        
        # Group by application and sort by role
        elements_by_app = {}
        for elem in interactive_elements:
            app = elem["app"] or "Unknown"
            if app not in elements_by_app:
                elements_by_app[app] = []
            elements_by_app[app].append(elem)
        
        # Format as readable list grouped by app
        result_lines = []
        for app_name, app_elements in elements_by_app.items():
            if len(app_elements) > 0:
                result_lines.append(f"\n{app_name}:")
                # Sort by role then by display text
                app_elements.sort(key=lambda x: (x["role"], x["display_text"]))
                for elem in app_elements[:20]:  # Limit to 20 elements per app
                    result_lines.append(f"  - {elem['role']} {elem['display_text']}: {elem['id']}")
        
        return "\n".join(result_lines)
    

