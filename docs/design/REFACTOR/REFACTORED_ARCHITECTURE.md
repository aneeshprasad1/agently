# Refactored Agently Architecture: Brain, Hands, and Eyes

## Overview

This document outlines the refactored architecture for Agently, moving from a distributed planning system to a clean separation of concerns with three main components:

- **Brain**: Planning loop, retry logic, prompting, and LLM orchestration (Python)
- **Hands**: Skills, actions, and execution (Swift)
- **Eyes**: Accessibility trees, screenshots, and UI observation (Swift)

The Brain component will use tool-use patterns to interact with Hands and Eyes, enabling all logic to be defined in prompts and eventually supporting multi-agent conversations via AutoGen.

## Current Architecture Problems

### 1. Distributed Planning Logic
- Planning logic is scattered across `main.swift`, `main.py`, and `planner.py`
- Retry logic and error recovery are mixed with execution logic
- Hard to maintain and extend planning strategies

### 2. Tight Coupling
- Swift and Python components are tightly coupled through JSON serialization
- Error handling and recovery logic is duplicated
- Difficult to test individual components in isolation

### 3. Limited Flexibility
- Planning strategies are hardcoded in Swift
- Difficult to implement complex reasoning chains
- No support for multi-agent conversations

## Proposed Architecture

### Component Separation

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│      Brain      │    │      Hands      │    │      Eyes       │
│    (Python)     │◄──►│     (Swift)     │◄──►│     (Swift)     │
│                 │    │                 │    │                 │
│ • Planning Loop │    │ • Skill Exec    │    │ • Accessibility │
│ • Retry Logic   │    │ • Action Types  │    │ • Screenshots   │
│ • LLM Prompts   │    │ • UI Control    │    │ • UI Graphs     │
│ • Tool Use      │    │ • Error Handling│    │ • Element Find  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### 1. Brain Component (Python)

#### Responsibilities
- **Planning Loop**: Orchestrates the entire task execution flow
- **Retry Logic**: Implements intelligent retry strategies with backoff
- **Prompting**: Manages all LLM interactions and prompt engineering
- **Tool Use**: Coordinates with Hands and Eyes through tool calls
- **Error Recovery**: Analyzes failures and generates recovery strategies
- **Multi-Agent Support**: Future integration with AutoGen for complex reasoning

#### Key Classes
```python
class AgentlyBrain:
    def __init__(self, llm_client, tools):
        self.llm_client = llm_client
        self.tools = tools  # Hands and Eyes tools
        self.conversation_logger = ConversationLogger()
    
    async def execute_task(self, task_description: str) -> TaskResult:
        """Main entry point for task execution"""
        
    async def planning_loop(self, task: str, context: Dict) -> ActionPlan:
        """Core planning loop with tool use"""
        
    async def execute_action_plan(self, plan: ActionPlan) -> ExecutionResult:
        """Execute actions using Hands tools"""
        
    async def observe_environment(self, context: Dict) -> ObservationResult:
        """Gather information using Eyes tools"""
        
    async def recover_from_error(self, error: ExecutionError) -> RecoveryPlan:
        """Generate and execute recovery strategies"""
```

#### Tool Use Pattern
```python
class ToolRegistry:
    def __init__(self):
        self.tools = {
            "click_element": ClickElementTool(),
            "type_text": TypeTextTool(),
            "take_screenshot": ScreenshotTool(),
            "find_element": FindElementTool(),
            "get_ui_graph": UIGraphTool(),
            "wait": WaitTool(),
            # ... more tools
        }
    
    async def execute_tool(self, tool_name: str, **kwargs):
        """Execute a tool and return results"""
```

### 2. Hands Component (Swift)

#### Responsibilities
- **Skill Execution**: Execute individual actions (click, type, scroll, etc.)
- **Action Types**: Define and implement all possible UI interactions
- **Error Handling**: Provide detailed error information for the Brain
- **UI Control**: Direct interaction with macOS accessibility APIs
- **Performance Monitoring**: Track execution metrics and timing

#### Key Classes
```swift
protocol SkillTool {
    var name: String { get }
    var description: String { get }
    func execute(parameters: [String: Any]) async throws -> SkillResult
}

class HandsOrchestrator {
    private let skills: [SkillTool]
    private let logger: Logger
    
    func executeSkill(_ skillName: String, parameters: [String: Any]) async throws -> SkillResult
    
    func getAvailableSkills() -> [SkillTool]
}

// Concrete skill implementations
class ClickElementSkill: SkillTool {
    func execute(parameters: [String: Any]) async throws -> SkillResult
}

class TypeTextSkill: SkillTool {
    func execute(parameters: [String: Any]) async throws -> SkillResult
}

class ScrollSkill: SkillTool {
    func execute(parameters: [String: Any]) async throws -> SkillResult
}
```

#### Skill Interface
```swift
struct SkillResult {
    let success: Bool
    let data: [String: Any]?
    let error: String?
    let executionTime: TimeInterval
    let metadata: [String: Any]
}
```

