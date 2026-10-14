import XCTest
@testable import CmuxRemote

/// Finished and running turns both spell their duration the way the terminal does.
final class DurationFormatTests: XCTestCase {
    func testFinishedTurnDurations() {
        XCTAssertEqual(ResponseRunLabel.compactDuration(7), "7s")
        XCTAssertEqual(ResponseRunLabel.compactDuration(59), "59s")
        XCTAssertEqual(ResponseRunLabel.compactDuration(227), "3m 47s")
        XCTAssertEqual(ResponseRunLabel.compactDuration(3_600), "1h 0m")
        XCTAssertEqual(ResponseRunLabel.compactDuration(4_380), "1h 13m")
    }
    /// Both places the running line appears share one formatter, so they cannot drift apart.
    func testBothRunningLinesAgree() {
        XCTAssertEqual(LiveRunLabel.line("chat.running_duration", seconds: 227), "运行中 3m 47s")
        XCTAssertEqual(LiveRunLabel.line("chat.running_duration", seconds: 7), "运行中 7s")
        XCTAssertEqual(LiveRunLabel.line("chat.compacting", seconds: 227), "正在压缩上下文 3m 47s")
    }
    func testRunningTurnDurations() {
        XCTAssertEqual(LiveRunLabel.timer(0), "0s")
        XCTAssertEqual(LiveRunLabel.timer(54), "54s")
        XCTAssertEqual(LiveRunLabel.timer(65), "1m 05s")
        XCTAssertEqual(LiveRunLabel.timer(90), "1m 30s")
        XCTAssertEqual(LiveRunLabel.timer(3_600), "60m 00s")
    }
}
