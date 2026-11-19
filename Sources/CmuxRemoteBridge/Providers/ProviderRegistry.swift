import Foundation
import CmuxRemoteCore

/// Owns the provider connections and keeps one failing provider from taking
/// down the others. Registration is owner-side only; devices never reach it.
public actor ProviderRegistry {
    private var providers: [String: any TerminalProvider] = [:]
    private var order: [String] = []

    public init() {}

    public func register(_ provider: any TerminalProvider) async throws {
        let descriptor = await provider.descriptor
        guard UUID(uuidString: descriptor.id) != nil, descriptor.name.utf8.count <= 256,
              descriptor.hostName.utf8.count <= 256, descriptor.capabilities.count <= ProviderCapability.allCases.count else {
            throw BridgeError("invalid_provider", "The terminal provider identity is invalid.", status: 502)
        }
        guard providers[descriptor.id] == nil, providers.count < 16 else {
            throw BridgeError("invalid_provider", "The terminal provider is already registered or the limit is reached.", status: 409)
        }
        providers[descriptor.id] = provider
        order.append(descriptor.id)
    }

    public func provider(id: String) -> (any TerminalProvider)? { providers[id] }

    public func all() -> [any TerminalProvider] { order.compactMap { providers[$0] } }

    /// Every registered provider, including one whose connection is currently
    /// unavailable. The descriptor carries the stable error state.
    public func descriptors() async -> [ProviderDescriptor] {
        var result: [ProviderDescriptor] = []
        for id in order {
            guard let provider = providers[id] else { continue }
            result.append(await provider.descriptor)
        }
        return result
    }
}
