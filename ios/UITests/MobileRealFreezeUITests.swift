import XCTest

/// Opens one real, content-heavy conversation and holds it to what a reader expects: it answers at once, and it
/// keeps answering while they read back through it.
///
/// Every other UI test runs on the phone fixture, whose conversation is short. A long transcript is the only thing
/// that reproduced the page going unresponsive while it loaded, so the session is supplied by the caller.
@MainActor
final class MobileRealFreezeUITests: XCTestCase {
    /// The longest a page may take to answer while the reader is looking at it. Generous on purpose: the fixture is
    /// a Debug build, whose work costs several times what the same code costs in an installed app.
    private let answerLimit: TimeInterval = 2
    func testAContentHeavyConversationOpensAndStaysInteractive() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let sessionID = environment["CMUX_REMOTE_TEST_FREEZE_SESSION"], !sessionID.isEmpty else {
            throw XCTSkip("Supply the id of a content-heavy session.")
        }
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        if let pairingPath = environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty {
            app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        }
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", sessionID)).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 30), "The real session did not appear in the list")
        capture(app, "0-list")

        open(session, label: "first", app: app)
        let page = app.scrollViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10))

        // Reading it once, then opening it again: the second visit restores what the phone stored, which is the
        // state the reader is in after they have paged through the conversation.
        Thread.sleep(forTimeInterval: TimeInterval(environment["CMUX_REMOTE_TEST_FREEZE_DWELL"] ?? "") ?? 5)
        XCTAssertTrue(app.buttons["chat.back"].isHittable, "The page stopped responding while it loaded")
        app.buttons["chat.back"].tap()
        XCTAssertTrue(session.waitForExistence(timeout: 20), "The list did not come back")
        open(session, label: "reopen", app: app)

        XCTAssertTrue(page.waitForExistence(timeout: 10))
        for index in 1...20 {
            let took = time { _ = app.buttons["chat.back"].isHittable }
            XCTAssertLessThan(took, answerLimit, "The page stopped answering while the reader looked at it")
            if index % 5 == 0 { print("FREEZE idle \(index) query=\(took)") }
            Thread.sleep(forTimeInterval: 0.5)
        }
        // Reading back through the conversation: each swipe must be answered, and the menu must still open.
        for index in 1...20 {
            page.swipeDown(velocity: .slow)
            let took = time { _ = app.buttons["chat.back"].isHittable }
            XCTAssertLessThan(took, answerLimit, "The page stopped answering while the reader read back")
            if index % 5 == 0 { print("FREEZE scroll \(index) query=\(took)") }
        }
        capture(app, "1-scrolled")
        // The header's own controls answer too: the page has not merely drawn, it is live.
        XCTAssertTrue(app.buttons["chat.more"].isHittable, "The page stopped responding")
        XCTAssertTrue(app.buttons["chat.back"].isHittable)
    }
    /// Taps the session and holds the opening to the same answer limit.
    private func open(_ session: XCUIElement, label: String, app: XCUIApplication) {
        let started = Date()
        session.tap()
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 30), "The conversation did not open")
        let appeared = Date().timeIntervalSince(started)
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 10))
        let answered = time { _ = app.staticTexts.count }
        XCTAssertLessThan(answered, answerLimit, "The page did not answer once it opened")
        print("FREEZE \(label) appeared=\(appeared) answered=\(answered)")
        capture(app, label)
    }
    private func time(_ work: () -> Void) -> TimeInterval {
        let started = Date(); work(); return Date().timeIntervalSince(started)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
