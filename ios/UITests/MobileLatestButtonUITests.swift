import XCTest

/// The way back to the newest message is offered only while the page's end is out of sight.
///
/// It follows the page's position, not the way the reader got there: scrolled back to the end by hand, the end is
/// in view, and a button promising to go there is noise until the content is covered again.
@MainActor
final class MobileLatestButtonUITests: XCTestCase {
    func testScrollingBackToTheEndByHandRemovesTheButton() throws {
        let app = try openConversation()
        let timeline = app.scrollViews.firstMatch
        let latest = app.buttons["chat.latest"]
        XCTAssertFalse(latest.exists, "The page opened at its end with the button showing.")
        timeline.swipeDown(velocity: .slow)
        XCTAssertTrue(latest.waitForExistence(timeout: 3), "Scrolling away did not offer the way back.")
        for _ in 0..<6 { timeline.swipeUp(velocity: .fast) }
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(latest.exists, "The page is back at its end by hand, but the button is still showing.")
    }
    func testOpeningAndClosingACardAtTheEndKeepsTheButtonAway() throws {
        let app = try openConversation()
        let latest = app.buttons["chat.latest"]
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity.")).allElementsBoundByIndex.last { $0.isHittable }
        guard let card else { throw XCTSkip("No activity card is on screen at the end of this transcript.") }
        card.tap(); Thread.sleep(forTimeInterval: 1.0)
        card.tap(); Thread.sleep(forTimeInterval: 1.0)
        // Closed again, the card leaves the page as it was: nothing under the composer to go back to.
        XCTAssertFalse(latest.exists, "Opening and closing a card at the end left the button showing.")
    }
    func testAfterASendScrollingToTheEndRemovesTheButton() throws {
        let app = try openConversation()
        let composer = app.textFields.firstMatch
        composer.tap(); composer.typeText("回到底部检查")
        app.buttons["chat.send"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 3.0)
        let timeline = app.scrollViews.firstMatch
        timeline.swipeDown(velocity: .slow)
        Thread.sleep(forTimeInterval: 1.0)
        for _ in 0..<6 { timeline.swipeUp(velocity: .fast) }
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(app.buttons["chat.latest"].exists, "After a send, the page is back at its end but the button is still showing.")
    }
    private func openConversation() throws -> XCUIApplication {
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
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2.5)
        return app
    }
}
