import AppKit
import ApplicationServices
import Foundation
import Logging
import UIGraph
import UniformTypeIdentifiers

/// Executes skill actions using macOS accessibility and event APIs
public class SkillExecutor {
    private let logger = Logger(label: "SkillExecutor")
    private let graphBuilder = AccessibilityGraphBuilder()
    
    public init() {}
    
    /// Execute a skill action
    public func execute(_ action: SkillAction, in graph: UIGraph) -> SkillResult {
        let startTime = Date()
        
        logger.info("Executing action: \(action.type.rawValue) - \(action.description)")
        
        do {
            try performAction(action, in: graph)
            let executionTime = Date().timeIntervalSince(startTime)
            
            logger.info("Action completed successfully in \(String(format: "%.3f", executionTime))s")
            
            return SkillResult(
                success: true,
                action: action,
                executionTime: executionTime
            )
            
        } catch {
            let executionTime = Date().timeIntervalSince(startTime)
            let errorMessage = error.localizedDescription
            
            logger.error("Action failed: \(errorMessage)")
            
            return SkillResult(
                success: false,
                action: action,
                errorMessage: errorMessage,
                executionTime: executionTime
            )
        }
    }
    
    // MARK: - Action Implementation
    
    private func performAction(_ action: SkillAction, in graph: UIGraph) throws {
        switch action.type {
        case .click:
            try performClick(action, in: graph)
        case .doubleClick:
            try performDoubleClick(action, in: graph)
        case .rightClick:
            try performRightClick(action, in: graph)
        case .type:
            try performType(action)
        case .keyPress:
            try performKeyPress(action)
        case .scroll:
            try performScroll(action)
        case .drag:
            try performDrag(action, in: graph)
        case .focus:
            try performFocus(action, in: graph)
        case .wait:
            try performWait(action)
        case .screenshot:
            try performScreenshot(action)
        }
    }
    
    private func performClick(_ action: SkillAction, in graph: UIGraph) throws {
        guard let elementId = action.targetElementId,
              let element = graph.element(withId: elementId) else {
            throw SkillError.elementNotFound
        }
        
        let clickPoint = CGPoint(
            x: element.position.x + element.size.width / 2,
            y: element.position.y + element.size.height / 2
        )
        
        // If this is an application element that should bring the app to front, activate it first
        if shouldActivateApplication(for: element) {
            try activateApplication(element.applicationName)
        }
        
        // Try accessibility action first
        if let axElement = try? findAXElement(for: element) {
            let result = AXUIElementPerformAction(axElement, kAXPressAction as CFString)
            if result == .success {
                return
            }
        }
        
        // Fallback to CGEvent
        try performMouseClick(at: clickPoint)
    }
    
    private func performDoubleClick(_ action: SkillAction, in graph: UIGraph) throws {
        guard let elementId = action.targetElementId,
              let element = graph.element(withId: elementId) else {
            throw SkillError.elementNotFound
        }
        
        let clickPoint = CGPoint(
            x: element.position.x + element.size.width / 2,
            y: element.position.y + element.size.height / 2
        )
        
        try performMouseClick(at: clickPoint, clickCount: 2)
    }
    
    private func performRightClick(_ action: SkillAction, in graph: UIGraph) throws {
        guard let elementId = action.targetElementId,
              let element = graph.element(withId: elementId) else {
            throw SkillError.elementNotFound
        }
        
        let clickPoint = CGPoint(
            x: element.position.x + element.size.width / 2,
            y: element.position.y + element.size.height / 2
        )
        
        try performMouseClick(at: clickPoint, button: .right)
    }
    
    private func performType(_ action: SkillAction) throws {
        guard let text = action.parameters["text"] else {
            throw SkillError.missingParameter("text")
        }
        
        for character in text {
            let keyCode = try keyCodeForCharacter(character)
            try sendKeyEvent(keyCode: keyCode)
            
            // Small delay between characters for reliability
            usleep(10_000) // 10ms
        }
    }
    
    private func performKeyPress(_ action: SkillAction) throws {
        guard let keyName = action.parameters["key"] else {
            throw SkillError.missingParameter("key")
        }
        
        // Handle compound keys like "Command+Space"
        if keyName.contains("+") {
            let components = keyName.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
            guard components.count >= 2 else {
                throw SkillError.unsupportedKey(keyName)
            }
            
            // Last component is the main key, everything else are modifiers
            let mainKey = String(components.last!)
            let modifierStrings = components.dropLast()
            
            let keyCode = try keyCodeForKeyName(mainKey)
            let modifiers = parseModifiersFromStrings(Array(modifierStrings))
            
            try sendKeyEvent(keyCode: keyCode, modifiers: modifiers)
        } else {
            // Original behavior: separate key and modifiers parameters
            let keyCode = try keyCodeForKeyName(keyName)
            let modifiers = parseModifiers(action.parameters["modifiers"])
            
            try sendKeyEvent(keyCode: keyCode, modifiers: modifiers)
        }
    }
    
