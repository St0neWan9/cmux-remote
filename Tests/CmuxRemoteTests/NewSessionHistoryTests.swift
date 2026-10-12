import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

private actor NewSessionCmux: CmuxControlling {
    let path: String
    let state: String
    init(path: String, state: String = "idle") { self.path = path; self.state = state }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        if method == "chat.sessions.dump" {
            return .object(["sessions": .array([.object([
                "session_id": .string("new-session"), "agent": .string("claude"),
                "workspace_id": .string("workspace"), "surface_id": .string("surface"),
                "state": .string(state), "transcript_path": .string(path)
            ])])])
        }
        return .object(["sessions": .array([])])
    }
}

@Suite struct NewSessionHistoryTests {
    @Test func liveSessionOpensBeforeFirstPromptThenReadsCreatedTranscript() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("new.jsonl")
        let service = SessionService(cmux: NewSessionCmux(path: file.path), home: root, transcriptRoots: [root])
        let router = BridgeRouter(service: service, token: "fixture")
        let first = await router.respond(method: "GET", uri: "/v1/sessions/new-session/history", authorization: "Bearer fixture", body: Data())
        #expect(first.0 == 200)
        let empty = try JSONDecoder().decode(ConversationSnapshot.self, from: first.1)
        #expect(empty.messages.isEmpty && !empty.hasMore)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let repeated = try await service.history(id: "new-session", beforeSeq: nil, limit: 100)
        #expect(repeated.generation == empty.generation)
        try Data((#"{"type":"user","uuid":"first","message":{"content":"Hello"}}"# + "\n").utf8).write(to: file)
        let populated = try await service.history(id: "new-session", beforeSeq: nil, limit: 100)
        #expect(populated.messages.count == 1)
        #expect(populated.generation != empty.generation)
        try FileManager.default.removeItem(at: file)
        await #expect(throws: (any Error).self) { _ = try await service.history(id: "new-session", beforeSeq: nil, limit: 100) }
    }

    @Test func endedSessionWithMissingTranscriptStillFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = SessionService(cmux: NewSessionCmux(path: root.appendingPathComponent("gone.jsonl").path, state: "ended"), home: root, transcriptRoots: [root])
        await #expect(throws: (any Error).self) { _ = try await service.history(id: "new-session", beforeSeq: nil, limit: 100) }
    }

    @Test func emptyHistoryDoesNotBypassWorkspaceAuthorization() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = SessionService(cmux: NewSessionCmux(path: root.appendingPathComponent("new.jsonl").path), home: root, transcriptRoots: [root])
        let access = SessionAccess(clientID: "unapproved") { _, _ in throw BridgeError("scope_denied", "Denied", status: 403) }
        do {
            _ = try await service.history(id: "new-session", beforeSeq: nil, limit: 100, access: access)
            Issue.record("Empty history must still require approval")
        } catch { #expect((error as? BridgeError)?.code == "scope_denied") }
    }
}
