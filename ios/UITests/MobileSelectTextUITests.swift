import XCTest

/// Part of a reply or of the reader's own message can be selected with the system's handles.
@MainActor
final class MobileSelectTextUITests: XCTestCase {
    func testSelectingPartOfAReplyAndOfAPrompt() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to open conversations without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 5))

        // A reply opens on its own page from its footer, where a double tap selects one word with handles.
        let select = app.buttons.matching(identifier: "response.select").allElementsBoundByIndex.last { $0.isHittable }
        XCTAssertNotNil(select, "No reply offers to select its text")
        select?.tap()
        let text = app.textViews["select.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5), "The reply did not open for selection")
        text.doubleTap()
        let copy = app.menuItems.matching(NSPredicate(format: "label IN %@", ["拷贝", "复制", "Copy"])).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "Selecting part of the reply showed no edit menu")
        capture(app, "reply-selected")
        app.buttons["page.close"].tap()

        // The reader's own message offers the same from a long press.
        let prompt = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "检查本地连接和页面样式")).firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.press(forDuration: 1.0)
        // The menu's entry, not the footers' buttons with the same label.
        let open = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "选择文本", "response.select")).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5), "The message's long press has no text selection")
        capture(app, "prompt-menu")
        open.tap()
        XCTAssertTrue(app.textViews["select.text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["select.text"].value as? String, "检查本地连接和页面样式")
        capture(app, "prompt-page")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
