import XCTest

/// Two Macs, one of them gone: the bar shows the first retries, then the dead Mac is retried in the background.
///
/// Driven by `scripts/e2e-reconnect-host.py`, which runs two isolated demo Bridges, approves this phone on both,
/// and on the `kill-b` marker replaces Mac B with a port that only counts dials.
@MainActor
final class MobileReconnectQuietUITests: XCTestCase {
    func testADeadMacStopsTurningTheBarButIsStillRetried() throws {
        guard let root = ProcessInfo.processInfo.environment["CMUX_REMOTE_E2E_ROOT"], !root.isEmpty else {
            throw XCTSkip("Run with the two-Mac reconnect host script.")
        }
        for mac in ["a", "b"] {
            let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
            app.launchEnvironment["CMUX_REMOTE_TEST_ENROLLMENT_PATH"] = "\(root)/\(mac)/bootstrap.json"
            app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
            app.launch()
            Thread.sleep(forTimeInterval: 15)
            app.terminate()
        }
        FileManager.default.createFile(atPath: "\(root)/kill-b", contents: Data())
        Thread.sleep(forTimeInterval: 4)

        let app = XCUIApplication(bundleIdentifier: "com.st0newan9.cmux-remote")
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let started = Date()
        var shown: [Int] = []
        while Date().timeIntervalSince(started) < 100 {
            let second = Int(Date().timeIntervalSince(started))
            if app.otherElements["connection.reconnecting"].exists || app.otherElements["connection.offline"].exists { shown.append(second) }
            Thread.sleep(forTimeInterval: 1)
        }
        print("E2E pill seconds: \(shown)")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "after"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertFalse(shown.isEmpty, "The bar never said a Mac was unreachable.")
        XCTAssertLessThan(shown.max() ?? 0, 50, "The bar was still turning \(shown.max() ?? 0)s after launch: \(shown)")
    }
}
