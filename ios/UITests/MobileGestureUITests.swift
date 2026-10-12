import XCTest

/// Sends a real touchscreen drag through the installed app's navigation stack.
@MainActor
final class MobileGestureUITests: XCTestCase {
    func testConnectionAndConversationReturnBySwiping() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to test navigation without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        XCTAssertTrue(app.buttons["sessions.sidebar"].waitForExistence(timeout: 10))
        app.buttons["sessions.sidebar"].tap()
        app.buttons["sidebar.connection"].tap()
        XCTAssertTrue(app.buttons["page.back"].waitForExistence(timeout: 5))
        capture(app, "connection")
        swipeBack(app)
        XCTAssertTrue(app.buttons["sessions.sidebar"].waitForExistence(timeout: 5))
        app.buttons["session.fixture-session"].tap()
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 5))
        capture(app, "conversation")
        for destination in ["chat.project", "chat.feed", "chat.timing"] {
            app.buttons["chat.more"].tap()
            app.buttons[destination].tap()
            XCTAssertTrue(app.buttons["page.back"].waitForExistence(timeout: 5))
            capture(app, destination)
            swipeBack(app)
            XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 5))
        }
        let image = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "image.history.")).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        image.tap()
        XCTAssertTrue(app.buttons["page.back"].waitForExistence(timeout: 5))
        capture(app, "image")
        swipeBack(app)
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 5))
        let activity = app.buttons["activity.design-tool"]
        if activity.exists { activity.tap() }
        let read = app.buttons["tool.disclosure.design-tool"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        read.tap()
        let detail = app.buttons["tool.detail.design-tool"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        detail.tap()
        XCTAssertTrue(app.buttons["page.back"].waitForExistence(timeout: 5))
        capture(app, "tool-detail")
        swipeBack(app)
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 5))
        swipeBack(app)
        XCTAssertTrue(app.buttons["sessions.sidebar"].waitForExistence(timeout: 5))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func swipeBack(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
    }
}
