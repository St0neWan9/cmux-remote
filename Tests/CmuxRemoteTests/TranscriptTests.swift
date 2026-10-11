import Foundation
import Testing
import CmuxRemoteBridge
import CmuxAgentChat

@Suite struct TranscriptTests {
    private func temporary() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    @Test func partialLineIsNotCommittedAndAppendPreservesGeneration() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("chat.jsonl")
        let complete = #"{"type":"user","uuid":"u1","message":{"content":"Hello"}}"#
        let partial = #"{"type":"assistant","uuid":"a1","message":{"content":[{"type":"text","text":"Working"}]}}"#
        try Data((complete + "\n" + partial).utf8).write(to: file)
        let reader = TranscriptReader()
        let first = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        #expect(first.messages.count == 1)
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd(); try handle.write(contentsOf: Data([10])); try handle.close()
        let second = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        #expect(second.messages.count == 2)
        #expect(first.generation == second.generation)
    }
    @Test func truncationReanchorsHistory() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("chat.jsonl")
        try Data((#"{"type":"user","uuid":"original","message":{"content":"A long original conversation"}}"# + "\n").utf8).write(to: file)
        let reader = TranscriptReader()
        let first = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        try Data((#"{"type":"user","uuid":"new","message":{"content":"New"}}"# + "\n").utf8).write(to: file)
        let second = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        #expect(first.generation != second.generation)
        #expect(second.messages.first?.id == "new")
    }
    @Test func equalSequenceGroupsAreNotSplitByPagination() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("chat.jsonl")
        let row = #"{"type":"assistant","uuid":"multi","message":{"content":[{"type":"text","text":"One"},{"type":"text","text":"Two"}]}}"#
        try Data((row + "\n").utf8).write(to: file)
        let page = try await TranscriptReader().history(path: file.path, agent: "claude", beforeSeq: nil, limit: 1)
        #expect(page.messages.count == 2)
        #expect(!page.hasMore)
    }
    @Test func codexRolloutIsNormalizedToChat() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("chat.jsonl")
        let row = #"{"timestamp":"2026-10-11T10:00:00Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Codex reply"}]}}"#
        try Data((row + "\n").utf8).write(to: file)
        let page = try await TranscriptReader().history(path: file.path, agent: "codex", beforeSeq: nil, limit: 100)
        #expect(page.messages.count == 1)
        if case .prose(let prose) = page.messages[0].kind { #expect(prose.text == "Codex reply") }
        else { Issue.record("Expected a prose message") }
    }
}
