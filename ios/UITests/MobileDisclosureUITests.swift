import XCTest

/// Opening or closing a tool card keeps the page where the reader left it; only the content below the card moves.
@MainActor
final class MobileDisclosureUITests: XCTestCase {
    func testOpeningAndClosingAToolCardKeepsThePageInPlace() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to test tool cards without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 5))
        sleep(2)
        // At the latest message, where the page otherwise follows new content.
        assertCardStaysInPlace(app, scenario: "at the latest message")
        // After reading back a little.
        app.scrollViews.firstMatch.swipeDown(velocity: .slow); sleep(1)
        assertCardStaysInPlace(app, scenario: "after reading back")
        // A single tool inside an open group behaves the same.
        var group: XCUIElement?
        for _ in 0..<6 {
            group = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity.")).allElementsBoundByIndex
                .first { $0.isHittable && $0.frame.midY > 150 && $0.frame.midY < app.windows.firstMatch.frame.height * 0.45 }
            if group != nil { break }
            app.scrollViews.firstMatch.swipeDown(velocity: .slow); sleep(1)
        }
        XCTAssertNotNil(group, "No tool group to open")
        if let group, group.value as? String != "已展开" { group.tap(); sleep(1) }
        assertCardStaysInPlace(app, scenario: "inside an open group", prefix: "tool.disclosure.")
    }

    /// Without a card opened, the page at the latest message still follows what arrives.
    func testThePageAtTheLatestMessageFollowsNewMessages() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to test following without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 5))
        sleep(2)
        let appended = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "运行中追加的回复"))
        func newest() -> Int { appended.allElementsBoundByIndex.compactMap { Int($0.label.split(separator: " ").last ?? "") }.max() ?? 0 }
        let before = newest()
        sleep(7)
        // Only meaningful while the fixture conversation is growing.
        guard newest() > before else { throw XCTSkip("The fixture conversation did not grow during the test.") }
        XCTAssertFalse(app.buttons["chat.latest"].exists, "The page stopped following new messages")
        let latest = newest()
        let shown = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "运行中追加的回复 \(latest)")).firstMatch
        XCTAssertTrue(shown.exists && shown.isHittable, "The newest message (\(latest)) is not on screen")
    }

    private func assertCardStaysInPlace(_ app: XCUIApplication, scenario: String, prefix: String = "activity.") {
        let height = app.windows.firstMatch.frame.height
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        // A card in the middle of the screen, with room above and below it.
        // Clear of the header and of the composer: a covered element is scrolled into view by the test runner
        // before it is tapped, which would be the runner moving the page rather than the app.
        let onScreen = cards.allElementsBoundByIndex.filter { $0.isHittable && $0.frame.minY > height * 0.15 && $0.frame.maxY < height * 0.6 }
        guard let card = onScreen.min(by: { abs($0.frame.midY - height * 0.45) < abs($1.frame.midY - height * 0.45) }) else {
            let frames = cards.allElementsBoundByIndex.map { "\($0.identifier)@\(Int($0.frame.minY))" }.joined(separator: ", ")
            return XCTFail("No tool card on screen \(scenario); height \(Int(height)), cards: \(frames)")
        }
        let identifier = card.identifier
        for action in ["opening", "closing"] {
            // A page that follows new messages moves with each one; tap only once it has come to rest.
            var before = app.buttons[identifier].frame.minY
            for _ in 0..<20 {
                Thread.sleep(forTimeInterval: 0.4)
                let now = app.buttons[identifier].frame.minY
                if abs(now - before) < 1 { break }
                before = now
            }
            XCTAssertTrue(app.buttons[identifier].isHittable, "The card is covered \(scenario)")
            app.buttons[identifier].tap()
            var worst: CGFloat = 0; var trace: [String] = []
            for delay in [0.3, 0.7, 1.5, 2.5, 2.5] {
                Thread.sleep(forTimeInterval: delay)
                let element = app.buttons[identifier]
                let moved = element.exists ? element.frame.minY - before : .infinity
                trace.append("\(Int(moved))")
                worst = max(worst, abs(moved))
            }
            XCTAssertLessThan(worst, 3, "\(action) a tool card \(scenario) moved it by \(worst)pt; trace \(trace.joined(separator: " "))")
        }
    }
}
