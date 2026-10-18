import XCTest

/// A request that asked several questions is answered from its first card, as the Feed lists it.
@MainActor
final class MobileMultiQuestionUITests: XCTestCase {
    func testTheFirstCardAnswersEveryQuestionInOneReply() throws {
        let shape = FixtureShape.current()
        try XCTSkipUnless(shape == "awaiting-multi-question", "This run's fixture holds the \(shape ?? "default") transcript.")
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to open conversations without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 5))

        // The first card carries the whole request: both questions' options are on it, and one submit row.
        let first = app.buttons["feed.question.option.0.fast"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), "The first card did not carry the request's form.")
        XCTAssertTrue(app.buttons["feed.question.option.1.front"].exists, "The second question was not on the first card.")
        let submits = app.buttons.matching(identifier: "feed.question.submit")
        XCTAssertEqual(submits.count, 1, "The request offered more than one submit row.")
        // The second question's own card is not repeated under the form while the request waits.
        let second = app.staticTexts.matching(NSPredicate(format: "label == %@", "改动范围?"))
        XCTAssertEqual(second.count, 1, "The second question was shown again as its own card under the form.")
        XCTAssertFalse(app.staticTexts["在第一张卡片中一起回答"].exists, "A duplicate card still pointed at the first one.")

        // The form passing under the composer is blurred like the rest of the page (checked on this screenshot).
        let page = app.scrollViews.firstMatch
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).press(forDuration: 0.05, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        sleep(1)
        let underEdge = XCTAttachment(screenshot: app.screenshot()); underEdge.name = "form-under-composer"; underEdge.lifetime = .keepAlways; add(underEdge)
        app.buttons["chat.latest"].firstMatch.tap()
        sleep(1)

        // One answer per question, then a single reply for the whole request.
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        app.buttons["feed.question.option.1.front"].tap()
        submits.firstMatch.tap()

        // Both cards become records: the form cannot be answered twice.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: first)
        waitForExpectations(timeout: 10)
        // Once answered, the second question is back as its own record.
        XCTAssertTrue(app.staticTexts["改动范围?"].waitForExistence(timeout: 10), "The answered request lost its second card.")
        let answered = XCTAttachment(screenshot: app.screenshot()); answered.name = "answered"; answered.lifetime = .keepAlways; add(answered)
    }
}
