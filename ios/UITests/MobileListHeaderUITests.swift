import XCTest

/// The list's title opens its options, search takes the whole bar, and pending items show under the Mac tabs.
@MainActor
final class MobileListHeaderUITests: XCTestCase {
    func testTitleMenuSearchAndPendingReminder() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to test the list without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let menu = app.buttons["sessions.title_menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        // The fixture holds pending questions, a permission and a plan; the reminder counts them under the Mac tabs.
        let reminder = app.descendants(matching: .any)["sessions.pending"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 10), "The pending reminder did not appear")
        XCTAssertTrue(app.descendants(matching: .any)["sessions.hosts"].exists)
        XCTAssertGreaterThan(reminder.frame.minY, app.descendants(matching: .any)["sessions.hosts"].frame.maxY - 1, "The reminder is not under the Mac tabs")
        capture(app, "list")

        menu.tap()
        XCTAssertTrue(app.buttons["sessions.refresh"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["按工作区"].exists || app.buttons["By workspace"].exists, "The sort choice is not in the title menu")
        XCTAssertTrue(app.buttons["添加 Mac"].exists, "Adding a Mac is not in the title menu")
        capture(app, "menu")
        app.buttons["sessions.refresh"].tap()

        // Search replaces the bar and takes the keyboard; closing it brings the bar back.
        app.buttons["sessions.search"].tap()
        let field = app.textFields["sessions.search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sessions.sidebar"].exists, "Search did not take the whole bar")
        capture(app, "search")
        app.buttons["sessions.search.close"].tap()
        XCTAssertTrue(app.buttons["sessions.sidebar"].waitForExistence(timeout: 5))

        reminder.tap()
        XCTAssertTrue(app.staticTexts["待处理事项"].waitForExistence(timeout: 5) || app.navigationBars["待处理事项"].exists, "The reminder did not open the pending items")
        capture(app, "feed")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
