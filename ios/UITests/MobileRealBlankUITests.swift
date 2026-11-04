import XCTest

/// Opens one real conversation and holds it to never showing a blank page: on opening from the list, while the
/// agent keeps writing, and after the app comes back from the background.
///
/// A blank page is a page whose scroll view shows no message row at all although the conversation has messages.
/// It reproduced only on real, running conversations with long tool output, so the session is supplied by the caller.
@MainActor
final class MobileRealBlankUITests: XCTestCase {
    func testARunningConversationNeverGoesBlank() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let sessionID = environment["CMUX_REMOTE_TEST_BLANK_SESSION"], !sessionID.isEmpty else {
            throw XCTSkip("Supply the id of a running real session.")
        }
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        if let pairingPath = environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty {
            app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        }
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", sessionID)).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 30), "The real session did not appear in the list")
        let seconds = TimeInterval(environment["CMUX_REMOTE_TEST_BLANK_SECONDS"] ?? "") ?? 20

        for visit in 1...3 {
            session.tap()
            XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 10))
            watch(app, label: "open\(visit)", seconds: seconds)
            // Out to the home screen and back, as a reader switching apps does.
            XCUIDevice.shared.press(.home)
            Thread.sleep(forTimeInterval: 4)
            app.activate()
            watch(app, label: "return\(visit)", seconds: seconds)
            app.buttons["chat.back"].tap()
            XCTAssertTrue(session.waitForExistence(timeout: 20), "The list did not come back")
            // A cold launch opens the conversation from the phone's stored copy, which by now holds every page the
            // background fill read: the state a reader is in the next day, and the one the page went blank in.
            app.terminate()
            app.launch()
            XCTAssertTrue(session.waitForExistence(timeout: 30), "The real session did not appear after a relaunch")
        }
    }
    /// Samples the page every half second; once it has shown a message row, it must keep showing one.
    private func watch(_ app: XCUIApplication, label: String, seconds: TimeInterval) {
        let page = app.scrollViews.firstMatch
        let deadline = Date().addingTimeInterval(seconds)
        var shown = false
        var blank = 0
        var sample = 0
        while Date() < deadline {
            sample += 1
            let visible = page.frame
            let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "message.")).allElementsBoundByIndex
            let inView = rows.contains { row in
                let frame = row.frame
                return !frame.isEmpty && frame.intersects(visible) && frame.height > 1
            }
            if inView { shown = true; blank = 0 }
            else if shown {
                blank += 1
                capture(app, "\(label)-blank-\(sample)")
                print("BLANK \(label) sample=\(sample) rows=\(rows.count) page=\(visible)")
                // A frame or two can land between a scroll and its layout; a page blank for over a second is the bug.
                XCTAssertLessThan(blank, 3, "The page went blank (\(label), sample \(sample))")
                if blank >= 3 { return }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(shown, "The page never showed a message (\(label))")
        if !shown { capture(app, "\(label)-never") }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
