import AppKit
import ApplicationServices
import Foundation
import Logging

/// Represents a UI element from the accessibility tree
public struct UIElement: Codable, Hashable {
    public let id: String
    public let role: String
    public let title: String?
    public let label: String?
    public let value: String?
    public let position: CGPoint
    public let size: CGSize
    public let isEnabled: Bool
    public let isFocused: Bool
    public let children: [String] // IDs of child elements
    public let parent: String? // ID of parent element
    public let applicationName: String
    
    public init(
        id: String,
        role: String,
        title: String? = nil,
        label: String? = nil,
        value: String? = nil,
        position: CGPoint,
        size: CGSize,
        isEnabled: Bool,
        isFocused: Bool,
        children: [String] = [],
        parent: String? = nil,
        applicationName: String
    ) {
        self.id = id
        self.role = role
        self.title = title
        self.label = label
        self.value = value
        self.position = position
        self.size = size
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.children = children
        self.parent = parent
        self.applicationName = applicationName
    }
}

/// Represents the complete UI graph at a point in time
public struct UIGraph: Codable {
    public let elements: [String: UIElement] // ID -> Element mapping
    public let rootElements: [String] // IDs of top-level elements
    public let timestamp: Date
    public let activeApplication: String?
    
    public init(
        elements: [String: UIElement],
        rootElements: [String],
        timestamp: Date = Date(),
        activeApplication: String? = nil
    ) {
        self.elements = elements
        self.rootElements = rootElements
        self.timestamp = timestamp
        self.activeApplication = activeApplication
    }
    
    /// Get element by ID
    public func element(withId id: String) -> UIElement? {
        return elements[id]
    }
    
    /// Get all child elements of a given element
    public func children(of element: UIElement) -> [UIElement] {
        return element.children.compactMap { elements[$0] }
    }
    
    /// Get parent element
    public func parent(of element: UIElement) -> UIElement? {
        guard let parentId = element.parent else { return nil }
        return elements[parentId]
    }
    
    /// Find elements by role
    public func elements(withRole role: String) -> [UIElement] {
        return elements.values.filter { $0.role == role }
    }
    
    /// Find elements by label or title containing text
    public func elements(containing text: String) -> [UIElement] {
        let lowercaseText = text.lowercased()
        return elements.values.filter { element in
            (element.label?.lowercased().contains(lowercaseText) == true) ||
            (element.title?.lowercased().contains(lowercaseText) == true) ||
            (element.value?.lowercased().contains(lowercaseText) == true)
        }
    }
}
