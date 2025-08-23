# Implementation Guide: Brain, Hands, and Eyes Architecture

## Overview

This document provides detailed implementation guidance for the refactored Agently architecture. It includes code examples, file structures, and step-by-step implementation details.

## Project Structure

```
agently/
├── brain/                          # Python Brain component
│   ├── __init__.py
│   ├── main.py                     # Entry point
│   ├── brain.py                    # Core brain implementation
│   ├── tool_registry.py            # Tool management
│   ├── planning_engine.py          # Planning logic
│   ├── retry_logic.py              # Retry strategies
│   └── tools/                      # Tool implementations
│       ├── __init__.py
│       ├── hands_tools.py          # Hands API client
│       └── eyes_tools.py           # Eyes API client
├── hands/                          # Swift Hands component
│   ├── Package.swift
│   ├── Sources/
│   │   └── Hands/
│   │       ├── main.swift          # HTTP server entry point
│   │       ├── HandsOrchestrator.swift
│   │       ├── Skills/
│   │       │   ├── SkillTool.swift
│   │       │   ├── ClickSkill.swift
│   │       │   ├── TypeSkill.swift
│   │       │   └── ScrollSkill.swift
│   │       └── API/
│   │           ├── Server.swift
│   │           └── Routes.swift
├── eyes/                           # Swift Eyes component
│   ├── Package.swift
│   ├── Sources/
│   │   └── Eyes/
│   │       ├── main.swift          # HTTP server entry point
│   │       ├── EyesOrchestrator.swift
│   │       ├── Tools/
│   │       │   ├── ObservationTool.swift
│   │       │   ├── UIGraphTool.swift
│   │       │   ├── ScreenshotTool.swift
│   │       │   └── FindElementTool.swift
│   │       └── API/
│   │           ├── Server.swift
│   │           └── Routes.swift
└── shared/                         # Shared types and utilities
    ├── types.py                    # Python type definitions
    └── swift/                      # Swift shared types
        └── SharedTypes.swift
```

## Phase 1: Core Separation

### 1.1 Extract Hands Component

#### HandsOrchestrator.swift
```swift
import Foundation
import Logging

public class HandsOrchestrator {
    private let skills: [String: SkillTool]
    private let logger: Logger
    
    public init() {
        self.logger = Logger(label: "HandsOrchestrator")
        self.skills = [
            "click_element": ClickSkill(),
            "type_text": TypeSkill(),
            "scroll": ScrollSkill(),
            "key_press": KeyPressSkill(),
            "wait": WaitSkill(),
            "screenshot": ScreenshotSkill()
        ]
    }
    
    public func executeSkill(_ skillName: String, parameters: [String: Any]) async throws -> SkillResult {
        guard let skill = skills[skillName] else {
            throw HandsError.unknownSkill(skillName)
        }
        
        logger.info("Executing skill: \(skillName) with parameters: \(parameters)")
        
        let startTime = Date()
        do {
            let result = try await skill.execute(parameters: parameters)
            let executionTime = Date().timeIntervalSince(startTime)
            
            return SkillResult(
                success: true,
                data: result,
                error: nil,
                executionTime: executionTime,
                metadata: ["skill": skillName]
            )
        } catch {
            let executionTime = Date().timeIntervalSince(startTime)
            logger.error("Skill execution failed: \(error)")
            
            return SkillResult(
                success: false,
                data: nil,
                error: error.localizedDescription,
                executionTime: executionTime,
                metadata: ["skill": skillName, "error": error.localizedDescription]
            )
        }
    }
    
    public func getAvailableSkills() -> [String: String] {
        return skills.mapValues { $0.description }
    }
}

public enum HandsError: Error, LocalizedError {
    case unknownSkill(String)
    case invalidParameters(String)
    case executionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .unknownSkill(let skill):
            return "Unknown skill: \(skill)"
        case .invalidParameters(let details):
            return "Invalid parameters: \(details)"
        case .executionFailed(let reason):
            return "Execution failed: \(reason)"
        }
    }
}
```

