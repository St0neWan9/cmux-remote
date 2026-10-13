import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// Prompts sent while Claude is still working appear in history as the person's own messages.
@Suite struct QueuedPromptTests {
    @Test func humanQueuedPromptBecomesAUserMessageAndAutomationDoesNot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("session.jsonl")
        let lines = [
            #"{"type":"user","uuid":"u1","timestamp":"2026-10-13T08:00:00.000Z","message":{"role":"user","content":"First prompt"}}"#,
            #"{"type":"assistant","uuid":"a1","timestamp":"2026-10-13T08:00:01.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Working on it"}]}}"#,
            #"{"type":"attachment","uuid":"q1","parentUuid":"a1","timestamp":"2026-10-13T08:00:02.000Z","attachment":{"type":"queued_command","prompt":"Sent from the phone mid-turn","origin":{"kind":"human"},"humanTurn":true}}"#,
            #"{"type":"attachment","uuid":"q2","timestamp":"2026-10-13T08:00:03.000Z","attachment":{"type":"queued_command","prompt":"<task-notification>done</task-notification>","origin":{"kind":"task-notification"}}}"#,
        ]
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
        let history = try await TranscriptReader().history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        let texts = history.messages.compactMap { message -> String? in if case .prose(let value) = message.kind { return value.text }; return nil }
        #expect(texts.contains("Sent from the phone mid-turn"))
        #expect(history.messages.first { message in if case .prose(let value) = message.kind { return value.text == "Sent from the phone mid-turn" }; return false }?.role == .user)
        #expect(!texts.contains { $0.contains("task-notification") }, "Automated queued commands must not appear as the person's messages")
    }
}
