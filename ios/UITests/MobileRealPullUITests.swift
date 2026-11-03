import XCTest

/// Pulling down at the top of a real, long conversation loads the messages before it until the first one.
///
/// Every other UI test runs on the phone fixture, whose conversation is shaped for the test. This one opens a
/// session the isolated Bridge is reading from the real Agent transcript, so paging is exercised over the same
/// byte-offset archive and the same message kinds the person actually sees.
@MainActor
final class MobileRealPullUITests: XCTestCase {
    func testPullingDownReachesTheFirstMessageOfARealConversation() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let sessionID = environment["CMUX_REMOTE_TEST_SESSION"], !sessionID.isEmpty,
              let firstMessage = environment["CMUX_REMOTE_TEST_FIRST_MESSAGE"], !firstMessage.isEmpty else {
            throw XCTSkip("Supply a session id and that session's first message.")
        }
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        // Without a pairing file the app uses the enrollment it already holds, so the test can run against the
        // installed Bridge on this Mac instead of an isolated one.
        if let pairingPath = environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty {
            app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        }
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", sessionID)).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 30), "The real session did not appear in the list")
        session.tap()
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 15), "The conversation did not open")
        let page = app.scrollViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        // The newest page has to be on screen before a pull means anything.
        let loading = app.staticTexts["正在加载对话…"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !loading.exists && app.staticTexts.count > 3
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 40), .completed, "The newest page of the real conversation did not load")
        capture(app, "0-opened")

        // Pulling down walks the conversation backwards one page at a time. The first message of the transcript
        // is the proof that the walk reaches the start: a page that loads but leaves pulls answering with
        // messages already on screen never gets there.
        let first = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", firstMessage)).firstMatch
        for pull in 1...60 where !first.exists {
            page.swipeDown(velocity: .fast)
            Thread.sleep(forTimeInterval: 0.7)
            XCTAssertFalse(app.buttons["Refresh"].exists, "A system refresh control appeared")
            if pull % 15 == 0 { capture(app, "pull-\(pull)") }
        }
        // The page keeps the reader beside the message they reached, so the first message sits just above it.
        for _ in 0..<12 where !first.exists {
            page.swipeDown(velocity: .fast)
            Thread.sleep(forTimeInterval: 0.3)
        }
        capture(app, "final")
        XCTAssertTrue(first.exists, "Pulling down never reached the conversation's first message")
    }
    func testStressSwipingStaysResponsive() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let sessionID = environment["CMUX_REMOTE_TEST_SESSION"], !sessionID.isEmpty else {
            throw XCTSkip("Supply a session id.")
        }
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        // Without a pairing file the app uses the enrollment it already holds, so the test can run against the
        // installed Bridge on this Mac instead of an isolated one.
        if let pairingPath = environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty {
            app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        }
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", sessionID)).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 30))
        session.tap()
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 15))
        let page = app.scrollViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 3)
        for index in 1...120 {
            page.swipeDown(velocity: .slow)
            if index % 20 == 0 { capture(app, "stress-\(index)") }
        }
        // Still able to answer a query and open the menu after the swipes.
        XCTAssertTrue(app.buttons["chat.back"].isHittable, "The page stopped responding after swiping")
        app.buttons["chat.more"].tap()
        XCTAssertTrue(app.buttons["chat.rename"].waitForExistence(timeout: 10), "The menu did not open after swiping")
        capture(app, "stress-end")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
