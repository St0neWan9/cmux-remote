import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// A desktop cmux with one live agent whose terminal runs the Codex picker emulator, or a Claude prompt.
private actor DesktopModelCmux: CmuxControlling {
    let agent: String
    let path: String
    var state: String
    var surface = "surface-1"
    var picker = CodexPickerEmulator()
    var sent: [String] = []
    var inputs: [String] = []
    /// Rebinds the conversation to another terminal once this many inputs arrived.
    var moveAfterInputs: Int?
    init(agent: String, path: String, state: String = "idle") { self.agent = agent; self.path = path; self.state = state }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "chat.sessions.dump":
            return .object(["sessions": .array([.object([
                "session_id": .string("live"), "agent": .string(agent), "workspace_id": .string("workspace"), "surface_id": .string(surface),
                "state": .string(state), "transcript_path": .string(path)])])])
        case "surface.input_state":
            return .object(["workspace_id": .string("workspace"), "surface_id": .string(surface), "terminal": .bool(true), "agent": .bool(true),
                            "state": .string("empty"), "blocks_typing": .bool(false)])
        case "mobile.chat.send":
            sent.append(params["text"]?.string ?? ""); return .object(["submitted": .bool(true)])
        case "surface.read_text":
            return .object(["text": .string(picker.rows.joined(separator: "\n"))])
        case "mobile.terminal.input":
            guard params["surface_id"]?.string == surface else { throw BridgeError("stale_binding", "Fixture surface moved", status: 409) }
            let text = params["text"]?.string ?? ""
            inputs.append(text); picker.input(text)
            if inputs.count == moveAfterInputs { surface = "surface-2" }
            return .object(["accepted": .bool(true)])
        default: return .object(["sessions": .array([])])
        }
    }
    func configure(follows: Bool = true, closesOnSession: Bool = true) { picker.follows = follows; picker.closesOnSession = closesOnSession }
    func setState(_ value: String) { state = value }
    func moveSurface(afterInputs count: Int) { moveAfterInputs = count }
    func applied() -> (model: String, effort: String, sessionOnly: Bool)? { picker.applied }
    func promptEscapes() -> Int { picker.promptEscapes }
}

/// A console over the emulator, for driving the switch without any backend.
private actor EmulatedConsole {
    var picker = CodexPickerEmulator()
    var writes: [String] = []
    func rows() -> [String] { picker.rows }
    func write(_ text: String) { writes.append(text); picker.input(text) }
    func configure(follows: Bool = true, closesOnSession: Bool = true) { picker.follows = follows; picker.closesOnSession = closesOnSession }
    func applied() -> (model: String, effort: String, sessionOnly: Bool)? { picker.applied }
    var console: AgentConsole { AgentConsole(rows: { await self.rows() }, write: { text, _ in await self.write(text) }) }
}

@Suite struct ModelSwitchTests {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    private let quick = CodexModelSwitch(attempts: 4, interval: .milliseconds(1))

