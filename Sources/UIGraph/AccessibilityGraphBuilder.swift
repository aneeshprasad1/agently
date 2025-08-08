import AppKit
import ApplicationServices
import Foundation
import Logging

/// Builds UI graphs from macOS accessibility APIs
public class AccessibilityGraphBuilder {
    private let logger = Logger(label: "AccessibilityGraphBuilder")
    private var elementIdCounter = 0
    
    public init() {}
    
    /// Build a complete UI graph of all accessible applications
    public func buildGraph() throws -> UIGraph {
        logger.info("Building accessibility graph")
        
        var elements: [String: UIElement] = [:]
        var rootElements: [String] = []
        
        // Get all running applications
        let runningApps = NSWorkspace.shared.runningApplications
        let activeApp = NSWorkspace.shared.frontmostApplication
        
        for app in runningApps {
            guard app.activationPolicy == .regular else { continue }
            
            do {
                let appElements = try buildGraphForApplication(app)
                for (id, element) in appElements {
                    elements[id] = element
                }
                
                // Find root elements for this app
                let appRoots = appElements.values.filter { $0.parent == nil }.map { $0.id }
                rootElements.append(contentsOf: appRoots)
                
            } catch {
                logger.warning("Failed to build graph for app \(app.localizedName ?? "unknown"): \(error)")
            }
        }
        
        logger.info("Built graph with \(elements.count) elements")
        
        return UIGraph(
            elements: elements,
            rootElements: rootElements,
            timestamp: Date(),
            activeApplication: activeApp?.localizedName
        )
    }
    
    /// Build UI graph for a specific application
    public func buildGraphForApplication(_ application: NSRunningApplication) throws -> [String: UIElement] {
        guard let pid = application.processIdentifier as pid_t? else {
            throw AccessibilityError.invalidApplication
        }
        
        let appRef = AXUIElementCreateApplication(pid)
        var elements: [String: UIElement] = [:]
        
        // Get all windows for this application
        var windowsRef: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard windowsResult == .success,
              let windowsArray = windowsRef as? [AXUIElement] else {
            throw AccessibilityError.noWindows
        }
        
        let appName = application.localizedName ?? "Unknown"
        
        for window in windowsArray {
            do {
                let windowElements = try buildElementTree(window, applicationName: appName, parent: nil)
                for (id, element) in windowElements {
                    elements[id] = element
                }
            } catch {
                logger.warning("Failed to process window: \(error)")
            }
        }
        
        return elements
    }
    
    /// Recursively build element tree starting from a given AXUIElement
    private func buildElementTree(
        _ axElement: AXUIElement,
        applicationName: String,
        parent: String?
    ) throws -> [String: UIElement] {
        
        var elements: [String: UIElement] = [:]
        let elementId = generateElementId()
        
        // Get basic properties
        let role = getStringAttribute(axElement, kAXRoleAttribute) ?? "Unknown"
        let title = getStringAttribute(axElement, kAXTitleAttribute)
        let label = getStringAttribute(axElement, kAXDescriptionAttribute)
        let value = getStringAttribute(axElement, kAXValueAttribute)
        
        // Get position and size
        let position = getPositionAttribute(axElement) ?? CGPoint.zero
        let size = getSizeAttribute(axElement) ?? CGSize.zero
        
        // Get state
        let isEnabled = getBoolAttribute(axElement, kAXEnabledAttribute) ?? false
        let isFocused = getBoolAttribute(axElement, kAXFocusedAttribute) ?? false
        
        // Get children
        var childIds: [String] = []
        var childrenRef: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(axElement, kAXChildrenAttribute as CFString, &childrenRef)
        
        if childrenResult == .success, let childrenArray = childrenRef as? [AXUIElement] {
            for child in childrenArray {
                do {
                    let childElements = try buildElementTree(child, applicationName: applicationName, parent: elementId)
                    for (id, element) in childElements {
                        elements[id] = element
                    }
                    
                    // Find the direct child ID (the one with parent == elementId)
                    if let childElement = childElements.values.first(where: { $0.parent == elementId }) {
                        childIds.append(childElement.id)
                    }
                } catch {
                    logger.debug("Skipping child element: \(error)")
                }
            }
        }
        
        // Create the UI element
        let element = UIElement(
            id: elementId,
            role: role,
            title: title,
            label: label,
            value: value,
            position: position,
            size: size,
            isEnabled: isEnabled,
            isFocused: isFocused,
            children: childIds,
            parent: parent,
            applicationName: applicationName
        )
        
        elements[elementId] = element
        
        return elements
    }
    
    // MARK: - Helper Methods
    
    private func generateElementId() -> String {
        elementIdCounter += 1
        return "element_\(elementIdCounter)"
    }
    
    private func getStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let stringValue = value as? String else { return nil }
        return stringValue
    }
    
    private func getBoolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let boolValue = value as? Bool else { return nil }
        return boolValue
    }
    
    private func getPositionAttribute(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value)
        guard result == .success else { return nil }
        
        var point = CGPoint.zero
        let success = AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return success ? point : nil
    }
    
    private func getSizeAttribute(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value)
        guard result == .success else { return nil }
        
        var size = CGSize.zero
        let success = AXValueGetValue(value as! AXValue, .cgSize, &size)
        return success ? size : nil
    }
}

// MARK: - Error Types

public enum AccessibilityError: Error, LocalizedError {
    case permissionDenied
    case invalidApplication
    case noWindows
    case elementNotFound
    case actionFailed
    
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Accessibility permission denied. Please grant accessibility access in System Settings."
        case .invalidApplication:
            return "Invalid application reference"
        case .noWindows:
            return "No accessible windows found"
        case .elementNotFound:
            return "UI element not found"
        case .actionFailed:
            return "Failed to perform accessibility action"
        }
    }
}
