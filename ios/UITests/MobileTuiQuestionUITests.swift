import XCTest

/// A question a Claude Agent asks in a cmux-tui terminal is answered from its conversation card.
///
/// Manual end-to-end check against a real daemon: run the branch Bridge on the daemon socket, start Claude in a
/// workspace named "…问题探测" with a prompt that asks two questions (方案: 快速方案/稳妥方案, single choice;
/// 范围: 前端/后端, several), and pass the Bridge's enrollment file as CMUX_REMOTE_TUI_QUESTION_BOOTSTRAP and the
/// waiting conversation's ID (`tui:…`) as CMUX_REMOTE_TUI_QUESTION_SESSION.
@MainActor
final class MobileTuiQuestionUITests: XCTestCase {
    func testTheConversationCardAnswersTheAgentsMenu() throws {
        guard let bootstrap = ProcessInfo.processInfo.environment["CMUX_REMOTE_TUI_QUESTION_BOOTSTRAP"], !bootstrap.isEmpty else {
            throw XCTSkip("Run against a cmux-tui daemon with an Agent waiting on a question.")
        }
        let enrolling = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        enrolling.launchEnvironment["CMUX_REMOTE_TEST_ENROLLMENT_PATH"] = bootstrap
        enrolling.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        enrolling.launch()
        Thread.sleep(forTimeInterval: 15)
        enrolling.terminate()

        let app = XCUIApplication(bundleIdentifier: "cmux-remote.mobile")
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        // CMUX_REMOTE_TUI_QUESTION_SESSION names the waiting conversation exactly; an earlier probe has the same title.
        let wanted = ProcessInfo.processInfo.environment["CMUX_REMOTE_TUI_QUESTION_SESSION"] ?? ""
        let session = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "session.", wanted)).firstMatch
        if !session.waitForExistence(timeout: 15) {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "sessions.group.", "问题探测")).firstMatch.tap()
        }
        XCTAssertTrue(session.waitForExistence(timeout: 15), "The probe conversation was not listed.")
        session.tap()

        let careful = app.descendants(matching: .any)["feed.question.option.0.2"]
        XCTAssertTrue(careful.waitForExistence(timeout: 30), "The question card offered no answer form.")
        careful.tap()
        let front = app.descendants(matching: .any)["feed.question.option.1.1"]
        if !front.isHittable { app.swipeUp() }
        front.tap()
        app.descendants(matching: .any)["feed.question.option.1.2"].tap()
        let submit = app.descendants(matching: .any)["feed.question.submit"]
        if !submit.isHittable { app.swipeUp() }
        XCTAssertTrue(submit.isEnabled, "Every question was answered, yet the form would not submit.")
        submit.tap()
        Thread.sleep(forTimeInterval: 4)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "answered"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertFalse(app.descendants(matching: .any)["feed.question.submit"].exists, "The form is still waiting after the answer was sent.")
    }
}
