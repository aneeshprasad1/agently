#!/usr/bin/env python3
"""
Step verification system for Agently.
Handles screenshot capture, UI graph building, and LLM-based validation.
"""

import json
import logging
import os
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Dict, Any, Optional, Tuple
import base64
from dataclasses import dataclass

import openai


@dataclass
class VerificationResult:
    """Result of a step verification."""
    success: bool
    confidence: float
    reasoning: str
    screenshot_path: Optional[str] = None
    ui_graph_path: Optional[str] = None
    validation_prompt: Optional[str] = None
    llm_response: Optional[Dict[str, Any]] = None
    should_retry: bool = False
    retry_reason: str = ""
    plan_update: Optional[Dict[str, Any]] = None


class StepVerifier:
    """Handles verification of individual steps in task execution."""
    
    def __init__(self, api_key: str, log_dir: Optional[str] = None):
        self.client = openai.OpenAI(api_key=api_key)
        self.logger = logging.getLogger(__name__)
        self.log_dir = log_dir
        
    def verify_step(
        self, 
        step_description: str, 
        action_type: str,
        action_description: str,
        run_dir: str,
        user_task: str = "",
        completed_actions: list = None
    ) -> VerificationResult:
        """
        Verify that a step was completed successfully.
        
        Args:
            step_description: Description of what the step should accomplish
            action_type: Type of action performed (e.g., 'click', 'type', 'key_press')
            action_description: Description of the action that was performed
            run_dir: Directory to save verification artifacts
            user_task: The original user task for state analysis
            completed_actions: List of actions that have been completed
            
        Returns:
            VerificationResult with success status and details
        """
        start_time = time.time()
        self.logger.info(f"Verifying step: {step_description}")
        
        # 0. Quick check for simple actions that don't need verification
        simple_actions = ["wait", "delay", "sleep"]
        if any(simple_action in action_type.lower() for simple_action in simple_actions):
            self.logger.info("⏭️ Skipping verification for simple action")
            return VerificationResult(
                success=True,
                confidence=1.0,
                reasoning="Simple action - no verification needed",
                should_retry=False,
                retry_reason="",
                screenshot_path="",
                ui_graph_path=None,
                plan_update=None
            )
        
        # 1. Capture screenshot
        screenshot_start = time.time()
        screenshot_path = self._capture_screenshot(run_dir)
        screenshot_duration = time.time() - screenshot_start
        self.logger.info(f"📸 Screenshot captured in {screenshot_duration:.2f}s")
        
        # 2. Generate validation prompt
        prompt_start = time.time()
        validation_prompt = self._generate_validation_prompt(
            step_description, action_type, action_description
        )
        prompt_duration = time.time() - prompt_start
        self.logger.info(f"📝 Validation prompt generated in {prompt_duration:.2f}s")
        
        # 3. Perform LLM validation with structured output
        llm_start = time.time()
        verification_result = self._perform_llm_validation(
            validation_prompt, screenshot_path
        )
        llm_duration = time.time() - llm_start
        self.logger.info(f"🤖 LLM validation completed in {llm_duration:.2f}s")
        
        # 4. Perform state analysis for plan updates (only if verification failed or for very complex tasks)
        plan_update = None
        if user_task and completed_actions and (not verification_result.success or len(completed_actions) > 5):
            try:
                analysis_start = time.time()
                plan_update = self.analyze_state_and_suggest_plan(
                    user_task, step_description, completed_actions, screenshot_path, run_dir
                )
                analysis_duration = time.time() - analysis_start
                self.logger.info(f"🧠 State analysis completed in {analysis_duration:.2f}s")
            except Exception as e:
                self.logger.error(f"State analysis failed: {e}")
        else:
            self.logger.info("⏭️ Skipping state analysis (verification successful and early in task)")
        
        # Add paths and plan update to result
        verification_result.screenshot_path = screenshot_path
        verification_result.ui_graph_path = None  # Not used
        verification_result.validation_prompt = validation_prompt
        verification_result.plan_update = plan_update
        
        # Determine if step should be retried
        should_retry, retry_reason = self.should_retry_step(verification_result)
        verification_result.should_retry = should_retry
        verification_result.retry_reason = retry_reason
        
        total_duration = time.time() - start_time
        self.logger.info(f"⏱️ Total verification completed in {total_duration:.2f}s")
        
        return verification_result
    
    def _capture_screenshot(self, run_dir: str) -> str:
        """Capture a screenshot of the current screen and resize it for faster processing."""
        try:
            # Ensure run_dir exists
            os.makedirs(run_dir, exist_ok=True)
            
            # Use macOS screencapture command
            timestamp = int(time.time())
            temp_screenshot_path = os.path.join(run_dir, f"temp_screenshot_{timestamp}.jpg")
            final_screenshot_path = os.path.join(run_dir, f"verification_screenshot_{timestamp}.jpg")
            
            # Capture screenshot with reduced quality for faster processing
            result = subprocess.run([
                'screencapture', '-x', '-t', 'jpg', temp_screenshot_path
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                # Resize the screenshot to reduce file size and processing time
                self._resize_screenshot(temp_screenshot_path, final_screenshot_path)
                
                # Clean up temp file
                if os.path.exists(temp_screenshot_path):
                    os.remove(temp_screenshot_path)
                
                self.logger.info(f"Screenshot captured and resized: {final_screenshot_path}")
                return final_screenshot_path
            else:
                self.logger.error(f"Failed to capture screenshot: {result.stderr}")
                return ""
                
        except Exception as e:
            self.logger.error(f"Error capturing screenshot: {e}")
            return ""
    
    def _resize_screenshot(self, input_path: str, output_path: str, max_width: int = 600, max_height: int = 450):
        """Resize screenshot to reduce file size while maintaining aspect ratio."""
        try:
            from PIL import Image
            
            with Image.open(input_path) as img:
                # Calculate new dimensions while maintaining aspect ratio
                width, height = img.size
                
                if width <= max_width and height <= max_height:
                    # Image is already small enough, just compress it
                    img.save(output_path, 'JPEG', quality=60, optimize=True)
                    return
                
                # Calculate scaling factor
                scale = min(max_width / width, max_height / height)
                new_width = int(width * scale)
                new_height = int(height * scale)
                
                # Resize image
                resized_img = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
                
                # Save with aggressive compression for faster processing
                resized_img.save(output_path, 'JPEG', quality=60, optimize=True)
                
                self.logger.debug(f"Resized screenshot from {width}x{height} to {new_width}x{new_height}")
                
        except Exception as e:
            self.logger.error(f"Error resizing screenshot: {e}")
            # Fallback: just copy the original file
            import shutil
            shutil.copy2(input_path, output_path)
    
    def _build_ui_graph(self, run_dir: str) -> str:
        """Build UI graph using the Swift graph builder."""
        try:
            timestamp = int(time.time())
            graph_path = os.path.join(run_dir, f"verification_ui_graph_{timestamp}.json")
            
            # Call Swift graph builder
            result = subprocess.run([
                'swift', 'run', 'agently-runner', '--graph-only', '--format', 'json'
            ], capture_output=True, text=True, cwd=os.getcwd())
            
            if result.returncode == 0:
                # Parse the output to extract JSON
                output_lines = result.stdout.strip().split('\n')
                json_start = None
                json_end = None
                
                for i, line in enumerate(output_lines):
                    if line.strip().startswith('{'):
                        json_start = i
                        break
                
                if json_start is not None:
                    json_content = '\n'.join(output_lines[json_start:])
                    with open(graph_path, 'w') as f:
                        f.write(json_content)
                    
                    self.logger.info(f"UI graph built: {graph_path}")
                    return graph_path
            
            self.logger.error(f"Failed to build UI graph: {result.stderr}")
            return ""
            
        except Exception as e:
            self.logger.error(f"Error building UI graph: {e}")
            return ""
    
    def _generate_validation_prompt(
        self, 
        step_description: str, 
        action_type: str, 
        action_description: str
    ) -> str:
        """Generate a validation prompt for the step."""
        
        prompt = f"""Verify if this step was completed successfully:

STEP: {step_description}
ACTION: {action_type} - {action_description}

Based on the screenshot, respond with JSON:
{{
    "success": true/false,
    "confidence": 0.0-1.0,
    "reasoning": "Brief explanation",
    "visual_evidence": "What you see",
    "suggested_next_action": "If failed, what to try next"
}}"""
        return prompt
    
    def _perform_llm_validation(
        self, 
        validation_prompt: str, 
        screenshot_path: str
    ) -> VerificationResult:
        """Perform LLM validation with structured output."""
        
        try:
            # Prepare messages for the LLM
            messages = [
                {
                    "role": "system",
                    "content": "You are a verification system for macOS automation. Analyze the current screen state and determine if a step was completed successfully."
                },
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": validation_prompt
                        }
                    ]
                }
            ]
            
            # Add screenshot if available
            if screenshot_path and os.path.exists(screenshot_path):
                with open(screenshot_path, 'rb') as f:
                    screenshot_data = f.read()
                    screenshot_base64 = base64.b64encode(screenshot_data).decode('utf-8')
                    
                    messages[1]["content"].append({
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/png;base64,{screenshot_base64}"
                        }
                    })
            
            # Call OpenAI with structured output using GPT-4o-mini (faster)
            response = self.client.chat.completions.create(
                model="gpt-4o-mini",
                messages=messages,
                response_format={"type": "json_object"},
                max_completion_tokens=300
            )
            
            # Parse the JSON response
            response_content = response.choices[0].message.content
            self.logger.debug(f"Raw LLM response: '{response_content}'")
            
            if not response_content or response_content.strip() == "":
                raise ValueError("Empty response from LLM")
            
            llm_response = json.loads(response_content)
            
            # Extract verification result
            success = llm_response.get("success", False)
            confidence = float(llm_response.get("confidence", 0.0))
            reasoning = llm_response.get("reasoning", "No reasoning provided")
            
            self.logger.info(f"Verification result: success={success}, confidence={confidence}")
            self.logger.debug(f"Reasoning: {reasoning}")
            
            return VerificationResult(
                success=success,
                confidence=confidence,
                reasoning=reasoning,
                llm_response=llm_response
            )
            
        except Exception as e:
            self.logger.error(f"Error during LLM validation: {e}")
            return VerificationResult(
                success=False,
                confidence=0.0,
                reasoning=f"Verification failed due to error: {e}",
                llm_response={
                    "success": False,
                    "confidence": 0.0,
                    "reasoning": f"Verification failed due to error: {e}",
                    "visual_evidence": "Error occurred during verification",
                    "suggested_next_action": "Retry the verification process"
                }
            )
    
    def should_retry_step(
        self, 
        verification_result: VerificationResult, 
        max_retries: int = 3
    ) -> Tuple[bool, str]:
        """
        Determine if a step should be retried based on verification result.
        
        Returns:
            Tuple of (should_retry, reason)
        """
        if verification_result.success:
            return False, "Step verified successfully"
        
        # Always retry if confidence is very low
        if verification_result.confidence < 0.3:
            return True, f"Low confidence ({verification_result.confidence}) - step likely failed"
        
        # Retry if confidence is moderate but step failed (more aggressive)
        if verification_result.confidence < 0.8:
            return True, f"Moderate confidence ({verification_result.confidence}) - step may have failed"
        
        # Retry for specific error conditions
        if "error" in verification_result.reasoning.lower():
            return True, "Error detected in verification"
        
        if "not found" in verification_result.reasoning.lower():
            return True, "Expected element not found"
        
        if "failed" in verification_result.reasoning.lower():
            return True, "Step explicitly marked as failed"
        
        # Retry for incomplete tasks (key indicators)
        if any(keyword in verification_result.reasoning.lower() for keyword in [
            "incomplete", "not finished", "didn't complete", "unfinished", 
            "not done", "still needs", "requires", "missing", "not sent",
            "not typed", "not clicked", "not focused", "no clear indicator"
        ]):
            return True, "Task appears incomplete based on verification"
        
        # Retry if the LLM suggests a next action (indicates current step didn't work)
        if verification_result.llm_response and "suggested_next_action" in verification_result.llm_response:
            suggested_action = verification_result.llm_response.get("suggested_next_action", "")
            if suggested_action and suggested_action.strip() and "try" in suggested_action.lower():
                return True, "LLM suggests retry action"
        
        # Default: retry if step didn't succeed (more aggressive approach)
        return True, "Step verification failed - retrying for completion"

    def analyze_state_and_suggest_plan(
        self,
        user_task: str,
        current_step: str,
        completed_actions: list,
        screenshot_path: str,
        run_dir: str
    ) -> Dict[str, Any]:
        """
        Analyze the current state and suggest plan updates based on what's observed.
        
        Args:
            user_task: The original user task
            current_step: Description of the current step being verified
            completed_actions: List of actions that have been completed
            screenshot_path: Path to the current screenshot
            run_dir: Directory for saving artifacts
            
        Returns:
            Dictionary with plan update suggestions
        """
        self.logger.info("Analyzing current state and suggesting plan updates")
        
        # Generate analysis prompt
        analysis_prompt = self._generate_state_analysis_prompt(
            user_task, current_step, completed_actions
        )
        
        # Perform LLM analysis
        analysis_result = self._perform_state_analysis(
            analysis_prompt, screenshot_path
        )
        
        return analysis_result

    def _generate_state_analysis_prompt(
        self,
        user_task: str,
        current_step: str,
        completed_actions: list
    ) -> str:
        """Generate a prompt for analyzing the current state and suggesting plan updates."""
        
        completed_summary = "\n".join([f"- {action}" for action in completed_actions[-5:]])  # Last 5 actions
        
        prompt = f"""
You are an AI assistant analyzing the current state of a macOS automation task and suggesting plan updates.

USER TASK: {user_task}
CURRENT STEP: {current_step}
RECENTLY COMPLETED ACTIONS:
{completed_summary}

Based on the current screenshot, analyze:
1. What has been accomplished so far
2. What still needs to be done to complete the user's task
3. Whether the current approach is working or if a different strategy is needed
4. What the next immediate actions should be

Consider:
- Is the task partially complete? What's missing?
- Are we on the right track or do we need to change approach?
- What specific actions would complete the task from the current state?
- Are there any obstacles or issues that need to be addressed?

Respond with a JSON object in this exact format:
{{
    "current_progress": "Description of what has been accomplished",
    "remaining_work": "What still needs to be done to complete the task",
    "task_completed": true/false,
    "completion_confidence": 0.0-1.0,
    "approach_working": true/false,
    "suggested_next_actions": [
        {{
            "action": "action_type",
            "description": "Detailed description of what to do",
            "priority": "high/medium/low"
        }}
    ],
    "plan_update_needed": true,
    "plan_update_reason": "Why the plan should be updated (if applicable)",
    "obstacles": ["List of any obstacles or issues encountered"],
    "confidence": 0.0-1.0
}}

Be specific and actionable in your suggestions.
"""
        return prompt

    def _perform_state_analysis(
        self,
        analysis_prompt: str,
        screenshot_path: str
    ) -> Dict[str, Any]:
        """Perform LLM analysis of current state and suggest plan updates."""
        
        try:
            # Prepare messages for the LLM
            messages = [
                {
                    "role": "system",
                    "content": "You are an AI assistant that analyzes the current state of macOS automation tasks and suggests plan updates based on visual evidence."
                },
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": analysis_prompt
                        }
                    ]
                }
            ]
            
            # Add screenshot if available
            if screenshot_path and os.path.exists(screenshot_path):
                with open(screenshot_path, 'rb') as f:
                    screenshot_data = f.read()
                    screenshot_base64 = base64.b64encode(screenshot_data).decode('utf-8')
                    
                    messages[1]["content"].append({
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/png;base64,{screenshot_base64}"
                        }
                    })
            
            # Call OpenAI with structured output
            response = self.client.chat.completions.create(
                model="gpt-4o-mini",
                messages=messages,
                response_format={"type": "json_object"},
                max_completion_tokens=500
            )
            
            # Parse the JSON response
            response_content = response.choices[0].message.content
            self.logger.debug(f"Raw LLM analysis response: '{response_content}'")
            
            if not response_content or response_content.strip() == "":
                raise ValueError("Empty response from LLM")
            
            analysis_result = json.loads(response_content)
            
            self.logger.info(f"State analysis completed with confidence: {analysis_result.get('confidence', 0.0)}")
            
            return analysis_result
            
        except Exception as e:
            self.logger.error(f"Error during state analysis: {e}")
            return {
                "current_progress": "Analysis failed",
                "remaining_work": "Unable to determine",
                "task_completed": False,
                "completion_confidence": 0.0,
                "approach_working": False,
                "suggested_next_actions": [],
                "plan_update_needed": True,
                "plan_update_reason": f"Analysis failed: {e}",
                "obstacles": ["Analysis error"],
                "confidence": 0.0
            }
