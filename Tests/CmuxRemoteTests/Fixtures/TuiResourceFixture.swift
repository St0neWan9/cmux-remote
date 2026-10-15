import Foundation
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// Hook-backed resource graph and acknowledged effects, without an Agent process or provider API.
actor TuiResourceFixture: TuiResourceRequesting {
    static let machine = "machine_" + String(repeating: "a", count: 32)
    static let session = "session_" + String(repeating: "b", count: 32)
    static let workspace = "ws_" + String(repeating: "c", count: 32)
    static let terminal = "term_" + String(repeating: "d", count: 32)
    /// The terminal a `workspace.run` opens.
    static let startedTerminal = "term_" + String(repeating: "e", count: 32)
    static let providerID = "11111111-2222-3333-4444-555555555555"
    var raw: JSONValue
    var screen = ""
    var replay: String
    var effects: [(String, [String: JSONValue], String?)] = []
    var lost = false
    var replaceDuringState = false
    var malformedReceipt = false
    /// Text an interrupted Agent puts back into its prompt, as Claude Code does when stopped before replying.
    var restoredOnInterrupt: String?
    /// Escape closes the open dialog and leaves an empty prompt.
    var dismissOnEscape = false
    init(provider: String = "claude") {
        raw = Self.graph(provider: provider)
        replay = "\u{1b}[?2004h\u{1b}[H" + (provider == "claude" ? "❯\u{00a0}" : "› ") + "\u{1b}[2mTry a task\u{1b}[22m"
    }
    func resource(_ operation: String, params: [String: JSONValue], idempotencyKey: String?) async throws -> JSONValue {
        switch operation {
        case "session.snapshot": return raw
        case "terminal.screen.read": return .object(["text": .string(screen), "revision": .string("7"), "cols": .number(80), "rows": .number(8)])
        case "terminal.state.read":
            if replaceDuringState { setAgentField("extra", .object(["agent": .string("claude"), "agent_session_id": .string("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")])) }
            return .object(["state_base64": .string(Data(replay.utf8).base64EncodedString()), "cols": .number(80), "rows": .number(8)])
        case "terminal.input.write", "terminal.input.keys":
            effects.append((operation, params, idempotencyKey))
            if operation == "terminal.input.keys", dismissOnEscape { replay = "\u{1b}[?2004h\u{1b}[H❯\u{00a0}\u{1b}[2mTry a task\u{1b}[22m" }
            if operation == "terminal.input.keys", let restoredOnInterrupt { replay = "\u{1b}[?2004h\u{1b}[H❯\u{00a0}" + restoredOnInterrupt.replacingOccurrences(of: "\n", with: "\r\n  ") }
            if let text = params["text"]?.string, !text.isEmpty, text.allSatisfy({ $0 == "\u{7f}" }) { replay = "\u{1b}[?2004h\u{1b}[H❯\u{00a0}\u{1b}[2mTry a task\u{1b}[22m" }
            if lost { throw BridgeError("outcome_unknown", "Fixture lost response", status: 504) }
            if malformedReceipt { return .null }
            return .object(["value": .object([:]), "generation": .string("fixture-generation"), "revision": .string("1"), "replayed": .bool(false)])
        case "workspace.run":
            effects.append((operation, params, idempotencyKey))
            if lost { throw BridgeError("outcome_unknown", "Fixture lost response", status: 504) }
            return .object(["value": .object(["kind": .string("terminal"), "workspace_id": params["workspace"] ?? .null, "terminal_id": .string(Self.startedTerminal)]),
                            "generation": .string("fixture-generation"), "revision": .string("2"), "replayed": .bool(false)])
        default: throw BridgeError("unsupported", "Unexpected fixture resource")
        }
    }
    /// Agent hook journal items in commit order, each carrying its sequence.
    var journal: [JSONValue] = []
    var journalHead: UInt64 = 0
    var journalReads: [JSONValue] = []
    var journalBroken = false
    var streamIDs: Set<String> = []
    func stream(_ operation: String, params: [String: JSONValue], limit: Int) async throws -> TuiStreamRead {
        guard operation == "session.journal.subscribe", params["filter"]?["max_sensitivity"].string == "sensitive" else { throw BridgeError("unsupported", "Unexpected fixture stream") }
        // The daemon requires its selectors and a fresh client stream identity on every subscription.
        guard params["machine"]?.string == Self.machine, params["session"]?.string == Self.session,
              let stream = params["stream_id"]?.string, stream.hasPrefix("stream_"), stream.count == 39, !streamIDs.contains(stream) else { throw BridgeError("socket_denied", "Fixture rejected the stream request") }
        streamIDs.insert(stream)
        if journalBroken { throw BridgeError("socket_denied", "Fixture journal refused") }
        journalReads.append(params["cursor"] ?? .null)
        let after = params["cursor"]?["revision"].string.flatMap(UInt64.init) ?? journalHead
        let pending = Array(journal.filter { UInt64($0["sequence"].string!)! > after }.prefix(limit))
        let full = pending.count == limit && journal.contains { UInt64($0["sequence"].string!)! > UInt64(pending.last!["sequence"].string!)! }
        let position = full ? pending.last!["sequence"].string! : String(journalHead)
        return TuiStreamRead(items: pending, cursor: .object(["generation": .string(Self.session), "revision": .string(position)]), complete: !full)
    }
    func hook(_ native: String, provider: String = "claude", session: String = providerID, tool: String? = nil, notification: String? = nil, source: String? = nil, unrelated: UInt64 = 3) {
        journalHead += unrelated + 1
        var normalized: [String: JSONValue] = ["agent_session_id": .string(session)], raw: [String: JSONValue] = [:]
        if let tool { normalized["tool_name"] = .string(tool) }
        if let notification { raw["notification_type"] = .string(notification) }
        if let source { raw["source"] = .string(source) }
        journal.append(.object(["kind": .string("agent.state.changed"), "sequence": .string(String(journalHead)),
                                "payload": .object(["adapter": .object(["id": .string(provider)]), "native_event": .string(native), "normalized": .object(normalized), "native": .object(raw)])]))
    }
    func breakJournal(_ broken: Bool) { journalBroken = broken }
    func configure(replay: String? = nil, screen: String? = nil, lost: Bool = false, replaced: Bool = false, malformed: Bool = false) {
        if let replay { self.replay = replay }; if let screen { self.screen = screen }
        self.lost = lost; replaceDuringState = replaced; malformedReceipt = malformed
    }
    func restore(_ text: String?) { restoredOnInterrupt = text }
    /// Moves the fixture terminal to another working directory.
    func setTerminalCWD(_ cwd: String) { setTerminalField("cwd", .string(cwd)) }
    func setTerminalField(_ field: String, _ value: JSONValue) {
        guard case .object(var graph) = raw, case .array(var terminals) = graph["terminals"] ?? .null, case .object(var terminal) = terminals[0] else { return }
        terminal[field] = value; terminals[0] = .object(terminal); graph["terminals"] = .array(terminals); raw = .object(graph)
    }
    func dismissesOnEscape() { dismissOnEscape = true }
    func setAgentField(_ field: String, _ value: JSONValue) {
        var root = raw.object!, row = root["agents"]!.array![0].object!; row[field] = value; root["agents"] = .array([.object(row)]); raw = .object(root)
    }
    func clearAgents() { var root = raw.object!; root["agents"] = .array([]); raw = .object(root) }
    func replaceIdentity() { var root = raw.object!; root["machine"] = .object(["id": .string("machine_" + String(repeating: "e", count: 32))]); raw = .object(root) }
    func makeAmbiguous() {
        var root = raw.object!
        let second = "ws_" + String(repeating: "9", count: 32), screen = "screen_" + String(repeating: "8", count: 32), pane = "pane_" + String(repeating: "7", count: 32)
        root["workspaces"] = .array(root["workspaces"]!.array! + [.object(["id": .string(second), "name": .string("Other")])])
        root["screens"] = .array(root["screens"]!.array! + [.object(["id": .string(screen), "workspace_id": .string(second)])])
        root["panes"] = .array(root["panes"]!.array! + [.object(["id": .string(pane), "screen_id": .string(screen)])])
        root["tabs"] = .array(root["tabs"]!.array! + [.object(["id": .string("tab_" + String(repeating: "6", count: 32)), "pane_id": .string(pane), "content_kind": .string("terminal"), "content_id": .string(Self.terminal)])]); raw = .object(root)
    }
    static func graph(provider: String) -> JSONValue {
        let screen = "screen_" + String(repeating: "1", count: 32), pane = "pane_" + String(repeating: "2", count: 32)
        return .object([
            "machine": .object(["id": .string(machine)]), "session": .object(["id": .string(session)]), "cursor": .object(["generation": .string("fixture-generation"), "revision": .string("1")]),
            "workspaces": .array([.object(["id": .string(workspace), "name": .string("Daemon workspace")])]),
            "screens": .array([.object(["id": .string(screen), "workspace_id": .string(workspace)])]),
            "panes": .array([.object(["id": .string(pane), "screen_id": .string(screen)])]),
            "tabs": .array([.object(["id": .string("tab_" + String(repeating: "3", count: 32)), "pane_id": .string(pane), "content_kind": .string("terminal"), "content_id": .string(terminal)])]),
            "terminals": .array([.object(["id": .string(terminal), "cwd": .string("/project"), "title": .string("Fixture Agent"), "running": .bool(true), "lifecycle": .string("running")])]),
            "agents": .array([.object(["id": .string("agent_" + String(repeating: "4", count: 32)), "terminal_id": .string(terminal), "source": .string("hook"), "state": .string("idle"), "extra": .object(["agent": .string(provider), "agent_session_id": .string(providerID)])])])
        ])
    }
}
