import XCTest
@testable import Skills

final class Computer13ActionParserTests: XCTestCase {
    
    func testParseClickAction() {
        let action = Computer13ActionParser.parse("click(button_1)")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.actionType, .click)
        XCTAssertEqual(action?.targetElementId, "button_1")
        XCTAssertEqual(action?.parameters.count, 0)
        XCTAssertEqual(action?.actionString, "click(button_1)")
    }
    
    func testParseDoubleClickAction() {
        let action = Computer13ActionParser.parse("double_click(elem_123)")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.actionType, .doubleClick)
        XCTAssertEqual(action?.targetElementId, "elem_123")
        XCTAssertEqual(action?.parameters.count, 0)
        XCTAssertEqual(action?.actionString, "double_click(elem_123)")
    }
    
    func testParseRightClickAction() {
        let action = Computer13ActionParser.parse("right_click(menu_item)")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.actionType, .rightClick)
        XCTAssertEqual(action?.targetElementId, "menu_item")
        XCTAssertEqual(action?.parameters.count, 0)
        XCTAssertEqual(action?.actionString, "right_click(menu_item)")
    }
    
    func testParseTypeAction() {
        let action = Computer13ActionParser.parse("type(text_field, \"hello world\")")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.actionType, .type)
        XCTAssertEqual(action?.targetElementId, "text_field")
        XCTAssertEqual(action?.parameters["text"], "hello world")
        XCTAssertEqual(action?.actionString, "type(text_field, \"hello world\")")
    }
    
    func testParseTypeActionWithSingleQuotes() {
        let action = Computer13ActionParser.parse("type(spotlight_field, 'Messages')")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.actionType, .type)
        XCTAssertEqual(action?.targetElementId, "spotlight_field")
        XCTAssertEqual(action?.parameters["text"], "Messages")
        XCTAssertEqual(action?.actionString, "type(spotlight_field, 'Messages')")
    }
    
    func testParseKeyPressAction() {
        let action = Computer13ActionParser.parse("key_press(\"Enter\")")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.actionType, .keyPress)
        XCTAssertNil(action?.targetElementId)
        XCTAssertEqual(action?.parameters["key"], "Enter")
        XCTAssertEqual(action?.actionString, "key_press(\"Enter\")")
    }
    
    func testParseKeyPressActionWithSingleQuotes() {
        let action = Computer13ActionParser.parse("key_press('Command+Space')")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.actionType, .keyPress)
        XCTAssertNil(action?.targetElementId)
        XCTAssertEqual(action?.parameters["key"], "Command+Space")
        XCTAssertEqual(action?.actionString, "key_press('Command+Space')")
    }
    
    func testParseWaitAction() {
        let action = Computer13ActionParser.parse("wait(\"2\")")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.actionType, .wait)
        XCTAssertNil(action?.targetElementId)
        XCTAssertEqual(action?.parameters["duration"], "2")
        XCTAssertEqual(action?.actionString, "wait(\"2\")")
    }
    
    func testParseWaitActionWithSingleQuotes() {
        let action = Computer13ActionParser.parse("wait('2')")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.actionType, .wait)
        XCTAssertNil(action?.targetElementId)
        XCTAssertEqual(action?.parameters["duration"], "2")
        XCTAssertEqual(action?.actionString, "wait('2')")
    }
    
    func testParseScrollAction() {
        let action = Computer13ActionParser.parse("scroll(\"down\")")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.actionType, .scroll)
        XCTAssertNil(action?.targetElementId)
        XCTAssertEqual(action?.parameters["deltaY"], "100")
        XCTAssertEqual(action?.actionString, "scroll(\"down\")")
    }
    
    func testParseFocusAction() {
        let action = Computer13ActionParser.parse("focus(elem_456)")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.actionType, .focus)
        XCTAssertEqual(action?.targetElementId, "elem_456")
        XCTAssertEqual(action?.parameters.count, 0)
        XCTAssertEqual(action?.actionString, "focus(elem_456)")
    }
    
    func testParseNavigateAction() {
        let action = Computer13ActionParser.parse("navigate(\"up\")")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.actionType, .keyPress)
        XCTAssertNil(action?.targetElementId)
        XCTAssertEqual(action?.parameters["key"], "Up")
        XCTAssertEqual(action?.actionString, "navigate(\"up\")")
    }
    
    func testParseInvalidAction() {
        let action = Computer13ActionParser.parse("invalid_action")
        XCTAssertNil(action)
    }
    
    func testParseEmptyAction() {
        let action = Computer13ActionParser.parse("")
        XCTAssertNil(action)
    }
    
    func testParseActionWithWhitespace() {
        let action = Computer13ActionParser.parse("  click(button_1)  ")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.actionType, .click)
        XCTAssertEqual(action?.targetElementId, "button_1")
    }
}
