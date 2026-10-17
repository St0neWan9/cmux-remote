import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

@Suite struct SessionLauncherTests {
    @Test func rootsComeOnlyFromTheApprovedWorkspace() async throws {
        let fixture = try LaunchFixture()
        let roots = try await fixture.launcher.directories(workspaceID: LaunchCmux.workspace, access: fixture.access())
        #expect(roots.map(\.path) == ["~/projects/app", "~/projects/other"])
        #expect(roots.allSatisfy { $0.id.count == 64 })
    }

    @Test func homeAndSensitiveFoldersAreNeverRoots() async throws {
        let fixture = try LaunchFixture(currentIsHome: true)
        let roots = try await fixture.launcher.directories(workspaceID: LaunchCmux.workspace, access: fixture.access())
        #expect(roots.map(\.path) == ["~/projects/other"])
    }

    @Test func missingCapabilityOrWorkspaceIsDeniedBeforeAnyTerminalOpens() async throws {
        let fixture = try LaunchFixture()
        let control = fixture.access([.conversationControl])
        #expect(await fixture.code { try await fixture.launcher.directories(workspaceID: LaunchCmux.workspace, access: control) } == "scope_denied")
        let root = try await fixture.launcher.directories(workspaceID: LaunchCmux.workspace, access: fixture.access())[0]
        #expect(await fixture.code { try await fixture.launcher.start(workspaceID: LaunchCmux.workspace, request: StartSessionRequest(rootID: root.id, agent: .claude), access: control) } == "scope_denied")
        let elsewhere = "55555555-5555-5555-5555-555555555555"
        #expect(await fixture.code { try await fixture.launcher.start(workspaceID: elsewhere, request: StartSessionRequest(rootID: root.id, agent: .claude), access: fixture.access()) } == "scope_denied")
        #expect(await fixture.cmux.creates.isEmpty)
    }

    @Test func listingShowsVisibleFoldersInsideTheRootOnly() async throws {
        let fixture = try LaunchFixture()
        let root = try await fixture.launcher.directories(workspaceID: LaunchCmux.workspace, access: fixture.access())[0]
        let listing = try await fixture.launcher.listing(workspaceID: LaunchCmux.workspace, rootID: root.id, path: "", access: fixture.access())
        #expect(listing.directories == ["docs", "inside", "src"])
        #expect(try await fixture.launcher.listing(workspaceID: LaunchCmux.workspace, rootID: root.id, path: "src", access: fixture.access()).directories == ["core"])
    }

    @Test func traversalHiddenAndEscapingLinksAreRefused() async throws {
        let fixture = try LaunchFixture()
        let root = try await fixture.launcher.directories(workspaceID: LaunchCmux.workspace, access: fixture.access())[0]
        for path in ["..", "../other", "src/../..", ".git", "escape", "hidden", "/etc", "README.md"] {
            let code = await fixture.code { try await fixture.launcher.start(workspaceID: LaunchCmux.workspace, request: StartSessionRequest(rootID: root.id, path: path, agent: .claude), access: fixture.access()) }
            #expect(code == "directory_forbidden" || code == "directory_missing", "\(path) gave \(code ?? "success")")
            #expect(await fixture.code { try await fixture.launcher.listing(workspaceID: LaunchCmux.workspace, rootID: root.id, path: path, access: fixture.access()) } != nil)
        }
        #expect(await fixture.cmux.creates.isEmpty)
    }

    @Test func startTypesOnlyTheFixedCommandWithoutFocus() async throws {
        let fixture = try LaunchFixture()
        let root = try await fixture.launcher.directories(workspaceID: LaunchCmux.workspace, access: fixture.access())[0]
        let receipt = try await fixture.launcher.start(workspaceID: LaunchCmux.workspace.uppercased(), request: StartSessionRequest(rootID: root.id, path: "inside/core", agent: .codex, prompt: "it's fine; rm -rf ~"), access: fixture.access())
        #expect(receipt.accepted && receipt.surfaceID == "44444444-4444-4444-4444-444444444441")
        let params = try #require(await fixture.cmux.creates.first)
        #expect(params["workspace_id"]?.string == LaunchCmux.workspace)
        #expect(params["working_directory"]?.string == fixture.root.appendingPathComponent("src/core").path)
        #expect(params["initial_input"]?.string == "codex --no-daemon 'it'\\''s fine; rm -rf ~'\r")
        #expect(params["focus"]?.bool == false && params["type"]?.string == "terminal" && params["initial_command"] == nil)
        // Daemon-only fields never reach the desktop.
        #expect(params["launch_agent"] == nil && params["operation_key"] == nil)
    }

