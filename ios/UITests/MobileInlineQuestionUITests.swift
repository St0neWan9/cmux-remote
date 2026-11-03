import XCTest

/// The runtime dialogs a terminal blocks on are answered from the phone.
@MainActor
final class MobileInlineQuestionUITests: XCTestCase {
    func testTappingContinueAnswersTheDialogsOwnChoice() throws {
        let shape = FixtureShape.current()
        try XCTSkipUnless(shape == "awaiting-question", "This run's fixture holds the \(shape ?? "default") transcript.")
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
        XCTAssertTrue(app.buttons["chat.more"].waitForExistence(timeout: 5))
        app.buttons["chat.more"].tap()
        XCTAssertTrue(app.buttons["chat.feed"].waitForExistence(timeout: 5))
        app.buttons["chat.feed"].tap()

        // A dialog that waits for Enter or Escape offers exactly those two answers: no free text, no skip.
        let cont = app.buttons["feed.question.option.0.enter"]
        XCTAssertTrue(cont.waitForExistence(timeout: 10), "The terminal dialog was not offered in the Feed.")
        XCTAssertTrue(app.buttons["feed.question.option.0.escape"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Press Enter to continue")).firstMatch.exists,
                      "The dialog's own words were not shown.")
        let dialog = cont.frame
        // Controls belonging to the dialog sit between its first option and its submit row.
        let below = app.descendants(matching: .any).allElementsBoundByIndex.filter { $0.frame.minY > dialog.minY - 200 && $0.frame.minY < dialog.minY + 200 }
        XCTAssertFalse(below.contains { $0.identifier.hasPrefix("feed.question.custom.") }, "The dialog offered free text.")
        XCTAssertFalse(below.contains { $0.identifier == "feed.question.skip" }, "The dialog offered a skip.")
        cont.tap()
        // Every card on this page has its own submit row; the dialog's is the first one below its options.
        let submit = app.buttons.matching(identifier: "feed.question.submit").allElementsBoundByIndex
            .filter { $0.frame.minY > dialog.minY }.min { $0.frame.minY < $1.frame.minY }
        let row = try XCTUnwrap(submit, "The dialog had no submit row.")

        // The reply reaches the Feed and the request stops waiting, so the card becomes its record.
        row.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: cont)
        waitForExpectations(timeout: 10)
    }
}
