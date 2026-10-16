import XCTest

/// Starting a conversation in a workspace sits before the chevron, and neither control takes the other's tap.
@MainActor
final class MobileGroupStartRowUITests: XCTestCase {
    func testStartingFromAWorkspaceRowDoesNotCollapseTheGroup() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to open conversations without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let start = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", ".start")).firstMatch
        guard start.waitForExistence(timeout: 10) else { throw XCTSkip("The fixture offers no workspace to start in") }
        let header = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sessions.group.")).firstMatch
        XCTAssertTrue(header.exists, "The grouped list has no workspace header")
        let toggle = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", ".toggle")).firstMatch
        XCTAssertTrue(toggle.exists, "The workspace row has no chevron control")
        let chevron = toggle.frame, plus = start.frame
        // Left of the chevron, sharing its vertical centre.
        XCTAssertLessThan(plus.maxX, chevron.minX + 1, "The plus is not left of the chevron")
        XCTAssertEqual(plus.midY, chevron.midY, accuracy: 2, "The plus is not on the chevron's line")
        capture(app, "group-row")
        let wasExpanded = header.value as? String
        start.tap()
        XCTAssertTrue(app.staticTexts["新会话"].waitForExistence(timeout: 5), "Tapping the plus did not open the start sheet")
        capture(app, "start-sheet")
        app.buttons.matching(NSPredicate(format: "label IN %@", ["关闭", "Close"])).firstMatch.tap()
        XCTAssertEqual(header.value as? String, wasExpanded, "Starting from the row collapsed its workspace")
        // The chevron's own target still collapses and expands the workspace.
        toggle.tap()
        XCTAssertNotEqual(header.value as? String, wasExpanded, "The chevron no longer collapses the workspace")
        toggle.tap()
        XCTAssertEqual(header.value as? String, wasExpanded, "The chevron no longer expands the workspace")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
