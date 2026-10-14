import Foundation
import Testing
import CmuxAgentChat

/// A finished card shows when its result arrived, which is the result record's own timestamp —
/// not the invocation's, so the time means "finished at" rather than "started at".
@Suite struct ToolCompletionTimeTests {
    private func parse(_ rows: [String]) -> [ChatMessage] {
        ClaudeTranscriptParser().parse(lines: rows, startingSeq: 0).messages
    }
    private func call(id: String, started: String) -> String {
        let body: [String: Any] = ["type": "assistant", "uuid": id, "timestamp": started,
                                   "message": ["content": [["type": "tool_use", "id": id, "name": "Bash", "input": ["command": "sleep 2", "description": "Wait"]]]]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: body), as: UTF8.self)
    }
    private func result(id: String, finished: String) -> String {
        let body: [String: Any] = ["type": "user", "uuid": id + "-r", "timestamp": finished,
                                   "message": ["content": [["type": "tool_result", "tool_use_id": id, "content": "ok"]]]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: body), as: UTF8.self)
    }
    @Test func theFinishedCardCarriesTheCompletionTime() throws {
        let messages = parse([call(id: "t1", started: "2026-10-14T09:00:00.000Z"), result(id: "t1", finished: "2026-10-14T09:00:07.000Z")])
        let capture = try #require(messages.compactMap { message -> ChatTerminalCapture? in
            if case .terminal(let value) = message.kind { return value }; return nil
        }.last)
        #expect(capture.isRunning == false)
        let finished = try #require(capture.completedAt)
        let expected = try Date("2026-10-14T09:00:07.000Z", strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        // The result's own moment, not the invocation's.
        #expect(abs(finished.timeIntervalSince(expected)) < 0.001)
    }
    /// A call still running has no completion time, so the card shows none.
    @Test func aRunningCardHasNoCompletionTime() throws {
        let messages = parse([call(id: "t2", started: "2026-10-14T09:00:00.000Z")])
        let capture = try #require(messages.compactMap { message -> ChatTerminalCapture? in
            if case .terminal(let value) = message.kind { return value }; return nil
        }.first)
        #expect(capture.completedAt == nil)
    }
}
