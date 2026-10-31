import XCTest

/// Reads a long conversation back to its first message with real touchscreen swipes, without a button.
@MainActor
final class MobileHistoryUITests: XCTestCase {
    func testSwipingToTheTopPagesInEarlierMessagesWithoutLosingThePlace() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to test paging without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 5))
        let latest = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "white background")).firstMatch
        XCTAssertTrue(latest.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["加载更早的消息"].exists)
        let labels = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "历史消息"))
        func earliest() -> Int { labels.allElementsBoundByIndex.compactMap { Int($0.label.suffix(4)) }.min() ?? 9_999 }
        // The newest page starts wherever its own size puts it; reading past it pages in the one before.
        let newestFirst = earliest()
        XCTAssertLessThan(newestFirst, 9_999, "The newest page showed no earlier message")
        let page = app.scrollViews.firstMatch
        for _ in 0..<150 where earliest() >= newestFirst { page.swipeDown(velocity: .slow) }
        sleep(1)
        let shown = earliest()
        XCTAssertLessThan(shown, newestFirst, "The page before the newest did not load")
        // The reader stays beside the message they reached instead of jumping to the top of the new page.
        XCTAssertGreaterThan(shown, newestFirst - 100, "Loading an earlier page moved the reader to message \(shown)")
        let first = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "历史消息 0001")).firstMatch
        for _ in 0..<80 where !first.exists { page.swipeDown(velocity: .fast) }
        XCTAssertTrue(first.waitForExistence(timeout: 5), "Swiping to the top did not reach the first message")
    }
}
