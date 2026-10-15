import XCTest

/// A Mac's capsule opens the workspaces it shares; the title menu no longer holds them.
@MainActor
final class MobileWorkspaceCapsuleUITests: XCTestCase {
    func testChoosingAWorkspaceFromTheMacCapsule() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to test the list without real sessions.")
        }
        // The fixture shares a second workspace only when asked to.
        let flagFile = URL(fileURLWithPath: pairingPath).deletingLastPathComponent().appendingPathComponent("two-workspaces")
        guard FileManager.default.createFile(atPath: flagFile.path, contents: Data()) else { throw XCTSkip("The fixture state directory is not writable from the test.") }
        defer { try? FileManager.default.removeItem(at: flagFile) }
        let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let arrow = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", ".workspaces")).firstMatch
        XCTAssertTrue(arrow.waitForExistence(timeout: 10), "The Mac capsule has no workspace arrow")
        capture(app, "capsule")
        arrow.tap()
        let second = app.buttons["Second workspace"]
        XCTAssertTrue(second.waitForExistence(timeout: 5), "The capsule's menu does not list the Mac's workspaces")
        // The menu opens from the capsule's leading edge, not from its arrow at the other end.
        XCTAssertLessThan(abs(second.frame.minX - arrow.frame.minX), 40, "The workspace menu is not aligned with the capsule's leading edge")
        XCTAssertTrue(app.buttons["全部已授权工作区"].exists)
        capture(app, "workspaces")
        second.tap()
        let capsule = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Second workspace")).firstMatch
        XCTAssertTrue(capsule.waitForExistence(timeout: 5), "The capsule does not name the chosen workspace")
        capture(app, "chosen")
        // The title menu keeps order, pending items, refresh and management only.
        app.buttons["sessions.title_menu"].tap()
        XCTAssertTrue(app.buttons["sessions.refresh"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["全部已授权工作区"].exists, "The workspace filter is still in the title menu")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
