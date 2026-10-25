import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// An asynchronous Agent records its own conversation under a sidecar naming its tool call; a detached
/// command writes its output beside the session. Both are read back without touching the parent conversation.
@Suite struct BackgroundTaskContentTests {
    private func temporary() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    /// A transcript at `<root>/projects/<project>/<session>.jsonl`, as the agent lays it out.
    private func layout(_ root: URL) throws -> (transcript: String, session: URL) {
        let session = root.appendingPathComponent("projects").appendingPathComponent("-Users-me-project").appendingPathComponent("session-1")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let transcript = session.deletingPathExtension().appendingPathExtension("jsonl")
        try Data((#"{"type":"user","uuid":"u1","timestamp":"2026-10-24T10:00:00.000Z","message":{"content":"Go"}}"# + "\n").utf8).write(to: transcript)
        return (transcript.path, session)
    }

    @Test func anAgentTaskReadsItsSidecarConversation() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let (transcript, session) = try layout(root)
        let subagents = session.appendingPathComponent("subagents")
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        try Data(#"{"toolUseId":"toolu_agent","description":"Audit the parser","agentType":"general-purpose","finished":false}"#.utf8)
            .write(to: subagents.appendingPathComponent("agent-a1.meta.json"))
        try Data((#"{"type":"user","isSidechain":true,"uuid":"s1","timestamp":"2026-10-24T10:00:01.000Z","message":{"content":"Audit it"}}"# + "\n" +
                  #"{"type":"assistant","isSidechain":true,"uuid":"s2","timestamp":"2026-10-24T10:00:02.000Z","message":{"content":[{"type":"text","text":"All clear"}]}}"# + "\n").utf8)
            .write(to: subagents.appendingPathComponent("agent-a1.jsonl"))
        let locator = BackgroundTaskLocator(temporaryRoot: root.appendingPathComponent("tmp").path)
        let location = try #require(locator.locate(transcript: transcript, taskID: "toolu_agent"))
        #expect(location.kind == .agent)
        // The conversation itself parses through the same reader the phone uses.
        let snapshot = try await TranscriptReader().history(path: location.path, agent: "claude", beforeSeq: nil, limit: 10, includesSidechain: true)
        #expect(snapshot.messages.contains { $0.role == .agent })
    }

    @Test func aDetachedCommandOutputPagesOnCharacterBoundaries() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("out.output")
        // "é" is two bytes; a page that ends inside it must not split the scalar.
        try Data("abcdefé".utf8).write(to: file)
        let first = try SessionService.outputPage(file.path, offset: 0, limit: 6)
        #expect(first.text == "abcdef")
        #expect(first.next == 6)
        let second = try SessionService.outputPage(file.path, offset: 6, limit: 2)
        #expect(second.text == "é")
        #expect(second.next == nil)
        #expect(second.total == 8)
    }

    @Test func anEmptyOrMissingRecordIsNotATask() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let locator = BackgroundTaskLocator(temporaryRoot: root.path)
        #expect(locator.locate(transcript: root.appendingPathComponent("x/session.jsonl").path, taskID: "nothere") == nil)
        // A task id is never a path.
        #expect(locator.locate(transcript: root.appendingPathComponent("x/session.jsonl").path, taskID: "../../etc/passwd") == nil)
    }
}
