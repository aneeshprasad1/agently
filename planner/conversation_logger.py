"""
Conversation logger for LLM interactions in Agently.
Handles detailed logging of LLM conversations to markdown files.
"""

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional


logger = logging.getLogger(__name__)


class ConversationLogger:
    """Handles detailed logging of LLM conversations to markdown files."""
    
    def __init__(self, log_dir: Optional[str] = None, model: str = "gpt-4o-mini", 
                 temperature: float = 0.1, max_tokens: int = 2000):
        """
        Initialize the conversation logger.
        
        Args:
            log_dir: Directory to save conversation logs
            model: LLM model name for metadata
            temperature: Temperature setting for metadata
            max_tokens: Max tokens setting for metadata
        """
        self.log_dir = log_dir
        self.model = model
        self.temperature = temperature
        self.max_tokens = max_tokens
        self.conversation_counter = 0
    
    def log_conversation(
        self, 
        conversation_type: str,
        messages: List[Dict[str, str]],
        response: Optional[str] = None,
        response_metadata: Optional[Dict] = None,
        error: Optional[str] = None,
        stage: str = "complete"
    ):
        """
        Log LLM conversation to a markdown file.
        
        Args:
            conversation_type: Type of conversation (e.g., "initial_planning", "error_recovery")
            messages: List of messages sent to the LLM
            response: LLM response content
            response_metadata: Metadata about the response (usage, model, etc.)
            error: Error message if the conversation failed
            stage: Stage of conversation ("request", "response", "error", "complete")
        """
        if not self.log_dir:
            return
            
        try:
            # Create conversation log directory
            conv_dir = Path(self.log_dir) / "llm_conversations"
            conv_dir.mkdir(parents=True, exist_ok=True)
            
            # Create filename with counter and type
            filename = f"{self.conversation_counter:02d}_{conversation_type}.md"
            filepath = conv_dir / filename
            
            # Prepare conversation log content
            timestamp = datetime.now().isoformat()
            
            if stage == "request":
                # Write the initial conversation
                with open(filepath, "w", encoding="utf-8") as f:
                    f.write(f"# LLM Conversation: {conversation_type}\n\n")
                    f.write(f"**Timestamp:** {timestamp}\n")
                    f.write(f"**Model:** {self.model}\n")
                    f.write(f"**Temperature:** {self.temperature}\n")
                    f.write(f"**Max Tokens:** {self.max_tokens}\n\n")
                    
                    # Write the messages
                    for i, message in enumerate(messages):
                        role = message["role"].title()
                        content = message["content"]
                        f.write(f"## {role} Message\n\n")
                        f.write(f"```\n{content}\n```\n\n")
            
            elif stage == "response" and response:
                # Append the response
                with open(filepath, "a", encoding="utf-8") as f:
                    f.write(f"## Assistant Response\n\n")
                    f.write(f"**Response Timestamp:** {timestamp}\n\n")
                    
                    if response_metadata:
                        f.write(f"**Response Metadata:**\n")
                        f.write(f"```json\n{json.dumps(response_metadata, indent=2)}\n```\n\n")
                    
                    f.write(f"**Content:**\n")
                    f.write(f"```\n{response}\n```\n\n")
                    f.write("---\n\n")
            
            elif stage == "error" and error:
                with open(filepath, "a", encoding="utf-8") as f:
                    f.write(f"## Error\n\n")
                    f.write(f"**Error Timestamp:** {timestamp}\n")
                    f.write(f"**Error:** {error}\n\n")
                    f.write("---\n\n")
            
            elif stage == "complete" and response:
                # Log complete conversation in one go (for backward compatibility)
                with open(filepath, "w", encoding="utf-8") as f:
                    f.write(f"# LLM Conversation: {conversation_type}\n\n")
                    f.write(f"**Timestamp:** {timestamp}\n")
                    f.write(f"**Model:** {self.model}\n")
                    f.write(f"**Temperature:** {self.temperature}\n")
                    f.write(f"**Max Tokens:** {self.max_tokens}\n\n")
                    
                    # Write the messages
                    for i, message in enumerate(messages):
                        role = message["role"].title()
                        content = message["content"]
                        f.write(f"## {role} Message\n\n")
                        f.write(f"```\n{content}\n```\n\n")
                    
                    # Write response
                    f.write(f"## Assistant Response\n\n")
                    if response_metadata:
                        f.write(f"**Response Metadata:**\n")
                        f.write(f"```json\n{json.dumps(response_metadata, indent=2)}\n```\n\n")
                    
                    f.write(f"**Content:**\n")
                    f.write(f"```\n{response}\n```\n\n")
                    f.write("---\n\n")
                    
        except Exception as e:
            logger.warning(f"Failed to log LLM conversation: {e}")
    
    def increment_counter(self):
        """Increment the conversation counter for the next conversation."""
        self.conversation_counter += 1
    
    def get_counter(self) -> int:
        """Get the current conversation counter."""
        return self.conversation_counter
