import XCTest

/// The conversation header shows the agent's own working line, and the preview never prints terminal chrome.
@MainActor
final class MobileStatusLineUITests: XCTestCase {
    private func launch(_ flags: [String]) throws -> XCUIApplication {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to test the working line without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchEnvironment["CMUX_REMOTE_FIXTURE_FLAGS"] = flags.joined(separator: ",")
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        return app
    }
    private func openTheSession(_ app: XCUIApplication) {
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 5))
    }
    /// `✻ Blanching… (54s · ↓ 2.3k tokens)`, with the elapsed time ticking locally.
    func testTheHeaderShowsTheAgentsOwnWorkingLine() throws {
        let app = try launch(["report-working"])
        openTheSession(app)
        let label = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Blanching")).firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 15), "The agent's activity word did not appear")
        XCTAssertTrue(label.label.contains("2.3k tokens"), "The token count is missing from: \(label.label)")
        XCTAssertTrue(label.label.contains("↓"), "The token direction is missing from: \(label.label)")
    }
    /// The composer's frame and the CLI notice sit between the answer and the working line; neither is prose.
    func testTerminalChromeNeverReachesThePreview() throws {
        let app = try launch(["report-working"])
        openTheSession(app)
        let chrome = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Update installed"))
        XCTAssertFalse(chrome.firstMatch.waitForExistence(timeout: 3), "A CLI notice was printed as the agent's prose")
        let box = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "╭"))
        XCTAssertFalse(box.firstMatch.waitForExistence(timeout: 2), "The input box frame was printed as the agent's prose")
    }
    /// Opening a long conversation starts at the newest message, not above it.
    func testOpeningAConversationLandsOnTheNewestMessage() throws {
        let app = try launch([])
        openTheSession(app)
        let newest = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "页面使用白色背景")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 15), "The newest message is not on screen after opening")
        XCTAssertTrue(newest.isHittable, "The newest message is off-screen after opening")
    }
}
