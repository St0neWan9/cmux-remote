import XCTest

/// The model under the conversation's title opens the agent's model choices and switches to one.
@MainActor
final class MobileModelMenuUITests: XCTestCase {
    func testModelMenuShowsChoicesAndSwitches() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to open conversations without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        let menu = app.buttons["model.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        sleep(2)
        capture(app, "1-header")
        menu.tap()
        let custom = app.buttons["model.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        sleep(1)
        capture(app, "2-menu")
        custom.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.textFields.firstMatch.typeText("volcengine/glm-5.3[1m]")
        capture(app, "3-custom")
        app.alerts.firstMatch.buttons["切换模型"].tap()
        let switched = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "glm-5.3")).firstMatch
        XCTAssertTrue(switched.waitForExistence(timeout: 10))
        sleep(2)
        capture(app, "4-switched")
    }
    /// A long conversation makes Claude Code ask before switching: the page asks the reader, and nothing changes until they say yes.
    func testSwitchClaudeCodeAsksToConfirmIsAnsweredFromThePhone() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to open conversations without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        let menu = app.buttons["model.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        sleep(2)
        for attempt in 1...2 {
            menu.tap()
            let custom = app.buttons["model.custom"]
            XCTAssertTrue(custom.waitForExistence(timeout: 5))
            custom.tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            app.alerts.firstMatch.textFields.firstMatch.typeText("heavy-model")
            app.alerts.firstMatch.buttons["切换模型"].tap()
            let ask = app.alerts["切换到这个模型？"]
            XCTAssertTrue(ask.waitForExistence(timeout: 10), "The agent's question did not reach the phone.")
            capture(app, "5-confirm-\(attempt)")
            if attempt == 1 {
                ask.buttons["取消"].tap()
                sleep(2)
                XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "heavy-model")).firstMatch.exists, "Cancelling the question still changed the model.")
            } else {
                ask.buttons["切换模型"].tap()
                let switched = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "heavy-model")).firstMatch
                XCTAssertTrue(switched.waitForExistence(timeout: 10), "Confirming the question did not switch the model.")
            }
        }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        if let directory = ProcessInfo.processInfo.environment["CMUX_REMOTE_SCREENSHOT_DIR"] {
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        }
    }
}
