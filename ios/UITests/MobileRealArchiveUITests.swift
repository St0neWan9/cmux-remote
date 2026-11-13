import XCTest

/// Conversations `/clear` replaced leave the main list for the Archive, each dated by its clear.
///
/// The Bridge only dates a conversation from real transcripts, where the session `/clear` started opens with the
/// command; the phone fixture has none, so this runs against an isolated Bridge reading the real ones.
@MainActor
final class MobileRealArchiveUITests: XCTestCase {
    func testClearedConversationsAreOnlyInTheArchiveWithTheirTime() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let pairingPath = environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply a pairing for a Bridge whose conversations include cleared ones.")
        }
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'session.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "The list did not load")
        let dated = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'session.' AND label CONTAINS '归档于'"))
        // Every Mac's list is read before judging what it holds.
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(dated.count, 0, "A cleared conversation is still in the main list")
        capture(app, "0-all")

        let archive = app.buttons["sessions.filter.archived"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()
        XCTAssertTrue(dated.firstMatch.waitForExistence(timeout: 10), "The Archive shows no dated conversation")
        // The Archive holds the cleared conversations only, and each says when it was cleared.
        XCTAssertEqual(rows.count, dated.count, "A conversation in the Archive has no clear time")
        let archivedID = dated.firstMatch.identifier
        capture(app, "1-archive")

        app.buttons["sessions.filter.all"].tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons[archivedID].exists, "An archived conversation is listed under All")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
