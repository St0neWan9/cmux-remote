import XCTest

/// Two Macs, one of them gone: its tab turns for the first retries, then shows a red dot while it is retried in the background.
///
/// Driven by `scripts/e2e-reconnect-host.py`, which runs two isolated demo Bridges, approves this phone on both,
/// and on the `kill-b` marker replaces Mac B with a port that only counts dials.
@MainActor
final class MobileReconnectQuietUITests: XCTestCase {
    func testADeadMacsTabStopsTurningButIsStillRetried() throws {
        guard let root = ProcessInfo.processInfo.environment["CMUX_REMOTE_E2E_ROOT"], !root.isEmpty else {
            throw XCTSkip("Run with the two-Mac reconnect host script.")
        }
        for mac in ["a", "b"] {
            let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
            app.launchEnvironment["CMUX_REMOTE_TEST_ENROLLMENT_PATH"] = "\(root)/\(mac)/bootstrap.json"
            app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
            app.launch()
            Thread.sleep(forTimeInterval: 15)
            app.terminate()
        }
        FileManager.default.createFile(atPath: "\(root)/kill-b", contents: Data())
        Thread.sleep(forTimeInterval: 4)

        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let started = Date()
        var shown: [Int] = []
        var unreachable = false
        var captured = false
        let tabs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sessions.host."))
        while Date().timeIntervalSince(started) < 100 {
            let second = Int(Date().timeIntervalSince(started))
            let values = tabs.allElementsBoundByIndex.compactMap { $0.value as? String }
            if values.contains("正在重新连接…") {
                shown.append(second)
                if !captured { captured = true; let turning = XCTAttachment(screenshot: app.screenshot()); turning.name = "turning"; turning.lifetime = .keepAlways; add(turning) }
            }
            if values.contains("无法连接到 Mac") { unreachable = true }
            Thread.sleep(forTimeInterval: 1)
        }
        print("E2E pill seconds: \(shown)")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "after"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(unreachable, "The Mac's tab never showed it was unreachable.")
        XCTAssertLessThan(shown.max() ?? 0, 50, "The tab was still turning \(shown.max() ?? 0)s after launch: \(shown)")
    }
}
