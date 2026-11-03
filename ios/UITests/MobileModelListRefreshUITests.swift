import XCTest

/// A model the owner adds to, or removes from, the agent's configuration shows the next time a conversation opens.
///
/// Run against the isolated fixture started with a private home (CFFIXED_USER_HOME); CMUX_REMOTE_MODEL_SETTINGS_PATH
/// names that home's `.claude/settings.json`, which this test rewrites between two visits to one conversation.
@MainActor
final class MobileModelListRefreshUITests: XCTestCase {
    func testAChangedModelListShowsWhenTheConversationOpensAgain() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let pairingPath = environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty,
              let settings = environment["CMUX_REMOTE_MODEL_SETTINGS_PATH"], !settings.isEmpty else {
            throw XCTSkip("Supply an isolated fixture whose home's Claude settings this test may rewrite.")
        }
        func configure(_ label: String) throws {
            let body = #"{"modelPicker":{"options":[{"model":"fixture-model","label":"\#(label)"}]}}"#
            try Data(body.utf8).write(to: URL(fileURLWithPath: settings))
        }
        try configure("Alpha 模型")
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        func openMenu() {
            XCTAssertTrue(session.waitForExistence(timeout: 10))
            session.tap()
            let menu = app.buttons["model.menu"]
            XCTAssertTrue(menu.waitForExistence(timeout: 10))
            sleep(2)
            menu.tap()
            XCTAssertTrue(app.buttons["model.custom"].waitForExistence(timeout: 5))
        }
        func closeMenuAndLeave() {
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
            sleep(1)
            app.buttons["chat.back"].tap()
        }
        openMenu()
        XCTAssertTrue(app.buttons["Alpha 模型"].exists, "The configured model was not offered.")
        closeMenuAndLeave()

        // The owner changes the agent's configuration on the Mac while the app keeps running.
        try configure("Beta 模型")
        openMenu()
        XCTAssertTrue(app.buttons["Beta 模型"].waitForExistence(timeout: 5), "The conversation kept the list it read before the change.")
        XCTAssertFalse(app.buttons["Alpha 模型"].exists, "A model removed from the configuration was still offered.")
        closeMenuAndLeave()
    }
}