### 3. Eyes Component (Swift)

#### Responsibilities
- **Accessibility Trees**: Build and maintain UI element graphs
- **Screenshots**: Capture visual information when needed
- **Element Finding**: Locate UI elements based on various criteria
- **UI State Monitoring**: Track changes in the UI environment
- **Context Gathering**: Provide rich context for the Brain

#### Key Classes
```swift
protocol ObservationTool {
    var name: String { get }
    var description: String { get }
    func execute(parameters: [String: Any]) async throws -> ObservationResult
}

class EyesOrchestrator {
    private let tools: [ObservationTool]
    private let graphBuilder: AccessibilityGraphBuilder
    
    func observe(_ observationType: String, parameters: [String: Any]) async throws -> ObservationResult
    
    func getCurrentUIGraph() async throws -> UIGraph
    
    func findElements(matching criteria: ElementCriteria) async throws -> [UIElement]
}

// Concrete observation tools
class UIGraphTool: ObservationTool {
    func execute(parameters: [String: Any]) async throws -> ObservationResult
}

class ScreenshotTool: ObservationTool {
    func execute(parameters: [String: Any]) async throws -> ObservationResult
}

class FindElementTool: ObservationTool {
    func execute(parameters: [String: Any]) async throws -> ObservationResult
}
```

#### Observation Interface
```swift
struct ObservationResult {
    let data: [String: Any]
    let timestamp: Date
    let metadata: [String: Any]
}
```

## Communication Architecture

### 1. Tool Use Protocol

The Brain communicates with Hands and Eyes through a standardized tool use protocol:

```python
# Brain sends tool call
tool_call = {
    "tool": "click_element",
    "parameters": {
        "element_id": "elem_123",
        "position": "center"
    }
}

# Hands/Eyes respond with result
tool_result = {
    "success": True,
    "data": {"clicked_at": "2024-01-01T12:00:00Z"},
    "error": None,
    "execution_time": 0.15
}
```

### 2. HTTP API Interface

Hands and Eyes expose HTTP APIs that the Brain can call:

```
POST /api/hands/execute
{
    "skill": "click_element",
    "parameters": {...}
}

POST /api/eyes/observe
{
    "observation": "get_ui_graph",
    "parameters": {...}
}
```

### 3. WebSocket for Real-time Updates

For long-running operations and real-time feedback:

```
WebSocket: /ws/hands/status
WebSocket: /ws/eyes/updates
```

## Implementation Plan

### Phase 1: Core Separation
1. Extract Hands functionality from current Swift code
2. Extract Eyes functionality from current Swift code
3. Create HTTP API interfaces for both components
4. Implement basic Brain with tool use

### Phase 2: Tool Use Integration
1. Implement comprehensive tool registry
2. Create standardized tool interfaces
3. Implement error handling and recovery
4. Add comprehensive logging and monitoring

### Phase 3: Advanced Planning
1. Implement sophisticated retry logic
2. Add context-aware planning
3. Implement multi-step reasoning
4. Add AutoGen integration for multi-agent conversations

### Phase 4: Performance & Reliability
1. Add caching and optimization
2. Implement parallel execution where possible
3. Add comprehensive error recovery
4. Performance benchmarking and optimization

## Benefits of New Architecture

### 1. Separation of Concerns
- Clear boundaries between planning, execution, and observation
- Easier to test and debug individual components
- Better code organization and maintainability

### 2. Flexibility
- All logic can be defined in prompts
- Easy to add new skills and observation tools
- Support for complex reasoning chains

### 3. Scalability
- Components can be deployed independently
- Easy to add new Brain implementations
- Support for distributed execution

### 4. Maintainability
- Clear interfaces between components
- Easier to implement new features
- Better error handling and debugging

## Migration Strategy

### 1. Gradual Migration
- Start with new components alongside existing code
- Migrate functionality piece by piece
- Maintain backward compatibility during transition

### 2. Testing Strategy
- Unit tests for each component
- Integration tests for component interactions
- End-to-end tests for complete workflows

### 3. Rollback Plan
- Keep existing code as fallback
- Feature flags for new vs. old behavior
- Gradual rollout to users

## Future Enhancements

### 1. Multi-Agent Conversations
- AutoGen integration for complex reasoning
- Multiple specialized agents (planner, executor, observer)
- Agent-to-agent communication

### 2. Advanced Planning
- Hierarchical task decomposition
- Dynamic plan adjustment
- Learning from execution history

### 3. Performance Optimization
- Parallel execution of independent actions
- Caching of UI graphs and observations
- Predictive planning based on patterns

## Conclusion

This refactored architecture provides a clean separation of concerns while maintaining the flexibility to implement complex reasoning and multi-agent conversations. The tool-use pattern allows the Brain to orchestrate complex workflows while keeping the Hands and Eyes components focused on their specific responsibilities.

The migration can be done gradually, ensuring stability while improving the overall system architecture and capabilities.
