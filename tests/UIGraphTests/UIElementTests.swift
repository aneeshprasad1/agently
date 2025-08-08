import XCTest
@testable import UIGraph

final class UIElementTests: XCTestCase {
    
    func testUIElementCreation() {
        let element = UIElement(
            id: "test_1",
            role: "AXButton",
            title: "Click Me",
            label: "Submit Button",
            value: nil,
            position: CGPoint(x: 100, y: 200),
            size: CGSize(width: 80, height: 30),
            isEnabled: true,
            isFocused: false,
            children: [],
            parent: nil,
            applicationName: "TestApp"
        )
        
        XCTAssertEqual(element.id, "test_1")
        XCTAssertEqual(element.role, "AXButton")
        XCTAssertEqual(element.title, "Click Me")
        XCTAssertEqual(element.label, "Submit Button")
        XCTAssertEqual(element.position.x, 100)
        XCTAssertEqual(element.position.y, 200)
        XCTAssertEqual(element.size.width, 80)
        XCTAssertEqual(element.size.height, 30)
        XCTAssertTrue(element.isEnabled)
        XCTAssertFalse(element.isFocused)
        XCTAssertEqual(element.applicationName, "TestApp")
    }
    
    func testUIGraphCreation() {
        let button = UIElement(
            id: "button_1",
            role: "AXButton",
            title: "OK",
            position: CGPoint(x: 0, y: 0),
            size: CGSize(width: 50, height: 20),
            isEnabled: true,
            isFocused: false,
            applicationName: "TestApp"
        )
        
        let textField = UIElement(
            id: "text_1",
            role: "AXTextField",
            label: "Name",
            position: CGPoint(x: 0, y: 30),
            size: CGSize(width: 100, height: 20),
            isEnabled: true,
            isFocused: true,
            applicationName: "TestApp"
        )
        
        let elements = [
            "button_1": button,
            "text_1": textField
        ]
        
        let graph = UIGraph(
            elements: elements,
            rootElements: ["button_1", "text_1"],
            activeApplication: "TestApp"
        )
        
        XCTAssertEqual(graph.elements.count, 2)
        XCTAssertEqual(graph.rootElements.count, 2)
        XCTAssertEqual(graph.activeApplication, "TestApp")
        
        // Test element retrieval
        let retrievedButton = graph.element(withId: "button_1")
        XCTAssertNotNil(retrievedButton)
        XCTAssertEqual(retrievedButton?.title, "OK")
        
        // Test role filtering
        let buttons = graph.elements(withRole: "AXButton")
        XCTAssertEqual(buttons.count, 1)
        XCTAssertEqual(buttons.first?.id, "button_1")
        
        // Test text search
        let nameElements = graph.elements(containing: "name")
        XCTAssertEqual(nameElements.count, 1)
        XCTAssertEqual(nameElements.first?.id, "text_1")
    }
    
    func testUIElementCoding() throws {
        let element = UIElement(
            id: "test_1",
            role: "AXButton",
            title: "Test Button",
            position: CGPoint(x: 10, y: 20),
            size: CGSize(width: 100, height: 30),
            isEnabled: true,
            isFocused: false,
            applicationName: "TestApp"
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(element)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decodedElement = try decoder.decode(UIElement.self, from: data)
        
        XCTAssertEqual(element.id, decodedElement.id)
        XCTAssertEqual(element.role, decodedElement.role)
        XCTAssertEqual(element.title, decodedElement.title)
        XCTAssertEqual(element.position.x, decodedElement.position.x)
        XCTAssertEqual(element.size.width, decodedElement.size.width)
        XCTAssertEqual(element.isEnabled, decodedElement.isEnabled)
        XCTAssertEqual(element.applicationName, decodedElement.applicationName)
    }
}
