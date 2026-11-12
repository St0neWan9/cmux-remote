import XCTest

/// A prompt sent from the phone lands at the end of the conversation, above the composer, and the reply grows under it.
///
/// The page used to lift the prompt to its top over a page of blank room: it jumped up on every send, sat blank, and
/// a miscounted room pushed the prompt half under the header. Now nothing moves but the new content arriving below.
///
/// Run on a fixture with `long-conversation` or `short-conversation`, plus `open-turn` and `report-working` flags: the
/// prompt is recorded late, the turn stays open so the running label lands under it, and the reply follows.
@MainActor
final class MobileSentPromptAnchorUITests: XCTestCase {
    func testASentPromptStaysAtTheEndAndTheReplyGrowsUnderIt() throws {
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
        let composer = app.textFields.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)
        composer.tap()
        composer.typeText("位置检查")
        app.buttons["chat.send"].firstMatch.tap()

        let header = app.buttons["chat.back"].frame
        let prompt = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "位置检查")).firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 10), "The sent prompt did not appear.")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@", "message.", "activity."))
        // Through the bubble, the recorded prompt replacing it and the reply landing under it: the prompt is never under
        // the header, and the conversation always reaches down to the composer, so no page of blank opens up.
        for sample in 1...20 {
            Thread.sleep(forTimeInterval: 0.5)
            XCTAssertTrue(prompt.exists, "The prompt disappeared from the page (sample \(sample)).")
            let composerTop = app.textFields.firstMatch.frame.minY
            // The running label and live preview under the prompt are content too, before the reply is recorded as a
            // row; the composer row's own running label sits just above the field and is left out.
            let labels = app.descendants(matching: .any).matching(identifier: "response.elapsed").allElementsBoundByIndex
                .map(\.frame).filter { !$0.isEmpty && $0.maxY < composerTop - 50 }
            let preview = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "UI fixture received")).allElementsBoundByIndex.map(\.frame)
            let end = (rows.allElementsBoundByIndex.map(\.frame) + labels + preview).filter { !$0.isEmpty && $0.maxY < composerTop }.map(\.maxY).max() ?? 0
            if prompt.frame.maxY > header.maxY + 4 {
                XCTAssertGreaterThan(prompt.frame.minY, header.maxY - 4, "The prompt was pushed \(Int(header.maxY - prompt.frame.minY))pt under the header (sample \(sample)).")
            }
            XCTAssertLessThan(composerTop - end, 200, "A page of blank opened \(Int(composerTop - end))pt above the composer (sample \(sample)).")
            if sample % 5 == 0 { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "s\(sample)"; shot.lifetime = .keepAlways; add(shot) }
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
