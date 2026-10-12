import Foundation
import CmuxRemoteCore

/// Atomic owner-only storage for completed attachments; partial mutations are excluded.
public actor MirrorCheckpointRepository {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load() throws -> [MirrorCheckpoint] {
        let path = directory.appendingPathComponent("mirror-checkpoints.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        let bytes = try Data(contentsOf: path)
        guard bytes.count <= 4_194_304 else { throw BridgeError("invalid_state", "Mirror checkpoint exceeds its limit.") }
        let records = try JSONDecoder().decode([MirrorCheckpoint].self, from: bytes)
        try validate(records); return records
    }
    public func save(_ records: [MirrorCheckpoint]) throws {
        try validate(records)
        let bytes = try JSONEncoder().encode(records)
        guard bytes.count <= 4_194_304 else { throw BridgeError("mirror_capacity", "Mirror checkpoint exceeds its limit.", status: 429) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("mirror-checkpoints.json")
        try bytes.write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
    private func validate(_ records: [MirrorCheckpoint]) throws {
        guard records.count <= 64,
              records.reduce(0, { $0 + $1.projections.count }) <= 4096,
              Set(records.map { $0.host.id + ":" + $0.snapshot.id.lowercased() }).count == records.count,
              Set(records.map(\.localWorkspaceID)).count == records.count else { throw BridgeError("invalid_state", "Invalid mirror checkpoint catalog.") }
        var ids = Set<UUID>(), surfaces = Set<String>()
        for record in records {
            try IdentityCryptography().validate(record.host)
            _ = try MirrorLayoutPlan.make(record.snapshot)
            guard UUID(uuidString: record.localWorkspaceID) != nil, record.projections.count == record.snapshot.surfaces.count,
                  Set(record.projections.map(\.surfaceID)) == Set(record.snapshot.surfaces.map(\.id)) else { throw BridgeError("invalid_state", "Invalid checkpoint workspace binding.") }
            for view in record.projections {
                guard ids.insert(view.id).inserted, view.hostID == record.host.id,
                      view.workspaceID.lowercased() == record.snapshot.id.lowercased(), view.localWorkspaceID == record.localWorkspaceID,
                      let surface = view.localSurfaceID, UUID(uuidString: surface) != nil, surfaces.insert(surface).inserted,
                      !view.runtimeEpoch.isEmpty, view.runtimeEpoch.utf8.count <= 4096 else { throw BridgeError("invalid_state", "Invalid checkpoint producer binding.") }
            }
        }
    }
}