#### SkillTool Protocol
```swift
import Foundation

public protocol SkillTool {
    var name: String { get }
    var description: String { get }
    func execute(parameters: [String: Any]) async throws -> [String: Any]
}

public struct SkillResult: Codable {
    public let success: Bool
    public let data: [String: Any]?
    public let error: String?
    public let executionTime: TimeInterval
    public let metadata: [String: Any]
    
    public init(success: Bool, data: [String: Any]?, error: String?, executionTime: TimeInterval, metadata: [String: Any]) {
        self.success = success
        self.data = data
        self.error = error
        self.executionTime = executionTime
        self.metadata = metadata
    }
}
```

#### ClickSkill Implementation
```swift
import Foundation
import ApplicationServices

public class ClickSkill: SkillTool {
    public let name = "click_element"
    public let description = "Click on a UI element at the specified position"
    
    public func execute(parameters: [String: Any]) async throws -> [String: Any] {
        guard let elementId = parameters["element_id"] as? String else {
            throw HandsError.invalidParameters("element_id is required")
        }
        
        let position = parameters["position"] as? String ?? "center"
        
        // Implementation using existing SkillExecutor logic
        let action = SkillAction(
            type: .click,
            targetElementId: elementId,
            parameters: ["position": position],
            description: "Click element \(elementId) at \(position)"
        )
        
        let executor = SkillExecutor()
        let graph = try AccessibilityGraphBuilder().buildGraph()
        let result = executor.execute(action, in: graph)
        
        if !result.success {
            throw HandsError.executionFailed(result.errorMessage ?? "Unknown error")
        }
        
        return [
            "clicked_element": elementId,
            "position": position,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
    }
}
```

### 1.2 Extract Eyes Component

#### EyesOrchestrator.swift
```swift
import Foundation
import Logging
import UIGraph

public class EyesOrchestrator {
    private let tools: [String: ObservationTool]
    private let graphBuilder: AccessibilityGraphBuilder
    private let logger: Logger
    
    public init() {
        self.logger = Logger(label: "EyesOrchestrator")
        self.graphBuilder = AccessibilityGraphBuilder()
        self.tools = [
            "get_ui_graph": UIGraphTool(graphBuilder: graphBuilder),
            "take_screenshot": ScreenshotTool(),
            "find_element": FindElementTool(graphBuilder: graphBuilder),
            "get_element_info": ElementInfoTool(graphBuilder: graphBuilder)
        ]
    }
    
    public func observe(_ observationType: String, parameters: [String: Any]) async throws -> ObservationResult {
        guard let tool = tools[observationType] else {
            throw EyesError.unknownObservation(observationType)
        }
        
        logger.info("Executing observation: \(observationType) with parameters: \(parameters)")
        
        let startTime = Date()
        do {
            let data = try await tool.execute(parameters: parameters)
            let executionTime = Date().timeIntervalSince(startTime)
            
            return ObservationResult(
                data: data,
                timestamp: Date(),
                metadata: [
                    "observation_type": observationType,
                    "execution_time": executionTime
                ]
            )
        } catch {
            let executionTime = Date().timeIntervalSince(startTime)
            logger.error("Observation failed: \(error)")
            
            throw EyesError.observationFailed(observationType, error.localizedDescription)
        }
    }
    
    public func getCurrentUIGraph() async throws -> UIGraph {
        return try graphBuilder.buildGraph()
    }
    
    public func getAvailableObservations() -> [String: String] {
        return tools.mapValues { $0.description }
    }
}

public enum EyesError: Error, LocalizedError {
    case unknownObservation(String)
    case observationFailed(String, String)
    
    public var errorDescription: String? {
        switch self {
        case .unknownObservation(let observation):
            return "Unknown observation type: \(observation)"
        case .observationFailed(let observation, let reason):
            return "Observation \(observation) failed: \(reason)"
        }
    }
}
```

#### ObservationTool Protocol
```swift
import Foundation

public protocol ObservationTool {
    var name: String { get }
    var description: String { get }
    func execute(parameters: [String: Any]) async throws -> [String: Any]
}

public struct ObservationResult: Codable {
    public let data: [String: Any]
    public let timestamp: Date
    public let metadata: [String: Any]
    
    public init(data: [String: Any], timestamp: Date, metadata: [String: Any]) {
        self.data = data
        self.timestamp = timestamp
        self.metadata = metadata
    }
}
```

