import XCTest

/// A reply is selected with the system's own text selection, in place, and does not move when it starts.
@MainActor
final class MobileSelectTextUITests: XCTestCase {
    func testSelectingPartOfAReplyInPlace() throws {
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
        // No separate page and no button that opens one: selection happens here.
        XCTAssertFalse(app.buttons["response.select"].exists, "A reply still offers a separate selection page")

        let reply = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "页面使用白色背景")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5), "No reply text is on screen")
        capture(app, "opened")
        let before = reply.frame
        reply.press(forDuration: 1.0)
        // The system's own menu, and the reply's own block, not a text view swapped in for it.
        let copy = app.menuItems.matching(NSPredicate(format: "label IN %@", ["拷贝", "复制", "Copy"])).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "Long pressing a reply showed no edit menu")
        capture(app, "reply-selected")
        let after = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "页面使用白色背景")).firstMatch
        if after.exists {
            XCTAssertEqual(before.minY, after.frame.minY, accuracy: 1, "The reply moved when it was selected")
            XCTAssertEqual(before.height, after.frame.height, accuracy: 1, "The reply changed height when it was selected")
        }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
