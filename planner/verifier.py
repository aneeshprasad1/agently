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
        run_dir: str
    ) -> VerificationResult:
        """
        Verify that a step was completed successfully.
        
        Args:
            step_description: Description of what the step should accomplish
            action_type: Type of action performed (e.g., 'click', 'type', 'key_press')
            action_description: Description of the action that was performed
            run_dir: Directory to save verification artifacts
            
        Returns:
            VerificationResult with success status and details
        """
        self.logger.info(f"Verifying step: {step_description}")
        
        # 1. Capture screenshot
        screenshot_path = self._capture_screenshot(run_dir)
        
        # 2. Generate validation prompt
        validation_prompt = self._generate_validation_prompt(
            step_description, action_type, action_description
        )
        
        # 3. Perform LLM validation with structured output
        verification_result = self._perform_llm_validation(
            validation_prompt, screenshot_path
        )
        
        # Add paths to result
        verification_result.screenshot_path = screenshot_path
        verification_result.ui_graph_path = None  # Not used
        verification_result.validation_prompt = validation_prompt
        
        return verification_result
    
    def _capture_screenshot(self, run_dir: str) -> str:
        """Capture a screenshot of the current screen and resize it for faster processing."""
        try:
            # Use macOS screencapture command
            timestamp = int(time.time())
            temp_screenshot_path = os.path.join(run_dir, f"temp_screenshot_{timestamp}.png")
            final_screenshot_path = os.path.join(run_dir, f"verification_screenshot_{timestamp}.png")
            
            # Capture screenshot
            result = subprocess.run([
                'screencapture', '-x', temp_screenshot_path
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
    
    def _resize_screenshot(self, input_path: str, output_path: str, max_width: int = 800, max_height: int = 600):
        """Resize screenshot to reduce file size while maintaining aspect ratio."""
        try:
            from PIL import Image
            
            with Image.open(input_path) as img:
                # Calculate new dimensions while maintaining aspect ratio
                width, height = img.size
                
                if width <= max_width and height <= max_height:
                    # Image is already small enough, just copy it
                    img.save(output_path, 'PNG', optimize=True, quality=85)
                    return
                
                # Calculate scaling factor
                scale = min(max_width / width, max_height / height)
                new_width = int(width * scale)
                new_height = int(height * scale)
                
                # Resize image
                resized_img = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
                
                # Save with compression
                resized_img.save(output_path, 'PNG', optimize=True, quality=85)
                
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
        
        prompt = f"""
You are a verification system for an AI agent that controls macOS applications. Your job is to verify whether a step was completed successfully.

STEP TO VERIFY: {step_description}
ACTION PERFORMED: {action_type} - {action_description}

Based on the current screenshot, determine if the step was completed successfully.

Consider:
1. What the step was supposed to accomplish
2. What action was actually performed
3. Whether the current screen state reflects successful completion
4. Any visual indicators that the step worked (new windows, changed UI elements, etc.)

Respond with a JSON object in this exact format:
{{
    "success": true/false,
    "confidence": 0.0-1.0,
    "reasoning": "Detailed explanation of why the step succeeded or failed",
    "visual_evidence": "Description of what you see that supports your conclusion",
    "suggested_next_action": "If failed, what should be tried next"
}}

Be strict but fair. If you're unsure, mark success as false and explain your uncertainty.
"""
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
            
            # Call OpenAI with structured output using GPT-5-mini
            response = self.client.chat.completions.create(
                model="gpt-5-mini",
                messages=messages,
                response_format={"type": "json_object"},
                max_completion_tokens=1000
            )
            
            # Parse the JSON response
            response_content = response.choices[0].message.content
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
                reasoning=f"Verification failed due to error: {e}"
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
        
        if verification_result.confidence < 0.3:
            return True, f"Low confidence ({verification_result.confidence}) - step likely failed"
        
        if "error" in verification_result.reasoning.lower():
            return True, "Error detected in verification"
        
        if "not found" in verification_result.reasoning.lower():
            return True, "Expected element not found"
        
        if "failed" in verification_result.reasoning.lower():
            return True, "Step explicitly marked as failed"
        
        # Default: don't retry if confidence is reasonable but step didn't succeed
        return False, "Step completed but verification inconclusive"
