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
    /// The transcript the fixture was started with; it decides which shape this run can measure.
    private var selectedShape: String { ProcessInfo.processInfo.environment["CMUX_REMOTE_FIXTURE_FLAGS"] ?? "" }
    /// The fixture writes one transcript per state directory; only the shape it wrote can be measured.
    private var isShort: Bool { selectedShape == "short-conversation" }
    private var isTall: Bool { selectedShape == "tall-reply" }
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
