import Foundation
import CmuxRemoteCore

/// Controls the LAN listener independently from resident owner and mirror services.
public actor ManagedSharingService {
    private let state: BridgeState
    private let authority: ConnectionAuthority
    private let router: BridgeRouter
    private let listen: String
    private let advertise: Bool
    private var port: Int
    private var phase = "stopped"
    private var failure: String?
    private var task: Task<Void, any Error>?
    private var generation: UUID?
    private var advertisement: BonjourAdvertisement?
    public init(state: BridgeState, authority: ConnectionAuthority, router: BridgeRouter, listen: String = "0.0.0.0", port: Int = 7740, advertise: Bool = true) {
        self.state = state; self.authority = authority; self.router = router
        self.listen = listen; self.port = port; self.advertise = advertise
    }
    public func status() -> JSONValue {
        .object(["state": .string(phase), "port": .number(Double(port)),
                 "address": LANAddressResolver().address().map(JSONValue.string) ?? .null,
                 "host_id": .string(authority.host.id), "name": .string(authority.host.name),
                 "certificate": .string(authority.host.certificateSHA256),
                 "error_code": failure.map(JSONValue.string) ?? .null])
    }
    public func start(port requested: Int? = nil) async throws -> JSONValue {
        guard phase == "stopped" else {
            if phase == "running", requested == nil || requested == port { return status() }
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
            if advertise {
                do { advertisement = try BonjourAdvertisement(host: authority.host, port: bound) }
                catch { failure = "discovery_failed" }
            }
            Task { [weak self] in _ = try? await running.value; await self?.finished(id: id) }
            return status()
        } catch {
            if generation == id { task = nil; generation = nil; phase = "stopped"; failure = "sharing_start_failed" }
            running.cancel(); _ = try? await running.value
            throw BridgeError("sharing_start_failed", "The sharing listener could not start. Check the port and local credentials.", status: 503)
        }
    }
    public func stop() async -> JSONValue {
        guard phase != "stopping" else { return status() }
        phase = "stopping"; generation = nil; advertisement = nil
        await authority.closeEnrollment()
        let running = task; task = nil; running?.cancel(); _ = try? await running?.value
        phase = "stopped"; failure = nil
        return status()
    }
    private func finished(id: UUID) {
        guard generation == id else { return }
        generation = nil; task = nil; advertisement = nil; phase = "stopped"; failure = "sharing_stopped"
    }
}