### 1.3 HTTP API Implementation

#### Hands Server
```swift
import Foundation
import Vapor

@main
struct HandsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    func configure(_ app: Application) throws {
        // Register routes
        try routes(app)
    }
}

func routes(_ app: Application) throws {
    let handsController = HandsController()
    
    app.post("api", "hands", "execute") { req -> EventLoopFuture<SkillResult> in
        let request = try req.content.decode(SkillExecutionRequest.self)
        return handsController.executeSkill(request, req: req)
    }
    
    app.get("api", "hands", "skills") { req -> EventLoopFuture<[String: String]> in
        return req.eventLoop.makeSucceededFuture(handsController.getAvailableSkills())
    }
}

struct SkillExecutionRequest: Content {
    let skill: String
    let parameters: [String: Any]
}

class HandsController {
    private let orchestrator = HandsOrchestrator()
    
    func executeSkill(_ request: SkillExecutionRequest, req: Request) -> EventLoopFuture<SkillResult> {
        return req.eventLoop.submit {
            try await self.orchestrator.executeSkill(request.skill, parameters: request.parameters)
        }
    }
    
    func getAvailableSkills() -> [String: String] {
        return orchestrator.getAvailableSkills()
    }
}
```

#### Eyes Server
```swift
import Foundation
import Vapor

@main
struct EyesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    func configure(_ app: Application) throws {
        try routes(app)
    }
}

func routes(_ app: Application) throws {
    let eyesController = EyesController()
    
    app.post("api", "eyes", "observe") { req -> EventLoopFuture<ObservationResult> in
        let request = try req.content.decode(ObservationRequest.self)
        return eyesController.observe(request, req: req)
    }
    
    app.get("api", "eyes", "observations") { req -> EventLoopFuture<[String: String]> in
        return req.eventLoop.makeSucceededFuture(eyesController.getAvailableObservations())
    }
}

struct ObservationRequest: Content {
    let observation: String
    let parameters: [String: Any]
}

class EyesController {
    private let orchestrator = EyesOrchestrator()
    
    func observe(_ request: ObservationRequest, req: Request) -> EventLoopFuture<ObservationResult> {
        return req.eventLoop.submit {
            try await self.orchestrator.observe(request.observation, parameters: request.parameters)
        }
    }
    
    func getAvailableObservations() -> [String: String] {
        return orchestrator.getAvailableObservations()
    }
}
```

## Phase 2: Brain Implementation

### 2.1 Core Brain Class