    private func performScroll(_ action: SkillAction) throws {
        guard let deltaYString = action.parameters["deltaY"],
              let deltaY = Int(deltaYString) else {
            throw SkillError.missingParameter("deltaY")
        }
        
        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(deltaY),
            wheel2: 0,
            wheel3: 0
        )
        
        scrollEvent?.post(tap: .cghidEventTap)
    }
    
    private func performDrag(_ action: SkillAction, in graph: UIGraph) throws {
        // Implement drag operation between two points
        throw SkillError.notImplemented("Drag action not yet implemented")
    }
    
    private func performFocus(_ action: SkillAction, in graph: UIGraph) throws {
        guard let elementId = action.targetElementId,
              let element = graph.element(withId: elementId) else {
            throw SkillError.elementNotFound
        }
        
        // If this is an application element that should bring the app to front, activate it first
        if shouldActivateApplication(for: element) {
            try activateApplication(element.applicationName)
        }
        
        // Try accessibility action first
        if let axElement = try? findAXElement(for: element) {
            let result = AXUIElementPerformAction(axElement, "AXFocus" as CFString)
            if result == AXError.success {
                return
            }
        }
        
        // Fallback: focus by clicking on the element
        let clickPoint = CGPoint(
            x: element.position.x + element.size.width / 2,
            y: element.position.y + element.size.height / 2
        )
        try performMouseClick(at: clickPoint)
    }
    
    private func performWait(_ action: SkillAction) throws {
        guard let durationString = action.parameters["duration"],
              let duration = TimeInterval(durationString) else {
            throw SkillError.missingParameter("duration")
        }
        
        Thread.sleep(forTimeInterval: duration)
    }
    
    private func performScreenshot(_ action: SkillAction) throws {
        // Take a screenshot for debugging/logging purposes
        let screenshot = CGWindowListCreateImage(
            CGRect.infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        )
        
        // Save to tmp directory with timestamp
        if let screenshot = screenshot {
            let timestamp = Int(Date().timeIntervalSince1970)
            let url = URL(fileURLWithPath: "/tmp/agently_screenshot_\(timestamp).png")
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
            
            if let destination = destination {
                CGImageDestinationAddImage(destination, screenshot, nil)
                CGImageDestinationFinalize(destination)
                logger.info("Screenshot saved to \(url.path)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func performMouseClick(at point: CGPoint, button: CGMouseButton = .left, clickCount: Int = 1) throws {
        let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: button == .left ? .leftMouseDown : .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: button
        )
        
        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: button == .left ? .leftMouseUp : .rightMouseUp,
            mouseCursorPosition: point,
            mouseButton: button
        )
        
        mouseDown?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        mouseUp?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        
        mouseDown?.post(tap: .cghidEventTap)
        usleep(50_000) // 50ms delay
        mouseUp?.post(tap: .cghidEventTap)
        
        if clickCount == 2 {
            usleep(100_000) // Additional delay for double click
        }
    }
    
    // MARK: - Application Activation
    
    private func shouldActivateApplication(for element: UIElement) -> Bool {
        // Disable automatic app activation since we're using Spotlight for app launching
        // This prevents hanging on AppleScript activation
        return false
    }
    
    private func activateApplication(_ appName: String) throws {
        logger.info("Attempting to activate application: \(appName)")
        
        // Method 1: Use AppleScript for reliable activation
        let script = """
            tell application "\(appName)"
                activate
                delay 0.5
            end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var errorDict: NSDictionary?
            let result = appleScript.executeAndReturnError(&errorDict)
            
            if errorDict == nil {
                logger.info("Successfully activated application via AppleScript: \(appName)")
                // Give extra time for the app to fully come to foreground
                usleep(750_000) // 750ms delay
                return
            } else {
                logger.debug("AppleScript activation failed: \(errorDict ?? [:])")
            }
        }
        
        // Method 2: Fallback to NSRunningApplication
        let runningApps = NSWorkspace.shared.runningApplications
        guard let app = runningApps.first(where: { $0.localizedName == appName }) else {
            logger.warning("Application \(appName) not found in running applications")
            return
        }
        
        let success = app.activate(options: [.activateAllWindows])
        if success {
            logger.info("Successfully activated application via NSRunningApplication: \(appName)")
            usleep(500_000) // 500ms delay
        } else {
            logger.warning("Failed to activate application: \(appName)")
        }
    }
    
    private func sendKeyEvent(keyCode: CGKeyCode, modifiers: CGEventFlags = []) throws {
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        
        keyDown?.flags = modifiers
        keyUp?.flags = modifiers
        
        keyDown?.post(tap: .cghidEventTap)
        usleep(50_000) // 50ms delay
        keyUp?.post(tap: .cghidEventTap)
    }
    
    private func findAXElement(for element: UIElement) throws -> AXUIElement? {
        // This is a simplified implementation
        // In practice, we'd need to maintain a mapping between UIElements and AXUIElements
        // or rebuild the AX tree to find the matching element
        throw SkillError.notImplemented("AXElement lookup not yet implemented")
    }
    
    private func keyCodeForCharacter(_ character: Character) throws -> CGKeyCode {
        // Basic character to keycode mapping
        switch character.lowercased().first {
        case "a": return 0x00
        case "s": return 0x01
        case "d": return 0x02
        case "f": return 0x03
        case "h": return 0x04
        case "g": return 0x05
        case "z": return 0x06
        case "x": return 0x07
        case "c": return 0x08
        case "v": return 0x09
        case "b": return 0x0B
        case "q": return 0x0C
        case "w": return 0x0D
        case "e": return 0x0E
        case "r": return 0x0F
        case "y": return 0x10
        case "t": return 0x11
        case "1": return 0x12
        case "2": return 0x13
        case "3": return 0x14
        case "4": return 0x15
        case "6": return 0x16
        case "5": return 0x17
        case "=": return 0x18
        case "9": return 0x19
        case "7": return 0x1A
        case "-": return 0x1B
        case "8": return 0x1C
        case "0": return 0x1D
        case "]": return 0x1E
        case "o": return 0x1F
        case "u": return 0x20
        case "[": return 0x21
        case "i": return 0x22
        case "p": return 0x23
        case "l": return 0x25
        case "j": return 0x26
        case "'": return 0x27
        case "k": return 0x28
        case ";": return 0x29
        case "\\": return 0x2A
        case ",": return 0x2B
        case "/": return 0x2C
        case "n": return 0x2D
        case "m": return 0x2E
        case ".": return 0x2F
        case " ": return 0x31
        default:
            throw SkillError.unsupportedCharacter(character)
        }
    }
    
    private func keyCodeForKeyName(_ keyName: String) throws -> CGKeyCode {
        switch keyName.lowercased() {
        case "return", "enter": return 0x24
        case "tab": return 0x30
        case "space": return 0x31
        case "delete", "backspace": return 0x33
        case "escape": return 0x35
        case "command", "cmd": return 0x37
        case "shift": return 0x38
        case "capslock": return 0x39
        case "option", "alt": return 0x3A
        case "control", "ctrl": return 0x3B
        case "up": return 0x7E
        case "down": return 0x7D
        case "left": return 0x7B
        case "right": return 0x7C
        
        // Alphabet letters (for keyboard shortcuts like Command+N)
        case "a": return 0x00
        case "b": return 0x0B
        case "c": return 0x08
        case "d": return 0x02
        case "e": return 0x0E
        case "f": return 0x03
        case "g": return 0x05
        case "h": return 0x04
        case "i": return 0x22
        case "j": return 0x26
        case "k": return 0x28
        case "l": return 0x25
        case "m": return 0x2E
        case "n": return 0x2D
        case "o": return 0x1F
        case "p": return 0x23
        case "q": return 0x0C
        case "r": return 0x0F
        case "s": return 0x01
        case "t": return 0x11
        case "u": return 0x20
        case "v": return 0x09
        case "w": return 0x0D
        case "x": return 0x07
        case "y": return 0x10
        case "z": return 0x06
        
        // Numbers (for keyboard shortcuts)
        case "0": return 0x1D
        case "1": return 0x12
        case "2": return 0x13
        case "3": return 0x14
        case "4": return 0x15
        case "5": return 0x17
        case "6": return 0x16
        case "7": return 0x1A
        case "8": return 0x1C
        case "9": return 0x19
        
        default:
            throw SkillError.unsupportedKey(keyName)
        }
    }
    
    private func parseModifiers(_ modifierString: String?) -> CGEventFlags {
        guard let modifierString = modifierString else { return [] }
        
        var flags: CGEventFlags = []
        let modifiers = modifierString.lowercased().split(separator: "+")
        
        for modifier in modifiers {
            switch modifier.trimmingCharacters(in: .whitespaces) {
            case "command", "cmd":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "option", "alt":
                flags.insert(.maskAlternate)
            case "control", "ctrl":
                flags.insert(.maskControl)
            default:
                break
            }
        }
        
        return flags
    }
    
    private func parseModifiersFromStrings(_ modifierStrings: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        
        for modifier in modifierStrings {
            switch modifier.lowercased().trimmingCharacters(in: .whitespaces) {
            case "command", "cmd":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "option", "alt":
                flags.insert(.maskAlternate)
            case "control", "ctrl":
                flags.insert(.maskControl)
            default:
                break
            }
        }
        
        return flags
    }
}

// MARK: - Error Types

public enum SkillError: Error, LocalizedError {
    case elementNotFound
    case missingParameter(String)
    case actionFailed(String)
    case unsupportedCharacter(Character)
    case unsupportedKey(String)
    case notImplemented(String)
    
    public var errorDescription: String? {
        switch self {
        case .elementNotFound:
            return "Target UI element not found"
        case .missingParameter(let param):
            return "Missing required parameter: \(param)"
        case .actionFailed(let message):
            return "Action failed: \(message)"
        case .unsupportedCharacter(let char):
            return "Unsupported character: \(char)"
        case .unsupportedKey(let key):
            return "Unsupported key: \(key)"
        case .notImplemented(let feature):
            return "Not implemented: \(feature)"
        }
    }
}
