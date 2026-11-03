import CmuxRemoteCore

/// Aggregates local desktop and discovered daemon resources under one phone pairing and scope model.
public actor CmuxBackendRouter: CmuxControlling {
    private let desktop: (any CmuxControlling)?
    private let discovery: TuiSocketDiscovery
    private let factory: @Sendable (String) -> TuiControlAdapter
    private var daemons: [String: TuiControlAdapter] = [:]
    public init(desktop: (any CmuxControlling)?, discovery: TuiSocketDiscovery, factory: @escaping @Sendable (String) -> TuiControlAdapter) {
        self.desktop = desktop; self.discovery = discovery; self.factory = factory
    }
    /// Injected daemon instances make backend routing testable without host discovery.
    public init(desktop: (any CmuxControlling)?, daemon: TuiControlAdapter) {
        self.desktop = desktop; discovery = TuiSocketDiscovery(directories: [])
        factory = { _ in daemon }
        self.daemons = ["injected": daemon]
    }
    public func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        for path in try discovery.sockets() where daemons[path] == nil { daemons[path] = factory(path) }
        guard daemons.count <= 32 else { throw BridgeError("too_large", "The backend routing table is full.", status: 413) }
        if ["workspace.list", "vault.sessions", "chat.sessions.dump"].contains(method) {
            let key = method == "workspace.list" ? "workspaces" : "sessions"
            var rows: [JSONValue] = [], errors: [JSONValue] = [], available = false, sources: [String] = []
            var identities = Set<String>()
            if let desktop {
                do { rows = try await desktop.request(method, params: params)[key].array ?? []; available = true; sources += Array(repeating: "desktop", count: rows.count) }
                catch { errors.append(.string((error as? BridgeError)?.code ?? "socket_unavailable")) }
            }
            for path in daemons.keys.sorted() {
                do {
                    guard let items = try await daemons[path]!.request(method, params: params)[key].array, items.count <= 4096 else { throw BridgeError("invalid_response", "A backend returned an invalid inventory.", status: 502) }
                    if let identity = await daemons[path]!.identity(), !identities.insert(identity).inserted { continue }
                    rows += items; available = true; sources += Array(repeating: String(path.split(separator: "/").last ?? "daemon"), count: items.count)
                } catch { errors.append(.string((error as? BridgeError)?.code ?? "socket_unavailable")) }
            }
            guard available, rows.count <= 4096 else { throw BridgeError("socket_unavailable", "No local cmux backend is available.", status: 503) }
            let field = key == "workspaces" ? "id" : "session_id"
            var ids = rows.map { $0[field].string?.lowercased() }
            // A resumed Codex session keeps its ID and writes a new transcript file, so one backend lists it once
            // per file. Rows from one backend that agree on agent and directory are that one session: the most
            // recently modified row stands for it.
            var newest: [String: Int] = [:]
            for index in rows.indices {
                guard let id = ids[index], let agent = rows[index]["agent"].string, let directory = rows[index]["cwd"].string else { continue }
                let group = id + "\u{0}" + sources[index] + "\u{0}" + agent + "\u{0}" + directory
                if let kept = newest[group] {
                    let later = (rows[index]["modified"].string ?? "") > (rows[kept]["modified"].string ?? "")
                    ids[later ? kept : index] = "\u{0}superseded"; if later { newest[group] = index }
                } else { newest[group] = index }
            }
            let superseded = ids.filter { $0 == "\u{0}superseded" }.count
            if superseded > 0 { BridgeLog.shared.info("inventory", "\(method) folded \(superseded) older transcript rows of resumed sessions") }
            let folded = rows.indices.filter { ids[$0] != "\u{0}superseded" }
            rows = folded.map { rows[$0] }; sources = folded.map { sources[$0] }; ids = folded.map { ids[$0] }
            var counts: [String: Int] = [:]
            for id in ids.compactMap({ $0 }) { counts[id, default: 0] += 1 }
            // An unidentified or ambiguous row cannot be routed safely, so it is left out on its own; every other
            // row is still listed. Failing the whole inventory left the phone with no sessions at all.
            let kept = rows.indices.filter { ids[$0].map { counts[$0] == 1 } ?? false }
            if kept.count != rows.count {
                let missing = rows.indices.filter { ids[$0] == nil }.map { sources[$0] }
                let duplicated = counts.filter { $0.value > 1 }.map { id, count in
                    "\(id.prefix(12))x\(count)[" + rows.indices.filter { ids[$0] == id }.map { sources[$0] }.joined(separator: ",") + "]"
                }
                BridgeLog.shared.warning("inventory", "\(method) left out \(rows.count - kept.count) of \(rows.count) rows; missing \(field) from \(missing); duplicated \(duplicated.sorted())")
                errors.append(.string("identity_collision"))
            }
            return .object([key: .array(kept.map { rows[$0] }), "backend_errors": .array(errors)])
        }
        if method == "system.ping" {
            var active = 0
            if let desktop, (try? await desktop.request(method, params: params)) != nil { active += 1 }
            for daemon in daemons.values where (try? await daemon.request(method, params: params)) != nil { active += 1 }
            guard active > 0 else { throw BridgeError("socket_unavailable", "No local cmux backend is available.", status: 503) }
            return .object(["active_backends": .number(Double(active))])
        }
        if method == "system.capabilities" {
            var fields = (try? await desktop?.request(method, params: params))?.object ?? [:]
            fields["tui_daemons"] = .number(Double(daemons.count)); return .object(fields)
        }
        for daemon in daemons.values {
            if let id = params["request_id"]?.string, await daemon.ownsDecision(id) { return try await daemon.request(method, params: params) }
            if let id = params["session_id"]?.string, await daemon.ownsConversation(id) { return try await daemon.request(method, params: params) }
            if let surface = params["surface_id"]?.string, await daemon.ownsSurface(surface) { return try await daemon.request(method, params: params) }
            // Creating a terminal names only its workspace.
            if params["surface_id"] == nil, let workspace = params["workspace_id"]?.string, await daemon.ownsWorkspace(workspace) { return try await daemon.request(method, params: params) }
        }
        // A missing namespaced target must never fall through to another backend.
        if params["session_id"]?.string?.hasPrefix("tui:") == true { throw BridgeError("stale_binding", "The daemon conversation is no longer available.", status: 409) }
        if params["request_id"]?.string?.hasPrefix("tui-decision:") == true { throw BridgeError("request_expired", "The daemon decision no longer exists.", status: 409) }
        if method == "feed.list" {
            var items = (try? await desktop?.request(method, params: params)["items"].array) ?? []
            for daemon in daemons.values { items += (try? await daemon.request(method, params: params)["items"].array) ?? [] }
            return .object(["items": .array(items)])
        }
        guard let desktop else { throw BridgeError("unsupported", "This operation requires a desktop cmux backend.", status: 422) }
        return try await desktop.request(method, params: params)
    }
}
