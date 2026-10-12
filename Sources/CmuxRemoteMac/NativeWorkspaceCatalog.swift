import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Creates native inventory rows without reading remote terminals until selection.
public actor NativeWorkspaceCatalog {
    private let local: any CmuxControlling
    private let repository: NativeWorkspaceRepository
    private let mirrors: WorkspaceMirrorCoordinator
    private let grouping: any NativeRemoteWorkspaceGrouping
    private let executable: URL
    private let stateDirectory: URL
    private let authorize: @Sendable (String, String) async throws -> (HostIdentity, any MirrorRemoteControlling)
    private let waitTimeout: Duration
    private var loaded = false
    private var entries: [UUID: NativeWorkspaceEntry] = [:]
    private var selected = Set<String>()
    private var syncing = Set<String>()
    private var waiters: [UUID: (UUID, AsyncStream<Void>.Continuation)] = [:]
    public init(local: any CmuxControlling, repository: NativeWorkspaceRepository, mirrors: WorkspaceMirrorCoordinator,
                grouping: any NativeRemoteWorkspaceGrouping, executable: URL, stateDirectory: URL,
                waitTimeout: Duration = .seconds(4),
                authorize: @escaping @Sendable (String, String) async throws -> (HostIdentity, any MirrorRemoteControlling)) {
        self.local = local; self.repository = repository; self.mirrors = mirrors; self.grouping = grouping
        self.executable = executable; self.stateDirectory = stateDirectory; self.authorize = authorize; self.waitTimeout = waitTimeout
    }
    private func load() async throws {
        guard !loaded else { return }
        let rows = try await repository.load()
        guard !loaded else { return }
        entries = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) }); loaded = true
    }
    private func persist() async throws {
        try await repository.save(entries.values.sorted { $0.id.uuidString < $1.id.uuidString })
    }
    /// Synchronizes only the host's authenticated, scoped metadata listing.
    public func sync(host: HostIdentity, workspaces: [WorkspaceSummary]) async throws {
        try await load(); try IdentityCryptography().validate(host)
        guard workspaces.count <= 64, Set(workspaces.map { $0.id.lowercased() }).count == workspaces.count,
              workspaces.allSatisfy({ UUID(uuidString: $0.id) != nil && $0.title.utf8.count <= 4096 }) else {
            throw BridgeError("invalid_response", "Invalid scoped native inventory.")
        }
        guard syncing.insert(host.id).inserted else { throw BridgeError("mirror_busy", "This host inventory is being refreshed.", status: 409) }
        defer { syncing.remove(host.id) }
        let localSnapshot = entries.values.contains(where: { $0.hostID == host.id }) ? try await localWindows() : [:]
        let available = Set(workspaces.map { $0.id.lowercased() })
        for id in entries.keys where entries[id]?.hostID == host.id && !available.contains(entries[id]!.workspaceID) {
            // Missing metadata must not erase an in-flight or uncertain local write.
            if ["creating", "attaching"].contains(entries[id]!.state) || entries[id]?.errorCode == "outcome_unknown" { continue }
            entries[id]?.state = "unavailable"; entries[id]?.errorCode = "not_found"
            waiters.removeValue(forKey: id)?.1.finish()
        }
        for workspace in workspaces {
            let remoteID = workspace.id.lowercased()
            if let existing = entries.values.first(where: { $0.hostID == host.id && $0.workspaceID == remoteID }) {
                // Creating/attaching intents are not repeated after a lost response.
                // Native rows remain available for inspection after restarts.
                if let seed = existing.seed {
                    guard let window = localSnapshot[seed.workspaceID] else { continue }
                    if window != seed.windowID { entries[existing.id]?.seed = .init(workspaceID: seed.workspaceID, surfaceID: seed.surfaceID, windowID: window) }
                    do { try await grouping.place(workspaceID: seed.workspaceID, windowID: window) }
                    catch let error as BridgeError where error.code == "stale_binding" { continue }
                    if entries[existing.id]?.state == "pending", try await localWindows()[seed.workspaceID] != nil { entries[existing.id]?.errorCode = nil }
                }
                continue
            }
            guard entries.count < 4096 else { throw BridgeError("mirror_capacity", "The native remote inventory is full.", status: 429) }
            var row = NativeWorkspaceEntry(hostID: host.id, workspaceID: remoteID, title: host.name + " · " + workspace.title)
            if let existingWS = await mirrors.existingWorkspace(hostID: host.id, workspaceID: remoteID),
               let view = await mirrors.list().first(where: { $0.localWorkspaceID == existingWS }), let surface = view.localSurfaceID {
                let tree = try await local.request("system.tree", params: ["all_windows": .bool(true)])
                guard let window = tree["windows"].array?.first(where: { ($0["workspaces"].array ?? []).contains { $0["id"].string == existingWS } })?["id"].string else {
                    throw BridgeError("stale_binding", "The attached native workspace moved.", status: 409)
                }
                row.seed = .init(workspaceID: existingWS, surfaceID: surface, windowID: window)
                row.state = "attached"; row.projectionID = view.id
                entries[row.id] = row; try await persist(); continue
            }
            entries[row.id] = row; try await persist()
            try await createPending(row.id)
        }
        try await persist()
    }
    private func createPending(_ id: UUID) async throws {
        guard let row = entries[id], row.state == "creating", row.seed == nil else { throw BridgeError("mirror_busy", "Native creation is already owned.", status: 409) }
        do {
            let created = try await local.request("workspace.create", params: ["title": .string(row.title),
                "initial_command": .string(command(id)), "focus": .bool(false)])
            guard let ws = created["workspace_id"].string, let surface = created["surface_id"].string, let window = created["window_id"].string,
                  [ws, surface, window].allSatisfy({ UUID(uuidString: $0) != nil }) else { throw BridgeError("outcome_unknown", "Inspect native inventory before repeating creation.", status: 409) }
            entries[id]?.seed = .init(workspaceID: ws, surfaceID: surface, windowID: window)
            entries[id]?.state = "pending"; try await persist()
            do { try await grouping.place(workspaceID: ws, windowID: window) }
            catch let error as BridgeError where error.code == "stale_binding" {
                // Confirmed creation can precede group/list publication. The
                // metadata watcher will place this same row after publication.
                entries[id]?.errorCode = error.code; try await persist()
            }
            for attempt in 0..<8 {
                try Task.checkCancellation()
                if try await localWindows()[ws] != nil { return }
                if attempt == 7 { throw BridgeError("mirror_busy", "Native creation is confirmed; wait for its inventory snapshot before opening again.", status: 409) }
            }
        } catch {
            if entries[id]?.seed == nil { entries[id]?.state = "paused" }
            entries[id]?.errorCode = (error as? BridgeError)?.code ?? "connection_failed"
            try await persist(); throw error
        }
    }
    /// An explicit open can replace a confirmed closed row, never an unknown creation.
    /// Existing partial/user-edited workspaces remain untouched for inspection.
    public func select(hostID: String, workspaceID: String) async throws -> JSONValue {
        try await load()
        guard let entry = entries.values.first(where: { $0.hostID == hostID && $0.workspaceID == workspaceID.lowercased() }) else { throw BridgeError("mirror_detached", "No native inventory row exists.", status: 409) }
        guard let seed = entry.seed else { throw BridgeError(entry.errorCode ?? "mirror_detached", "Inspect unknown native creation before opening another row.", status: 409) }
        guard !syncing.contains(hostID), entry.state != "attaching", entry.state != "creating" else { throw BridgeError("mirror_busy", "Native inventory is being updated.", status: 409) }
        syncing.insert(hostID); defer { syncing.remove(hostID) }
        let windows = try await localWindows()
        if let window = windows[seed.workspaceID] {
            let presented = await presentation(entry)
            guard presented.state == "pending" || presented.state == "attached" else { throw BridgeError(presented.errorCode ?? "mirror_detached", "Inspect this existing local mirror before recreating its views.", status: 409) }
            if window != seed.windowID {
                entries[entry.id]?.seed = .init(workspaceID: seed.workspaceID, surfaceID: seed.surfaceID, windowID: window)
                try await persist(); try await grouping.place(workspaceID: seed.workspaceID, windowID: window)
            }
            _ = try await mirrors.selectCatalogWorkspace(seed.workspaceID, windowID: window)
            return .object(["workspace_id": .string(seed.workspaceID), "catalog_pending": .bool(presented.state == "pending")])
        }
        guard entry.state != "pending" || entry.errorCode != "mirror_busy" else { throw BridgeError("mirror_busy", "Wait for the confirmed native row to become visible.", status: 409) }
        // Read the complete local window inventory again; moving a workspace
        // between windows cannot be mistaken for closing it.
        guard try await localWindows()[seed.workspaceID] == nil else { throw BridgeError("mirror_busy", "The native workspace moved during inspection.", status: 409) }
        let returnedConfirmedRow = entry.state == "unavailable" && entry.errorCode == "not_found"
        guard entry.errorCode != "outcome_unknown", entry.state == "attached" || entry.state == "pending" || entry.state == "paused" || returnedConfirmedRow else {
            throw BridgeError("outcome_unknown", "Inspect the prior native operation before creating another row.", status: 409)
        }
        let (host, remote) = try await authorize(hostID, entry.workspaceID)
        guard host.id == hostID else { throw BridgeError("host_changed", "Native inventory host changed.", status: 409) }
        let snapshot = try await remote.workspace(entry.workspaceID)
        guard snapshot.id.lowercased() == entry.workspaceID else { throw BridgeError("invalid_response", "The remote returned another workspace.") }
        // Authority reads suspend the actor: verify absence once more before intent.
        guard try await localWindows()[seed.workspaceID] == nil else { throw BridgeError("mirror_busy", "The original native row returned during authorization.", status: 409) }
        entries[entry.id]?.seed = nil; entries[entry.id]?.projectionID = nil
        entries[entry.id]?.state = "creating"; entries[entry.id]?.errorCode = nil
        waiters.removeValue(forKey: entry.id)?.1.finish()
        try await persist(); try await createPending(entry.id)
        guard let replacement = entries[entry.id]?.seed else { throw BridgeError("outcome_unknown", "Inspect native creation before repeating it.", status: 409) }
        _ = try await mirrors.selectCatalogWorkspace(replacement.workspaceID, windowID: replacement.windowID)
        return .object(["workspace_id": .string(replacement.workspaceID), "catalog_pending": .bool(true), "recreated": .bool(true)])
    }
    private func localWindows() async throws -> [String: String] {
        let tree = try await local.request("system.tree", params: ["all_windows": .bool(true)])
        guard let windows = tree["windows"].array, windows.count <= 128 else { throw BridgeError("invalid_response", "Invalid complete local window inventory.") }
        var result: [String: String] = [:]
        for window in windows {
            guard let windowID = window["id"].string, UUID(uuidString: windowID) != nil, let rows = window["workspaces"].array, rows.count <= 4096 else { throw BridgeError("invalid_response", "Invalid local workspace inventory.") }
            for row in rows {
                guard let id = row["id"].string, UUID(uuidString: id) != nil, result[id] == nil, result.count < 4096 else { throw BridgeError("invalid_response", "Invalid local workspace identity.") }
                result[id] = windowID
            }
        }
        return result
    }
    private func presentation(_ entry: NativeWorkspaceEntry) async -> NativeWorkspaceEntry {
        var value = entry
        guard entry.state == "attached" else { return value }
        let views = await mirrors.list(), status = await mirrors.syncStatus().first { $0.hostID == entry.hostID && $0.workspaceID.lowercased() == entry.workspaceID }
        if status?.state == "paused" || entry.projectionID == nil || !views.contains(where: { $0.id == entry.projectionID && $0.localWorkspaceID == entry.seed?.workspaceID }) {
            value.state = "paused"; value.errorCode = status?.errorCode ?? "mirror_detached"
        }
        return value
    }
    /// Reads local selection once per window; it never selects or raises a workspace.
    public func refreshSelection() async throws {
        try await load()
        var next = Set<String>()
        for window in Set(entries.values.compactMap { $0.seed?.windowID }) {
            let listing = try await local.request("workspace.list", params: ["window_id": .string(window)])
            guard let rows = listing["workspaces"].array, rows.count <= 4096 else { throw BridgeError("invalid_response", "Invalid native selection snapshot.") }
            for row in rows where row["selected"].bool == true { if let id = row["id"].string { next.insert(id) } }
        }
        selected = next
        for (id, waiter) in waiters {
            if let seed = entries[id]?.seed, next.contains(seed.workspaceID) { waiter.1.yield(()); waiter.1.finish() }
        }
    }
    /// Waits for selection with one bounded, cancellable waiter per pending row.
    public func wait(_ id: UUID) async throws -> Bool {
        try await load()
        guard let entry = entries[id] else { throw BridgeError("mirror_detached", "This native row is no longer owned.", status: 410) }
        guard entry.state == "pending" || entry.state == "creating" else { throw BridgeError(entry.errorCode ?? "mirror_detached", "Inspect the native row before reattaching.", status: 409) }
        if let seed = entry.seed, selected.contains(seed.workspaceID) { return true }
        guard waiters[id] == nil else { throw BridgeError("mirror_busy", "This row already has a selection waiter.", status: 409) }
        let token = UUID(), stream = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        waiters[id] = (token, stream.continuation)
        defer { if waiters[id]?.0 == token { waiters[id] = nil }; stream.continuation.finish() }
        let timeout = waitTimeout
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { var iterator = stream.stream.makeAsyncIterator(); return await iterator.next() != nil }
            group.addTask { try await Task.sleep(for: timeout); return false }
            defer { group.cancelAll() }
            return try await group.next() ?? false
        }
    }
    /// Opens only the exact selected local pending row, with freshly checked host authority.
    public func open(_ id: UUID, workspaceID: String, surfaceID: String) async throws -> UUID {
        try await load()
        guard let entry = entries[id], let seed = entry.seed, seed.workspaceID == workspaceID, seed.surfaceID == surfaceID else {
            throw BridgeError("stale_binding", "The native row's local binding changed.", status: 409)
        }
        if entry.state == "attached", let projection = entry.projectionID,
           await mirrors.list().contains(where: { $0.id == projection }) { return projection }
        guard entry.state == "pending" else { throw BridgeError(entry.errorCode ?? "mirror_detached", "This native attachment cannot be retried automatically.", status: 409) }
        try await refreshSelection()
        guard selected.contains(workspaceID) else { throw BridgeError("not_selected", "Select the native remote row first.", status: 409) }
        entries[id]?.state = "attaching"; try await persist()
        do {
            let (host, remote) = try await authorize(entry.hostID, entry.workspaceID)
            guard host.id == entry.hostID else { throw BridgeError("host_changed", "Native inventory host identity changed.", status: 409) }
            let result = try await mirrors.create(host: host, workspaceID: entry.workspaceID, remote: remote, seed: seed)
            guard result["workspace_id"].string == workspaceID, let raw = result["projection_id"].string, let projection = UUID(uuidString: raw) else {
                throw BridgeError("outcome_unknown", "Inspect the native row before repeating attachment.", status: 409)
            }
            entries[id]?.state = "attached"; entries[id]?.projectionID = projection; try await persist()
            return projection
        } catch {
            entries[id]?.state = "paused"; entries[id]?.errorCode = (error as? BridgeError)?.code ?? "connection_failed"
            try await persist(); throw error
        }
    }
    public func rows() async throws -> [NativeWorkspaceEntry] {
        try await load(); let windows = try await localWindows(); var result: [NativeWorkspaceEntry] = []
        for entry in entries.values.sorted(by: { $0.title < $1.title }) {
            var value = await presentation(entry)
            if let seed = entry.seed, windows[seed.workspaceID] == nil, !(entry.state == "pending" && entry.errorCode == "mirror_busy") { value.state = "paused"; value.errorCode = "mirror_detached" }
            result.append(value)
        }
        return result
    }
    public func row(hostID: String, workspaceID: String) async throws -> NativeWorkspaceEntry? {
        try await load(); return entries.values.first { $0.hostID == hostID && $0.workspaceID == workspaceID.lowercased() }
    }
    public func forget(hostID: String) async throws {
        try await load()
        guard !syncing.contains(hostID), !entries.values.contains(where: { $0.hostID == hostID && $0.state == "attaching" }) else {
            throw BridgeError("mirror_busy", "Wait for this host's native workspace operation to finish.", status: 409)
        }
        for id in entries.keys where entries[id]?.hostID == hostID { waiters.removeValue(forKey: id)?.1.finish(); entries[id] = nil }
        try await persist()
    }
    private func command(_ id: UUID) -> String {
        quote(executable.path) + " mirror pending --state " + quote(stateDirectory.path) + " --entry " + quote(id.uuidString)
    }
    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
