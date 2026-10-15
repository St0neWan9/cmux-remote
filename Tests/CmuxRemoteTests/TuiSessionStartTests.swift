import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// The desktop must never receive a request meant for a daemon workspace.
private actor RecordingDesktop: CmuxControlling {
    var creates = 0
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "workspace.list": return .object(["workspaces": .array([])])
        case "vault.sessions", "chat.sessions.dump": return .object(["sessions": .array([])])
        case "surface.create": creates += 1; return .object(["surface_id": .string("99999999-9999-9999-9999-999999999999")])
        default: return .object([:])
        }
    }
}

@Suite struct TuiSessionStartTests {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tui-start-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("projects/app/src"), withIntermediateDirectories: true); return root
    }
    /// The fixture graph with its terminal sitting in a real folder, so the launcher can resolve it.
    private func fixture(cwd: String) async -> TuiResourceFixture {
        let source = TuiResourceFixture()
        await source.setTerminalCWD(cwd)
        return source
    }
    private func adapter(_ source: TuiResourceFixture) -> TuiControlAdapter {
        TuiControlAdapter(client: source, transcripts: .init(claudeRoot: URL(fileURLWithPath: "/nonexistent-fixture/.claude"), codexRoot: URL(fileURLWithPath: "/nonexistent-fixture/.codex")))
    }
    private var workspaceID: String { TuiResourceIdentity().uuid(machine: TuiResourceFixture.machine, session: TuiResourceFixture.session, resource: TuiResourceFixture.workspace) }
    private func access() -> SessionAccess { SessionAccess(clientID: "phone") { _, _ in } }

    @Test func aDaemonWorkspaceListsItsTerminalFolders() async throws {
        let home = try temporary(), folder = home.appendingPathComponent("projects/app")
        let daemon = adapter(await fixture(cwd: folder.path))
        let row = try #require(try await daemon.request("workspace.list", params: [:])["workspaces"].array?.first)
        #expect(row["backend"].string == "cmux-tui")
        #expect(row["directories"].array?.compactMap(\.string) == [folder.path])
    }

    @Test func startingInADaemonWorkspaceRunsTheFixedCommandOnTheDaemon() async throws {
        let home = try temporary(), folder = home.appendingPathComponent("projects/app")
        let source = await fixture(cwd: folder.path), desktop = RecordingDesktop()
        let router = CmuxBackendRouter(desktop: desktop, daemon: adapter(source))
        let launcher = SessionLauncher(cmux: router, home: home, mutations: MutationLedger(), sessions: { [] })
        let roots = try await launcher.directories(workspaceID: workspaceID, access: access())
        #expect(roots.map(\.path) == ["~/projects/app"])
        let request = StartSessionRequest(rootID: roots[0].id, path: "src", agent: .codex)
        let receipt = try await launcher.start(workspaceID: workspaceID, request: request, access: access())
        let started = TuiResourceIdentity().uuid(machine: TuiResourceFixture.machine, session: TuiResourceFixture.session, resource: TuiResourceFixture.startedTerminal)
        #expect(receipt.surfaceID == started)
        #expect(await desktop.creates == 0)
        let run = try #require(await source.effects.first { $0.0 == "workspace.run" })
        #expect(run.1["workspace"]?.string == TuiResourceFixture.workspace && run.1["machine"]?.string == TuiResourceFixture.machine)
        #expect(run.1["cwd"]?.string == folder.appendingPathComponent("src").path)
        #expect(run.1["shell"]?.string == "exec \"${SHELL:-/bin/zsh}\" -ic 'codex; exec \"${SHELL:-/bin/zsh}\" -l'")
        #expect(run.1["argv"] == nil && run.1["name"]?.string == "codex")
        // The daemon's own idempotency key comes from the operation, so a resent write is deduplicated there too.
        #expect(run.2 != nil && run.1["correlation_key"]?.string == run.2)
    }

    @Test func aLostDaemonReplyIsUnknownAndNotRepeated() async throws {
        let home = try temporary(), folder = home.appendingPathComponent("projects/app")
        let source = await fixture(cwd: folder.path)
        let launcher = SessionLauncher(cmux: CmuxBackendRouter(desktop: RecordingDesktop(), daemon: adapter(source)), home: home, mutations: MutationLedger(), sessions: { [] })
        let root = try await launcher.directories(workspaceID: workspaceID, access: access())[0]
        await source.configure(lost: true)
        let request = StartSessionRequest(rootID: root.id, agent: .claude)
        await #expect(throws: BridgeError.self) { _ = try await launcher.start(workspaceID: workspaceID, request: request, access: access()) }
        await source.configure(lost: false)
        await #expect(throws: BridgeError.self) { _ = try await launcher.start(workspaceID: workspaceID, request: request, access: access()) }
        #expect(await source.effects.filter { $0.0 == "workspace.run" }.count == 1)
    }

    @Test func theAdapterRefusesAnythingButAFixedAgentInAKnownWorkspace() async throws {
        let source = await fixture(cwd: "/project"), daemon = adapter(source)
        _ = try await daemon.request("workspace.list", params: [:])
        let valid: [String: JSONValue] = ["workspace_id": .string(workspaceID), "type": .string("terminal"), "working_directory": .string("/project"),
                                          "launch_agent": .string("claude"), "operation_key": .string("key")]
        var arbitrary = valid; arbitrary["launch_agent"] = .string("rm -rf ~")
        var relative = valid; relative["working_directory"] = .string("project")
        var missingKey = valid; missingKey.removeValue(forKey: "operation_key")
        for params in [arbitrary, relative, missingKey] {
            await #expect(throws: BridgeError.self) { _ = try await daemon.request("surface.create", params: params) }
        }
        var unknown = valid; unknown["workspace_id"] = .string("12345678-1234-1234-1234-123456789012")
        do { _ = try await daemon.request("surface.create", params: unknown); Issue.record("An unknown workspace was accepted") }
        catch { #expect((error as? BridgeError)?.code == "stale_binding") }
        #expect(await source.effects.isEmpty)
    }
}
