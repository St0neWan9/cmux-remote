import XCTest

/// Starts a conversation from the phone against the isolated fixture, which records the terminal instead of opening one.
@MainActor
final class MobileStartSessionUITests: XCTestCase {
    func testStartAConversationInAFolderAndOpenIt() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file; this test must never start a real agent.")
        }
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        // Starting a conversation is under the list's title menu.
        let menu = app.buttons["sessions.title_menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        capture(app, "list")
        menu.tap()
        let start = app.buttons["sessions.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let workspace = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "start.workspace.")).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 5))
        capture(app, "workspaces")
        workspace.tap()
        let root = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "start.root.")).firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        capture(app, "roots")
        root.tap()
        let sources = app.buttons["Sources"]
        XCTAssertTrue(sources.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["docs"].exists)
        capture(app, "folder")
        sources.tap()
        let folder = app.buttons["App"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        folder.tap()
        XCTAssertTrue(app.staticTexts["没有子目录。"].waitForExistence(timeout: 5))
        app.buttons["Codex"].tap()
        // Codex needs a first message before it can start.
        XCTAssertFalse(app.buttons["start.here"].isEnabled)
        let prompt = app.textFields["start.prompt"].exists ? app.textFields["start.prompt"] : app.textViews["start.prompt"]
        prompt.tap()
        prompt.typeText("检查构建")
        XCTAssertTrue(app.buttons["start.here"].isEnabled)
        capture(app, "subfolder")
        app.buttons["start.here"].tap()
        // The list waits for the new conversation and opens it.
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 20))
        capture(app, "started")
        app.buttons["chat.back"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-started")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "list-after")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
