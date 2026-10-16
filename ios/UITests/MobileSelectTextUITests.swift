import XCTest

/// A reply's text is selected in place, and the selection offers adding it to the chat, copying, sharing and selecting all.
@MainActor
final class MobileSelectTextUITests: XCTestCase {
    func testSelectingPartOfAReplyInPlace() throws {
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
        // The footer no longer opens a separate page for selection.
        XCTAssertFalse(app.buttons["response.select"].exists, "A reply still offers a separate selection page")

        capture(app, "opened")
        let reply = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "页面使用白色背景")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5), "No reply text is on screen")
        // The reply must not move when it becomes selectable: the reader's long press should keep the text still.
        // The footer of this reply, not of any other turn on the page.
        func footerBelow(_ element: XCUIElement) -> XCUIElement {
            app.buttons.matching(identifier: "response.quote").allElementsBoundByIndex
                .filter { $0.frame.minY > element.frame.maxY }.min { $0.frame.minY < $1.frame.minY } ?? element
        }
        let before = (reply.frame, footerBelow(reply).frame)
        reply.press(forDuration: 1.0)
        capture(app, "after-press")
        let add = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "添加到聊天")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Selecting a reply showed no menu with 添加到聊天")
        capture(app, "reply-selected")
        let selected = app.textViews["message.text"]
        XCTAssertTrue(selected.exists, "The reply was not selected in place")
        let after = (selected.frame, footerBelow(selected).frame)
        XCTAssertEqual(before.0.minY, after.0.minY, accuracy: 1, "The reply moved vertically when it became selectable")
        XCTAssertEqual(before.0.height, after.0.height, accuracy: 2, "The reply changed height when it became selectable")
        XCTAssertEqual(before.1.minY, after.1.minY, accuracy: 2, "The footer moved when the reply became selectable")
        for item in ["复制", "分享", "全选"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", item)).firstMatch.exists, "The menu has no \(item)")
        }
        add.tap()
        let composer = app.descendants(matching: .any)["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        let quoted = NSPredicate(format: "value BEGINSWITH %@", "> ")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: quoted, object: composer)], timeout: 5), .completed,
                       "The selection was not quoted into the draft: \(String(describing: composer.value))")
        capture(app, "quoted")
        // Adding it ends the selection, and the reply is plain text again.
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["message.text"].exists, "The reply stayed a text view after its selection ended")

        // Select all takes the whole turn.
        reply.press(forDuration: 1.0)
        let all = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "全选")).firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()
        capture(app, "select-all")
        let addAll = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "添加到聊天")).firstMatch
        XCTAssertTrue(addAll.waitForExistence(timeout: 5), "Selecting all showed no menu")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
