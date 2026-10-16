import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

private actor RoutingDesktopFixture: CmuxControlling {
    var sends = 0
    let workspace = "99999999-1111-2222-3333-444444444444"
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "system.ping", "system.capabilities": return .object([:])
        case "workspace.list": return .object(["workspaces": .array([.object(["id": .string(workspace), "title": .string("Desktop")])])])
        case "vault.sessions": return .object(["sessions": .array([.object(["session_id": .string(TuiResourceFixture.providerID), "agent": .string("claude"), "title": .string("Desktop Agent")])])])
        case "chat.sessions.dump": return .object(["sessions": .array([.object(["session_id": .string(TuiResourceFixture.providerID), "agent": .string("claude"), "workspace_id": .string(workspace), "surface_id": .string("desktop-surface"), "state": .string("idle")])])])
        case "surface.input_state": return .object(["agent": .bool(true), "workspace_id": .string(workspace), "surface_id": .string("desktop-surface"), "blocks_typing": .bool(false)])
        case "mobile.chat.send": sends += 1; return .object(["submitted": .bool(true)])
        default: throw BridgeError("unsupported", "Fixture")
        }
    }
}

@Suite struct TuiRoutingTests {
    @Test func oneBridgeCombinesBothBackendsWithoutCollidingProviderIDsOrRoutingWritesWrongly() async throws {
        let desktop = RoutingDesktopFixture(), resource = TuiResourceFixture()
        let daemon = TuiControlAdapter(client: resource, transcripts: .init(claudeRoot: URL(fileURLWithPath: "/missing"), codexRoot: URL(fileURLWithPath: "/missing")))
        let control = CmuxBackendRouter(desktop: desktop, daemon: daemon)
        let service = SessionService(cmux: control, home: URL(fileURLWithPath: "/fixture"), transcriptRoots: [])
        #expect(try await service.workspaces()["workspaces"].array?.count == 2)
        let sessions = try await service.sessions(); #expect(sessions.count == 2)
        let live = try #require(sessions.first { $0.id.hasPrefix("tui:") })
        _ = try await service.send(id: live.id, request: .init(text: "Daemon only"))
        #expect(await desktop.sends == 0); #expect(await resource.effects.count == 1)
        _ = try await service.send(id: TuiResourceFixture.providerID, request: .init(text: "Desktop only"))
        #expect(await desktop.sends == 1); #expect(await resource.effects.count == 1)
        // A daemon conversation that is really over must not fall through to the desktop backend.
        await resource.clearAgents(); await resource.stopTerminal()
        await #expect(throws: BridgeError.self) { _ = try await service.send(id: live.id, request: .init(text: "Never fall through")) }
        #expect(await desktop.sends == 1)
    }
    @Test func exactTranscriptLookupRejectsSymlinksAndAmbiguityAndRemainsBounded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("claude/projects/first"), second = root.appendingPathComponent("claude/projects/second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let file = first.appendingPathComponent(TuiResourceFixture.providerID + ".jsonl")
        try Data("fixture".utf8).write(to: file)
        let lookup = TuiTranscriptLocator(claudeRoot: root.appendingPathComponent("claude"), codexRoot: root.appendingPathComponent("codex"))
        #expect(try lookup.locate(provider: "claude", sessionID: TuiResourceFixture.providerID, cwd: nil) == file.path)
        let duplicate = second.appendingPathComponent(TuiResourceFixture.providerID + ".jsonl")
        try FileManager.default.createSymbolicLink(at: duplicate, withDestinationURL: file)
        #expect(try lookup.locate(provider: "claude", sessionID: TuiResourceFixture.providerID, cwd: nil) == file.path)
        try FileManager.default.removeItem(at: duplicate); try Data("duplicate".utf8).write(to: duplicate)
        #expect(throws: BridgeError.self) { _ = try lookup.locate(provider: "claude", sessionID: TuiResourceFixture.providerID, cwd: nil) }
        let bounded = TuiTranscriptLocator(claudeRoot: root.appendingPathComponent("claude"), codexRoot: root.appendingPathComponent("codex"), entryLimit: 1)
        #expect(throws: BridgeError.self) { _ = try bounded.locate(provider: "claude", sessionID: TuiResourceFixture.providerID, cwd: nil) }
    }
}
