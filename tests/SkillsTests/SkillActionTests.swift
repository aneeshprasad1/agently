import XCTest
@testable import Skills

final class SkillActionTests: XCTestCase {
    
    func testSkillActionCreation() {
        let action = SkillAction(
            type: .click,
            targetElementId: "button_1",
            parameters: ["x": "100", "y": "200"],
            description: "Click the submit button"
        )
        
        XCTAssertEqual(action.type, .click)
        XCTAssertEqual(action.targetElementId, "button_1")
        XCTAssertEqual(action.parameters["x"], "100")
        XCTAssertEqual(action.parameters["y"], "200")
        XCTAssertEqual(action.description, "Click the submit button")
    }
    
    func testActionTypeCases() {
        let allTypes: [ActionType] = [
            .click, .doubleClick, .rightClick, .type, .keyPress,
            .scroll, .drag, .focus, .wait, .screenshot
        ]
        
        // Test that all action types can be created
        for type in allTypes {
            let action = SkillAction(
                type: type,
                description: "Test \(type.rawValue) action"
            )
            XCTAssertEqual(action.type, type)
        }
    }
    
    func testSkillActionCoding() throws {
        let action = SkillAction(
            type: .type,
            targetElementId: "text_field_1",
            parameters: ["text": "Hello World", "clear_first": "true"],
            description: "Type text into field"
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(action)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decodedAction = try decoder.decode(SkillAction.self, from: data)
        
        XCTAssertEqual(action.type, decodedAction.type)
        XCTAssertEqual(action.targetElementId, decodedAction.targetElementId)
        XCTAssertEqual(action.parameters, decodedAction.parameters)
        XCTAssertEqual(action.description, decodedAction.description)
    }
    
    func testSkillResultCreation() {
        let action = SkillAction(
            type: .click,
            targetElementId: "button_1",
            description: "Test click"
        )
        
        let result = SkillResult(
            success: true,
            action: action,
            executionTime: 0.5
        )
        
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.action.type, .click)
        XCTAssertEqual(result.executionTime, 0.5)
        XCTAssertNil(result.errorMessage)
    }
    
    func testSkillResultWithError() {
        let action = SkillAction(
            type: .click,
            targetElementId: "invalid_element",
            description: "Test failed click"
        )
        
        let result = SkillResult(
            success: false,
            action: action,
            errorMessage: "Element not found",
            executionTime: 0.1
        )
        
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorMessage, "Element not found")
        XCTAssertEqual(result.executionTime, 0.1)
    }
}
