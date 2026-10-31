import XCTest

/// Opening a conversation from the list shows its latest message, the first time and again from the stored copy.
@MainActor
final class MobileOpenConversationUITests: XCTestCase {
    func testOpeningAConversationShowsItsLatestMessage() throws {
        guard let pairingPath = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], !pairingPath.isEmpty else {
            throw XCTSkip("Supply an isolated fixture pairing file to open conversations without real sessions.")
        }
        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        app.launchEnvironment["CMUX_REMOTE_TEST_PAIRING_PATH"] = pairingPath
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "fixture-session")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        let latest = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "white background")).firstMatch
        for pass in ["first", "stored"] {
            session.tap()
            XCTAssertTrue(app.buttons["chat.back"].waitForExistence(timeout: 5))
            var seen: [String] = []
            for (delay, name) in [(0.5, "0.5s"), (1.0, "1.5s"), (1.5, "3s")] {
                Thread.sleep(forTimeInterval: delay)
                capture(app, "\(pass)-\(name)")
                seen.append("\(name)=\(latest.exists && latest.isHittable)")
            }
            XCTAssertTrue(latest.exists && latest.isHittable, "Opening (\(pass)) did not show the latest message: \(seen.joined(separator: " "))")
            app.buttons["chat.back"].tap()
            XCTAssertTrue(session.waitForExistence(timeout: 5))
            sleep(1)
        }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
