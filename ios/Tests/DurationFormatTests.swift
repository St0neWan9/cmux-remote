import XCTest
@testable import CmuxRemote

/// Finished and running turns both spell their duration the way the terminal does.
@MainActor
final class DurationFormatTests: XCTestCase {
    func testFinishedTurnDurations() {
        XCTAssertEqual(ResponseRunLabel.compactDuration(7), "7s")
        XCTAssertEqual(ResponseRunLabel.compactDuration(59), "59s")
        XCTAssertEqual(ResponseRunLabel.compactDuration(227), "3m 47s")
        XCTAssertEqual(ResponseRunLabel.compactDuration(65), "1m 05s")
        XCTAssertEqual(ResponseRunLabel.compactDuration(3_600), "1h 00m")
        XCTAssertEqual(ResponseRunLabel.compactDuration(4_380), "1h 13m")
    }
    /// Both places the running line appears share one formatter, so they cannot drift apart.
    func testBothRunningLinesAgree() {
        XCTAssertTrue(LiveRunLabel.line("chat.running_duration", seconds: 227).hasSuffix(" 3m 47s"))
        XCTAssertTrue(LiveRunLabel.line("chat.compacting", seconds: 7).hasSuffix(" 7s"))
    }
    /// A finished turn spells its time exactly as it read while running.
    func testFinishedAndRunningSpellTheSame() {
        for seconds in [7, 59, 65, 90, 227, 3_599] {
            XCTAssertEqual(ResponseRunLabel.compactDuration(Double(seconds)), LiveRunLabel.timer(seconds))
        }
    }
    func testRunningTurnDurations() {
        XCTAssertEqual(LiveRunLabel.timer(0), "0s")
        XCTAssertEqual(LiveRunLabel.timer(54), "54s")
        XCTAssertEqual(LiveRunLabel.timer(65), "1m 05s")
        XCTAssertEqual(LiveRunLabel.timer(90), "1m 30s")
        XCTAssertEqual(LiveRunLabel.timer(3_600), "60m 00s")
    }
}
