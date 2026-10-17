import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

private actor FakeCmux: CmuxControlling {
    var sendCount = 0
    var interruptCount = 0
    var hardInterrupt: Bool?
    var screenReadCount = 0
    /// The rendered screen the fake terminal serves; the working line and the CLI chrome both live here.
    var screen = "Other agent output"
    func setScreen(_ value: String) { screen = value }
    static let surfaceID = "11111111-1111-1111-1111-111111111111"
    var ended = false
    func markEnded() { ended = true }
    func setResumedTo(_ id: String) { resumedTo = id }
    let validBinding: Bool
    let echoesBinding: Bool
    /// The screen state cmux reports; nil models a response that omits the field entirely.
    let screenState: String?
    let terminal: Bool
    let failSend: Bool
    let blocksTyping: Bool
    let vaultFile: String?
    var resumedTo: String?
    var creates = 0
    var sentSessionIDs: [String] = []
    init(validBinding: Bool = true, echoesBinding: Bool = true, screenState: String? = "empty", terminal: Bool = true, failSend: Bool = false, blocksTyping: Bool = false, vaultFile: String? = nil, ended: Bool = false) {
        self.validBinding = validBinding; self.echoesBinding = echoesBinding; self.screenState = screenState; self.terminal = terminal; self.failSend = failSend; self.blocksTyping = blocksTyping; self.vaultFile = vaultFile; self.ended = ended
    }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "vault.sessions":
            var item: [String: JSONValue] = ["session_id": .string("session"), "agent": .string("claude"), "title": .string("Task")]
            if let vaultFile { item["file"] = .string(vaultFile); item["cwd"] = .string("project") }
            return .object(["sessions": .array([.object(item)])])
        case "chat.sessions.dump":
            var rows: [JSONValue] = [.object(["session_id": .string("session"), "agent": .string("claude"), "workspace_id": .string("workspace"), "surface_id": .string(Self.surfaceID), "state": .string(ended ? "ended" : "idle"), "resumable": .bool(ended)])]
            if let resumedTo { rows.append(.object(["session_id": .string(resumedTo), "agent": .string("claude"), "workspace_id": .string("workspace"), "surface_id": .string(Self.surfaceID), "state": .string("idle")])) }
            return .object(["sessions": .array(rows)])
        case "surface.create": creates += 1; return .object(["surface_id": .string(Self.surfaceID)])
        case "surface.input_state":
            var reply: [String: JSONValue] = ["agent": .bool(validBinding), "workspace_id": .string(echoesBinding ? "workspace" : "moved-workspace"), "surface_id": .string(echoesBinding ? Self.surfaceID : "moved-surface"), "terminal": .bool(terminal), "blocks_typing": .bool(blocksTyping)]
            if let screenState { reply["state"] = .string(screenState) }
            return .object(reply)
        case "mobile.chat.interrupt": interruptCount += 1; hardInterrupt = params["hard"]?.bool; return .object(["interrupted": .bool(true)])
        case "mobile.chat.send":
            sendCount += 1
            if let id = params["session_id"]?.string { sentSessionIDs.append(id) }
            if failSend { throw BridgeError("outcome_unknown", "Response lost", status: 504) }
            return .object(["submitted": .bool(true)])
        case "surface.read_text": screenReadCount += 1; return .object(["text": .string(screen)])
        default: return .object([:])
        }
    }
}

