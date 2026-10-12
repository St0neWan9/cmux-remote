import Foundation
import CmuxRemoteCore
import CmuxRemoteClient

/// Resident owner-side connection and mirror operations shared by CLI and Companion UI.
public actor MacCompanionService: LocalMacControlling {
    private let repository: MacConnectionRepository
    private let mirrors: WorkspaceMirrorCoordinator
    private let discovery: ResidentMacDiscovery?
    private let catalog: NativeWorkspaceCatalog?
    private var selectionTask: Task<Void, Never>?
    private var inventoryTask: Task<Void, Never>?
    private var forgetting = Set<String>()
    private var pending: EnrollmentClient?
    public init(repository: MacConnectionRepository, mirrors: WorkspaceMirrorCoordinator, discovery: ResidentMacDiscovery? = nil, catalog: NativeWorkspaceCatalog? = nil) {
        self.repository = repository; self.mirrors = mirrors; self.discovery = discovery; self.catalog = catalog
    }
    /// Starts independent bounded metadata and local-selection watchers.
    public func start() {
        guard let catalog, selectionTask == nil else { return }
        selectionTask = Task {
            for await _ in MirrorTopologyTicker().start() {
                guard !Task.isCancelled else { return }; try? await catalog.refreshSelection()
            }
        }
        inventoryTask = Task { [weak self] in
            await self?.refreshCatalogs()
            for await _ in MirrorTopologyTicker().start() {
                guard !Task.isCancelled, let self else { return }; await self.refreshCatalogs()
            }
        }
    }
    public func stop() { selectionTask?.cancel(); inventoryTask?.cancel(); selectionTask = nil; inventoryTask = nil }
    private func refreshCatalogs() async {
        guard let connections = try? await repository.connections() else { return }
        for connection in connections {
            guard !Task.isCancelled else { return }
            _ = try? await scopedWorkspaces(connection)
        }
    }
    private func scopedWorkspaces(_ connection: AuthorizedConnection) async throws -> JSONValue {
        guard !forgetting.contains(connection.host.id) else { throw BridgeError("mirror_busy", "This connection is being removed.", status: 409) }
        let client = try RemoteClient(connection: connection); defer { client.close() }
        let value = try await client.get("/v1/workspaces", as: JSONValue.self)
        guard !forgetting.contains(connection.host.id) else { throw BridgeError("mirror_busy", "This connection is being removed.", status: 409) }
        if let catalog, connection.grant.value.scope.capabilities.contains(.terminalRead) {
            guard let rows = value["workspaces"].array else { throw BridgeError("invalid_response", "Invalid scoped workspace listing.") }
            let summaries = rows.compactMap(WorkspaceSummary.init(json:))
            guard summaries.count == rows.count else { throw BridgeError("invalid_response", "Invalid workspace metadata.") }
            try await catalog.sync(host: connection.host, workspaces: summaries)
        }
        return value
    }
    public func request(_ method: String, params: JSONValue) async throws -> JSONValue {
        switch method {
        case "mac.discovery.refresh":
            guard let discovery else { throw BridgeError("discovery_failed", "Update the local Bridge to enable Mac discovery.") }
            await discovery.refresh(); return .object(["refreshed": .bool(true)])
        case "mac.discovery.list":
            guard let discovery else { throw BridgeError("discovery_failed", "Update the local Bridge to enable Mac discovery.") }
            return try json(await discovery.snapshot())
        case "mac.discovery.resolve":
            guard let discovery else { throw BridgeError("discovery_failed", "Update the local Bridge to enable Mac discovery.") }
            return try json(await discovery.resolve(hostID: hostID(params)))
        case "mac.connections":
            return .array(try await repository.connections().map { value in
                .object(["id": .string(value.host.id), "name": .string(value.host.name), "host": try json(value.host),
                    "endpoint": try json(value.endpoint), "scope": try json(value.grant.value.scope)])
            })
        case "mac.enrollment.start":
            guard params["trust_confirmed"].bool == true else { throw BridgeError("trust_required", "Confirm the host identity before requesting enrollment.") }
            let host = try decode(HostIdentity.self, params["host"]); let endpoint = try decode(BridgeEndpoint.self, params["endpoint"])
            if let saved = try? await repository.connection(hostID: host.id) {
                let moved = try saved.relocated(to: endpoint, advertisedHost: host)
                let client = try RemoteClient(connection: moved); defer { client.close() }
                _ = try await client.get("/v1/status", as: JSONValue.self)
                try await repository.save(moved); _ = try await scopedWorkspaces(moved); return .object(["state": .string("connected")])
            }
            pending?.close(); pending = nil
            let bootstrap = try await EnrollmentBootstrapClient().fetch(endpoint: endpoint, trustedHost: host)
            let client = try EnrollmentClient(bootstrap: bootstrap, privateKey: await repository.privateKey(), name: params["name"].string ?? "Mac Companion", kind: "mac", capabilities: [.workspaceRead, .terminalRead, .terminalInput], endpoint: endpoint)
            pending = client
            return try json(await client.submit())
        case "mac.enrollment.status":
            guard let client = pending else { throw BridgeError("enrollment_pending", "No pending enrollment request exists.") }
            let status = try await client.status()
            if status.state == "approved" {
                let connection = try client.connection(from: status)
                try await repository.save(connection); pending = nil; client.close(); _ = try await scopedWorkspaces(connection)
            }
            return try json(status)
        case "mac.enrollment.cancel":
            if let pending { try await pending.cancel(); pending.close() }; pending = nil
            return .object(["cancelled": .bool(true)])
        case "mac.workspaces":
            let connection = try await repository.connection(hostID: hostID(params))
            return try await scopedWorkspaces(connection)
        case "mac.forget":
            let id = try hostID(params)
            guard forgetting.insert(id).inserted else { throw BridgeError("mirror_busy", "This connection is being removed.", status: 409) }
            defer { forgetting.remove(id) }
            try await catalog?.forget(hostID: id); try await mirrors.detach(hostID: id); try await repository.remove(hostID: id)
            return .object(["removed": .bool(true)])
        case "mirror.workspace":
            let connection = try await repository.connection(hostID: hostID(params))
            guard let workspace = params["workspace_id"].string,
                  connection.grant.value.scope.workspaces.contains(workspace.lowercased()),
                  connection.grant.value.scope.capabilities.contains(.terminalRead) else { throw BridgeError("scope_denied", "Approve terminal viewing for this workspace first.", status: 403) }
            if let catalog {
                _ = try await scopedWorkspaces(connection)
                return try await catalog.select(hostID: connection.host.id, workspaceID: workspace)
            }
            return try await mirrors.create(host: connection.host, workspaceID: workspace, remote: RemoteMirrorClient(connection: connection))
        case "mirror.catalog.list":
            guard let catalog else { throw BridgeError("not_found", "Native catalog is unavailable.") }
            return try json(await catalog.rows())
        case "mirror.catalog.wait":
            guard let catalog else { throw BridgeError("not_found", "Native catalog is unavailable.") }
            let ready = try await catalog.wait(entryID(params))
            return .object(["ready": .bool(ready)])
        case "mirror.catalog.open":
            guard let catalog, let ws = params["local_workspace_id"].string, let surface = params["local_surface_id"].string else { throw BridgeError("invalid_input", "Use the native pending row binding.") }
            let projection = try await catalog.open(entryID(params), workspaceID: ws, surfaceID: surface)
            return .object(["projection_id": .string(projection.uuidString)])
        case "mirror.list": return try json(await mirrors.list())
        case "mirror.status": return try json(await mirrors.syncStatus())
        case "mirror.sync":
            guard let workspace = params["workspace_id"].string, UUID(uuidString: workspace) != nil else { throw BridgeError("invalid_input", "Choose an exact mirrored workspace.") }
            return try await mirrors.reconcile(hostID: hostID(params), workspaceID: workspace, force: true)
        case "mirror.replay": return try json(await mirrors.replay(projectionID(params)))
        case "mirror.input":
            let input = try decode(MirrorInputRequest.self, params["input"])
            return try json(await mirrors.input(projectionID(params), request: input))
        case "mirror.detach": try await mirrors.detach(projectionID(params), reason: params["reason"].string); return .object(["detached": .bool(true)])
        default: throw BridgeError("not_found", "Unknown Companion operation.", status: 404)
        }
    }
    private func entryID(_ params: JSONValue) throws -> UUID {
        guard let raw = params["entry_id"].string, let id = UUID(uuidString: raw) else { throw BridgeError("invalid_input", "Choose an exact native inventory entry.") }; return id
    }
    private func hostID(_ params: JSONValue) throws -> String {
        guard let id = params["host_id"].string, id.count == 64, id.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw BridgeError("invalid_input", "Choose an exact saved host identity.") }; return id
    }
    private func projectionID(_ params: JSONValue) throws -> UUID {
        guard let raw = params["projection_id"].string, let id = UUID(uuidString: raw) else { throw BridgeError("invalid_input", "Choose an exact local projection.") }; return id
    }
    private func json<T: Encodable>(_ value: T) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) }
    private func decode<T: Decodable>(_ type: T.Type, _ value: JSONValue) throws -> T { try JSONDecoder().decode(type, from: JSONEncoder().encode(value)) }
}
