import Foundation
import UIGraph

/// Represents a high-level intent action
public struct SkillAction: Codable {
    public let type: ActionType
    public let targetElementId: String?
    public let parameters: [String: String]
    public let description: String
    
    public init(
        type: ActionType,
        targetElementId: String? = nil,
        parameters: [String: String] = [:],
        description: String
    ) {
        self.type = type
        self.targetElementId = targetElementId
        self.parameters = parameters
        self.description = description
    }
}

/// Types of actions the agent can perform
public enum ActionType: String, Codable, CaseIterable {
    case click = "click"
    case doubleClick = "double_click"
    case rightClick = "right_click"
    case type = "type"
    case keyPress = "key_press"
    case scroll = "scroll"
    case drag = "drag"
    case focus = "focus"
    case wait = "wait"
    case screenshot = "screenshot"
}

/// Result of executing a skill action
public struct SkillResult: Codable {
    public let success: Bool
    public let action: SkillAction
    public let errorMessage: String?
    public let executionTime: TimeInterval
    public let timestamp: Date
    
    public init(
        success: Bool,
        action: SkillAction,
        errorMessage: String? = nil,
        executionTime: TimeInterval,
        timestamp: Date = Date()
    ) {
        self.success = success
        self.action = action
        self.errorMessage = errorMessage
        self.executionTime = executionTime
        self.timestamp = timestamp
    }
}
