import XCTest

/// The conversation list folds history under one row per list and opens it in place.
///
/// Run against a Bridge whose Mac keeps old conversations (any long-used Mac does): the list shows the recent
/// ones, each list ends in an "earlier" row, and tapping it shows the rest.
@MainActor
final class MobileEarlierFoldUITests: XCTestCase {
    func testOldConversationsFoldAndOpenInPlace() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CMUX_REMOTE_TEST_FOLD"] == "1" else { throw XCTSkip("Run against a Mac that keeps old conversations.") }
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        if let pairingPath = environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty {
            app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        }
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-sessionSortMode", "workspace"]
        app.launch()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30), "The list did not load")
        let folds = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sessions.earlier."))
        XCTAssertTrue(folds.firstMatch.waitForExistence(timeout: 10), "No list folded its earlier conversations")
        capture(app, "0-folded")
        // The reader's choice is remembered across launches, so the fold may start either way: toggling it must
        // change its label and how many rows show, and toggling again must put both back.
        let fold = folds.firstMatch
        let identifier = fold.identifier
        let label = fold.label
        let before = shownRows(app)
        fold.tap()
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.buttons[identifier].label, label, "The fold did not toggle")
        XCTAssertNotEqual(shownRows(app), before, "Toggling the fold changed nothing in the list")
        capture(app, "1-toggled")
        app.buttons[identifier].tap()
        XCTAssertEqual(app.buttons[identifier].label, label, "The fold did not toggle back")
        XCTAssertEqual(shownRows(app), before, "Toggling back did not restore the list")

        // Time order keeps six of the newest before its single fold.
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-sessionSortMode", "time"]
        app.launch()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30))
        // The fold ends the list, below the six it keeps; a lazy list builds it only once it is near the screen.
        let timeFold = app.buttons["sessions.earlier.time"]
        for _ in 0..<6 where !timeFold.exists { app.swipeUp() }
        XCTAssertTrue(timeFold.waitForExistence(timeout: 5), "Time order did not fold its history")
        if timeFold.label.contains("收起") { timeFold.tap() }
        // Six at least; every conversation of the last three days stays above the fold as well.
        XCTAssertGreaterThanOrEqual(shownRows(app), 6, "Time order kept fewer than its six newest rows")
        capture(app, "2-time")
    }
    private func shownRows(_ app: XCUIApplication) -> Int {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session.")).count
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