#### brain.py
```python
import asyncio
import logging
from typing import Dict, List, Optional, Any
from dataclasses import dataclass

from .tool_registry import ToolRegistry
from .planning_engine import PlanningEngine
from .retry_logic import RetryLogic
from .conversation_logger import ConversationLogger


@dataclass
class TaskResult:
    success: bool
    actions_executed: int
    total_time: float
    final_state: Dict[str, Any]
    errors: List[str]


class AgentlyBrain:
    def __init__(
        self,
        llm_client,
        hands_url: str = "http://localhost:8080",
        eyes_url: str = "http://localhost:8081",
        log_dir: Optional[str] = None
    ):
        self.llm_client = llm_client
        self.hands_url = hands_url
        self.eyes_url = eyes_url
        self.logger = logging.getLogger(__name__)
        
        # Initialize components
        self.tool_registry = ToolRegistry(hands_url, eyes_url)
        self.planning_engine = PlanningEngine(llm_client, self.tool_registry)
        self.retry_logic = RetryLogic()
        self.conversation_logger = ConversationLogger(log_dir)
    
    async def execute_task(self, task_description: str) -> TaskResult:
        """Main entry point for task execution"""
        self.logger.info(f"Starting task execution: {task_description}")
        
        start_time = asyncio.get_event_loop().time()
        executed_actions = 0
        errors = []
        
        try:
            # Initial observation
            context = await self._observe_environment()
            
            # Planning loop
            while True:
                # Generate plan
                plan = await self.planning_engine.generate_plan(task_description, context)
                
                if not plan.actions:
                    self.logger.info("No more actions to execute")
                    break
                
                # Execute actions
                for action in plan.actions:
                    try:
                        result = await self.tool_registry.execute_tool(
                            action["tool"],
                            **action["parameters"]
                        )
                        
                        if result["success"]:
                            executed_actions += 1
                            self.logger.info(f"Action executed successfully: {action['tool']}")
                        else:
                            errors.append(f"Action failed: {action['tool']} - {result.get('error', 'Unknown error')}")
                            
                            # Try recovery
                            recovery_plan = await self._recover_from_error(action, result, context)
                            if recovery_plan:
                                # Execute recovery actions
                                for recovery_action in recovery_plan.actions:
                                    await self.tool_registry.execute_tool(
                                        recovery_action["tool"],
                                        **recovery_action["parameters"]
                                    )
                    
                    except Exception as e:
                        errors.append(f"Action execution error: {action['tool']} - {str(e)}")
                        self.logger.error(f"Action execution failed: {e}")
                
                # Update context
                context = await self._observe_environment()
                
                # Check if task is complete
                if await self._is_task_complete(task_description, context):
                    break
        
        except Exception as e:
            errors.append(f"Task execution failed: {str(e)}")
            self.logger.error(f"Task execution failed: {e}")
        
        total_time = asyncio.get_event_loop().time() - start_time
        
        return TaskResult(
            success=len(errors) == 0,
            actions_executed=executed_actions,
            total_time=total_time,
            final_state=context,
            errors=errors
        )
    
    async def _observe_environment(self) -> Dict[str, Any]:
        """Gather current environment information"""
        try:
            # Get UI graph
            ui_graph = await self.tool_registry.execute_tool("get_ui_graph")
            
            # Take screenshot if needed
            screenshot = await self.tool_registry.execute_tool("take_screenshot")
            
            return {
                "ui_graph": ui_graph["data"],
                "screenshot": screenshot["data"],
                "timestamp": asyncio.get_event_loop().time()
            }
        except Exception as e:
            self.logger.error(f"Failed to observe environment: {e}")
            return {"error": str(e)}
    
    async def _recover_from_error(self, failed_action: Dict, error_result: Dict, context: Dict) -> Optional[Any]:
        """Generate recovery plan for failed action"""
        try:
            recovery_plan = await self.planning_engine.generate_recovery_plan(
                failed_action, error_result, context
            )
            return recovery_plan
        except Exception as e:
            self.logger.error(f"Failed to generate recovery plan: {e}")
            return None
    
    async def _is_task_complete(self, task_description: str, context: Dict) -> bool:
        """Check if the task has been completed"""
        try:
            completion_check = await self.planning_engine.check_task_completion(
                task_description, context
            )
            return completion_check["completed"]
        except Exception as e:
            self.logger.error(f"Failed to check task completion: {e}")
            return False
```

### 2.2 Tool Registry

