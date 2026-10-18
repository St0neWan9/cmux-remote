import XCTest

/// Every conversation that can send offers its model menu, even when the reader only glances at it.
///
/// Manual check against real sessions: run a Bridge on the reader's cmux and pass its enrollment file as
/// CMUX_REMOTE_REAL_MODEL_BOOTSTRAP. The test opens the first conversations in the list for three seconds each.
@MainActor
final class MobileModelMenuEverywhereUITests: XCTestCase {
    func testEveryWritableConversationOffersTheModelMenuWithinAGlance() throws {
        guard let bootstrap = ProcessInfo.processInfo.environment["CMUX_REMOTE_REAL_MODEL_BOOTSTRAP"], !bootstrap.isEmpty else {
            throw XCTSkip("Run against a real Bridge.")
        }
        let enrolling = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        enrolling.launchEnvironment["CMUX_REMOTE_TEST_ENROLLMENT_PATH"] = bootstrap
        enrolling.launch()
        Thread.sleep(forTimeInterval: 12)
        enrolling.terminate()

        let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20), "No conversations were listed.")
        let ids = rows.allElementsBoundByIndex.prefix(6).map(\.identifier)
        var report: [String] = [], missing: [String] = []
        for id in ids {
            let row = app.buttons[id]
            guard row.waitForExistence(timeout: 5) else { continue }
            if !row.isHittable { app.swipeUp() }
            row.tap()
            let started = Date()
            let menu = app.descendants(matching: .any)["model.menu"]
            let shown = menu.waitForExistence(timeout: 3)
            // A conversation whose Agent is gone offers to resume it instead; it cannot send, so it has no menu.
            let resumable = app.staticTexts["恢复会话"].exists || app.buttons["恢复会话"].exists
            let writable = !resumable && app.textFields["chat.composer"].exists && app.textFields["chat.composer"].isEnabled
            report.append("\(id.suffix(12)) writable=\(writable) menu=\(shown) after=\(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            if writable && !shown { missing.append(String(id.suffix(12))) }
            app.buttons["chat.back"].tap()
            _ = rows.firstMatch.waitForExistence(timeout: 5)
        }
        print("MODELMENU " + report.joined(separator: " | "))
        XCTAssertTrue(missing.isEmpty, "These writable conversations showed no model menu within 3s: \(missing)")
    }
}
