import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

private actor DiscoveryCmux: CmuxControlling {
    let dumpAvailable: Bool
    let tabTitle: String
    /// A compaction can leave the daemon's row without its terminal binding for a while.
    let dumpDropsBinding: Bool
    init(dumpAvailable: Bool = true, tabTitle: String = "Renamed tab", dumpDropsBinding: Bool = false) {
        self.dumpAvailable = dumpAvailable; self.tabTitle = tabTitle; self.dumpDropsBinding = dumpDropsBinding
    }
    /// The cmux tree shape the bridge reads for tab names.
    var tree: JSONValue {
        let surface: JSONValue = .object(["id": .string("surface"), "type": .string("terminal"), "title": .string(tabTitle)])
        let pane: JSONValue = .object(["id": .string("surface"), "surfaces": .array([surface])])
        let workspace: JSONValue = .object(["id": .string("workspace"), "title": .string("Project"), "panes": .array([pane])])
        return .object(["windows": .array([.object(["workspaces": .array([workspace])])])])
    }

    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "vault.sessions":
            return .object(["sessions": .array(["managed", "outside", "registered-without-binding", "hook-managed"].map {
                .object(["session_id": .string($0), "agent": .string("claude"), "title": .string($0), "cwd": .string("/example/shared-project")])
            })])
        case "system.tree":
            return tree
        case "chat.sessions.dump":
            guard dumpAvailable else { throw BridgeError("method_not_found", "Unavailable") }
            return .object(["sessions": .array([
                dumpDropsBinding
                    ? .object(["session_id": .string("managed"), "agent": .string("claude"), "state": .string("working")])
                    : .object(["session_id": .string("managed"), "agent": .string("claude"), "workspace_id": .string("workspace"), "surface_id": .string("surface"), "state": .string("idle")]),
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
    @Test func aRenamedTabNamesTheConversationOverTheAgentsOwnTitle() async throws {
        let service = SessionService(cmux: DiscoveryCmux(), home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        #expect(try await service.sessions().first?.title == "Renamed tab")
    }
    @Test func aDirectoryShapedTabNameNeverRenamesTheConversation() async throws {
        let service = SessionService(cmux: DiscoveryCmux(tabTitle: "~/projects/cmux-remote"), home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        let sessions = try await service.sessions()
        #expect(sessions.first(where: { $0.id == "managed" })?.title == "managed")
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
    @Test func aDumpRowWithoutABindingKeepsTheLiveHookBinding() async throws {
        // A compaction restarts the agent session inside the running turn; the daemon's row can lose its
        // workspace/surface while the hook stream still carries them. The conversation must stay writable.
        let service = SessionService(cmux: DiscoveryCmux(dumpDropsBinding: true), home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        await service.acceptEvent(.object([
            "type": .string("event"), "category": .string("agent"), "workspace_id": .string("workspace"), "surface_id": .string("surface"),
            "payload": .object(["session_id": .string("managed"), "hook_event_name": .string("SessionStart")])
        ]))
        let session = try await service.sessions().first(where: { $0.id == "managed" })
        #expect(session?.writable == true)
        #expect(session?.workspaceID == "workspace")
        #expect(session?.surfaceID == "surface")
    }

    @Test func disconnectedEventBindingsCannotKeepAReusedTerminalWritable() async throws {
        let service = SessionService(cmux: DiscoveryCmux(dumpAvailable: false), home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        await service.acceptEvent(.object(["type": .string("event"), "category": .string("agent"), "workspace_id": .string("workspace"),
            "surface_id": .string("surface"), "seq": .number(10), "boot_id": .string("boot-a"),
            "payload": .object(["session_id": .string("hook-managed"), "hook_event_name": .string("SessionStart")])]))
        #expect(try await service.sessions().first?.writable == true)
        await service.invalidateEventBindings()
        #expect(try await service.sessions().isEmpty)
        #expect(await service.eventCursor() == nil)
        await #expect(throws: BridgeError.self) { _ = try await service.send(id: "hook-managed", request: .init(text: "must not target the old surface")) }
    }

}
