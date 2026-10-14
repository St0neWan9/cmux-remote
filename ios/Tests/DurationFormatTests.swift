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
    func testRunningTurnDurations() {
        XCTAssertEqual(LiveRunLabel.timer(0), "0s")
        XCTAssertEqual(LiveRunLabel.timer(54), "54s")
        XCTAssertEqual(LiveRunLabel.timer(65), "1m 05s")
        XCTAssertEqual(LiveRunLabel.timer(90), "1m 30s")
        XCTAssertEqual(LiveRunLabel.timer(3_600), "60m 00s")
    }
}
