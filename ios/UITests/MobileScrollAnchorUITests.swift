import XCTest

/// Opening a conversation lands on its newest message whether or not that message fits the page.
///
/// The isolated fixture writes one transcript shape per state directory: an empty `short-conversation` file
/// seeds a conversation shorter than the page, `tall-reply` seeds one whose newest reply is taller than it.
@MainActor
final class MobileScrollAnchorUITests: XCTestCase {
    func testAShortConversationRestsAgainstTheComposer() throws {
        try XCTSkipUnless(isShort, "This run's fixture holds the \(selectedShape) transcript.")
        let app = try openConversation()
        let reply = try row(app, "message.short-reply")
        let composer = app.textFields.firstMatch.frame
        // The newest line sits at the bottom of the page rather than floating above empty white.
        let gap = composer.minY - reply.maxY
        XCTAssertLessThan(gap, 160, "A short conversation left \(Int(gap))pt of empty page under its newest message.")
        XCTAssertGreaterThan(reply.minY, 110, "The short conversation started under the header.")
    }
    func testATallReplyOpensAtItsFirstLine() throws {
        try XCTSkipUnless(isTall, "This run's fixture holds the \(selectedShape) transcript.")
        let app = try openConversation()
        let reply = try row(app, "message.tall-reply")
        XCTAssertGreaterThan(reply.height, 600, "The fixture's newest reply was not taller than the page.")
        // Anchoring the page's end would carry this row's first line off the top; it must be readable on open.
        XCTAssertGreaterThan(reply.minY, 110, "The tall reply opened with its first line above the header.")
        XCTAssertLessThan(reply.minY, 180, "The tall reply opened below its first line.")
    }
    /// A finished turn at the end of a long conversation must rest at the page's real end.
    ///
    /// Anchoring the newest row leaves the page's own foot and the marker after it below the fold, so the page
    /// stops short: the last reply's action buttons can still sit under the composer, and one more pull moves
    /// the content. Both the opening scroll and the "latest" button share this path, so this measures the button
    /// after the reader has scrolled away and asks to come back.
    func testTheLatestButtonReachesTheEndOfALongConversation() throws {
        try XCTSkipUnless(isLong, "This run's fixture holds the \(selectedShape) transcript.")
        let app = try openConversation()
        let timeline = app.scrollViews.firstMatch
        // The newest reply ends in a short line, so its own action row is the page's last content.
        let newest = try row(app, "message.long-reply")
        let composer = app.textFields.firstMatch.frame
        // Opening lands on the end: the reply's line, and the room under it, are above the composer.
        XCTAssertLessThan(newest.minY, composer.minY, "The newest reply opened \(Int(newest.minY - composer.minY))pt under the composer.")
        // Scrolling away is what offers the way back; that button must land on the same end.
        timeline.swipeDown(velocity: .slow)
        Thread.sleep(forTimeInterval: 0.8)
        let latestButton = app.buttons["chat.latest"]
        XCTAssertTrue(latestButton.waitForExistence(timeout: 3), "Scrolling up did not offer the way back to the end.")
        latestButton.tap()
        Thread.sleep(forTimeInterval: 2.0)
        let returned = try row(app, "message.long-reply")
        XCTAssertLessThan(abs(returned.minY - newest.minY), 3, "The button stopped \(Int(returned.minY - newest.minY))pt away from where opening rests.")
        // A page that rests above its end still moves when pulled further; this one must not.
        let before = try row(app, "message.long-reply")
        timeline.swipeUp(velocity: .slow)
        Thread.sleep(forTimeInterval: 0.8)
        let after = try row(app, "message.long-reply")
        XCTAssertLessThan(abs(after.minY - before.minY), 3, "The page was still \(Int(after.minY - before.minY))pt above its end.")
    }
    /// The transcript the fixture was started with; it decides which shape this run can measure.
    private var selectedShape: String { ProcessInfo.processInfo.environment["CMUX_REMOTE_FIXTURE_FLAGS"] ?? "" }
    /// The fixture writes one transcript per state directory; only the shape it wrote can be measured.
    private var isShort: Bool { selectedShape == "short-conversation" }
    private var isTall: Bool { selectedShape == "tall-reply" }
    private var isLong: Bool { selectedShape == "long-conversation" }
    private func openConversation() throws -> XCUIApplication {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to open conversations without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchEnvironment["CMUX_REMOTE_FIXTURE_FLAGS"] = selectedShape
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        // The opening scroll settles over a few layouts; measure once it has.
        Thread.sleep(forTimeInterval: 2.5)
        return app
    }
    private func row(_ app: XCUIApplication, _ identifier: String) throws -> CGRect {
        let element = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        return element.frame
    }
}
