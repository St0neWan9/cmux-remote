import Foundation
import Network
import CmuxRemoteCore
import CmuxRemoteClient
import CmuxRemoteBridge

/// Reads bounded Mac discovery snapshots through the same private owner channel as enrollment.
@MainActor public final class OwnerBridgeDiscovery: MacBridgeDiscovering {
    private let owner: any CmuxControlling
    private var task: Task<Void, Never>?
    public init(owner: any CmuxControlling) { self.owner = owner }
    public func start() -> AsyncStream<[DiscoveredBridge]> {
        stop()
        let stream = AsyncStream<[DiscoveredBridge]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let owner = owner
        let task = Task {
            do {
                _ = try await owner.request("mac.discovery.refresh", params: [:])
                while !Task.isCancelled {
                    let value = try await owner.request("mac.discovery.list", params: [:])
                    let hints = try JSONDecoder().decode([MacDiscoveredHost].self, from: JSONEncoder().encode(value))
                    guard hints.count <= 64 else { throw BridgeError("invalid_response", "Too many discovery hints.") }
                    let devices = try hints.map { hint in
                        try IdentityCryptography().validate(hint.host)
                        guard ["_cmux-remote._tcp", "_cmux-remote._tcp."].contains(hint.serviceType), hint.serviceDomain == "local.",
                              !hint.serviceName.isEmpty, hint.serviceName.utf8.count <= 255 else {
                            throw BridgeError("invalid_response", "Invalid discovery hint.")
                        }
                        return DiscoveredBridge(host: hint.host, service: .service(name: hint.serviceName, type: hint.serviceType, domain: hint.serviceDomain, interface: nil))
                    }
                    try Task.checkCancellation(); stream.continuation.yield(devices)
                    // The owner socket is request/response; this is the intended bounded metadata refresh cadence.
                    try await Task.sleep(for: .seconds(2))
                }
            } catch {}
            stream.continuation.finish()
        }
        stream.continuation.onTermination = { _ in task.cancel() }
        self.task = task; return stream.stream
    }
    public func stop() { task?.cancel(); task = nil }
    public func resolve(_ discovered: DiscoveredBridge) async throws -> BridgeEndpoint {
        let value = try await owner.request("mac.discovery.resolve", params: ["host_id": .string(discovered.host.id)])
        let endpoint = try JSONDecoder().decode(BridgeEndpoint.self, from: JSONEncoder().encode(value))
        try endpoint.validate(); return endpoint
    }
}
