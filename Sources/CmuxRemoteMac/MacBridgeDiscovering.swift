import CmuxRemoteClient
import CmuxRemoteCore

/// Injectable LAN discovery seam; discovering an identity does not authorize it.
@MainActor public protocol MacBridgeDiscovering: Sendable {
    func start() -> AsyncStream<[DiscoveredBridge]>
    func stop()
    func resolve(_ discovered: DiscoveredBridge) async throws -> BridgeEndpoint
}

extension BridgeDiscovery: MacBridgeDiscovering {}
