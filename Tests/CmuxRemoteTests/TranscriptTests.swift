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
    @Test func longTranscriptReadsAClippedTailWithAStableWindow() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("chat.jsonl")
        func row(_ id: String) -> String { #"{"type":"user","uuid":""# + id + #"","message":{"content":"message "# + id + #""}}"# + "\n" }
        // Each row is 70-80 bytes; a 400-byte window with 100-byte steps keeps 300 to 400 bytes of tail.
        try Data((1...12).map { row(String(format: "m%02d", $0)) }.joined().utf8).write(to: file)
        let reader = TranscriptReader(windowLimit: 400, windowStep: 100)
        let first = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        #expect(first.clipped)
        #expect(!first.hasMore)
        #expect(first.messages.last?.id == "m12")
        #expect(first.messages.count >= 3 && first.messages.count <= 5)
        // The record cut by the window start is never shown as a partial message.
        #expect(first.messages.allSatisfy { message in
            if case .prose(let prose) = message.kind { return prose.text == "message " + message.id } else { return false }
        })
        // Growth inside the same step keeps the generation; crossing a step re-anchors the client.
        let size = try #require(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber).intValue
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd()
        var appended = 0; var index = 13
        while (size + appended - 400 + 99) / 100 == (size - 400 + 99) / 100 {
            let next = row(String(format: "m%02d", index)); try handle.write(contentsOf: Data(next.utf8)); appended += next.utf8.count; index += 1
            if (size + appended - 400 + 99) / 100 == (size - 400 + 99) / 100 {
                let same = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
                #expect(same.generation == first.generation)
            }
        }
        try handle.close()
        let moved = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        #expect(moved.generation != first.generation)
        #expect(moved.clipped)
        #expect(moved.messages.last?.id == String(format: "m%02d", index - 1))
    }
    @Test func compactionSummaryBecomesAStatusRowNotAUserBubble() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("chat.jsonl")
        let rows = [#"{"type":"user","uuid":"before","timestamp":"2026-10-13T10:00:00.000Z","message":{"content":"Earlier prompt"}}"#,
                    #"{"type":"user","uuid":"summary","isCompactSummary":true,"isVisibleInTranscriptOnly":true,"timestamp":"2026-10-13T10:45:07.265Z","message":{"role":"user","content":"This session is being continued from a previous conversation. A very long summary."}}"#,
                    #"{"type":"user","uuid":"after","timestamp":"2026-10-13T10:46:00.000Z","message":{"content":"Next prompt"}}"#]
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: file)
        let page = try await TranscriptReader().history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        #expect(page.messages.map(\.id) == ["before", "summary", "after"])
        let summary = try #require(page.messages.first { $0.id == "summary" })
        #expect(summary.role == .system)
        if case .status(let status) = summary.kind { #expect(status.event == .contextCompacted) }
        else { Issue.record("Expected a compaction status row") }
        #expect(!page.messages.contains { message in
            if case .prose(let prose) = message.kind { return prose.text.contains("being continued") } else { return false }
        })
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
