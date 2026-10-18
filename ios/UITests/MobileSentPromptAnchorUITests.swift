import XCTest

/// A prompt sent from the phone opens at the top of the page, with the reply arriving below it.
@MainActor
final class MobileSentPromptAnchorUITests: XCTestCase {
    func testASentPromptRestsAtTheTopOfThePage() throws {
        try XCTSkipUnless(FixtureShape.current() == "long-conversation", "This run's fixture holds the \(FixtureShape.current() ?? "default") transcript.")
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to send without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))

        let composer = app.textFields.firstMatch
        composer.tap()
        composer.typeText("置顶检查")
        app.buttons["chat.send"].firstMatch.tap()

        let sent = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "message.outgoing")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 10), "The sent prompt did not appear.")
        // Give the pin scroll a moment to animate in.
        Thread.sleep(forTimeInterval: 1.0)
        let header = app.buttons["chat.back"].frame
        let bubble = sent.frame
        // The bubble sits at the top of the page: just under the header, not floating mid-page.
        XCTAssertLessThan(bubble.minY - header.maxY, 140, "The sent prompt rested \(Int(bubble.minY - header.maxY))pt below the header instead of at the top.")
    }
}
