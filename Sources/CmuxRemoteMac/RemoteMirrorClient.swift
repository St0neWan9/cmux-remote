import Foundation
import CmuxRemoteClient
import CmuxRemoteCore

/// Typed remote operations used by the local projection owner.
public protocol MirrorRemoteControlling: Sendable {
    func workspace(_ id: String) async throws -> MirrorWorkspaceSnapshot
    func replay(workspaceID: String, surfaceID: String) async throws -> MirrorTerminalSnapshot
    func input(workspaceID: String, surfaceID: String, request: MirrorInputRequest) async throws -> MutationReceipt
}

/// Reuses signed enrollment transport; never sends a generic remote cmux RPC.
public final class RemoteMirrorClient: MirrorRemoteControlling, Sendable {
    private let client: RemoteClient
    public init(connection: AuthorizedConnection) throws { client = try RemoteClient(connection: connection) }
    deinit { client.close() }
    public func workspace(_ id: String) async throws -> MirrorWorkspaceSnapshot {
        try await read("/v1/workspaces/\(id)/mirror", as: MirrorWorkspaceSnapshot.self)
    }
    public func replay(workspaceID: String, surfaceID: String) async throws -> MirrorTerminalSnapshot {
        try await read("/v1/workspaces/\(workspaceID)/terminals/\(surfaceID)/replay", as: MirrorTerminalSnapshot.self)
    }
    public func input(workspaceID: String, surfaceID: String, request: MirrorInputRequest) async throws -> MutationReceipt {
        try await client.post("/v1/workspaces/\(workspaceID)/terminals/\(surfaceID)/input", body: request, as: MutationReceipt.self)
    }
    private func read<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        let client = client
        do {
            do { return try await MirrorReadDeadline().run { try await client.get(path, as: type) } }
            catch let error as BridgeError where error.code == "invalid_proof" {
                // A peer restart can invalidate an epoch between identity and
                // resource reads. Re-authenticate this GET once, using the same
                // identity/pin. Permission and signature failures never retry.
                return try await MirrorReadDeadline().run { try await client.get(path, as: type) }
            }
        } catch { throw MirrorReadFailure().normalize(error) }
    }
}
