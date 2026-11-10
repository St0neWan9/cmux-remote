import XCTest

/// A quick trip to another app keeps the link, and the page catches up on its own once it is back.
///
/// Manual check against a real Bridge, over its encrypted link rather than the fixture's per-request pairing: pass the
/// Bridge's enrollment file as CMUX_REMOTE_REAL_RETURN_BOOTSTRAP and a session as CMUX_REMOTE_REAL_RETURN_SESSION,
/// and approve the request on the Mac while the test waits.
@MainActor
final class MobileReturnKeepsLinkUITests: XCTestCase {
    func testAQuickSwitchKeepsTheLinkAndALongOneRedials() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let bootstrap = environment["CMUX_REMOTE_REAL_RETURN_BOOTSTRAP"], !bootstrap.isEmpty,
              let sessionID = environment["CMUX_REMOTE_REAL_RETURN_SESSION"], !sessionID.isEmpty else {
            throw XCTSkip("Run against a real Bridge.")
        }
        let enrolling = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        enrolling.launchEnvironment["CMUX_REMOTE_TEST_ENROLLMENT_PATH"] = bootstrap
        enrolling.launch()
        Thread.sleep(forTimeInterval: 12)
        enrolling.terminate()

        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let session = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", sessionID)).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 30), "The session was not listed.")
        session.tap()
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "message."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30), "The conversation never showed a message.")
        Thread.sleep(forTimeInterval: 3)

        // A glance at another app: the link is kept, so the page never says it is reconnecting.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 6)
        app.activate()
        print("RETURN short at \(Date().timeIntervalSince1970)")
        let reconnecting = app.descendants(matching: .any)["connection.reconnecting"]
        let updating = app.descendants(matching: .any)["connection.updating"]
        var sawReconnecting = false
        for _ in 0..<16 {
            if reconnecting.exists { sawReconnecting = true; add(XCTAttachment(screenshot: app.screenshot())) }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertFalse(sawReconnecting, "A six-second trip to another app redialed the link.")
        XCTAssertTrue(rows.firstMatch.exists, "The page lost its messages after a short trip.")
        XCTAssertFalse(updating.exists, "The page still said it was updating four seconds after a short trip.")

        // Past iOS's background allowance the app is suspended and its sockets go: the return dials again, and the
        // page is back on fresh content within a few seconds of the link.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 45)
        app.activate()
        print("RETURN long at \(Date().timeIntervalSince1970)")
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !reconnecting.exists && !updating.exists && rows.firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 15), .completed, "The page did not settle on fresh content after a long absence.")
        add(XCTAttachment(screenshot: app.screenshot()))
    }
}