#### tool_registry.py
```python
import aiohttp
import logging
from typing import Dict, Any, Optional


class ToolRegistry:
    def __init__(self, hands_url: str, eyes_url: str):
        self.hands_url = hands_url
        self.eyes_url = eyes_url
        self.logger = logging.getLogger(__name__)
        
        # Define available tools
        self.tools = {
            # Hands tools
            "click_element": {
                "url": f"{hands_url}/api/hands/execute",
                "method": "POST",
                "description": "Click on a UI element"
            },
            "type_text": {
                "url": f"{hands_url}/api/hands/execute",
                "method": "POST",
                "description": "Type text into a text field"
            },
            "scroll": {
                "url": f"{hands_url}/api/hands/execute",
                "method": "POST",
                "description": "Scroll in a specific direction"
            },
            
            # Eyes tools
            "get_ui_graph": {
                "url": f"{eyes_url}/api/eyes/observe",
                "method": "POST",
                "description": "Get current UI accessibility graph"
            },
            "take_screenshot": {
                "url": f"{eyes_url}/api/eyes/observe",
                "method": "POST",
                "description": "Take a screenshot of the current screen"
            },
            "find_element": {
                "url": f"{eyes_url}/api/eyes/observe",
                "method": "POST",
                "description": "Find UI elements matching criteria"
            }
        }
    
    async def execute_tool(self, tool_name: str, **kwargs) -> Dict[str, Any]:
        """Execute a tool and return results"""
        if tool_name not in self.tools:
            raise ValueError(f"Unknown tool: {tool_name}")
        
        tool_info = self.tools[tool_name]
        
        # Prepare request payload
        if tool_name.startswith("get_ui_graph") or tool_name.startswith("take_screenshot") or tool_name.startswith("find_element"):
            # Eyes tools
            payload = {
                "observation": tool_name,
                "parameters": kwargs
            }
            url = tool_info["url"]
        else:
            # Hands tools
            payload = {
                "skill": tool_name,
                "parameters": kwargs
            }
            url = tool_info["url"]
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(url, json=payload) as response:
                    if response.status == 200:
                        result = await response.json()
                        return result
                    else:
                        error_text = await response.text()
                        raise Exception(f"Tool execution failed: {response.status} - {error_text}")
        
        except Exception as e:
            self.logger.error(f"Failed to execute tool {tool_name}: {e}")
            raise
    
    def get_available_tools(self) -> Dict[str, str]:
        """Get list of available tools with descriptions"""
        return {name: info["description"] for name, info in self.tools.items()}
    
    def get_tool_schema(self, tool_name: str) -> Optional[Dict[str, Any]]:
        """Get schema for a specific tool"""
        if tool_name not in self.tools:
            return None
        
        # This could be enhanced with actual parameter schemas
        return {
            "name": tool_name,
            "description": self.tools[tool_name]["description"],
            "parameters": self._get_tool_parameters(tool_name)
        }
    
    def _get_tool_parameters(self, tool_name: str) -> Dict[str, Any]:
        """Get parameter schema for a tool"""
        # This would be more sophisticated in practice
        parameter_schemas = {
            "click_element": {
                "element_id": {"type": "string", "description": "ID of element to click"},
                "position": {"type": "string", "description": "Position to click (center, left, right, top, bottom)"}
            },
            "type_text": {
                "text": {"type": "string", "description": "Text to type"},
                "element_id": {"type": "string", "description": "ID of text field element"}
            },
            "get_ui_graph": {
                "include_screenshots": {"type": "boolean", "description": "Whether to include screenshots"}
            }
        }
        
        return parameter_schemas.get(tool_name, {})
```

### 2.3 Planning Engine

