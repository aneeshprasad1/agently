import Foundation
import UIGraph

/// Parser for computer_13 action format
public class Computer13ActionParser {
    
    /// Parse a computer_13 action string into a SkillAction
    /// - Parameter actionString: Action in computer_13 format (e.g., "click(elem_123)", "type(field, \"text\")")
    /// - Returns: Parsed SkillAction
    public static func parse(_ actionString: String) -> SkillAction? {
        let trimmed = actionString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle different action patterns
        if let action = parseClickAction(trimmed) { return action }
        if let action = parseTypeAction(trimmed) { return action }
        if let action = parseKeyPressAction(trimmed) { return action }
        if let action = parseWaitAction(trimmed) { return action }
        if let action = parseScrollAction(trimmed) { return action }
        if let action = parseFocusAction(trimmed) { return action }
        if let action = parseNavigateAction(trimmed) { return action }
        
        return nil
    }
    
    // MARK: - Action Parsers
    
    private static func parseClickAction(_ action: String) -> SkillAction? {
        let patterns = [
            #"^click\(([^)]+)\)$"#,           // click(element_id)
            #"^double_click\(([^)]+)\)$"#,     // double_click(element_id)
            #"^right_click\(([^)]+)\)$"#       // right_click(element_id)
        ]
        
        for (index, pattern) in patterns.enumerated() {
            if let match = action.range(of: pattern, options: .regularExpression) {
                let elementId = String(action[match]).replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
                let actionType: ActionType = index == 0 ? .click : (index == 1 ? .doubleClick : .rightClick)
                
                return SkillAction(
                    actionString: action,
                    actionType: actionType,
                    targetElementId: elementId,
                    parameters: [:],
                    description: "\(actionType.rawValue) on \(elementId)"
                )
            }
        }
        
        return nil
    }
    
    private static func parseTypeAction(_ action: String) -> SkillAction? {
        // type(element_id, "text") or type(element_id, 'text')
        let pattern = #"^type\(([^,]+),\s*["']([^"']+)["']\)$"#
        
        if let match = action.range(of: pattern, options: .regularExpression) {
            let elementId = String(action[match]).replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
            let text = String(action[match]).replacingOccurrences(of: pattern, with: "$2", options: .regularExpression)
            
            return SkillAction(
                actionString: action,
                actionType: .type,
                targetElementId: elementId,
                parameters: ["text": text],
                description: "Type '\(text)' into \(elementId)"
            )
        }
        
        return nil
    }
    
    private static func parseKeyPressAction(_ action: String) -> SkillAction? {
        // key_press("key") or key_press('key')
        let pattern = #"^key_press\(["']([^"']+)["']\)$"#
        
        if let match = action.range(of: pattern, options: .regularExpression) {
            let key = String(action[match]).replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
            
            return SkillAction(
                actionString: action,
                actionType: .keyPress,
                targetElementId: nil,
                parameters: ["key": key],
                description: "Press key: \(key)"
            )
        }
        
        return nil
    }
    
    private static func parseWaitAction(_ action: String) -> SkillAction? {
        // wait("seconds") or wait('seconds')
        let pattern = #"^wait\(["']([^"']+)["']\)$"#
        
        if let match = action.range(of: pattern, options: .regularExpression) {
            let duration = String(action[match]).replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
            
            return SkillAction(
                actionString: action,
                actionType: .wait,
                targetElementId: nil,
                parameters: ["duration": duration],
                description: "Wait for \(duration) seconds"
            )
        }
        
        return nil
    }
    
    private static func parseScrollAction(_ action: String) -> SkillAction? {
        // scroll("direction") or scroll('direction')
        let pattern = #"^scroll\(["']([^"']+)["']\)$"#
        
        if let match = action.range(of: pattern, options: .regularExpression) {
            let direction = String(action[match]).replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
            
            // Convert direction to deltaY for our scroll implementation
            let deltaY: String
            switch direction.lowercased() {
            case "up": deltaY = "-100"
            case "down": deltaY = "100"
            case "left": deltaY = "-100"
            case "right": deltaY = "100"
            default: deltaY = "100"
            }
            
            return SkillAction(
                actionString: action,
                actionType: .scroll,
                targetElementId: nil,
                parameters: ["deltaY": deltaY],
                description: "Scroll \(direction)"
            )
        }
        
        return nil
    }
    
    private static func parseFocusAction(_ action: String) -> SkillAction? {
        // focus(element_id)
        let pattern = #"^focus\(([^)]+)\)$"#
        
        if let match = action.range(of: pattern, options: .regularExpression) {
            let elementId = String(action[match]).replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
            
            return SkillAction(
                actionString: action,
                actionType: .focus,
                targetElementId: elementId,
                parameters: [:],
                description: "Focus on \(elementId)"
            )
        }
        
        return nil
    }
    
    private static func parseNavigateAction(_ action: String) -> SkillAction? {
        // navigate("direction")
        let pattern = #"^navigate\("([^"]+)"\)$"#
        
        if let match = action.range(of: pattern, options: .regularExpression) {
            let direction = String(action[match]).replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
            
            // For now, treat navigate as a key press for arrow keys
            let key: String
            switch direction.lowercased() {
            case "up": key = "Up"
            case "down": key = "Down"
            case "left": key = "Left"
            case "right": key = "Right"
            default: key = "Down"
            }
            
            return SkillAction(
                actionString: action,
                actionType: .keyPress,
                targetElementId: nil,
                parameters: ["key": key],
                description: "Navigate \(direction)"
            )
        }
        
        return nil
    }
}
