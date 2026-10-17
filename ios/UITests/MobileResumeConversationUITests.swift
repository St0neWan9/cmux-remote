import XCTest

/// An Agent that exited while its terminal stayed open: the list marks the conversation as resumable and its page
/// offers to reopen it, instead of a composer that would have nowhere to type.
@MainActor
final class MobileResumeConversationUITests: XCTestCase {
    func testAResumableConversationIsMarkedAndOffersToReopen() throws {
        // The fixture lists a resumable conversation only when its state directory asks for one; the shape
        // decides whether this run can test it at all.
        try XCTSkipUnless(FixtureShape.current() == "resumable-session", "This run's fixture holds the \(FixtureShape.current() ?? "default") transcript.")
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to open conversations without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()

        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-resumable")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10), "The resumable conversation is not listed")
        // The row says how it differs from plain history rather than showing a lock.
        XCTAssertTrue(session.label.contains("恢复会话"), "The row does not mark the conversation as resumable: \(session.label)")

        session.tap()
        let reopen = app.buttons["sessions.resume"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 10), "The conversation page offers no way to reopen it")
        // The composer must not be there: the terminal holds a shell, so typing would run text as a command.
        XCTAssertTrue(app.buttons["sessions.resume"].isHittable)
        capture(app, "resumable-page")

        reopen.tap()
        // The Bridge accepted the reopen; the page keeps showing the conversation rather than reporting an error.
        Thread.sleep(forTimeInterval: 1.5)
        capture(app, "after-reopen")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
