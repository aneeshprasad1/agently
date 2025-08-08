import AppKit
import ApplicationServices
import Foundation
import Logging

/// Builds UI graphs from macOS accessibility APIs
public class AccessibilityGraphBuilder {
    private let logger = Logger(label: "AccessibilityGraphBuilder")
    private var elementIdCounter = 0
    
    // Performance configuration
    private let maxDepth: Int
    private let maxElements: Int
    private let timeoutSeconds: Double
    private let skipLargeContainers: Bool
    
    public init(maxDepth: Int = 10, maxElements: Int = 5000, timeoutSeconds: Double = 15.0, skipLargeContainers: Bool = true) {
        self.maxDepth = maxDepth
        self.maxElements = maxElements
        self.timeoutSeconds = timeoutSeconds
        self.skipLargeContainers = skipLargeContainers
    }
    
    /// Build a complete UI graph of all accessible applications
    public func buildGraph() throws -> UIGraph {
        logger.info("Building accessibility graph (max elements: \(maxElements), max depth: \(maxDepth), timeout: \(timeoutSeconds)s)")
        
        let startTime = Date()
        var elements: [String: UIElement] = [:]
        var rootElements: [String] = []
        
        // Get all running applications
        let runningApps = NSWorkspace.shared.runningApplications
        let activeApp = NSWorkspace.shared.frontmostApplication
        
        for app in runningApps {
            guard app.activationPolicy == .regular else { continue }
            
            // Check timeout
            if Date().timeIntervalSince(startTime) > timeoutSeconds {
                logger.warning("Graph building timed out after \(timeoutSeconds)s")
                break
            }
            
            // Check element count limit
            if elements.count >= maxElements {
                logger.warning("Reached max elements limit (\(maxElements))")
                break
            }
            
            do {
                let appElements = try buildGraphForApplication(app, remainingElements: maxElements - elements.count)
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
        
        let duration = Date().timeIntervalSince(startTime)
        logger.info("Built graph with \(elements.count) elements in \(String(format: "%.2f", duration))s")
        
        return UIGraph(
            elements: elements,
            rootElements: rootElements,
            timestamp: Date(),
            activeApplication: activeApp?.localizedName
        )
    }
    
    /// Build UI graph for a specific application
    public func buildGraphForApplication(_ application: NSRunningApplication, remainingElements: Int = Int.max) throws -> [String: UIElement] {
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
            // Check if we've hit our element limit
            if elements.count >= remainingElements {
                logger.info("Stopping window processing for \(appName) - reached element limit")
                break
            }
            
            do {
                let windowElements = try buildElementTree(window, applicationName: appName, parent: nil, depth: 0, remainingElements: remainingElements - elements.count)
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
        parent: String?,
        depth: Int = 0,
        remainingElements: Int = Int.max
    ) throws -> [String: UIElement] {
        
        // Check depth limit
        if depth >= maxDepth {
            return [:]
        }
        
        // Check element count limit
        if remainingElements <= 0 {
            return [:]
        }
        
        var elements: [String: UIElement] = [:]
        
        // Get basic properties first
        let role = getStringAttribute(axElement, kAXRoleAttribute) ?? "Unknown"
        let title = getStringAttribute(axElement, kAXTitleAttribute)
        let label = getStringAttribute(axElement, kAXDescriptionAttribute)
        let value = getStringAttribute(axElement, kAXValueAttribute)
        
        // Skip certain element types that are not useful for automation
        if shouldSkipElement(role: role, applicationName: applicationName, depth: depth) {
            return [:]
        }
        
        // Get position and size
        let position = getPositionAttribute(axElement) ?? CGPoint.zero
        let size = getSizeAttribute(axElement) ?? CGSize.zero
        
        // Generate stable ID based on properties
        let elementId = generateStableElementId(
            role: role,
            position: position,
            size: size,
            label: label,
            title: title,
            applicationName: applicationName,
            parent: parent
        )
        
        // Get state
        let isEnabled = getBoolAttribute(axElement, kAXEnabledAttribute) ?? false
        let isFocused = getBoolAttribute(axElement, kAXFocusedAttribute) ?? false
        
        // Get children
        var childIds: [String] = []
        var childrenRef: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(axElement, kAXChildrenAttribute as CFString, &childrenRef)
        
        var remainingForChildren = remainingElements - 1 // Reserve 1 for current element
        
        if childrenResult == .success, let childrenArray = childrenRef as? [AXUIElement] {
            // For large containers, limit the number of children processed
            let maxChildren = shouldLimitChildren(role: role, childCount: childrenArray.count) ? 50 : childrenArray.count
            let childrenToProcess = Array(childrenArray.prefix(maxChildren))
            
            if maxChildren < childrenArray.count {
                logger.debug("Limiting children for \(role) from \(childrenArray.count) to \(maxChildren)")
            }
            
            for child in childrenToProcess {
                if remainingForChildren <= 0 {
                    break
                }
                
                do {
                    let childElements = try buildElementTree(child, applicationName: applicationName, parent: elementId, depth: depth + 1, remainingElements: remainingForChildren)
                    for (id, element) in childElements {
                        elements[id] = element
                    }
                    
                    remainingForChildren -= childElements.count
                    
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
    
    /// Determine if an element should be skipped based on role and other factors
    private func shouldSkipElement(role: String, applicationName: String, depth: Int) -> Bool {
        // Skip purely decorative elements at deeper levels
        if depth > 3 {
            let decorativeRoles = ["AXImage", "AXStaticText"]
            if decorativeRoles.contains(role) {
                return true
            }
        }
        
        // Skip certain roles that are not useful for automation
        let skipRoles = ["AXUnknown"]
        return skipRoles.contains(role)
    }
    
    /// Determine if we should limit children for large containers
    private func shouldLimitChildren(role: String, childCount: Int) -> Bool {
        if !skipLargeContainers {
            return false
        }
        
        // Limit children for large scrollable areas and tables
        let largContainerRoles = ["AXScrollArea", "AXTable", "AXList", "AXOutline"]
        return largContainerRoles.contains(role) && childCount > 100
    }
    
    /// Generate a stable ID based on element properties
    private func generateStableElementId(
        role: String,
        position: CGPoint,
        size: CGSize,
        label: String?,
        title: String?,
        applicationName: String,
        parent: String?
    ) -> String {
        // Create a stable identifier based on element properties
        let components = [
            applicationName,
            role,
            String(format: "%.0f,%.0f", position.x, position.y),
            String(format: "%.0fx%.0f", size.width, size.height),
            label ?? "",
            title ?? "",
            parent ?? ""
        ]
        
        let combined = components.joined(separator: "|")
        let hash = combined.hashValue
        
        // Use absolute value to avoid negative hashes, and make it readable
        return "elem_\(abs(hash))"
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
