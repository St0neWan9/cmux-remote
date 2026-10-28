import Foundation
import CmuxRemoteCore

/// One authoritative graph cut, mapped to the existing Bridge scope and binding model.
struct TuiSessionSnapshot: Sendable {
    struct Binding: Codable, Sendable, Equatable {
        let id: String
        let provider: String
        let providerSession: String
        let terminal: String
        let workspace: String
        let surfaceID: String
        let workspaceID: String
        let title: String
        let cwd: String?
        let state: String
    }
    let machine: String
    let session: String
    let generation: String
    let revision: String
    let workspaces: [JSONValue]
    /// Published workspace UUIDs back to the daemon's own `ws_` identities.
    let rawWorkspaces: [String: String]
    let bindings: [Binding]
    let surfaces: Set<String>
    /// Each terminal's own title, which an agent may use for its activity (Claude Code marks idle with `✳`).
    let terminalTitles: [String: String]
    /// Each terminal tab's own identity, so a rename can name the tab the conversation runs in.
    let tabIDs: [String: String]
    /// Terminals the daemon still reports as running. A conversation whose Agent stopped reporting keeps its
    /// terminal, so this is what separates a resumed Agent the daemon has forgotten from a historical one.
    let runningTerminals: Set<String>
    init(_ raw: JSONValue) throws {
        let identity = TuiResourceIdentity()
        machine = try identity.validate(raw["machine"]["id"].string, prefix: "machine")
        session = try identity.validate(raw["session"]["id"].string, prefix: "session")
        guard let revision = raw["cursor"]["revision"].string, UInt64(revision) != nil,
              let generation = raw["cursor"]["generation"].string, !generation.isEmpty, generation.utf8.count <= 256 else {
            throw BridgeError("invalid_response", "The daemon omitted its snapshot cursor.", status: 502)
        }
        self.generation = generation; self.revision = revision
        var arrays: [String: [JSONValue]] = [:]
        for key in ["workspaces", "screens", "panes", "tabs", "terminals", "agents"] {
            guard let rows = raw[key].array, rows.count <= 4096 else { throw BridgeError("too_large", "The daemon graph exceeds the discovery limit.", status: 413) }
            arrays[key] = rows
        }
        func indexed(_ key: String, _ prefix: String) throws -> [String: JSONValue] {
            var result: [String: JSONValue] = [:]
            for row in arrays[key]! {
                let id = try identity.validate(row["id"].string, prefix: prefix)
                guard result[id] == nil else { throw BridgeError("invalid_response", "The daemon returned duplicate resource identities.", status: 502) }
                result[id] = row
            }
            return result
        }
        let workspaceRows = try indexed("workspaces", "ws"), screens = try indexed("screens", "screen"), panes = try indexed("panes", "pane"), terminals = try indexed("terminals", "term")
        _ = try indexed("tabs", "tab"); _ = try indexed("agents", "agent")
        var memberships: [String: Set<String>] = [:], tabNames: [String: String] = [:], tabIDs: [String: String] = [:]
        for tab in arrays["tabs"]! {
            guard tab["content_kind"].string == "terminal", let terminal = tab["content_id"].string else { continue }
            if let name = tab["name"].string?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { tabNames[terminal] = name }
            if let id = tab["id"].string, tabIDs[terminal] == nil { tabIDs[terminal] = id }
            guard terminals[terminal] != nil, let pane = tab["pane_id"].string.flatMap({ panes[$0] }),
                  let screen = pane["screen_id"].string.flatMap({ screens[$0] }), let workspace = screen["workspace_id"].string, workspaceRows[workspace] != nil else {
                throw BridgeError("invalid_response", "The daemon terminal has an invalid ownership path.", status: 502)
            }
            memberships[terminal, default: []].insert(workspace)
        }
        let machineID = machine, sessionID = session
        // A workspace's folders are its terminals' working directories; there is no workspace-level directory.
        var folders: [String: [String]] = [:]
        for (terminal, scopes) in memberships.sorted(by: { $0.key < $1.key }) where scopes.count == 1 {
            guard let cwd = terminals[terminal]?["cwd"].string, cwd.hasPrefix("/"), let workspace = scopes.first,
                  !(folders[workspace] ?? []).contains(cwd), (folders[workspace] ?? []).count < 32 else { continue }
            folders[workspace, default: []].append(cwd)
        }
        workspaces = arrays["workspaces"]!.map { row in
            let raw = row["id"].string!
            return .object(["id": .string(identity.uuid(machine: machineID, session: sessionID, resource: raw)), "title": row["name"], "backend": .string("cmux-tui"),
                            "directories": .array((folders[raw] ?? []).map(JSONValue.string))])
        }
        rawWorkspaces = Dictionary(uniqueKeysWithValues: workspaceRows.keys.map { (identity.uuid(machine: machineID, session: sessionID, resource: $0), $0) })
        surfaces = Set(terminals.keys.map { identity.uuid(machine: machineID, session: sessionID, resource: $0) })
        terminalTitles = terminals.compactMapValues { $0["title"].string }
        self.tabIDs = tabIDs
        runningTerminals = Set(terminals.compactMap { id, row in
            row["running"].bool == true && row["lifecycle"].string == "running" ? identity.uuid(machine: machineID, session: sessionID, resource: id) : nil
        })
        var bound: [Binding] = [], claimed = Set<String>()
        for agent in arrays["agents"]! {
            guard agent["source"].string == "hook", let provider = agent["extra"]["agent"].string, ["claude", "codex"].contains(provider),
                  let providerSession = agent["extra"]["agent_session_id"].string, UUID(uuidString: providerSession) != nil,
                  let terminal = agent["terminal_id"].string, let content = terminals[terminal], content["running"].bool == true,
                  content["lifecycle"].string == "running", let scopes = memberships[terminal], scopes.count == 1, let workspace = scopes.first else { continue }
            guard claimed.insert(terminal).inserted else { throw BridgeError("stale_binding", "Multiple Agent records claim one terminal.", status: 409) }
            let state: String
            switch agent["state"].string {
            case "working": state = "working"
            case "idle", "done": state = "idle"
            case "blocked": state = "needs_input"
            default: continue
            }
            bound.append(Binding(id: identity.conversation(machine: machine, session: session, provider: provider, providerSession: providerSession), provider: provider, providerSession: providerSession.lowercased(), terminal: terminal, workspace: workspace,
                                 surfaceID: identity.uuid(machine: machine, session: session, resource: terminal), workspaceID: identity.uuid(machine: machine, session: session, resource: workspace),
                                 // The name the owner gave the tab wins, as a workspace's own name does; the agent's
                                 // terminal title is only a fallback, so renaming the tab renames the conversation.
                                 title: tabNames[terminal] ?? content["title"].string.flatMap { $0.isEmpty ? nil : $0 } ?? workspaceRows[workspace]?["name"].string ?? provider, cwd: content["cwd"].string, state: state))
        }
        bindings = bound
    }
    func selectors(_ binding: Binding? = nil) -> [String: JSONValue] {
        var result: [String: JSONValue] = ["machine": .string(machine), "session": .string(session)]
        if let binding { result["workspace"] = .string(binding.workspace); result["terminal"] = .string(binding.terminal) }
        return result
    }
}
