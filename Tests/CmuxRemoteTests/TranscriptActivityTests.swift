import Foundation
import Testing
@testable import CmuxRemoteBridge

@Suite struct TranscriptActivityTests {
    @Test func newestMessageTimeIgnoresBookkeepingAndPartialLines() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        // Mode and permission records arrive when an idle session is reopened; they are not activity.
        let claude = [#"{"type":"user","timestamp":"2026-10-13T09:00:00.000Z","message":{"role":"user","content":"a"}}"#,
                      #"{"type":"assistant","timestamp":"2026-10-13T09:05:30.250Z","message":{"role":"assistant","content":[]}}"#,
                      #"{"type":"queue-operation","operation":"dequeue","timestamp":"2026-10-13T11:00:00.000Z"}"#,
                      #"{"type":"mode","mode":"normal"}"#,
                      #"{"type":"permission-mode","permissionMode":"default"}"#].joined(separator: "\n") + "\n"
        try Data(claude.utf8).write(to: file)
        let expected = try Date("2026-10-13T09:05:30.250Z", strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        #expect(TranscriptActivity().lastMessage(path: file.path, size: claude.utf8.count) == expected)
        let codex = [#"{"type":"response_item","timestamp":"2026-10-13T08:00:00Z","payload":{"type":"message"}}"#,
                     #"{"type":"event_msg","timestamp":"2026-10-13T12:00:00Z","payload":{"type":"token_count"}}"#].joined(separator: "\n") + "\n"
        try Data(codex.utf8).write(to: file)
        #expect(TranscriptActivity().lastMessage(path: file.path, size: codex.utf8.count) == (try Date("2026-10-13T08:00:00Z", strategy: .iso8601)))
        // Large attachment records after the reply widen the search instead of falling back to write time.
        let buried = #"{"type":"assistant","timestamp":"2026-10-13T10:00:00Z","message":{"role":"assistant","content":[]}}"# + "\n"
            + #"{"type":"attachment","timestamp":"2026-10-13T10:00:01Z","note":""# + String(repeating: "x", count: 400_000) + "\"}\n" + #"{"type":"mode","mode":"normal"}"# + "\n"
        try Data(buried.utf8).write(to: file)
        #expect(TranscriptActivity().lastMessage(path: file.path, size: buried.utf8.count) == (try Date("2026-10-13T10:00:00Z", strategy: .iso8601)))
        // A fragment cut by the widest window must not be trusted, and no message means no activity time.
        let large = #"{"type":"user","timestamp":"2026-10-13T10:00:00Z","note":""# + String(repeating: "x", count: 2_200_000) + "\"}\n" + #"{"type":"mode","mode":"normal"}"# + "\n"
        try Data(large.utf8).write(to: file)
        #expect(TranscriptActivity().lastMessage(path: file.path, size: large.utf8.count) == nil)
    }
}