@Suite struct ServiceTests {
    @Test func interruptCanStopAnAgentWithBlockedTyping() async throws {
        let cmux = FakeCmux(blocksTyping: true)
        let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        do { _ = try await service.send(id: "session", request: SendRequest(text: "Test")); Issue.record("Expected draft protection") }
        catch { #expect((error as? BridgeError)?.code == "input_busy") }
        _ = try await service.interrupt(id: "session", request: InterruptRequest())
        #expect(await cmux.interruptCount == 1)
        #expect(await cmux.sendCount == 0)
    }
    @Test func hardInterruptUsesTheSameVerifiedBinding() async throws {
        let cmux = FakeCmux()
        let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/fixture/home"), transcriptRoots: [])
        _ = try await service.interrupt(id: "session", request: InterruptRequest(hard: true))
        #expect(await cmux.hardInterrupt == true)
        #expect(await cmux.interruptCount == 1)
    }
    @Test func staleBindingNeverInterruptsAnotherAgent() async {
        let cmux = FakeCmux(echoesBinding: false, blocksTyping: true)
        let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        do { _ = try await service.interrupt(id: "session", request: InterruptRequest()); Issue.record("Expected stale binding rejection") }
        catch { #expect((error as? BridgeError)?.code == "stale_binding") }
        #expect(await cmux.interruptCount == 0)
    }
    @Test func successfulSendIsNotRepeatedForSameOperation() async throws {
        let cmux = FakeCmux(); let home = URL(fileURLWithPath: "/example/home")
        let service = SessionService(cmux: cmux, home: home, transcriptRoots: [])
        let request = SendRequest(text: "Test")
        _ = try await service.send(id: "session", request: request)
        _ = try await service.send(id: "session", request: request)
        #expect(await cmux.sendCount == 1)
    }
    @Test func staleBindingNeverTypesIntoAnotherAgent() async {
        let cmux = FakeCmux(echoesBinding: false); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        do { _ = try await service.send(id: "session", request: SendRequest(text: "Test")); Issue.record("Expected stale binding rejection") }
        catch { #expect((error as? BridgeError)?.code == "stale_binding") }
        #expect(await cmux.sendCount == 0)
    }
    @Test func aFalseAgentBadgeDoesNotBlockSendWhileTheBindingEchoes() async throws {
        // cmux's sidebar fold can report no agent while the hook record that authorizes a send is
        // alive; the badge is advisory and the send proceeds so cmux's own record check decides.
        let cmux = FakeCmux(validBinding: false, screenState: "empty"); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        _ = try await service.send(id: "session", request: SendRequest(text: "Test"))
        #expect(await cmux.sendCount == 1)
    }
    @Test func aDialogOrDraftAlsoProvesTheAgentIsOnScreen() async throws {
        for state in ["draft", "dialog"] {
            let cmux = FakeCmux(validBinding: false, screenState: state); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
            // Interrupt stays available during a dialog and never pastes over a draft.
            _ = try await service.interrupt(id: "session", request: InterruptRequest())
            #expect(await cmux.interruptCount == 1)
        }
    }
    @Test func aResumedSessionTakesOverTheConversationIdentity() async throws {
        // A desktop resume starts `claude --resume`, which forks a new Agent session id on the opened
        // surface. The conversation keeps its identity, adopts the live session's transcript and
        // state, and sends address the live session cmux knows.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let project = dir.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let transcript = dir.appendingPathComponent("session.jsonl")
        try Data("{\"type\":\"user\",\"cwd\":\"\(project.path)\"}\n".utf8).write(to: transcript)
        let aliases = SessionAliasStore(directory: dir.appendingPathComponent("state"))
        let cmux = FakeCmux(vaultFile: transcript.path, ended: true)
        let service = SessionService(cmux: cmux, home: dir, transcriptRoots: [dir], aliases: aliases)
        _ = try await service.resume(id: "session", request: ResumeRequest())
        #expect(await cmux.creates == 1)
        await cmux.setResumedTo("resumed-session")
        let list = try await service.sessions()
        #expect(list.map(\.id) == ["session"])
        #expect(list.first?.state == "idle")
        #expect(list.first?.resumable == false)
        _ = try await service.send(id: "session", request: SendRequest(text: "Test"))
        #expect(await cmux.sentSessionIDs == ["resumed-session"])
    }
    @Test func aTerminalWithoutAnAgentPromptNeverAcceptsASend() async throws {
        // A retained binding whose process died without a SessionEnd hook leaves the list looking
        // live; the screen check is what keeps the send out of the bare shell that remains.
        let cmux = FakeCmux(validBinding: false, screenState: "unknown"); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        do { _ = try await service.send(id: "session", request: SendRequest(text: "Test")); Issue.record("Expected dead-terminal rejection") }
        catch { #expect((error as? BridgeError)?.code == "stale_binding") }
        #expect(await cmux.sendCount == 0)
    }
    @Test func aScreenStateTheDetectionCannotReadFailsClosed() async throws {
        // A reply that omits `state` proves nothing about the screen, so a missing badge plus a
        // missing screen state is rejected exactly like the `unknown` reading.
        let cmux = FakeCmux(validBinding: false, screenState: nil); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        do { _ = try await service.interrupt(id: "session", request: InterruptRequest()); Issue.record("Expected an unreadable terminal rejection") }
        catch { #expect((error as? BridgeError)?.code == "stale_binding") }
        #expect(await cmux.interruptCount == 0)
    }
    @Test func aNonTerminalSurfaceNeverAcceptsAnAgentWrite() async throws {
        let cmux = FakeCmux(screenState: "empty", terminal: false); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        do { _ = try await service.send(id: "session", request: SendRequest(text: "Test")); Issue.record("Expected non-terminal rejection") }
        catch { #expect((error as? BridgeError)?.code == "stale_binding") }
        #expect(await cmux.sendCount == 0)
    }
    @Test func aLiveAgentBadgeStillAllowsASendWhenTheScreenIsUnreadable() async throws {
        // cmux's lifecycle record is authoritative when it says an agent is there; the screen reading
        // only has to break the tie when the badge is missing.
        let cmux = FakeCmux(validBinding: true, screenState: "unknown"); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        _ = try await service.send(id: "session", request: SendRequest(text: "Test"))
        #expect(await cmux.sendCount == 1)
    }
    @Test func uncertainWriteIsNotRetried() async {
        let cmux = FakeCmux(failSend: true); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        let request = SendRequest(text: "Test")
        for _ in 0..<2 {
            do { _ = try await service.send(id: "session", request: request); Issue.record("Expected unknown outcome") }
            catch { #expect((error as? BridgeError)?.code == "outcome_unknown") }
        }
        #expect(await cmux.sendCount == 1)
    }
    @Test func unauthorizedHTTPDoesNotReachCmux() async throws {
        let cmux = FakeCmux(); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        let router = BridgeRouter(service: service, token: String(repeating: "a", count: 64))
        let result = await router.respond(method: "POST", uri: "/v1/sessions/session/send", authorization: nil, body: try JSONEncoder().encode(SendRequest(text: "Test")))
        #expect(result.0 == 401)
        #expect(await cmux.sendCount == 0)
    }
    @Test func endedSessionNeverReadsAReusedTerminalPreview() async throws {
        let cmux = FakeCmux(); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        _ = try await service.sessions()
        await service.acceptEvent(.object(["type": .string("event"), "category": .string("agent"), "workspace_id": .string("workspace"), "surface_id": .string("surface"), "payload": .object(["session_id": .string("session"), "hook_event_name": .string("SessionEnd")])]))
        let preview = try await service.preview(id: "session")
        #expect(!preview.available)
        #expect(await cmux.screenReadCount == 0)
    }
    /// Compaction is printed on the agent's working line, and the chrome around it is never prose.
    @Test func thePreviewReportsCompactionAndNoChrome() async throws {
        let cmux = FakeCmux(); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        await cmux.setScreen([
            "⏺ The table now fits the message width.",
            "✔ Update installed · Restart to update",
            "╭──────────────────────────────────────╮",
            "│ ❯                                    │",
            "╰──────────────────────────────────────╯",
            "✻ Compacting… (1m12s · ↓ 4.1k tokens)",
        ].joined(separator: "\n"))
        let preview = try await service.preview(id: "session")
        #expect(preview.available)
        #expect(preview.compacting == true)
        // The chrome around the working line is never reported as the agent's prose.
        #expect(preview.text == "The table now fits the message width.")
    }
    @Test func anOrdinaryTurnIsNotCompacting() async throws {
        let cmux = FakeCmux(); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        await cmux.setScreen("⏺ Answering.\n✻ Blanching… (54s · ↓ 2.3k tokens)")
        let preview = try await service.preview(id: "session")
        #expect(preview.compacting == false)
    }
    @Test func authoritativeProcessExitWinsOverOldStopHook() async throws {
        let cmux = FakeCmux(); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        await service.acceptEvent(.object(["type": .string("event"), "category": .string("agent"), "workspace_id": .string("workspace"), "surface_id": .string("surface"), "payload": .object(["session_id": .string("session"), "hook_event_name": .string("Stop")])]))
        await cmux.markEnded()
        let preview = try await service.preview(id: "session")
        #expect(!preview.available)
        #expect(await cmux.screenReadCount == 0)
    }
}

/// A desktop backend that keeps a transcript-backed row and records the terminal it is asked to open.
private actor DesktopCmux: CmuxControlling {
    let transcript: String?
    let ended: Bool
    var created: [[String: JSONValue]] = []
    init(transcript: String?, ended: Bool = true) { self.transcript = transcript; self.ended = ended }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        let id = "515f4a08-349b-4fef-9edb-c42c0881383b"
        switch method {
        case "vault.sessions":
            guard let transcript else { return .object(["sessions": .array([])]) }
            return .object(["sessions": .array([.object(["session_id": .string(id), "agent": .string("claude"), "title": .string("Task"), "cwd": .string("/tmp/project"), "file": .string(transcript), "status": .string(ended ? "exited" : "live")])])])
        case "chat.sessions.dump":
            guard let transcript else { return .object(["sessions": .array([])]) }
            return .object(["sessions": .array([.object(["session_id": .string(id), "agent": .string("claude"), "workspace_id": .string("workspace"), "surface_id": .string("surface"), "state": .string(ended ? "ended" : "idle"), "transcript_path": .string(transcript)])])])
        case "surface.create":
            created.append(params)
            return .object(["surface_id": .string("11111111-1111-1111-1111-111111111111")])
        default: return .object([:])
        }
    }
}

@Suite struct DesktopResumeTests {
    /// A transcript whose first line records the directory the Agent ran in.
    private func transcript(in root: URL, cwd: String?) throws -> String {
        let file = root.appendingPathComponent("515f4a08-349b-4fef-9edb-c42c0881383b.jsonl")
        var fields: [String: JSONValue] = ["type": .string("user"), "uuid": .string("first")]
        if let cwd { fields["cwd"] = .string(cwd) }
        try Data((String(decoding: try JSONEncoder().encode(JSONValue.object(fields)), as: UTF8.self) + "\n").utf8).write(to: file)
        return file.path
    }
    /// A project inside a home the policy accepts; `ProjectFilePolicy` refuses the home and its parents.
    private func project(_ root: URL) throws -> (home: URL, directory: URL) {
        let home = root.appendingPathComponent("home", isDirectory: true)
        let project = home.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        return (home, project)
    }
    @Test func anEndedDesktopRowWhoseTranscriptRecordsItsDirectoryIsResumable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cmux-resume-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (home, project) = try project(root)
        let path = try transcript(in: root, cwd: project.path)
        let service = SessionService(cmux: DesktopCmux(transcript: path), home: home, transcriptRoots: [root])
        let row = try await service.sessions().first
        // cmux's desktop dump carries no `resumable`, so the Bridge applies the documented rule itself.
        #expect(row?.resumable == true)
        #expect(row?.writable == false)
    }
    @Test func aTranscriptWithoutItsOwnDirectoryIsNotResumable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cmux-resume-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try transcript(in: root, cwd: nil)
        let service = SessionService(cmux: DesktopCmux(transcript: path), home: try project(root).home, transcriptRoots: [root])
        #expect(try await service.sessions().first?.resumable == false)
    }
    @Test func aLiveDesktopRowIsNotResumable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cmux-resume-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (home, project) = try project(root)
        let path = try transcript(in: root, cwd: project.path)
        let service = SessionService(cmux: DesktopCmux(transcript: path, ended: false), home: home, transcriptRoots: [root])
        // A live conversation is never offered as a reopen target.
        #expect(try await service.sessions().first?.resumable == false)
    }
    @Test func resumeStartsTheRecordedAgentInTheTranscriptsDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cmux-resume-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (home, project) = try project(root)
        let path = try transcript(in: root, cwd: project.path)
        let cmux = DesktopCmux(transcript: path)
        let service = SessionService(cmux: cmux, home: home, transcriptRoots: [root])
        _ = try await service.resume(id: "515f4a08-349b-4fef-9edb-c42c0881383b", request: ResumeRequest())
        let created = await cmux.created
        // Desktop cmux has no resume RPC: the reopen is a fixed terminal start with the recorded command.
        #expect(created.count == 1)
        #expect(created.first?["working_directory"]?.string == project.path)
        #expect(created.first?["initial_input"]?.string?.contains("--resume 515f4a08-349b-4fef-9edb-c42c0881383b") == true)
    }
}