    @Test func claudeReportsItsReplyModelAndALaterSwitchButNotASubagent() {
        let lines = [
            #"{"type":"assistant","message":{"model":"claude-opus-5","content":[]}}"#,
            #"{"type":"assistant","isSidechain":true,"message":{"model":"claude-haiku-4-5","content":[]}}"#,
            #"{"type":"assistant","message":{"model":"<synthetic>","content":[]}}"#
        ]
        #expect(TranscriptModelReader().read(lines: lines, agent: "claude") == AgentModelState(model: "claude-opus-5"))
        // The switch is recorded before any reply uses the new model.
        let switched = lines + [#"{"type":"user","message":{"role":"user","content":"<local-command-stdout>Set model to `Haiku 5.5` and saved as your default for new sessions</local-command-stdout>"}}"#]
        #expect(TranscriptModelReader().read(lines: switched, agent: "claude") == AgentModelState(model: "Haiku 5.5"))
        let replied = switched + [#"{"type":"assistant","message":{"model":"claude-haiku-5-5","content":[]}}"#]
        #expect(TranscriptModelReader().read(lines: replied, agent: "claude") == AgentModelState(model: "claude-haiku-5-5"))
    }

    @Test func codexReportsTheLatestTurnContextWithItsEffort() {
        let lines = [
            #"{"type":"turn_context","payload":{"model":"gpt-6.1-sol","effort":"high"}}"#,
            #"{"type":"response_item","payload":{"type":"message","model":"ignored"}}"#,
            #"{"type":"turn_context","payload":{"model":"gpt-6-luna","effort":"medium"}}"#
        ]
        #expect(TranscriptModelReader().read(lines: lines, agent: "codex") == AgentModelState(model: "gpt-6-luna", effort: "medium"))
    }

    @Test func onlyTheNewestCompletePageCarriesTheModel() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("t.jsonl")
        var text = ""
        for index in 0..<3 { text += #"{"type":"user","uuid":"u\#(index)","message":{"content":"Prompt \#(index)"}}"# + "\n" }
        text += #"{"type":"assistant","uuid":"a1","message":{"id":"m1","model":"claude-opus-5","content":[{"type":"text","text":"Reply"}]}}"# + "\n"
        // An unfinished trailing record is not committed, so its model is not reported yet.
        text += #"{"type":"assistant","uuid":"a2","message":{"id":"m2","model":"claude-sonnet-5-5""#
        try Data(text.utf8).write(to: file)
        let reader = TranscriptReader()
        let newest = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 2)
        #expect(newest.agentModel?.model == "claude-opus-5")
        let older = try await reader.history(path: file.path, agent: "claude", beforeSeq: newest.messages.first?.seq, limit: 2)
        #expect(older.agentModel == nil)
    }

    @Test func modelNamesThatWouldChangeTheCommandAreRefused() throws {
        #expect(try AgentModelName.validated(" volcengine/deepseek-v4.1-flash[1m] ") == "volcengine/deepseek-v4.1-flash[1m]")
        for bad in ["", "opus; rm -rf /", "opus\nhi", "two words", "\"quoted\"", "-flag", "a\u{1b}[31m", String(repeating: "a", count: 129)] {
            #expect(throws: BridgeError.self) { try AgentModelName.validated(bad) }
        }
    }

    @Test func pickerRowsAreReadAsCodexRendersThem() throws {
        let rows = ["  Select Model and Effort", "", "  1. GPT-6.1-Sol (current)  Latest workhorse model.", "› 2. GPT-6-Astra            Frontier intelligence.",
                    "  3. GPT-6-Sol              Previous generation.", "", "  enter select · esc back"]
        let screen = try #require(CodexModelPicker().screen(rows))
        #expect(screen.stage == .model); #expect(screen.highlighted == 2)
        #expect(screen.entries.map(\.label) == ["GPT-6.1-Sol", "GPT-6-Astra", "GPT-6-Sol"])
        #expect(CodexModelPicker().number(matching: ["gpt-6-sol"], in: screen) == 3)
        // The composer's own prompt is not a picker.
        #expect(CodexModelPicker().screen(["› Ask Codex to do anything", "  GPT-6.1-Sol high"]) == nil)
    }

    @Test func codexSwitchesForTheSessionOnlyAndKeepsItsEffort() async throws {
        let terminal = EmulatedConsole()
        try await quick.run(on: terminal.console, candidates: ["gpt-6-luna", "GPT-6-Luna"], effort: "high")
        let applied = try #require(await terminal.applied())
        #expect(applied.model == "GPT-6-Luna"); #expect(applied.effort == "High"); #expect(applied.sessionOnly)
        // `s`, never Enter, confirms the level: Enter would save the choice as the default for every session.
        #expect(await terminal.writes == ["/model", "\r", "\u{1b}[B\u{1b}[B\u{1b}[B", "\r", "\u{1b}[B", "s"])
    }

    @Test func aModelThePickerDoesNotListIsClosedUnapplied() async throws {
        let terminal = EmulatedConsole()
        await #expect(throws: BridgeError("model_unavailable", "Codex does not offer this model in its picker.", status: 422)) {
            try await quick.run(on: terminal.console, candidates: ["gpt-9"], effort: nil)
        }
        #expect(await terminal.applied() == nil)
        #expect(await terminal.writes == ["/model", "\r", "\u{1b}"])
        #expect(await terminal.rows().contains { $0.hasPrefix("› Ask Codex") })
    }

    @Test func aPickerThatDoesNotFollowIsClosedBeforeAnythingApplies() async throws {
        let terminal = EmulatedConsole(); await terminal.configure(follows: false)
        await #expect(throws: BridgeError.self) { try await quick.run(on: terminal.console, candidates: ["gpt-6-astra"], effort: nil) }
        #expect(await terminal.applied() == nil)
        // No Enter after the list opened, and one Escape closes it.
        #expect(await terminal.writes == ["/model", "\r", "\u{1b}[B", "\u{1b}"])
    }

