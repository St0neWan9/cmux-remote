import Foundation
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// Hook-backed resource graph and acknowledged effects, without an Agent process or provider API.
actor TuiResourceFixture: TuiResourceRequesting {
    static let machine = "machine_" + String(repeating: "a", count: 32)
    static let session = "session_" + String(repeating: "b", count: 32)
    static let workspace = "ws_" + String(repeating: "c", count: 32)
    static let terminal = "term_" + String(repeating: "d", count: 32)
    static let providerID = "11111111-2222-3333-4444-555555555555"
    var raw: JSONValue
    var screen = ""
    var replay: String
    var effects: [(String, [String: JSONValue], String?)] = []
    var lost = false
    var replaceDuringState = false
    var malformedReceipt = false
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
            if lost { throw BridgeError("outcome_unknown", "Fixture lost response", status: 504) }
            if malformedReceipt { return .null }
            return .object(["value": .object([:]), "generation": .string("fixture-generation"), "revision": .string("1"), "replayed": .bool(false)])
        default: throw BridgeError("unsupported", "Unexpected fixture resource")
        }
    }
    func configure(replay: String? = nil, screen: String? = nil, lost: Bool = false, replaced: Bool = false, malformed: Bool = false) {
        if let replay { self.replay = replay }; if let screen { self.screen = screen }
        self.lost = lost; replaceDuringState = replaced; malformedReceipt = malformed
    }
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
