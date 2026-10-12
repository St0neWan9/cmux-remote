import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxAgentChat

private actor ToolDetailCmux: CmuxControlling {
    let transcript: String
    var workspace = "workspace"
    init(transcript: String) { self.transcript = transcript }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "vault.sessions": return .object(["sessions": .array([.object(["session_id": .string("session"), "agent": .string("claude"), "file": .string(transcript)])])])
        case "chat.sessions.dump": return .object(["sessions": .array([.object(["session_id": .string("session"), "agent": .string("claude"), "workspace_id": .string(workspace), "surface_id": .string("surface")])])])
        default: return .object([:])
        }
    }
}
private actor DetailRevocation {
    var checks = 0
    func check(_ capability: ClientCapability, _ workspace: String) throws {
        #expect(capability == .conversationRead && workspace == "workspace")
        checks += 1
        if checks == 2 { throw BridgeError("scope_denied", "Grant revoked", status: 403) }
    }
}

@Suite struct ToolDetailTests {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cmux-tool-detail-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func claude(input: String, output: String) throws -> Data {
        let rows: [[String: Any]] = [
            ["type": "assistant", "uuid": "call", "message": ["content": [["type": "tool_use", "id": "tool", "name": "Read", "input": ["file_path": input]]]]],
            ["type": "user", "uuid": "result", "message": ["content": [["type": "tool_result", "tool_use_id": "tool", "content": output]]]],
        ]
        return try rows.reduce(into: Data()) { data, row in data.append(try JSONSerialization.data(withJSONObject: row)); data.append(10) }
    }
    @Test func readInputAndLongOutputRemainAvailableBeyondHistoryBudgets() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("claude.jsonl")
        let input = "/project/" + String(repeating: "路径", count: 1600)
        let output = String(repeating: "line of recorded output\n", count: 2000) + "FINAL_MARKER"
        try claude(input: input, output: output).write(to: file)
        let reader = TranscriptReader(); let snapshot = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        guard case .toolUse(let summary) = snapshot.messages[0].kind else { Issue.record("Expected Read tool"); return }
        #expect(summary.inputDetail?.count == 2049 && summary.output?.count == 16385)
        let completeInput = try await reader.toolText(path: file.path, agent: "claude", messageID: "call", generation: snapshot.generation, field: "input", offset: 0, contentID: nil, limit: 16_384)
        #expect(completeInput.text.contains(input) && completeInput.nextOffset == nil)
        var collected = ""; var offset = 0; var revision: String?
        repeat {
            let page = try await reader.toolText(path: file.path, agent: "claude", messageID: "call", generation: snapshot.generation, field: "output", offset: offset, contentID: revision, limit: 16_384)
            #expect(page.text.count <= 16_384 && page.totalCharacters == output.count)
            revision = page.contentID; collected += page.text
            guard let next = page.nextOffset else { break }; offset = next
        } while true
        #expect(collected == output && collected.hasSuffix("FINAL_MARKER"))
    }
    @Test func oversizedGraphemeStillProducesBoundedTraversablePages() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("combining.jsonl")
        let output = "a" + String(repeating: "\u{0301}", count: 4_500_000)
        try claude(input: "README.md", output: output).write(to: file)
        let reader = TranscriptReader(); let snapshot = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        let page = try await reader.toolText(path: file.path, agent: "claude", messageID: "call", generation: snapshot.generation, field: "output", offset: 0, contentID: nil, limit: 16_384)
        #expect(page.text.utf8.count <= 65_536)
        #expect(page.nextOffset != nil)
    }
    @Test func shortReadInputIsNotLostAndUnsupportedFieldsNeverExposeAnotherMessage() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("claude.jsonl")
        try claude(input: "/project/README.md", output: "File contents").write(to: file)
        let reader = TranscriptReader(); let snapshot = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        let input = try await reader.toolText(path: file.path, agent: "claude", messageID: "call", generation: snapshot.generation, field: "input", offset: 0, contentID: nil, limit: 16_384)
        #expect(input.text.contains("README.md"))
        for (message, field, offset, code) in [("missing", "input", 0, "detail_not_found"), ("call", "prose", 0, "invalid_input"), ("call", "input", -1, "invalid_input"), ("call", "input", Int.max, "invalid_input")] {
            do { _ = try await reader.toolText(path: file.path, agent: "claude", messageID: message, generation: snapshot.generation, field: field, offset: offset, contentID: nil, limit: 16_384); Issue.record("Expected \(code)") }
            catch { #expect((error as? BridgeError)?.code == code) }
        }
    }
    @Test func replacementAndChangedOutputInvalidatePagingCoordinates() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("claude.jsonl")
        try claude(input: "README.md", output: "Original recorded output").write(to: file)
        let reader = TranscriptReader(); let snapshot = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        let page = try await reader.toolText(path: file.path, agent: "claude", messageID: "call", generation: snapshot.generation, field: "output", offset: 0, contentID: nil, limit: 8)
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd()
        let extra: [String: Any] = ["type":"assistant","uuid":"unrelated","message":["content":[["type":"text","text":"Unrelated append"]]]]
        try handle.write(contentsOf: JSONSerialization.data(withJSONObject: extra) + Data([10])); try handle.close()
        let afterAppend = try await reader.toolText(path: file.path, agent: "claude", messageID: "call", generation: snapshot.generation, field: "output", offset: 8, contentID: page.contentID, limit: 8)
        #expect(afterAppend.contentID == page.contentID)
        // Replacement preserves the call ID but changes the inode and its generation.
        try claude(input: "README.md", output: "New output").write(to: file, options: .atomic)
        do { _ = try await reader.toolText(path: file.path, agent: "claude", messageID: "call", generation: snapshot.generation, field: "output", offset: 8, contentID: page.contentID, limit: 8); Issue.record("Expected generation invalidation") }
        catch { #expect((error as? BridgeError)?.code == "stale_detail") }
        let current = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        do { _ = try await reader.toolText(path: file.path, agent: "claude", messageID: "call", generation: current.generation, field: "output", offset: 8, contentID: page.contentID, limit: 8); Issue.record("Expected content invalidation") }
        catch { #expect((error as? BridgeError)?.code == "stale_detail") }
    }
    @Test func partialResultIsNotCommittedAndCodexOutputIsFullyPaged() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("codex.jsonl")
        let output = String(repeating: "text-", count: 8000) + "END"
        let rows: [[String: Any]] = [
            ["type":"response_item","payload":["type":"function_call","name":"exec_command","call_id":"codex-tool","arguments":"{\"cmd\":\"cat README.md\"}"]],
            ["type":"response_item","payload":["type":"function_call_output","call_id":"codex-tool","output":output]]
        ]
        let first = try JSONSerialization.data(withJSONObject: rows[0]) + Data([10])
        let unfinished = try JSONSerialization.data(withJSONObject: rows[1])
        try (first + unfinished).write(to: file)
        let reader = TranscriptReader(); let snapshot = try await reader.history(path: file.path, agent: "codex", beforeSeq: nil, limit: 100)
        let id = try #require(snapshot.messages.first?.id)
        let absent = try await reader.toolText(path: file.path, agent: "codex", messageID: id, generation: snapshot.generation, field: "output", offset: 0, contentID: nil, limit: 16_384)
        #expect(absent.text.isEmpty)
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd(); try handle.write(contentsOf: Data([10])); try handle.close()
        let full = try await reader.toolText(path: file.path, agent: "codex", messageID: id, generation: snapshot.generation, field: "output", offset: 0, contentID: nil, limit: 100_000)
        #expect(full.text.count == 16_384 && full.totalCharacters == output.count)
    }
    @Test func routeRequiresCurrentConversationScopeAndRechecksBeforeReturningBytes() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("chat.jsonl"); try claude(input: "README.md", output: "Private tool text").write(to: file)
        let cmux = ToolDetailCmux(transcript: file.path)
        let service = SessionService(cmux: cmux, home: root, transcriptRoots: [root])
        let snapshot = try await service.history(id: "session", beforeSeq: nil, limit: 100)
        let router = BridgeRouter(service: service, token: "fixture-token")
        let uri = "/v1/sessions/session/tool-detail?message_id=call&generation=\(snapshot.generation)&field=output"
        let unauthorized = await router.respond(method: "GET", uri: uri, authorization: nil, body: Data())
        #expect(unauthorized.0 == 401)
        let success = await router.respond(method: "GET", uri: uri, authorization: "Bearer fixture-token", body: Data())
        let page = try JSONDecoder().decode(ToolTextPage.self, from: success.1)
        #expect(success.0 == 200 && page.text == "Private tool text")
        let malformed = await router.respond(method: "GET", uri: uri + "&offset=invalid", authorization: "Bearer fixture-token", body: Data())
        #expect(malformed.0 == 400)
        let revoked = DetailRevocation()
        let access = SessionAccess { capability, workspace in try await revoked.check(capability, workspace) }
        do { _ = try await service.toolText(id: "session", messageID: "call", generation: snapshot.generation, field: "output", offset: 0, contentID: nil, limit: 16_384, access: access); Issue.record("Expected final revocation denial") }
        catch { #expect((error as? BridgeError)?.code == "scope_denied") }
    }
}
