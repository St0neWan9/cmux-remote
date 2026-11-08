import XCTest

/// The list's title menu opens the app's own page, which names the build and where the project lives.
@MainActor
final class MobileAboutUITests: XCTestCase {
    func testTheTitleMenuOpensTheAboutPage() throws {
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        if let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty {
            app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        }
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        XCTAssertTrue(app.buttons["sessions.title_menu"].waitForExistence(timeout: 30), "The list did not load")
        app.buttons["sessions.title_menu"].tap()
        let about = app.buttons["sessions.about"]
        XCTAssertTrue(about.waitForExistence(timeout: 5), "The menu offered no about entry")
        about.tap()
        XCTAssertTrue(app.staticTexts["about.version"].waitForExistence(timeout: 5), "The page did not name its build")
        XCTAssertTrue(app.descendants(matching: .any)["about.website"].exists, "The page did not link the website")
        XCTAssertTrue(app.descendants(matching: .any)["about.source"].exists, "The page did not link the source")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "about"; attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["page.back"].tap()
        XCTAssertTrue(app.buttons["sessions.title_menu"].waitForExistence(timeout: 5), "The list did not come back")
    }
}