#### planning_engine.py
```python
import logging
from typing import Dict, List, Any, Optional
from dataclasses import dataclass


@dataclass
class ActionPlan:
    reasoning: str
    actions: List[Dict[str, Any]]
    confidence: float
    metadata: Optional[Dict[str, Any]] = None


class PlanningEngine:
    def __init__(self, llm_client, tool_registry):
        self.llm_client = llm_client
        self.tool_registry = tool_registry
        self.logger = logging.getLogger(__name__)
    
    async def generate_plan(self, task: str, context: Dict[str, Any]) -> ActionPlan:
        """Generate action plan using LLM and available tools"""
        try:
            # Build prompt with available tools
            tools_info = self.tool_registry.get_available_tools()
            tools_schema = self._build_tools_schema()
            
            prompt = self._build_planning_prompt(task, context, tools_info, tools_schema)
            
            # Call LLM
            response = await self._call_llm(prompt)
            
            # Parse response
            plan = self._parse_plan_response(response)
            
            return plan
        
        except Exception as e:
            self.logger.error(f"Failed to generate plan: {e}")
            return ActionPlan(
                reasoning=f"Planning failed: {str(e)}",
                actions=[],
                confidence=0.0
            )
    
    async def generate_recovery_plan(self, failed_action: Dict, error_result: Dict, context: Dict) -> Optional[ActionPlan]:
        """Generate recovery plan for failed action"""
        try:
            prompt = self._build_recovery_prompt(failed_action, error_result, context)
            response = await self._call_llm(prompt)
            plan = self._parse_plan_response(response)
            return plan
        
        except Exception as e:
            self.logger.error(f"Failed to generate recovery plan: {e}")
            return None
    
    async def check_task_completion(self, task: str, context: Dict[str, Any]) -> Dict[str, Any]:
        """Check if task has been completed"""
        try:
            prompt = self._build_completion_check_prompt(task, context)
            response = await self._call_llm(prompt)
            
            # Parse completion check response
            completion_result = self._parse_completion_response(response)
            return completion_result
        
        except Exception as e:
            self.logger.error(f"Failed to check task completion: {e}")
            return {"completed": False, "reason": str(e)}
    
    def _build_planning_prompt(self, task: str, context: Dict, tools_info: Dict, tools_schema: str) -> str:
        """Build prompt for action planning"""
        return f"""
You are an AI agent that can control a macOS system using various tools. Your task is to plan a sequence of actions to accomplish the given task.

TASK: {task}

CURRENT CONTEXT:
{self._format_context(context)}

AVAILABLE TOOLS:
{tools_schema}

INSTRUCTIONS:
1. Analyze the task and current context
2. Plan a sequence of actions using the available tools
3. Return your plan in the following JSON format:
{{
    "reasoning": "Your reasoning for the plan",
    "actions": [
        {{
            "tool": "tool_name",
            "parameters": {{"param1": "value1"}},
            "description": "What this action will do"
        }}
    ],
    "confidence": 0.8
}}

PLAN:
"""
    
    def _build_recovery_prompt(self, failed_action: Dict, error_result: Dict, context: Dict) -> str:
        """Build prompt for error recovery planning"""
        return f"""
An action has failed and you need to create a recovery plan.

FAILED ACTION: {failed_action}
ERROR: {error_result}

CURRENT CONTEXT:
{self._format_context(context)}

AVAILABLE TOOLS:
{self._build_tools_schema()}

Create a recovery plan that addresses the failure and continues toward the original goal.
Return your plan in the same JSON format as before.
"""
    
    def _build_completion_check_prompt(self, task: str, context: Dict) -> str:
        """Build prompt for checking task completion"""
        return f"""
Check if the following task has been completed based on the current context.

TASK: {task}

CURRENT CONTEXT:
{self._format_context(context)}

Return your assessment in JSON format:
{{
    "completed": true/false,
    "reason": "Explanation of why the task is or isn't complete",
    "evidence": "Specific evidence from the context"
}}
"""
    
    def _format_context(self, context: Dict) -> str:
        """Format context for prompt inclusion"""
        if "error" in context:
            return f"ERROR: {context['error']}"
        
        ui_graph = context.get("ui_graph", {})
        elements_count = len(ui_graph.get("elements", {}))
        active_app = ui_graph.get("activeApplication", "Unknown")
        
        return f"""
Active Application: {active_app}
UI Elements: {elements_count}
Screenshot: Available
Timestamp: {context.get('timestamp', 'Unknown')}
"""
    
    def _build_tools_schema(self) -> str:
        """Build tools schema for prompts"""
        tools = self.tool_registry.get_available_tools()
        schema_lines = []
        
        for tool_name, description in tools.items():
            params = self.tool_registry.get_tool_schema(tool_name)
            if params and "parameters" in params:
                param_desc = ", ".join([f"{k}: {v['type']}" for k, v in params["parameters"].items()])
                schema_lines.append(f"- {tool_name}: {description} (params: {param_desc})")
            else:
                schema_lines.append(f"- {tool_name}: {description}")
        
        return "\n".join(schema_lines)
    
    async def _call_llm(self, prompt: str) -> str:
        """Call the LLM with the given prompt"""
        # This would integrate with your actual LLM client
        # For now, return a placeholder
        return "{}"
    
    def _parse_plan_response(self, response: str) -> ActionPlan:
        """Parse LLM response into ActionPlan"""
        try:
            import json
            data = json.loads(response)
            
            return ActionPlan(
                reasoning=data.get("reasoning", ""),
                actions=data.get("actions", []),
                confidence=data.get("confidence", 0.5),
                metadata=data.get("metadata")
            )
        except Exception as e:
            self.logger.error(f"Failed to parse plan response: {e}")
            return ActionPlan(
                reasoning=f"Failed to parse response: {str(e)}",
                actions=[],
                confidence=0.0
            )
    
    def _parse_completion_response(self, response: str) -> Dict[str, Any]:
        """Parse completion check response"""
        try:
            import json
            return json.loads(response)
        except Exception as e:
            self.logger.error(f"Failed to parse completion response: {e}")
            return {"completed": False, "reason": f"Parse error: {str(e)}"}
```

