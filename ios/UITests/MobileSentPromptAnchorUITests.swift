import XCTest

/// A prompt sent from the phone opens at the top of the page and stays there while the reply starts.
///
/// Run on a fixture with `long-conversation` or `short-conversation`, plus `open-turn` and `report-working` flags: the prompt is recorded late,
/// the turn stays open so the running label lands under it, and the reply follows. Without a delay the bubble is
/// replaced before it can be found, which is how this test failed on every run before.
@MainActor
final class MobileSentPromptAnchorUITests: XCTestCase {
    func testASentPromptRestsAtTheTopAndStaysThereWhileTheTurnRuns() throws {
        // A conversation shorter than the page is the harder case: the room under the prompt is then exactly what
        // makes the page a page tall, and anything that lands under the prompt without shrinking it grows the page.
        try XCTSkipUnless(["long-conversation", "short-conversation"].contains(FixtureShape.current() ?? ""), "This run's fixture holds the \(FixtureShape.current() ?? "default") transcript.")
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to send without real sessions.")
        }
        let refuses = URL(fileURLWithPath: pairingPath).deletingLastPathComponent().appendingPathComponent("refuse-send")
        try XCTSkipIf(FileManager.default.fileExists(atPath: refuses.path), "This run's fixture refuses every send.")
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
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
        Thread.sleep(forTimeInterval: 1.0)
        let header = app.buttons["chat.back"].frame
        let bubble = sent.frame
        XCTAssertLessThan(bubble.minY - header.maxY, 140, "The sent prompt rested \(Int(bubble.minY - header.maxY))pt below the header instead of at the top.")

        // The fixture records the prompt after a delay (`open-turn`), so the turn's running state appears
        // first, then the recorded prompt replaces the bubble and the reply lands under it. Through all of it the
        // prompt keeps the top it was given: neither carried back down by a follow scroll, nor pushed up under the
        // header by a running label that grew the page below it.
        let prompt = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "置顶检查")).firstMatch
        for sample in 1...20 {
            Thread.sleep(forTimeInterval: 0.5)
            XCTAssertTrue(prompt.exists, "The prompt disappeared from the page (sample \(sample)).")
            let offset = prompt.frame.minY - header.maxY
            XCTAssertLessThan(offset, 140, "The prompt drifted \(Int(offset))pt below the header (sample \(sample)).")
            XCTAssertGreaterThan(offset, -4, "The prompt was pushed \(Int(-offset))pt up under the header (sample \(sample)).")
        }
    }
    /// The turn runs from the tap: the running time sits under the prompt from the moment it is sent, stays there when
    /// the transcript records the prompt and the bubble's "sent" line goes away, and never starts again from zero.
    ///
    /// Run on a fixture with `short-conversation` and `open-turn` but without `report-working`: the Mac then lists the
    /// session idle, as a cmux-tui session does until its screen shows the agent working.
    func testTheRunningTimeFollowsTheSentPromptWithoutAGap() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to send without real sessions.")
        }
        let directory = URL(fileURLWithPath: pairingPath).deletingLastPathComponent()
        func flag(_ name: String) -> Bool { FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) }
        try XCTSkipUnless(flag("open-turn") && !flag("report-working") && !flag("refuse-send"), "This run's fixture does not record a turn late on an idle session.")
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        let composer = app.textFields.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)
        composer.tap()
        composer.typeText("计时检查")
        app.buttons["chat.send"].firstMatch.tap()
        let header = app.buttons["chat.back"].frame
        let prompt = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "计时检查")).firstMatch
        let elapsed = app.descendants(matching: .any).matching(identifier: "response.elapsed")
        var last = -1
        for sample in 1...20 {
            Thread.sleep(forTimeInterval: 0.5)
            // The label in the page, under the prompt; the composer row carries a second one.
            let labels = elapsed.allElementsBoundByIndex.filter { $0.exists && $0.frame.minY > header.maxY && $0.frame.minY < composer.frame.minY - 60 }
            guard let label = labels.first else {
                add(XCTAttachment(screenshot: app.screenshot()))
                return XCTFail("No running time on the page \(sample * 500)ms after sending.")
            }
            XCTAssertTrue(prompt.exists && label.frame.minY > prompt.frame.minY, "The running time is not under the prompt (sample \(sample)).")
            // The label's own text, read where it is drawn: "运行中 12s".
            let text = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "运行中")).allElementsBoundByIndex
                .first { abs($0.frame.midY - label.frame.midY) < 30 }?.label ?? ""
            let seconds = Int(text.filter(\.isNumber)) ?? -1
            XCTAssertGreaterThanOrEqual(seconds, last, "The running time went back from \(last) to \(seconds)s (sample \(sample)).")
            last = seconds
        }
        XCTAssertGreaterThanOrEqual(last, 8, "The running time did not count from the tap (it read \(last)s after ten seconds).")
    }
    /// A send that never reached the agent takes its bubble back, and the page goes back to its end with it.
    ///
    /// The pin used to outlive the bubble: the room it left under the prompt stayed, the last reply sat under the
    /// header above a page of blank, and with the end "in sight" nothing offered the way back. A link that is down
    /// at the moment of sending does exactly this; the fixture's `refuse-send` flag stands in for it.
    func testARefusedSendLeavesNoBlankPage() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to send without real sessions.")
        }
        let directory = URL(fileURLWithPath: pairingPath).deletingLastPathComponent()
        try XCTSkipUnless(FileManager.default.fileExists(atPath: directory.appendingPathComponent("refuse-send").path), "This run's fixture accepts sends.")
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        let composer = app.textFields.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)
        composer.tap()
        composer.typeText("拒绝检查")
        app.buttons["chat.send"].firstMatch.tap()
        // The prompt comes back to the composer once the refusal lands.
        let returned = NSPredicate(format: "value CONTAINS %@", "拒绝检查")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: returned, object: composer)], timeout: 10), .completed,
                       "The refused prompt did not return to the composer.")
        Thread.sleep(forTimeInterval: 1.5)
        // Measured from the conversation's own rows: the first scroll view in the tree is the list under it.
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@", "message.", "activity."))
        let end = rows.allElementsBoundByIndex.map(\.frame).filter { !$0.isEmpty }.map(\.maxY).max() ?? 0
        let gap = composer.frame.minY - end
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "refused"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertLessThan(gap, 200, "The page rests \(Int(gap))pt above the composer, a page of blank under the last reply.")
    }
}