    @Test func aRepeatedOperationReplaysItsReceiptAndNeverOpensASecondTerminal() async throws {
        let fixture = try LaunchFixture(ledgerDirectory: true)
        let root = try await fixture.launcher.directories(workspaceID: LaunchCmux.workspace, access: fixture.access())[0]
        let request = StartSessionRequest(rootID: root.id, agent: .claude)
        _ = try await fixture.launcher.start(workspaceID: LaunchCmux.workspace, request: request, access: fixture.access())
        let replay = try await fixture.launcher.start(workspaceID: LaunchCmux.workspace, request: request, access: fixture.access())
        #expect(replay.accepted && replay.surfaceID == nil)
        let changed = StartSessionRequest(rootID: root.id, path: "docs", agent: .claude, operationID: request.operationID)
        #expect(await fixture.code { try await fixture.launcher.start(workspaceID: LaunchCmux.workspace, request: changed, access: fixture.access()) } == "operation_conflict")
        // Another device's identical identity is its own operation.
        _ = try await fixture.launcher.start(workspaceID: LaunchCmux.workspace, request: request, access: fixture.access(client: "tablet"))
        #expect(await fixture.cmux.creates.count == 2)
        // The durable receipt survives a Bridge restart.
        let restarted = SessionLauncher(cmux: fixture.cmux, home: fixture.home, mutations: MutationLedger(directory: fixture.home.appendingPathComponent("state")), sessions: { [] })
        #expect(try await restarted.start(workspaceID: LaunchCmux.workspace, request: request, access: fixture.access()).accepted)
        #expect(await fixture.cmux.creates.count == 2)
    }

    @Test func anUnknownOutcomeIsNeverRetriedUnderTheSameIdentity() async throws {
        let fixture = try LaunchFixture()
        let root = try await fixture.launcher.directories(workspaceID: LaunchCmux.workspace, access: fixture.access())[0]
        await fixture.cmux.setFailure(true)
        let request = StartSessionRequest(rootID: root.id, agent: .claude)
        #expect(await fixture.code { try await fixture.launcher.start(workspaceID: LaunchCmux.workspace, request: request, access: fixture.access()) } == "outcome_unknown")
        await fixture.cmux.setFailure(false)
        #expect(await fixture.code { try await fixture.launcher.start(workspaceID: LaunchCmux.workspace, request: request, access: fixture.access()) } == "outcome_unknown")
        #expect(await fixture.cmux.creates.count == 1)
        // A new identity is a deliberate second terminal.
        _ = try await fixture.launcher.start(workspaceID: LaunchCmux.workspace, request: StartSessionRequest(rootID: root.id, agent: .claude), access: fixture.access())
        #expect(await fixture.cmux.creates.count == 2)
    }

    @Test func aRootThatLeftTheWorkspaceIsAStaleBinding() async throws {
        let fixture = try LaunchFixture()
        let unknown = String(repeating: "a", count: 64)
        #expect(await fixture.code { try await fixture.launcher.start(workspaceID: LaunchCmux.workspace, request: StartSessionRequest(rootID: unknown, agent: .claude), access: fixture.access()) } == "stale_binding")
        #expect(await fixture.code { try await fixture.launcher.listing(workspaceID: LaunchCmux.workspace, rootID: unknown, path: "", access: fixture.access()) } == "stale_binding")
        #expect(await fixture.cmux.creates.isEmpty)
    }

    @Test func codexNeedsAFirstMessageAndTheMessageIsNotStored() async throws {
        let fixture = try LaunchFixture(ledgerDirectory: true)
        let root = try await fixture.launcher.directories(workspaceID: LaunchCmux.workspace, access: fixture.access())[0]
        #expect(await fixture.code { try await fixture.launcher.start(workspaceID: LaunchCmux.workspace, request: StartSessionRequest(rootID: root.id, agent: .codex), access: fixture.access()) } == "prompt_required")
        #expect(await fixture.code { try await fixture.launcher.start(workspaceID: LaunchCmux.workspace, request: StartSessionRequest(rootID: root.id, agent: .codex, prompt: "  \n"), access: fixture.access()) } == "prompt_required")
        #expect(await fixture.cmux.creates.isEmpty)
        let request = StartSessionRequest(rootID: root.id, agent: .claude, prompt: "secret plan for the release")
        _ = try await fixture.launcher.start(workspaceID: LaunchCmux.workspace, request: request, access: fixture.access())
        // The program's fixed flags precede the message, which stays one quoted literal argument.
        #expect(await fixture.cmux.creates.first?["initial_input"]?.string == LaunchAgent.claude.command + " 'secret plan for the release'\r")
        let ledger = try String(contentsOf: fixture.home.appendingPathComponent("state/mutation-receipts.ndjson"), encoding: .utf8)
        #expect(!ledger.contains("secret plan"))
        // The same identity with a different message is a different operation.
        let changed = StartSessionRequest(rootID: root.id, agent: .claude, prompt: "another plan", operationID: request.operationID)
        #expect(await fixture.code { try await fixture.launcher.start(workspaceID: LaunchCmux.workspace, request: changed, access: fixture.access()) } == "operation_conflict")
    }

    @Test func aDaemonWorkspaceWithoutTerminalFoldersOffersNoRoot() async throws {
        let fixture = try LaunchFixture()
        let daemon = SessionAccess(clientID: "phone") { _, _ in }
        #expect(try await fixture.launcher.directories(workspaceID: LaunchCmux.daemonWorkspace, access: daemon).isEmpty)
    }

    @Test func requestsAndReceiptsUseStableWireNames() throws {
        let request = StartSessionRequest(rootID: "r", path: "src", agent: .codex, operationID: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!)
        let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
        #expect(json["root_id"].string == "r" && json["agent"].string == "codex" && json["operation_id"].string == "66666666-6666-6666-6666-666666666666")
        #expect(throws: (any Error).self) { try JSONDecoder().decode(StartSessionRequest.self, from: Data(#"{"root_id":"r","path":"","agent":"bash","operation_id":"66666666-6666-6666-6666-666666666666"}"#.utf8)) }
    }
}
