import Foundation
import Network
import CmuxRemoteCore
import CmuxRemoteClient

/// Runs Mac Bonjour discovery in the resident Bridge and resolves only its observed peers.
public actor ResidentMacDiscovery {
    private let discovery: any MacBridgeDiscovering
    private let excludedHostID: String?
    private let enabled: Bool
    private var devices: [String: DiscoveredBridge] = [:]
    private var observer: Task<Void, Never>?
    private var observationID: UUID?
    public init(discovery: any MacBridgeDiscovering, excludingHostID: String? = nil, enabled: Bool = true) {
        self.discovery = discovery; self.excludedHostID = excludingHostID; self.enabled = enabled
    }
    deinit { observer?.cancel() }
    public func start() async {
        guard enabled, observationID == nil else { return }
        let id = UUID(); observationID = id
        let stream = await discovery.start()
        guard observationID == id else { return }
        observer = Task { [weak self] in
            for await values in stream {
                guard !Task.isCancelled else { return }
                await self?.accept(values, observationID: id)
            }
        }
    }
    public func stop() async { observationID = nil; observer?.cancel(); observer = nil; devices = [:]; await discovery.stop() }
    public func refresh() async { await stop(); await start() }
    public func snapshot() throws -> [MacDiscoveredHost] {
        try devices.values.sorted { $0.host.id < $1.host.id }.compactMap { device in
            guard case .service(let name, let type, let domain, _) = device.service else { return nil }
            try IdentityCryptography().validate(device.host)
            return MacDiscoveredHost(host: device.host, serviceName: name, serviceType: type, serviceDomain: domain)
        }
    }
    public func resolve(hostID: String) async throws -> BridgeEndpoint {
        guard let device = devices[hostID] else { throw BridgeError("discovery_failed", "Choose a currently discovered host.") }
        return try await discovery.resolve(device)
    }
    private func accept(_ values: [DiscoveredBridge], observationID id: UUID) {
        guard observationID == id else { return }
        var next: [String: DiscoveredBridge] = [:]
        for device in values.prefix(64) where device.host.id != excludedHostID {
            guard (try? IdentityCryptography().validate(device.host)) != nil else { continue }
            next[device.host.id] = device
        }
        devices = next
    }
}
