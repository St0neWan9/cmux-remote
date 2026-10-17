import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

@Suite struct TuiAdapterTests {
    private func adapter(_ source: TuiResourceFixture, root: URL? = nil, ledger: MutationLedger = MutationLedger()) -> TuiControlAdapter {
        let home = root ?? URL(fileURLWithPath: "/nonexistent-fixture")
        return TuiControlAdapter(client: source, transcripts: .init(claudeRoot: home.appendingPathComponent(".claude"), codexRoot: home.appendingPathComponent(".codex")),
                                 attachments: root.map { TuiAttachmentStore(directory: $0) }, decisions: ledger, archive: root.map { TuiBindingRepository(directory: $0) },
                                 restoreChecks: 3, restoreInterval: .milliseconds(5))
    }
    private func service(_ adapter: TuiControlAdapter, root: URL? = nil, ledger: MutationLedger = MutationLedger()) -> SessionService {
        let home = root ?? URL(fileURLWithPath: "/nonexistent-fixture")
        return SessionService(cmux: adapter, home: home, transcriptRoots: [home.appendingPathComponent(".claude"), home.appendingPathComponent(".codex")], mutations: ledger)
    }
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]); return root
    }
    @Test func stableIDsAndHookOnlyProvenance() async throws {
        let source = TuiResourceFixture(), bridge = adapter(source)
        let first = try await bridge.request("workspace.list", params: [:])["workspaces"].array![0]["id"].string!
        #expect(UUID(uuidString: first) != nil)
        #expect(try await bridge.request("workspace.list", params: [:])["workspaces"].array![0]["id"].string == first)
        let records = try await service(bridge).sessions(); #expect(records.count == 1); let record = try #require(records.first); #expect(record.id.hasPrefix("tui:"))
        // A daemon record that is not hook provenance does not bind, and with its terminal gone it is historical.
        await source.setAgentField("source", .string("socket")); await source.stopTerminal()
        let after = try await service(bridge).sessions(); #expect(after.count == 1 && after[0].state == "ended")
        #expect(try await service(adapter(source)).sessions().isEmpty)
    }
    @Test func anAgentTheDaemonForgotOnARunningTerminalStaysWritable() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let source = TuiResourceFixture(), bridge = adapter(source, root: root), session = service(bridge, root: root)
        let id = try #require(try await session.sessions().first?.id)
        #expect(try await session.sessions().first?.writable == true)
        // The Agent resumed into the same terminal and the daemon dropped its hook row; the conversation reads as
        // idle rather than ended, and a send still reaches that terminal.
        await source.clearAgents()
        let resumed = service(adapter(source, root: root), root: root)
        let revived = try #require(try await resumed.sessions().first)
        #expect(revived.id == id); #expect(revived.state == "idle"); #expect(revived.writable)
        _ = try await resumed.send(id: id, request: .init(text: "after the resume"))
        #expect(await source.effects.count == 1)
        #expect(await source.effects.first?.1["terminal"]?.string == TuiResourceFixture.terminal)
    }
    @Test func aConversationIsIdentifiedByItsAgentNotItsTerminal() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let identity = TuiResourceIdentity()
        let machine = TuiResourceFixture.machine, session = TuiResourceFixture.session
        let first = identity.conversation(machine: machine, session: session, provider: "claude", providerSession: TuiResourceFixture.providerID)
        let other = identity.conversation(machine: machine, session: session, provider: "claude", providerSession: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        #expect(first == identity.conversation(machine: machine, session: session, provider: "claude", providerSession: TuiResourceFixture.providerID.uppercased()))
        #expect(first != other)
        // An archive written before this rule is re-keyed on load, so the same Agent keeps one identity.
        let stale = TuiSessionSnapshot.Binding(id: "tui:" + UUID().uuidString.lowercased(), provider: "claude", providerSession: TuiResourceFixture.providerID.lowercased(),
                                              terminal: TuiResourceFixture.terminal, workspace: TuiResourceFixture.workspace, surfaceID: "surface", workspaceID: "workspace", title: "Old", cwd: "/tmp", state: "idle")
        try TuiBindingRepository(directory: root).save(identity: "\(TuiResourceFixture.machine):\(TuiResourceFixture.session)", rows: [stale])
        let repository = TuiBindingRepository(directory: root)
        let daemonIdentity = "\(TuiResourceFixture.machine):\(TuiResourceFixture.session)"
        let loaded = try repository.load(identity: daemonIdentity)
        #expect(loaded.first?.id == first)
        // The re-keyed archive is written back, so a restart reads the current rule rather than migrating again.
        #expect(try repository.load(identity: daemonIdentity).first?.id == first)
    }
    @Test func aConversationWhoseSurfaceIsGoneCanBeReopenedFromItsOwnTranscript() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(".claude/projects/-project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let session = TuiResourceFixture.providerID
        try Data((#"{"type":"user","cwd":"/project"}"# + "\n").utf8).write(to: folder.appendingPathComponent(session + ".jsonl"))
        let source = TuiResourceFixture(), bridge = adapter(source, root: root), live = service(bridge, root: root)
        let id = try #require(try await live.sessions().first?.id)
        // A live conversation is not offered for reopening; only one whose terminal is gone is.
        #expect(try await live.sessions().first?.resumable == false)
        // The Agent's terminal is closed; the workspace outlived it, so the conversation can be reopened.
        await source.removeTerminal()
        let reopened = service(adapter(source, root: root), root: root)
        let record = try #require(try await reopened.sessions().first)
        #expect(record.id == id); #expect(record.resumable); #expect(!record.writable)
        _ = try await reopened.resume(id: id, request: ResumeRequest())
        let effects = await source.effects
        #expect(effects.count == 1); #expect(effects[0].0 == "workspace.run")
        let argv = effects[0].1["argv"]?.array?.compactMap { $0.string } ?? []
        #expect(argv.count == 3 && argv[1] == "-ic")
        // The Agent's own session id and directory, never a caller's choice.
        #expect(argv[2].contains("--resume " + session.lowercased()))
        #expect(argv[2].hasPrefix(LaunchAgent.claude.command))
        #expect(effects[0].1["cwd"]?.string == "/project")
    }
    @Test func aConversationWithoutAReservableSessionCannotBeReopened() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let source = TuiResourceFixture(), bridge = adapter(source, root: root), live = service(bridge, root: root)
        let id = try #require(try await live.sessions().first?.id)
        await source.removeTerminal()
        // No transcript, so no directory the Agent itself recorded: reopening would guess.
        let reopened = service(adapter(source, root: root), root: root)
        let record = try #require(try await reopened.sessions().first)
        #expect(!record.resumable)
        await #expect(throws: BridgeError.self) { _ = try await reopened.resume(id: id, request: ResumeRequest()) }
        #expect(await source.effects.isEmpty)
    }
    @Test func ambiguousWorkspaceAndReplacedDaemonCannotBecomeWritable() async throws {
        let source = TuiResourceFixture(); await source.makeAmbiguous()
        #expect(try await service(adapter(source)).sessions().isEmpty)
        let live = TuiResourceFixture(), bridge = adapter(live)
        _ = try await bridge.request("system.ping", params: [:]); await live.replaceIdentity()
        await #expect(throws: BridgeError.self) { _ = try await bridge.request("workspace.list", params: [:]) }
        #expect(await live.effects.isEmpty)
    }
    @Test(arguments: ["claude", "codex"])
    func faintPlaceholderAllowsSingleBoundedSendAndNoReplay(_ provider: String) async throws {
        let source = TuiResourceFixture(provider: provider), bridge = adapter(source), session = service(bridge)
        let id = try #require(try await session.sessions().first?.id), request = SendRequest(text: "Review this\nthen explain")
        _ = try await session.send(id: id, request: request); _ = try await session.send(id: id, request: request)
        let effects = await source.effects
        #expect(effects.count == 1); #expect(effects[0].0 == "terminal.input.write")
        #expect(effects[0].1["text"]?.string == "\u{1b}[200~Review this\nthen explain\u{1b}[201~\r")
        #expect(effects[0].1["terminal"]?.string == TuiResourceFixture.terminal)
        #expect(effects[0].1["expected_revision"]?.string == "1")
        #expect(effects[0].2?.hasPrefix("cmux-remote:send:") == true)
    }
    @Test func aPhoneSendErasesADesktopDraftFirst() async throws {
        let source = TuiResourceFixture(); await source.configure(replay: "\u{1b}[?2004h\u{1b}[H❯\u{00a0}unfinished draft")
        let session = service(adapter(source)), id = try #require(try await session.sessions().first?.id)
        _ = try await session.send(id: id, request: .init(text: "from the phone"))
        let effects = await source.effects
        #expect(effects.count == 2)
        #expect(effects[0].1["text"]?.string?.allSatisfy { $0 == "\u{7f}" } == true); #expect((effects[0].1["text"]?.string?.count ?? 0) >= "unfinished draft".count)
        #expect(effects[0].2?.hasPrefix("cmux-remote:send-clear:") == true)
        #expect(effects[1].1["text"]?.string == "\u{1b}[200~from the phone\u{1b}[201~\r")
    }
    @Test func aPhoneSendDismissesAnOpenDialogFirst() async throws {
        let source = TuiResourceFixture(); await source.configure(replay: "\u{1b}[?2004h\u{1b}[H❯\u{00a0}\r\nEsc to cancel"); await source.dismissesOnEscape()
        let session = service(adapter(source)), id = try #require(try await session.sessions().first?.id)
        _ = try await session.send(id: id, request: .init(text: "from the phone"))
        let effects = await source.effects
        #expect(effects.count == 2); #expect(effects[0].1["keys"]?.array == [.string("escape")]); #expect(effects[1].0 == "terminal.input.write")
    }
    @Test(arguments: ["\u{1b}[Hunknown UI", "\u{1b}[H❯\u{00a0}\r\nEsc to cancel"])
    func aScreenThatNeverShowsAnEmptyPromptIsNeverTypedInto(_ replay: String) async throws {
        let source = TuiResourceFixture(); await source.configure(replay: replay)
        let session = service(adapter(source)), id = try #require(try await session.sessions().first?.id)
        do { _ = try await session.send(id: id, request: .init(text: "Never typed")); Issue.record("Expected input protection") }
        catch { #expect((error as? BridgeError)?.code == "input_busy") }
        let effects = await source.effects
        #expect(effects.count == 3); #expect(effects.allSatisfy { $0.0 == "terminal.input.keys" && $0.1["keys"]?.array == [.string("escape")] })
        _ = try await session.interrupt(id: id, request: .init())
        #expect(await source.effects.last?.1["keys"]?.array == [.string("escape")])
    }
    @Test(arguments: [false, true])
    func promptRestoredByAnInterruptIsErasedSoTheNextSendIsAccepted(_ hard: Bool) async throws {
        let source = TuiResourceFixture(), session = service(adapter(source)), id = try #require(try await session.sessions().first?.id)
        _ = try await session.send(id: id, request: .init(text: "合并 发版"))
        await source.restore("合并 发版")
        _ = try await session.interrupt(id: id, request: .init(hard: hard))
        let effects = await source.effects
        #expect(effects.count == 3)
        #expect(effects[1].1["keys"]?.array == [.string(hard ? "ctrl+c" : "escape")])
        #expect(effects[2].0 == "terminal.input.write"); #expect(effects[2].1["text"]?.string == String(repeating: "\u{7f}", count: 5))
        #expect(effects[2].2?.hasPrefix("cmux-remote:interrupt-clear:") == true)
        // No extra ctrl+c ever reaches an empty prompt, where a second one would quit the Agent.
        #expect(effects.filter { $0.1["keys"]?.array == [.string("ctrl+c")] }.count == (hard ? 1 : 0))
        await source.restore(nil)
        _ = try await session.send(id: id, request: .init(text: "next"))
        #expect(await source.effects.count == 4)
    }
    @Test func anInterruptNeverErasesADifferentDesktopDraft() async throws {
        let source = TuiResourceFixture(), session = service(adapter(source)), id = try #require(try await session.sessions().first?.id)
        _ = try await session.send(id: id, request: .init(text: "from the phone"))
        await source.restore("typed on the Mac")
        _ = try await session.interrupt(id: id, request: .init())
        #expect(await source.effects.count == 2)
        #expect(await source.effects.count == 2)
    }
    @Test func anInterruptWithoutARestoredPromptSendsNothingMore() async throws {
        let source = TuiResourceFixture(), session = service(adapter(source)), id = try #require(try await session.sessions().first?.id)
        _ = try await session.send(id: id, request: .init(text: "keep going"))
        _ = try await session.interrupt(id: id, request: .init())
        #expect(await source.effects.count == 2)
        // A later interrupt no longer owns the earlier text, even if it appears now.
        await source.restore("keep going")
        _ = try await session.interrupt(id: id, request: .init())
        #expect(await source.effects.count == 3)
    }
    @Test func sessionReplacementBetweenInspectionAndSendRejectsTheOldTarget() async throws {
        let source = TuiResourceFixture(), session = service(adapter(source))
        let id = try #require(try await session.sessions().first?.id)
        await source.configure(replaced: true)
        await #expect(throws: BridgeError.self) { _ = try await session.send(id: id, request: .init(text: "Old target")) }
        #expect(await source.effects.isEmpty)
    }
    @Test func lostAndMalformedMutationReceiptsNeverPermitRetry() async throws {
        for malformed in [false, true] {
            let source = TuiResourceFixture(); await source.configure(lost: !malformed, malformed: malformed)
            let session = service(adapter(source)), id = try #require(try await session.sessions().first?.id), request = SendRequest(text: "Once only")
            await #expect(throws: BridgeError.self) { _ = try await session.send(id: id, request: request) }
            await #expect(throws: BridgeError.self) { _ = try await session.send(id: id, request: request) }
            #expect(await source.effects.count == 1)
        }
    }
    @Test func hardStopAndClientScopedOperationKeys() async throws {
        let source = TuiResourceFixture(), session = service(adapter(source)), record = try #require(try await session.sessions().first), operation = UUID()
        for client in ["first", "second"] {
            let access = SessionAccess(clientID: client) { _, workspace in #expect(workspace == record.workspaceID) }
            _ = try await session.interrupt(id: record.id, request: .init(hard: true, operationID: operation), access: access)
        }
        let effects = await source.effects
        #expect(effects.count == 2); #expect(effects[0].2 != effects[1].2)
        #expect(effects.allSatisfy { $0.1["keys"]?.array == [.string("ctrl+c")] })
    }
    @Test func historyIsExactAndRemainsReadOnlyAfterDaemonEndAndRestart() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(".claude/projects/-project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(TuiResourceFixture.providerID + ".jsonl")
        try Data((#"{"type":"assistant","uuid":"reply","message":{"content":"Recorded result"}}"# + "\n").utf8).write(to: file)
        let source = TuiResourceFixture(), bridge = adapter(source, root: root), session = service(bridge, root: root)
        let id = try #require(try await session.sessions().first?.id)
        #expect(try await session.history(id: id, beforeSeq: nil, limit: 20).messages.count == 1)
        await source.clearAgents(); await source.stopTerminal()
        let restarted = service(adapter(source, root: root), root: root)
        let historical = try #require(try await restarted.sessions().first)
        #expect(historical.id == id && !historical.writable)
        #expect(try await restarted.history(id: id, beforeSeq: nil, limit: 20).messages.count == 1)
        await #expect(throws: BridgeError.self) { _ = try await restarted.send(id: id, request: .init(text: "Never resume")) }
        #expect(await source.effects.isEmpty)
    }
    @Test func attachmentOnlySendUsesPrivateLocalPathsAndKeepsImageScope() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let source = TuiResourceFixture(), bridge = adapter(source, root: root), session = service(bridge, root: root), id = try #require(try await session.sessions().first?.id)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAKklEQVR4nGPQyrtDU8QwasGoBaMWjFowasGoBaMWjFowasGoBaMWDBULAFSk0ExUjkswAAAAAElFTkSuQmCC")!
        _ = try await session.send(id: id, request: .init(text: "", attachments: [.init(fileName: "safe.png", format: "png", data: png)]))
        let input = try #require(await source.effects.first?.1["text"]?.string)
        #expect(input.hasPrefix("\u{1b}[200~'")); #expect(!input.contains(png.base64EncodedString()))
        let files = FileManager.default.enumerator(at: root.appendingPathComponent("tui-images"), includingPropertiesForKeys: nil)!
        let file = try #require(files.compactMap { $0 as? URL }.first { $0.pathExtension == "png" })
        #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let stored = try await bridge.request("conversation.image.read", params: ["session_id": .string(id), "path": .string(file.path)])
        #expect(stored["data_b64"].string == png.base64EncodedString())
        #expect(try TuiAttachmentStore(directory: root).image(conversation: "other", path: file.path) == nil)
    }
    @Test func existingPhoneRouteAndWorkspaceGrantArePreserved() async throws {
        let source = TuiResourceFixture(), session = service(adapter(source)), record = try #require(try await session.sessions().first)
        let denied = SessionAccess(clientID: "denied") { _, _ in throw BridgeError("scope_denied", "Denied", status: 403) }
        await #expect(throws: BridgeError.self) { _ = try await session.send(id: record.id, request: .init(text: "No grant"), access: denied) }
        #expect(await source.effects.isEmpty)
        let router = BridgeRouter(service: session, token: "fixture")
        let response = await router.respond(method: "POST", uri: "/v1/sessions/" + record.id + "/send", authorization: "Bearer fixture", body: try JSONEncoder().encode(SendRequest(text: "Existing API")))
        #expect(response.0 == 200); #expect(await source.effects.count == 1)
    }
}
