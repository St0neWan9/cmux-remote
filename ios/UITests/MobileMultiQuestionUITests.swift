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

        // One answer per question, then a single reply for the whole request.
        first.tap()
        app.buttons["feed.question.option.1.front"].tap()
        submits.firstMatch.tap()

        // Both cards become records: the form cannot be answered twice.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: first)
        waitForExpectations(timeout: 10)
    }
}
