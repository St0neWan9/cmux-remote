import XCTest

/// Captures the screens the App Store listing shows, at the largest iPhone size, from the fixture bridge.
@MainActor
final class MobileStoreScreenshotsUITests: XCTestCase {
    func testCaptureListingScreens() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to capture listing screens.")
        }
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["sessions.sidebar"].waitForExistence(timeout: 15))
        capture(app, "01-sessions")
        app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch.tap()
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 8))
        sleep(3)
        // At the top the page shows the start of the conversation; scrolled to the bottom the rows run on
        // under the translucent header, which reads as ghosted text in a still.
        app.scrollViews.firstMatch.swipeDown(velocity: .slow)
        sleep(2)
        capture(app, "02-conversation")
        let image = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "image.history.")).firstMatch
        if image.waitForExistence(timeout: 5) {
            image.tap()
            XCTAssertTrue(app.buttons["page.back"].waitForExistence(timeout: 8))
            sleep(2)
            capture(app, "03-image")
            app.buttons["page.back"].tap()
            XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 8))
        }
        app.buttons["chat.more"].tap()
        app.buttons["chat.feed"].tap()
        XCTAssertTrue(app.buttons["page.back"].waitForExistence(timeout: 8))
        sleep(2)
        capture(app, "04-questions")
        app.buttons["page.back"].tap()
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 8))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
