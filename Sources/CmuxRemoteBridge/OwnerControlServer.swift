import Foundation
import NIOCore
import NIOPosix
import CmuxRemoteCore

/// Owner-only local administration, isolated from the HTTPS listener.
public struct OwnerControlServer: Sendable {
    public init() {}
    public func run(path: String, authority: ConnectionAuthority, service: SessionService, onListening: (@Sendable () -> Void)? = nil) async throws {
        guard !FileManager.default.fileExists(atPath: path) else { throw BridgeError("owner_socket_exists", "The owner socket already exists. Check for another running Bridge.") }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let router = OwnerControlRouter(authority: authority, service: service)
            let server = try await ServerBootstrap(group: group).childChannelInitializer { channel in
                channel.pipeline.addHandler(OwnerControlHandler(router: router))
            }.bind(unixDomainSocketPath: path).get()
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            onListening?()
            try await withTaskCancellationHandler { try await server.closeFuture.get() } onCancel: { server.close(promise: nil) }
            try await group.shutdownGracefully()
        } catch { try? await group.shutdownGracefully(); throw error }
    }
}
