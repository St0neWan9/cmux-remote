import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Owns local-only projections and starts viewers without restarting any remote process.
public actor WorkspaceMirrorCoordinator {
    private let local: any CmuxControlling
    private let executable: URL
    private let stateDirectory: URL
    private let nativeGroup: (any NativeRemoteWorkspaceGrouping)?
    private let checkpoints: MirrorCheckpointRepository?
    private var projections: [UUID: MirrorProjection] = [:]
    private var sources: [UUID: any MirrorRemoteControlling] = [:]
    private var workspaces: [String: String] = [:]
    private var creating = Set<String>()
    private struct Attachment {
        let generation = UUID()
        let host: HostIdentity
        let remote: any MirrorRemoteControlling
        let localWorkspace: String
        var snapshot: MirrorWorkspaceSnapshot
    }
    private var attachments: [String: Attachment] = [:]
    private var retired: [UUID: MirrorProjection] = [:]
    private var watchers: [String: Task<Void, Never>] = [:]
    private var syncErrors: [String: String] = [:]
    private var syncDetails: [String: String] = [:]
    private var transportFailures: [String: String] = [:]
    private var restorationFailures: [String: MirrorSyncStatus] = [:]
    private let topologyTicks: @Sendable () -> AsyncStream<Void>
    public init(local: any CmuxControlling, executable: URL, stateDirectory: URL,
                topologyTicks: (@Sendable () -> AsyncStream<Void>)? = nil,
                nativeGroup: (any NativeRemoteWorkspaceGrouping)? = nil, checkpoints: MirrorCheckpointRepository? = nil) {
        self.local = local; self.executable = executable; self.stateDirectory = stateDirectory
        self.topologyTicks = topologyTicks ?? { MirrorTopologyTicker().start() }
        self.nativeGroup = nativeGroup
        self.checkpoints = checkpoints
    }

    public func create(host: HostIdentity, workspaceID: String, remote: any MirrorRemoteControlling, seed: MirrorLocalSeed? = nil) async throws -> JSONValue {
        guard UUID(uuidString: workspaceID) != nil else { throw BridgeError("invalid_input", "Choose an explicit workspace UUID.") }
        let key = host.id + ":" + workspaceID.lowercased()
        guard !creating.contains(key) else { throw BridgeError("mirror_busy", "This mirror is being updated.", status: 409) }
        if let id = workspaces[key] {
            let list = try await local.request("workspace.list", params: [:])
            let hasAttachedView = projections.values.contains { $0.localWorkspaceID == id && sources[$0.id] != nil }
            if hasAttachedView, (list["workspaces"].array ?? []).contains(where: { $0["id"].string == id }) {
                _ = try await local.request("workspace.select", params: ["workspace_id": .string(id)])
                if let code = syncErrors[key] { throw BridgeError(code, "Inspect the local mirror before resuming layout updates.", status: 409) }
                return .object(["workspace_id": .string(id), "existing": .bool(true)])
            }
            for id in projections.keys.filter({ projections[$0]?.hostID == host.id && projections[$0]?.workspaceID.lowercased() == workspaceID.lowercased() }) {
                projections[id] = nil; sources[id] = nil
            }
            workspaces[key] = nil
            watchers.removeValue(forKey: key)?.cancel(); attachments[key] = nil; syncErrors[key] = nil; syncDetails[key] = nil
            retired = retired.filter { $0.value.localWorkspaceID != id }
        }
        guard projections.count < 4096 else { throw BridgeError("mirror_capacity", "Detach old local views before creating more mirrors.", status: 429) }
        guard creating.insert(key).inserted else { throw BridgeError("mirror_busy", "This workspace mirror is already being created.", status: 409) }
        defer { creating.remove(key) }
        if let seed {
            guard UUID(uuidString: seed.workspaceID) != nil, UUID(uuidString: seed.surfaceID) != nil, UUID(uuidString: seed.windowID) != nil else { throw BridgeError("invalid_input", "Invalid native catalog seed.") }
            let members = try await local.request("surface.list", params: ["workspace_id": .string(seed.workspaceID)])
            guard members["workspace_id"].string == seed.workspaceID,
                  members["surfaces"].array?.count == 1, members["surfaces"].array?.first?["id"].string == seed.surfaceID else {
                throw BridgeError("mirror_local_changed", "The native catalog workspace was edited.", status: 409)
            }
        }
        let snapshot = try await remote.workspace(workspaceID)
        guard snapshot.id.lowercased() == workspaceID.lowercased() else { throw BridgeError("invalid_response", "The host returned another workspace.") }
        let layout = try MirrorLayoutPlan.make(snapshot)
        guard projections.count + retired.count + snapshot.surfaces.count <= 4096 else { throw BridgeError("mirror_capacity", "Detach old local views before creating more mirrors.", status: 429) }
        var tickets: [String: UUID] = [:]
        do {
            // Prove replay support before creating any local workspace or view.
            for surface in snapshot.surfaces {
                let replay = try await remote.replay(workspaceID: workspaceID, surfaceID: surface.id)
                try validate(replay, workspaceID: workspaceID, surfaceID: surface.id)
                let projection = MirrorProjection(hostID: host.id, workspaceID: workspaceID, surfaceID: surface.id, runtimeEpoch: replay.runtimeEpoch)
                projections[projection.id] = projection; sources[projection.id] = remote; tickets[surface.id] = projection.id
            }
            let first = layout.firstSurface
            let created: JSONValue
            if let seed {
                created = .object(["workspace_id": .string(seed.workspaceID), "surface_id": .string(seed.surfaceID), "window_id": .string(seed.windowID)])
            } else {
                created = try await local.request("workspace.create", params: ["title": .string(host.name + " · " + snapshot.title),
                    "initial_command": .string(command(tickets[first.id]!)), "focus": .bool(false)])
            }
            guard let localWorkspace = created["workspace_id"].string, let localSurface = created["surface_id"].string,
                  UUID(uuidString: localWorkspace) != nil, UUID(uuidString: localSurface) != nil else {
                throw BridgeError("invalid_response", "cmux did not identify the newly created mirror.")
            }
            workspaces[key] = localWorkspace
            try await populate(layout, localWorkspace: localWorkspace, localSurface: localSurface, tickets: tickets)
            try await nativeGroup?.place(workspaceID: localWorkspace, windowID: created["window_id"].string)
            // This selection is the user's explicit mirror action, not a remote focus command.
            if seed == nil { _ = try await local.request("workspace.select", params: ["workspace_id": .string(localWorkspace)]) }
            attachments[key] = Attachment(host: host, remote: remote, localWorkspace: localWorkspace, snapshot: snapshot)
            restorationFailures[key] = nil
            try await persist(including: key)
            startWatching(key)
            return .object(["workspace_id": .string(localWorkspace), "terminals": .number(Double(snapshot.surfaces.count)),
                            "projection_id": .string(tickets[first.id]!.uuidString), "mode": .string("snapshot"), "ratios_preserved": .bool(false)])
        } catch {
            for ticket in tickets.values { projections[ticket] = nil; sources[ticket] = nil }
            workspaces[key] = nil
            attachments[key] = nil; watchers.removeValue(forKey: key)?.cancel()
            // Keep a partial local workspace visible for inspection; never retry a lost create.
            throw error
        }
    }
    /// Returns only an already attached projection owned by this coordinator.
    public func existingWorkspace(hostID: String, workspaceID: String) -> String? {
        guard let id = workspaces[hostID + ":" + workspaceID.lowercased()],
              projections.values.contains(where: { $0.localWorkspaceID == id && sources[$0.id] != nil }) else { return nil }
        return id
    }
    /// Routes an explicit catalog-row selection without opening another workspace.
    public func selectCatalogWorkspace(_ id: String, windowID: String? = nil) async throws -> JSONValue {
        guard UUID(uuidString: id) != nil else { throw BridgeError("invalid_input", "Use an exact native workspace.") }
        var params: [String: JSONValue] = ["workspace_id": .string(id)]
        if let windowID { guard UUID(uuidString: windowID) != nil else { throw BridgeError("invalid_input", "Use an exact native window.") }; params["window_id"] = .string(windowID) }
        return try await local.request("workspace.select", params: params)
    }

    public func replay(_ id: UUID) async throws -> MirrorTerminalSnapshot {
        guard let projection = projections[id], let remote = sources[id] else { throw BridgeError("mirror_detached", "This viewer is detached. Recreate the mirror explicitly.", status: 410) }
        let key = projection.hostID + ":" + projection.workspaceID.lowercased()
        let snapshot: MirrorTerminalSnapshot
        do { snapshot = try await remote.replay(workspaceID: projection.workspaceID, surfaceID: projection.surfaceID) }
        catch {
            if (error as? BridgeError)?.code == "mirror_remote_unavailable", projections[id] != nil { transportFailures[key] = "mirror_remote_unavailable" }
            throw error
        }
        try validate(snapshot, workspaceID: projection.workspaceID, surfaceID: projection.surfaceID)
        guard projections[id] != nil else {
            // A read that started before deliberate removal cannot resurrect
            // its retired binding or pause the surviving workspace.
            throw BridgeError("mirror_detached", "This local viewer was removed.", status: 410)
        }
        guard snapshot.runtimeEpoch == projection.runtimeEpoch else {
            retired[id] = projection; projections[id] = nil; sources[id] = nil
            pause(key: projection.hostID + ":" + projection.workspaceID.lowercased(), code: "stale_binding")
            try await persist()
            throw BridgeError("stale_binding", "The terminal runtime changed; this viewer was detached.", status: 409)
        }
        transportFailures[key] = nil
        // Keep older peers' baseline and paint inside the same presentation.
        // This boundary also repairs existing viewers without restarting them.
        var presentation = MirrorTerminalSnapshot(workspaceID: snapshot.workspaceID, surfaceID: snapshot.surfaceID,
            runtimeEpoch: snapshot.runtimeEpoch, columns: snapshot.columns, rows: snapshot.rows,
            bytes: TerminalPresentationFrame().bytes(for: snapshot.bytes))
        presentation.allowsInput = snapshot.allowsInput
        presentation.presentationKey = snapshot.presentationKey
        presentation.repaintBytes = snapshot.repaintBytes
        presentation.renderGrid = snapshot.renderGrid
        presentation.pasteSupported = snapshot.pasteSupported
        return presentation
    }
    public func input(_ id: UUID, request: MirrorInputRequest) async throws -> MutationReceipt {
        guard let projection = projections[id], let remote = sources[id], projection.runtimeEpoch == request.runtimeEpoch else {
            throw BridgeError("stale_binding", "Input does not belong to this attached producer.", status: 409)
        }
        return try await remote.input(workspaceID: projection.workspaceID, surfaceID: projection.surfaceID, request: request)
    }
    public func detach(_ id: UUID, reason: String? = nil) async throws {
        guard let view = projections[id] ?? retired[id] else { return }
        if reason == "stale_binding" || reason == "not_found" {
            retired[id] = view; projections[id] = nil; sources[id] = nil
            try await persist(excluding: view.hostID + ":" + view.workspaceID.lowercased())
            // A removed source can still be reconciled. A replaced runtime is
            // refused when the next scoped workspace snapshot contains its ID.
            return
        }
        projections[id] = nil; sources[id] = nil; retired[id] = nil
        pause(key: view.hostID + ":" + view.workspaceID.lowercased(), code: reason ?? "mirror_detached")
        try await persist()
    }
    public func detach(hostID: String) async throws {
        restorationFailures = restorationFailures.filter { $0.value.hostID != hostID }
        transportFailures = transportFailures.filter { !$0.key.hasPrefix(hostID + ":") }
        for id in projections.keys.filter({ projections[$0]?.hostID == hostID }) { projections[id] = nil; sources[id] = nil }
        workspaces = workspaces.filter { !$0.key.hasPrefix(hostID + ":") }
        retired = retired.filter { $0.value.hostID != hostID }
        for key in attachments.keys.filter({ $0.hasPrefix(hostID + ":") }) {
            watchers.removeValue(forKey: key)?.cancel(); attachments[key] = nil; syncErrors[key] = nil; syncDetails[key] = nil
        }
        try await persist()
    }
    public func list() -> [MirrorProjection] { Array(projections.values).sorted { $0.id.uuidString < $1.id.uuidString } }
    /// Updates one attached workspace using only fixed local layout operations.
    public func reconcile(hostID: String, workspaceID: String, force: Bool = false) async throws -> JSONValue {
        let key = hostID + ":" + workspaceID.lowercased()
        guard let attachment = attachments[key] else { throw BridgeError("mirror_detached", "Attach this workspace first.", status: 410) }
        if let code = syncErrors[key] { throw BridgeError(code, "Inspect the paused local mirror before recreating it.", status: 409) }
        guard creating.insert(key).inserted else { throw BridgeError("mirror_busy", "This mirror is being updated.", status: 409) }
        defer { creating.remove(key) }
        var localWritesStarted = false
        do {
            let next = try await attachment.remote.workspace(workspaceID)
            guard next.id.lowercased() == workspaceID.lowercased() else { throw BridgeError("invalid_response", "The host returned another workspace.") }
            let plan = try MirrorLayoutPlan.make(next), previous = try MirrorLayoutPlan.make(attachment.snapshot)
            try admit(key, generation: attachment.generation)
            if next == attachment.snapshot, !force {
                let owned = Set(projections.values.filter { $0.localWorkspaceID == attachment.localWorkspace }.compactMap(\.localSurfaceID))
                _ = try await MirrorLayoutUpdater(local: local).members(workspace: attachment.localWorkspace, owned: owned)
                transportFailures[key] = nil
                return .object(["changed": .bool(false)])
            }
            let updater = MirrorLayoutUpdater(local: local)
            let old = (Array(projections.values) + Array(retired.values)).filter { $0.localWorkspaceID == attachment.localWorkspace }
            var owned = Set(old.compactMap(\.localSurfaceID))
            guard old.count == attachment.snapshot.surfaces.count, owned.count == old.count else {
                throw BridgeError("mirror_local_changed", "The local mirror was detached or edited.", status: 409)
            }
            let nextIDs = Set(next.surfaces.map(\.id))
            let removedLocal = Set(old.filter { !nextIDs.contains($0.surfaceID) }.compactMap(\.localSurfaceID))
            let observed = try await updater.observedMembers(workspace: attachment.localWorkspace)
            let missing = owned.subtracting(observed.keys)
            guard Set(observed.keys).isSubset(of: owned), missing.isSubset(of: removedLocal) else {
                _ = try await updater.members(workspace: attachment.localWorkspace, owned: owned)
                throw BridgeError("mirror_local_changed", "The local mirror changed.", status: 409)
            }
            // cmux may remove an owned local viewer when its foreground process
            // exits after source deletion. Only already-removed sources qualify.
            owned.subtract(missing)
            let current = observed
            var mapping = Dictionary(uniqueKeysWithValues: old.map { ($0.surfaceID, $0.localSurfaceID!) })
            let structural = force || plan.topologySignature != previous.topologySignature
            // A crash during layout writes cannot restore an incomplete binding.
            if structural {
                // Validate every retained producer before any layout mutation.
                var newViews: [MirrorProjection] = []
                for terminal in next.surfaces {
                    let replay = try await attachment.remote.replay(workspaceID: workspaceID, surfaceID: terminal.id)
                    try validate(replay, workspaceID: workspaceID, surfaceID: terminal.id)
                    if let retained = old.first(where: { $0.surfaceID == terminal.id }) {
                        guard retained.runtimeEpoch == replay.runtimeEpoch, sources[retained.id] != nil else {
                            throw BridgeError("stale_binding", "Reattach a replaced producer explicitly.", status: 409)
                        }
                    } else {
                        newViews.append(.init(hostID: hostID, workspaceID: workspaceID.lowercased(), surfaceID: terminal.id, runtimeEpoch: replay.runtimeEpoch))
                    }
                }
                guard projections.count + retired.count + newViews.count <= 4096 else { throw BridgeError("mirror_capacity", "Detach old mirrors before adding more views.", status: 429) }
                guard let pane = current.values.first else { throw BridgeError("mirror_local_changed", "No retained local viewer remains.", status: 409) }
                localWritesStarted = true
                try await persist(excluding: key)
                for var view in newViews {
                    try admit(key, generation: attachment.generation)
                    _ = try await updater.members(workspace: attachment.localWorkspace, owned: owned)
                    view.localWorkspaceID = attachment.localWorkspace
                    projections[view.id] = view; sources[view.id] = attachment.remote
                    let created = try await local.request("surface.create", params: ["workspace_id": .string(attachment.localWorkspace), "pane_id": .string(pane),
                        "type": .string("terminal"), "initial_command": .string(command(view.id)), "focus": .bool(false)])
                    guard let id = created["surface_id"].string, UUID(uuidString: id) != nil else { throw BridgeError("outcome_unknown", "Inspect the local mirror before repeating creation.", status: 409) }
                    projections[view.id]?.localSurfaceID = id; mapping[view.surfaceID] = id; owned.insert(id)
                    try await updater.awaitCreatedSurface(id, workspace: attachment.localWorkspace, owned: owned)
                }
                for view in old where !nextIDs.contains(view.surfaceID) {
                    try admit(key, generation: attachment.generation)
                    _ = try await updater.members(workspace: attachment.localWorkspace, owned: owned)
                    let id = view.localSurfaceID!
                    if owned.contains(id) {
                        let state = try await local.request("surface.input_state", params: ["workspace_id": .string(attachment.localWorkspace), "surface_id": .string(id)])
                        guard state["surface_id"].string == id, state["workspace_id"].string == attachment.localWorkspace,
                              state["terminal"].bool == true, state["agent"].bool == false else { throw BridgeError("mirror_local_changed", "The local mirror terminal was repurposed.", status: 409) }
                        _ = try await local.request("surface.close", params: ["workspace_id": .string(attachment.localWorkspace), "surface_id": .string(id), "force": .bool(true), "focus": .bool(false)])
                    }
                    projections[view.id] = nil; retired[view.id] = nil; sources[view.id] = nil; mapping[view.surfaceID] = nil; owned.remove(id)
                }
                try await updater.apply(plan, workspace: attachment.localWorkspace, mapping: mapping) { [weak self] in
                    guard let self else { throw CancellationError() }; try await self.admit(key, generation: attachment.generation)
                }
            }
            if !structural { localWritesStarted = true; try await persist(excluding: key) }
            for terminal in next.surfaces where attachment.snapshot.surfaces.first(where: { $0.id == terminal.id })?.title != terminal.title {
                try admit(key, generation: attachment.generation)
                _ = try await updater.members(workspace: attachment.localWorkspace, owned: owned)
                try await rename(terminal, localWorkspace: attachment.localWorkspace, localSurface: mapping[terminal.id]!)
            }
            try admit(key, generation: attachment.generation)
            attachments[key]?.snapshot = next
            try await persist(including: key)
            transportFailures[key] = nil
            return .object(["changed": .bool(true), "workspace_id": .string(attachment.localWorkspace), "terminals": .number(Double(next.surfaces.count))])
        } catch {
            if attachments[key]?.generation == attachment.generation {
                if !localWritesStarted, (error as? BridgeError)?.code == "mirror_remote_unavailable" { transportFailures[key] = "mirror_remote_unavailable" }
                else { pause(key: key, code: (error as? BridgeError)?.code ?? "connection_failed", detail: (error as? BridgeError)?.message) }
            }
            throw error
        }
    }
    /// Returns replaceable local synchronization status for the CLI and Companion.
    public func syncStatus() -> [MirrorSyncStatus] {
        let live: [MirrorSyncStatus] = attachments.values.map { attachment in
            let key = attachment.host.id + ":" + attachment.snapshot.id.lowercased()
            return .init(hostID: attachment.host.id, workspaceID: attachment.snapshot.id, localWorkspaceID: attachment.localWorkspace,
                         state: syncErrors[key] != nil ? "paused" : transportFailures[key] != nil ? "reconnecting" : creating.contains(key) ? "syncing" : "watching", errorCode: syncErrors[key] ?? transportFailures[key], detail: syncDetails[key])
        }
        return (live + restorationFailures.values).sorted { $0.localWorkspaceID < $1.localWorkspaceID }
    }
    private func admit(_ key: String, generation: UUID) throws {
        try Task.checkCancellation()
        guard attachments[key]?.generation == generation, syncErrors[key] == nil else { throw BridgeError("mirror_detached", "This layout update was cancelled.", status: 410) }
    }
    private func persist(excluding: String? = nil, including: String? = nil) async throws {
        guard let checkpoints else { return }
        let previous = try await checkpoints.load()
        let records = attachments.compactMap { key, attachment -> MirrorCheckpoint? in
            let views = projections.values.filter { $0.localWorkspaceID == attachment.localWorkspace }
            guard key != excluding, !creating.contains(key) || key == including,
                  syncErrors[key] == nil, views.count == attachment.snapshot.surfaces.count else { return nil }
            return .init(host: attachment.host, localWorkspaceID: attachment.localWorkspace, snapshot: attachment.snapshot, projections: Array(views))
        }
        // Failed read-only restoration owns no active attachment. Keep that
        // metadata while other mirrors persist; explicit forget clears its status.
        let retained = previous.filter { record in
            let key = record.host.id + ":" + record.snapshot.id.lowercased()
            return key != excluding && attachments[key] == nil && restorationFailures[key] != nil
        }
        try await checkpoints.save(records + retained)
    }
    /// Restores completed bindings after checking fresh authority, membership and producer epochs.
    /// It does not create, rename, close, select or type into any local or remote terminal.
    public func restore(authorize: @Sendable (String, String) async throws -> (HostIdentity, any MirrorRemoteControlling)) async throws -> Int {
        guard let checkpoints else { return 0 }
        let records = try await checkpoints.load()
        var restored = 0
        for record in records {
            let key = record.host.id + ":" + record.snapshot.id.lowercased()
            guard attachments[key] == nil, creating.insert(key).inserted else { continue }
            defer { creating.remove(key) }
            var stage = "authorization"
            do {
                let (host, remote) = try await authorize(record.host.id, record.snapshot.id)
                guard host.id == record.host.id, host.publicKey == record.host.publicKey else { throw BridgeError("host_changed", "Checkpoint host identity changed.", status: 409) }
                stage = "local_membership"
                _ = try await MirrorLayoutUpdater(local: local).members(workspace: record.localWorkspaceID, owned: Set(record.projections.compactMap(\.localSurfaceID)))
                stage = "remote_workspace"
                let latest = try await remote.workspace(record.snapshot.id)
                guard latest.id.lowercased() == record.snapshot.id.lowercased() else { throw BridgeError("invalid_response", "Checkpoint returned another workspace.") }
                for view in record.projections {
                    stage = "remote_replay"
                    let replay = try await remote.replay(workspaceID: view.workspaceID, surfaceID: view.surfaceID)
                    try validate(replay, workspaceID: view.workspaceID, surfaceID: view.surfaceID)
                    guard replay.runtimeEpoch == view.runtimeEpoch else { throw BridgeError("stale_binding", "Checkpoint producer changed.", status: 409) }
                    stage = "local_input_state"
                    let state = try await local.request("surface.input_state", params: ["workspace_id": .string(record.localWorkspaceID), "surface_id": .string(view.localSurfaceID!)])
                    guard state["workspace_id"].string == record.localWorkspaceID, state["surface_id"].string == view.localSurfaceID,
                          state["terminal"].bool == true, state["agent"].bool == false else { throw BridgeError("mirror_local_changed", "The checkpoint's local terminal was repurposed.", status: 409) }
                }
                stage = "final_local_membership"
                _ = try await MirrorLayoutUpdater(local: local).members(workspace: record.localWorkspaceID, owned: Set(record.projections.compactMap(\.localSurfaceID)))
                try Task.checkCancellation()
                for view in record.projections { projections[view.id] = view; sources[view.id] = remote }
                workspaces[key] = record.localWorkspaceID
                attachments[key] = Attachment(host: host, remote: remote, localWorkspace: record.localWorkspaceID, snapshot: record.snapshot)
                restorationFailures[key] = nil
                startWatching(key); restored += 1
            } catch is CancellationError { throw CancellationError() }
            catch {
                // Retain only stable diagnostics, never peer content or credentials.
                restorationFailures[key] = .init(hostID: record.host.id, workspaceID: record.snapshot.id,
                    localWorkspaceID: record.localWorkspaceID, state: "paused",
                    errorCode: (error as? BridgeError)?.code ?? "connection_failed", detail: "restore." + stage)
            }
        }
        return restored
    }
    private func pause(key: String, code: String, detail: String? = nil) {
        guard attachments[key] != nil else { return }
        transportFailures[key] = nil; syncErrors[key] = code; syncDetails[key] = detail; watchers.removeValue(forKey: key)?.cancel()
    }
    private func startWatching(_ key: String) {
        guard let attachment = attachments[key] else { return }
        let ticks = topologyTicks()
        watchers[key] = Task { [weak self] in
            for await _ in ticks {
                guard !Task.isCancelled, let self else { return }
                do { _ = try await self.reconcile(hostID: attachment.host.id, workspaceID: attachment.snapshot.id) }
                catch let error as BridgeError where ["mirror_busy", "mirror_remote_unavailable"].contains(error.code) { continue }
                catch { return }
            }
        }
    }

    private func populate(_ layout: MirrorLayoutPlan, localWorkspace: String, localSurface: String, tickets: [String: UUID]) async throws {
        switch layout {
        case .pane(let terminals):
            if let ticket = tickets[terminals[0].id] {
                projections[ticket]?.localWorkspaceID = localWorkspace; projections[ticket]?.localSurfaceID = localSurface
            }
            try await rename(terminals[0], localWorkspace: localWorkspace, localSurface: localSurface)
            let listed = try await local.request("surface.list", params: ["workspace_id": .string(localWorkspace)])
            guard let pane = (listed["surfaces"].array ?? []).first(where: { $0["id"].string == localSurface })?["pane_id"].string else {
                throw BridgeError("invalid_response", "The newly created mirror pane is unavailable.")
            }
            for (index, terminal) in terminals.enumerated().dropFirst() {
                let ticket = tickets[terminal.id]!
                let created = try await local.request("surface.create", params: ["workspace_id": .string(localWorkspace), "pane_id": .string(pane),
                    "type": .string("terminal"), "initial_command": .string(command(ticket)), "focus": .bool(false)])
                guard let surface = created["surface_id"].string, UUID(uuidString: surface) != nil else { throw BridgeError("invalid_response", "cmux did not identify the new terminal view.") }
                projections[ticket]?.localWorkspaceID = localWorkspace; projections[ticket]?.localSurfaceID = surface
                // cmux inserts after the selected tab when focus=false; make
                // the source's order explicit instead of assuming append.
                _ = try await local.request("surface.reorder", params: ["workspace_id": .string(localWorkspace), "surface_id": .string(surface),
                    "index": .number(Double(index)), "focus": .bool(false)])
                try await rename(terminal, localWorkspace: localWorkspace, localSurface: surface)
            }
        case .split(let direction, let first, let second):
            let ticket = tickets[second.firstSurface.id]!
            let created = try await local.request("surface.split", params: ["workspace_id": .string(localWorkspace), "surface_id": .string(localSurface),
                "direction": .string(direction), "initial_command": .string(command(ticket)), "focus": .bool(false)])
            guard let secondSurface = created["surface_id"].string, UUID(uuidString: secondSurface) != nil else { throw BridgeError("invalid_response", "cmux did not identify the new split view.") }
            try await populate(first, localWorkspace: localWorkspace, localSurface: localSurface, tickets: tickets)
            try await populate(second, localWorkspace: localWorkspace, localSurface: secondSurface, tickets: tickets)
        }
    }
    private func rename(_ terminal: MirrorSurface, localWorkspace: String, localSurface: String) async throws {
        guard !terminal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        _ = try await local.request("surface.action", params: ["workspace_id": .string(localWorkspace), "surface_id": .string(localSurface),
            "action": .string("rename"), "title": .string(terminal.title), "focus": .bool(false)])
    }
    private func command(_ id: UUID) -> String {
        // Only local trusted paths and an opaque ID enter this fixed startup command.
        quote(executable.path) + " mirror view --state " + quote(stateDirectory.path) + " --projection " + quote(id.uuidString)
    }
    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func validate(_ snapshot: MirrorTerminalSnapshot, workspaceID: String, surfaceID: String) throws {
        let cellBytes = try snapshot.renderGrid.map { try JSONEncoder().encode($0).count } ?? 0
        guard snapshot.workspaceID.lowercased() == workspaceID.lowercased(), snapshot.surfaceID.lowercased() == surfaceID.lowercased(),
              !snapshot.runtimeEpoch.isEmpty, snapshot.bytes.count + (snapshot.repaintBytes?.count ?? 0) + cellBytes <= 4_194_304,
              snapshot.presentationKey == nil || snapshot.presentationKey!.utf8.count <= 128 else { throw BridgeError("invalid_response", "A replay named another terminal or exceeded its limit.") }
    }
}
