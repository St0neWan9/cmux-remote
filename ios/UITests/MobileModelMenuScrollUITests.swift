import XCTest

/// The model menu stays where the reader scrolled it while the conversation behind it keeps updating.
///
/// Run against the isolated fixture while its transcript grows (a running conversation), so the page re-renders
/// under the open menu; the Mac's model choices must be long enough to scroll.
@MainActor
final class MobileModelMenuScrollUITests: XCTestCase {
    func testAnOpenModelMenuKeepsItsScrollWhileThePageUpdates() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file.")
        }
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        let menu = app.buttons["model.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        // Let the opening reads and the background model refresh land first, as a reader would.
        sleep(3)
        menu.tap()
        let custom = app.buttons["model.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        // Scroll the menu down from one of its rows, then let the page keep updating behind it.
        let row = app.buttons["Haiku"]
        XCTAssertTrue(row.waitForExistence(timeout: 3), "The menu shows no built-in model rows.")
        row.swipeUp(velocity: .slow)
        sleep(1)
        // Menu rows carry no identifier; the page's own buttons all do.
        func visibleRows() -> Set<String> {
            Set(app.buttons.allElementsBoundByIndex.filter { $0.identifier.isEmpty && $0.isHittable }.map(\.label))
        }
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        let scrolled = visibleRows()
        shot("scrolled")
        XCTAssertFalse(scrolled.isEmpty, "Scrolling closed the menu.")
        XCTAssertFalse(custom.exists && custom.isHittable, "The menu did not scroll away from its top.")
        sleep(6)
        shot("after-6s")
        XCTAssertFalse(custom.exists && custom.isHittable, "The open menu jumped back to its top while the page updated.")
        XCTAssertEqual(visibleRows(), scrolled, "The open menu moved while the page updated.")
    }
}