    @Test func anUnconfirmedFinalKeyIsAnUnknownOutcome() async throws {
        let terminal = EmulatedConsole(); await terminal.configure(closesOnSession: false)
        do {
            try await quick.run(on: terminal.console, candidates: ["gpt-6-astra"], effort: nil)
            Issue.record("An open picker after the final key must not read as a switch")
        } catch let error as BridgeError { #expect(error.code == "outcome_unknown") }
        // The key was sent; whether Codex took it is unknown, so nothing more is typed.
        #expect(await terminal.writes.last == "s")
    }

    @Test func desktopClaudeSwitchIsOneModelCommandAndIsNotRepeated() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let cmux = DesktopModelCmux(agent: "claude", path: root.appendingPathComponent("t.jsonl").path)
        let service = SessionService(cmux: cmux, home: root, transcriptRoots: [root])
        let request = ModelSwitchRequest(model: "opus")
        let receipt = try await service.switchModel(id: "live", request: request)
        #expect(receipt.accepted && receipt.operationID == request.operationID)
        // The same operation answers from its receipt instead of typing the command again.
        _ = try await service.switchModel(id: "live", request: request)
        #expect(await cmux.sent == ["/model opus"])
        // A different model under the same operation is a different payload, never a second write.
        await #expect(throws: BridgeError.self) { try await service.switchModel(id: "live", request: ModelSwitchRequest(model: "haiku", operationID: request.operationID)) }
        #expect(await cmux.sent.count == 1)
    }

    @Test func aTurnInProgressOrAnUnsafeNameNeverReachesTheAgent() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let cmux = DesktopModelCmux(agent: "claude", path: root.appendingPathComponent("t.jsonl").path, state: "working")
        let service = SessionService(cmux: cmux, home: root, transcriptRoots: [root])
        await #expect(throws: BridgeError("agent_busy", "Wait for the Agent to finish its turn before switching models.", status: 409)) {
            try await service.switchModel(id: "live", request: ModelSwitchRequest(model: "opus"))
        }
        await cmux.setState("idle")
        await #expect(throws: BridgeError.self) { try await service.switchModel(id: "live", request: ModelSwitchRequest(model: "opus\r/exit")) }
        #expect(await cmux.sent.isEmpty)
    }

    @Test func desktopCodexWalksThePickerAndStopsWhenTheTerminalMoves() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("rollout.jsonl")
        try Data((#"{"type":"turn_context","payload":{"model":"gpt-6.1-sol","effort":"low"}}"# + "\n").utf8).write(to: file)
        let cmux = DesktopModelCmux(agent: "codex", path: file.path)
        let service = SessionService(cmux: cmux, home: root, transcriptRoots: [root])
        _ = try await service.switchModel(id: "live", request: ModelSwitchRequest(model: "GPT-6-Sol"))
        let applied = try #require(await cmux.applied())
        #expect(applied.model == "GPT-6-Sol"); #expect(applied.effort == "Low"); #expect(applied.sessionOnly)
        #expect(await cmux.sent.isEmpty)
        #expect(await cmux.promptEscapes() == 0)
    }

    @Test func aTerminalReboundDuringTheSwitchReceivesNoFurtherInput() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let cmux = DesktopModelCmux(agent: "codex", path: root.appendingPathComponent("rollout.jsonl").path)
        let service = SessionService(cmux: cmux, home: root, transcriptRoots: [root])
        // The picker opened, then the conversation's terminal changed hands before the selection.
        await cmux.moveSurface(afterInputs: 2)
        do {
            _ = try await service.switchModel(id: "live", request: ModelSwitchRequest(model: "gpt-6-astra"))
            Issue.record("A rebound terminal must not receive the rest of the switch")
        } catch let error as BridgeError { #expect(error.code == "stale_binding") }
        #expect(await cmux.inputs == ["/model", "\r"])
        #expect(await cmux.applied() == nil)
    }

    @Test func choicesComeFromTheAgentsOwnConfiguration() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try Data(#"{"env":{"ANTHROPIC_AUTH_TOKEN":"secret"},"modelPicker":{"options":[{"label":"GLM · Ark","model":"volcengine/glm-5.3[1m]","description":"via proxy"},{"label":"Bad","model":"two words"}]}}"#.utf8)
            .write(to: root.appendingPathComponent(".claude/settings.json"))
        try Data(#"{"models":[{"slug":"gpt-6-luna","display_name":"GPT-6-Luna","visibility":"list"},{"slug":"gpt-reserve","display_name":"Reserve","visibility":"hide"}]}"#.utf8)
            .write(to: root.appendingPathComponent(".codex/models_cache.json"))
        let catalog = ModelChoiceCatalog(home: root)
        let claude = catalog.choices(agent: "claude")
        #expect(claude.persistsDefault && claude.acceptsCustom)
        #expect(claude.choices.map(\.id) == ["default", "opus", "sonnet", "haiku", "fable", "volcengine/glm-5.3[1m]"])
        #expect(claude.choices.last?.label == "GLM · Ark")
        let codex = catalog.choices(agent: "codex")
        #expect(!codex.persistsDefault); #expect(codex.choices == [ModelChoice(id: "gpt-6-luna", label: "GPT-6-Luna")])
    }
}
