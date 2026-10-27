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
        // The detached tasks sit above the input box; open them to name each one.
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        sleep(1)
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        sleep(2)
        let bar = app.buttons["chat.background"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "The conversation shows no background tasks")
        capture(app, "03-background-bar")
        bar.tap()
        sleep(2)
        capture(app, "04-background-list")
        app.buttons["chat.back"].tap()
        XCTAssertTrue(app.buttons["sessions.sidebar"].waitForExistence(timeout: 8))
        app.buttons["sessions.sidebar"].tap()
        let addDevice = app.buttons["sidebar.add_device"]
        XCTAssertTrue(addDevice.waitForExistence(timeout: 5))
        addDevice.tap()
        sleep(3)
        capture(app, "05-add-a-mac")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
