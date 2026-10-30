import Foundation
import Testing
@testable import CmuxRemoteBridge

/// A Workflow keeps its run in a journal of steps, not in the empty `.output` file its launch result names.
@Suite struct WorkflowTaskTests {
    private func journal(_ rows: [[String: Any]]) throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("journal.jsonl")
        try rows.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }

    @Test func rendersStepsByPhaseWithTheirResults() throws {
        let path = try journal([
            ["type": "launched"],
            ["type": "started", "key": "a", "label": "Apple docs", "phase": "Research"],
            ["type": "started", "key": "b", "label": "synthesize", "phase": "Synthesize"],
            ["type": "result", "key": "a", "result": "Found the entitlement name."],
        ])
        let text = try SessionService.workflowText(path)
        #expect(text.contains("2 steps, 1 finished"))
        #expect(text.contains("== Research =="))
        #expect(text.contains("· Apple docs"))
        #expect(text.contains("  Found the entitlement name."))
        // A step whose result never arrived still appears, so a stalled run reads as stalled rather than empty.
        #expect(text.contains("· synthesize"))
        #expect(text.contains("(no result recorded)"))
    }

    /// A workflow whose steps report structured findings shows them rather than an empty line.
    @Test func rendersAStructuredResult() throws {
        let path = try journal([
            ["type": "started", "key": "a", "label": "Apple docs", "phase": "Research"],
            ["type": "result", "key": "a", "result": ["findings": [["claim": "The entitlement is requestable"]]]],
        ])
        let text = try SessionService.workflowText(path)
        #expect(text.contains("The entitlement is requestable"))
        #expect(text.contains("findings"))
    }

    @Test func anEmptyJournalSaysSoRatherThanReturningNothing() throws {
        let path = try journal([["type": "launched"]])
        #expect(try SessionService.workflowText(path).contains("recorded no steps"))
    }

    /// The journal is paged like a command's output, so a long run arrives in bounded pieces.
    @Test func pagesGeneratedTextOnCharacterBoundaries() {
        let text = String(repeating: "结果 line\n", count: 200)
        let first = SessionService.textPage(text, offset: 0, limit: 64)
        #expect(first.text.utf8.count <= 64)
        #expect(first.total == text.utf8.count)
        let next = try! #require(first.next)
        let second = SessionService.textPage(text, offset: next, limit: 1_000_000)
        #expect(second.next == nil)
    }
}

/// The row that lists a Workflow names the run, not the script it was started from.
@Suite struct WorkflowLaunchSummaryTests {
    private func row(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    @Test func aWorkflowIsNamedByItsOwnSummary() {
        let use: [String: Any] = ["type": "tool_use", "id": "toolu_w", "name": "Workflow", "input": ["script": "export const meta = { name: 'passkey' }"]]
        let call = row(["type": "assistant", "message": ["content": [use]]])
        let text = "Workflow launched in background. Task ID: wd0tx4vrw\nSummary: Research the entitlement\nTranscript dir: /tmp/wf_1"
        let answer: [String: Any] = ["type": "tool_result", "tool_use_id": "toolu_w", "content": [["type": "text", "text": text]]]
        let result = row(["type": "user", "message": ["content": [answer]]])
        let running = BackgroundTaskTracker().running(in: [call, result], at: Date())
        #expect(running.map(\.summary) == ["Research the entitlement"])
    }
}
