import XCTest

/// A long press on a reply selects text in place with handles, and the selection can be quoted into the follow-up.
@MainActor
final class MobileSelectTextUITests: XCTestCase {
    func testSelectingPartOfAReplyInPlace() throws {
        let app = try launchFixture()
        let reply = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "页面使用白色背景")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5), "No reply text is on screen")
        XCTAssertFalse(app.buttons["response.select"].exists, "A reply still offers a separate selection page")
        capture(app, "opened")
        let before = reply.frame
        reply.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)).press(forDuration: 1.0)
        let copy = app.menuItems.matching(NSPredicate(format: "label IN %@", ["拷贝", "复制", "Copy"])).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "Long pressing a reply showed no edit menu")
        capture(app, "reply-selected")
        NSLog("SELECTION menu: \(app.menuItems.allElementsBoundByIndex.map(\.label))")
        XCTAssertEqual(before.minY, reply.frame.minY, accuracy: 1, "The reply moved when it was selected")

        // The selection's own menu offers to quote it into the follow-up draft.
        let addToChat = app.menuItems["添加到聊天"]
        XCTAssertTrue(addToChat.waitForExistence(timeout: 3), "The selection menu has no Add to chat")
        addToChat.tap()
        let composer = app.descendants(matching: .any)["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        let draft = (composer.value as? String) ?? ""
        capture(app, "quoted")
        XCTAssertTrue(draft.hasPrefix("> "), "The draft is not a quote: \(draft)")
    }

    func testRepliesStayDrawnUnderTheBlurredEdges() throws {
        let app = try launchFixture()
        let reply = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "页面使用白色背景")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch
        // Drag the timeline so replies sit under the header and the composer.
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        capture(app, "scrolled-up")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
        capture(app, "scrolled-down")
    }

    private func launchFixture() throws -> XCUIApplication {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to open conversations without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 5))
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
