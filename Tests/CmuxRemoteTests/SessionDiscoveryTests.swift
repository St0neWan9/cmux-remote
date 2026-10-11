import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

private actor DiscoveryCmux: CmuxControlling {
    let dumpAvailable: Bool
    init(dumpAvailable: Bool = true) { self.dumpAvailable = dumpAvailable }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "vault.sessions":
            return .object(["sessions": .array(["managed", "outside", "registered-without-binding", "hook-managed"].map {
                .object(["session_id": .string($0), "agent": .string("claude"), "title": .string($0), "cwd": .string("/example/shared-project")])
            })])
        case "chat.sessions.dump":
            guard dumpAvailable else { throw BridgeError("method_not_found", "Unavailable") }
            return .object(["sessions": .array([
                .object(["session_id": .string("managed"), "agent": .string("claude"), "workspace_id": .string("workspace"), "surface_id": .string("surface"), "state": .string("idle")]),
                .object(["session_id": .string("registered-without-binding"), "agent": .string("claude"), "state": .string("ended")])
            ])])
        default: return .object([:])
        }
    }
}

@Suite struct SessionDiscoveryTests {
    @Test func globalHistoryDoesNotBecomeTheCmuxConversationList() async throws {
        let service = SessionService(cmux: DiscoveryCmux(), home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        let sessions = try await service.sessions()
        #expect(sessions.map(\.id) == ["managed"])
        #expect(sessions.first?.writable == true)
        do { _ = try await service.history(id: "outside", beforeSeq: nil, limit: 10); Issue.record("Outside history must not be accessible") }
        catch { #expect((error as? BridgeError)?.code == "session_not_found") }
    }
    @Test func unavailableRegistryDoesNotFallBackToGlobalHistory() async throws {
        let service = SessionService(cmux: DiscoveryCmux(dumpAvailable: false), home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        #expect(try await service.sessions().isEmpty)
        await service.acceptEvent(.object([
            "type": .string("event"), "category": .string("agent"), "workspace_id": .string("workspace"), "surface_id": .string("surface"),
            "payload": .object(["session_id": .string("hook-managed"), "hook_event_name": .string("SessionStart")])
        ]))
        #expect(try await service.sessions().map(\.id) == ["hook-managed"])
    }
    @Test func endedCmuxSessionRemainsReadOnlyWithoutImportingOutsideHistory() async throws {
        let service = SessionService(cmux: DiscoveryCmux(dumpAvailable: false), home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        await service.acceptEvent(.object([
            "type": .string("event"), "category": .string("agent"), "workspace_id": .string("workspace"), "surface_id": .string("surface"),
            "payload": .object(["session_id": .string("hook-managed"), "hook_event_name": .string("SessionEnd")])
        ]))
        let sessions = try await service.sessions()
        #expect(sessions.map(\.id) == ["hook-managed"])
        #expect(sessions.first?.writable == false)
    }
}