## Phase 3: Integration and Testing

### 3.1 Main Entry Point

#### brain/main.py
```python
#!/usr/bin/env python3
"""
Main entry point for the Agently Brain component.
"""

import asyncio
import argparse
import logging
import os
from pathlib import Path

from .brain import AgentlyBrain
from .conversation_logger import ConversationLogger


def setup_logging(verbose: bool = False):
    """Setup logging configuration."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )


async def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Agently Brain')
    parser.add_argument('--task', required=True, help='Task description')
    parser.add_argument('--hands-url', default='http://localhost:8080', help='Hands service URL')
    parser.add_argument('--eyes-url', default='http://localhost:8081', help='Eyes service URL')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose logging')
    parser.add_argument('--log-dir', help='Directory to save conversation logs')
    
    args = parser.parse_args()
    
    setup_logging(args.verbose)
    logger = logging.getLogger(__name__)
    
    try:
        # Initialize brain
        brain = AgentlyBrain(
            llm_client=None,  # Replace with actual LLM client
            hands_url=args.hands_url,
            eyes_url=args.eyes_url,
            log_dir=args.log_dir
        )
        
        # Execute task
        logger.info(f"Starting task execution: {args.task}")
        result = await brain.execute_task(args.task)
        
        # Output results
        if result.success:
            logger.info(f"Task completed successfully in {result.total_time:.2f}s")
            logger.info(f"Executed {result.actions_executed} actions")
        else:
            logger.error(f"Task failed after {result.total_time:.2f}s")
            logger.error(f"Errors: {result.errors}")
        
        # Output JSON result
        import json
        print(json.dumps({
            "success": result.success,
            "actions_executed": result.actions_executed,
            "total_time": result.total_time,
            "errors": result.errors
        }, indent=2))
        
    except Exception as e:
        logger.error(f"Brain execution failed: {e}")
        raise


if __name__ == '__main__':
    asyncio.run(main())
```

### 3.2 Testing Strategy

#### Unit Tests
```python
# tests/test_brain.py
import pytest
from unittest.mock import Mock, AsyncMock
from brain.brain import AgentlyBrain
from brain.tool_registry import ToolRegistry


@pytest.fixture
def mock_llm_client():
    return Mock()


@pytest.fixture
def mock_tool_registry():
    registry = Mock(spec=ToolRegistry)
    registry.execute_tool = AsyncMock()
    return registry


@pytest.fixture
def brain(mock_llm_client, mock_tool_registry):
    return AgentlyBrain(
        llm_client=mock_llm_client,
        hands_url="http://localhost:8080",
        eyes_url="http://localhost:8081"
    )


@pytest.mark.asyncio
async def test_execute_task_success(brain, mock_tool_registry):
    """Test successful task execution"""
    # Mock tool responses
    mock_tool_registry.execute_tool.side_effect = [
        {"data": {"ui_graph": {"elements": {}}}},
        {"success": True, "data": {"clicked": True}},
        {"data": {"ui_graph": {"elements": {}}}},
    ]
    
    result = await brain.execute_task("Click the save button")
    
    assert result.success
    assert result.actions_executed > 0
    assert len(result.errors) == 0


@pytest.mark.asyncio
async def test_execute_task_with_error(brain, mock_tool_registry):
    """Test task execution with errors"""
    # Mock tool failure
    mock_tool_registry.execute_tool.side_effect = [
        {"data": {"ui_graph": {"elements": {}}}},
        {"success": False, "error": "Element not found"},
    ]
    
    result = await brain.execute_task("Click the save button")
    
    assert not result.success
    assert len(result.errors) > 0
```

## Next Steps

1. **Implement the basic Swift components** (Hands and Eyes)
2. **Set up HTTP servers** for both components
3. **Implement the Python Brain** with basic tool use
4. **Add comprehensive error handling** and retry logic
5. **Implement advanced planning** with context awareness
6. **Add AutoGen integration** for multi-agent conversations

This implementation provides a solid foundation for the refactored architecture while maintaining the flexibility to add more sophisticated features over time.
