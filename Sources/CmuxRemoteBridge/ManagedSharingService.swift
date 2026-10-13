import Foundation
import CmuxRemoteCore

/// Controls the LAN listener independently from resident owner and mirror services.
public actor ManagedSharingService {
    private let state: BridgeState
    private let authority: ConnectionAuthority
    private let router: BridgeRouter
    private let listen: String
    private let advertise: Bool
    private var relay: CloudRelayService?
    private var relayKeyFile: String?
    private var port: Int
    private var phase = "stopped"
    private var failure: String?
    private var task: Task<Void, any Error>?
    private var generation: UUID?
    private var advertisement: BonjourAdvertisement?
    private let workspaces: @Sendable () async throws -> [String]
    /// Set for the menu bar resident; owner start/stop choices are remembered across restarts.
    private let preference: SharingPreferenceRepository?
    public init(state: BridgeState, authority: ConnectionAuthority, router: BridgeRouter, listen: String = "0.0.0.0", port: Int = 7740, advertise: Bool = true, relay: CloudRelayService? = nil, relayKeyFile: String? = nil, workspaces: @escaping @Sendable () async throws -> [String] = { [] }, remembersChoice: Bool = false) {
        self.workspaces = workspaces; preference = remembersChoice ? SharingPreferenceRepository(directory: state.directory) : nil; self.state = state; self.authority = authority; self.router = router
        self.relayKeyFile = relayKeyFile; self.relay = relay; self.listen = listen; self.port = port; self.advertise = advertise
    }
    public func status() async -> JSONValue {
        var relayState = await relay?.status() ?? .null
        if var fields = relayState.object { fields["key_file"] = relayKeyFile.map(JSONValue.string) ?? .null; relayState = .object(fields) }
        return .object(["state": .string(phase), "port": .number(Double(port)),
                 "address": LANAddressResolver().address().map(JSONValue.string) ?? .null,
                 "host_id": .string(authority.host.id), "name": .string(authority.host.name),
                 "certificate": .string(authority.host.certificateSHA256),
                 "relay": relayState, "error_code": failure.map(JSONValue.string) ?? .null])
    }
    /// Owner-only configuration; changing it never starts sharing or expands client grants.
    public func configureRelay(origin: String?, keyFile: String?) async throws -> JSONValue {
        guard phase == "stopped" else { throw BridgeError("sharing_busy", "Stop sharing before changing the relay.", status: 409) }
        let repository = RelayConfigurationRepository(directory: state.directory)
        if let origin, !origin.isEmpty {
            guard let keyFile else { throw BridgeError("relay_configuration", "Choose a private relay registration key file.") }
            do {
                let value = try repository.save(origin: origin, keyFile: keyFile)
                let service = try CloudRelayService(origin: value.origin, secret: repository.secret(value), router: router, authority: authority)
                try await authority.configureRelay(origin: value.origin)
                relay = service; relayKeyFile = value.keyFile
            } catch { throw BridgeError("relay_configuration", "Check the HTTPS origin and private registration key file.") }
        } else {
            try repository.remove(); try await authority.configureRelay(origin: nil); relay = nil; relayKeyFile = nil
        }
        await authority.closeEnrollment()
        return await status()
    }
    /// Reopens sharing when the owner last left it on; a failure is reported in status and the resident keeps running.
    public func restore() async {
        guard let saved = preference?.load(), saved.enabled, phase == "stopped" else { return }
        _ = try? await start(port: saved.port, remember: false)
    }
    /// An owner request; on success the choice is remembered so a restarted resident restores it.
    public func start(port requested: Int? = nil) async throws -> JSONValue { try await start(port: requested, remember: true) }
    private func start(port requested: Int?, remember: Bool) async throws -> JSONValue {
        guard phase == "stopped" else {
            if phase == "running", requested == nil || requested == port { return await status() }
            throw BridgeError("sharing_busy", "Stop sharing before changing its listener.", status: 409)
        }
        let chosen = requested ?? port
        guard (chosen == 0 && requested == nil) || (1...65535).contains(chosen) else { throw BridgeError("invalid_endpoint", "Choose a port from 1 to 65535.") }
        port = chosen; phase = "starting"; failure = nil
        let id = UUID(); generation = id
        let ready = AsyncThrowingStream<Int, any Error>.makeStream()
        let state = state; let router = router; let listen = listen
        let running = Task {
            do { try await HTTPServer().run(host: listen, port: chosen, certificate: state.certificate, key: state.key, router: router, onListening: { ready.continuation.yield($0); ready.continuation.finish() }) }
            catch { ready.continuation.finish(throwing: error); throw error }
        }
        task = running
        do {
            var iterator = ready.stream.makeAsyncIterator()
            guard let bound = try await iterator.next(), generation == id, phase == "starting" else { throw CancellationError() }
            port = bound; phase = "running"
            if let relay {
                let authority = authority, workspaces = workspaces
                // Listed while online: the entry carries this Mac's current workspaces; the owner narrows at approval.
                await relay.setListing {
                    let current = try await workspaces()
                    guard !current.isEmpty else { return nil }
                    return try await authority.openDirectory(endpoint: BridgeEndpoint(host: LANAddressResolver().address() ?? "localhost", port: bound), workspaces: current)
                }
                try await relay.start()
            }
            if advertise {
                do { advertisement = try BonjourAdvertisement(host: authority.host, port: bound) }
                catch { failure = "discovery_failed" }
            }
            Task { [weak self] in _ = try? await running.value; await self?.finished(id: id) }
            if remember { try? preference?.save(.init(enabled: true, port: bound)) }
            return await status()
        } catch {
            if generation == id { task = nil; generation = nil; phase = "stopped"; failure = "sharing_start_failed" }
            running.cancel(); _ = try? await running.value
            throw BridgeError("sharing_start_failed", "The sharing listener could not start. Check the port and local credentials.", status: 503)
        }
    }
    public func stop() async -> JSONValue {
        guard phase != "stopping" else { return await status() }
        // Only an explicit stop records "off"; a listener that ends on its own is restored on the next start.
        try? preference?.save(.init(enabled: false, port: port))
        phase = "stopping"; generation = nil; advertisement = nil
        await authority.closeEnrollment()
        await relay?.stop()
        let running = task; task = nil; running?.cancel(); _ = try? await running?.value
        phase = "stopped"; failure = nil
        return await status()
    }
    private func finished(id: UUID) async {
        guard generation == id else { return }
        generation = nil; task = nil; advertisement = nil; phase = "stopped"; failure = "sharing_stopped"
        await relay?.stop()
    }
}
