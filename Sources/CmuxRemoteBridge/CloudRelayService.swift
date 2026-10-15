import Foundation
import os
import CmuxRemoteCore

/// Maintains outbound relay routing while all Agent and device authority stays on Bridge.
public actor CloudRelayService {
    private let origin: RelayOrigin
    private let secret: String
    private let router: BridgeRouter
    private let authority: ConnectionAuthority
    private let onConnected: (@Sendable () -> Void)?
    private let dial: @Sendable (URL, [String: String]) -> any CloudRelayConnecting
    private let liveness: CloudRelayLiveness
    private var running: Task<Void, Never>?
    private var registry: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var publisher: Task<Void, Never>?
    /// Supplies this host's signed directory entry; nil keeps the host out of the directory.
    private var listing: (@Sendable () async throws -> SignedValue<EnrollmentBootstrap>?)?
    private var failure: String?
    private var socket: (any CloudRelayConnecting)?
    private var writer: LinkPacketWriter?
    private var sessions: [String: LinkServerSession] = [:]
    private var phase = "stopped"
    private var generation: UUID?
    public init(origin: String, secret: String, router: BridgeRouter, authority: ConnectionAuthority, dial: @escaping @Sendable (URL, [String: String]) -> any CloudRelayConnecting = { CloudRelaySocket(url: $0, headers: $1) }, liveness: CloudRelayLiveness = CloudRelayLiveness(), onConnected: (@Sendable () -> Void)? = nil) throws {
        self.onConnected = onConnected; self.origin = try RelayOrigin(origin); self.secret = secret; self.router = router; self.authority = authority; self.dial = dial; self.liveness = liveness
        guard secret.utf8.count >= 32, secret.utf8.count <= 256, !secret.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw BridgeError("invalid_identity", "Invalid private relay registration key.") }
    }
    /// Set before `start`; the entry is republished well before each window's ten-minute expiry.
    public func setListing(_ provider: (@Sendable () async throws -> SignedValue<EnrollmentBootstrap>?)?) { listing = provider }
    public func status() -> JSONValue { .object(["state": .string(phase), "origin": .string(origin.value), "error_code": failure.map(JSONValue.string) ?? .null]) }
    public func start() async throws {
        guard running == nil else { return }
        try await authority.configureRelay(origin: origin.value)
        Logger.relay.info("relay connecting origin=\(self.origin.value, privacy: .public)")
        let id = UUID(); generation = id; phase = "connecting"
        running = Task { [weak self] in await self?.run(id) }
    }
    public func stop() async {
        Logger.relay.info("relay stopped")
        generation = nil; phase = "stopped"; failure = nil
        let task = running; running = nil; task?.cancel()
        await disconnect(); _ = await task?.value
        // A transient reconnect keeps windows so listed requests stay approvable; stopping ends them.
        await authority.closeDirectory()
    }
    private func run(_ id: UUID) async {
        var attempt = 0
        while generation == id && !Task.isCancelled {
            do {
                let registration = try await authority.relayRegistration(origin: origin.value)
                let url = try origin.socketURL(hostID: authority.host.id, role: "bridge")
                let socket = dial(url, ["Authorization": "Bearer " + secret, "X-Cmux-Registration": try JSONEncoder().encode(registration).base64EncodedString()])
                self.socket = socket
                let writer = LinkPacketWriter(send: { try await socket.send($0) }, terminate: { socket.close() }, packetLimit: 3_000_000)
                self.writer = writer
                // Observing first means a revocation during the dial is not missed; its initial signal is this sync.
                let changes = try await authority.registryChanges()
                try await synchronizeRegistry()
                let ready = try JSONDecoder().decode(RelayEnvelope.self, from: await Self.within(liveness.readyDeadline, orClose: socket) { try await socket.receive() })
                guard ready.kind == "ready" else { throw BridgeError("invalid_response", "The relay did not acknowledge Bridge registration.") }
                phase = "connected"; failure = nil; attempt = 0; onConnected?()
                Logger.relay.info("relay connected attempt=\(attempt, privacy: .public)")
                let liveness = liveness
                heartbeat = Task {
                    // A dead path closes the socket, which ends the receive loop and redials.
                    do { while !Task.isCancelled { try await Task.sleep(for: liveness.pingInterval); try await Self.within(liveness.pongDeadline, orClose: socket) { try await socket.ping() } } }
                    catch { if !Task.isCancelled { socket.close() } }
                }
                if let listing {
                    publisher = Task { [weak self] in
                        while !Task.isCancelled {
                            // A listing failure (e.g. no workspaces yet) withdraws the entry instead of ending the relay.
                            let entry = try? await listing()
                            try? await self?.publish(entry)
                            do { try await Task.sleep(for: .seconds(240)) } catch { break }
                        }
                    }
                }
                registry = Task { [weak self] in
                    var initial = true
                    for await _ in changes {
                        guard !Task.isCancelled else { break }
                        if initial { initial = false; continue }
                        do { try await self?.synchronizeRegistry() } catch { socket.close(); break }
                    }
                }
                while !Task.isCancelled && generation == id {
                    let bytes = try await socket.receive()
                    try await accept(JSONDecoder().decode(RelayEnvelope.self, from: bytes))
                }
            } catch { failure = socket?.failureCode() ?? "connection_failed" }
            await disconnect()
            guard generation == id, !Task.isCancelled else { break }
            phase = "reconnecting"; attempt = min(attempt + 1, 5)
            Logger.relay.warning("relay reconnecting attempt=\(attempt, privacy: .public) error=\(self.failure ?? "unknown", privacy: .public)")
            do { try await Task.sleep(for: .seconds(1 << attempt)) } catch { break }
        }
    }
    private func publish(_ entry: SignedValue<EnrollmentBootstrap>?) async throws {
        if let entry { try await send(RelayEnvelope(kind: "directory", data: JSONEncoder().encode(entry))) }
        else { try await send(RelayEnvelope(kind: "withdraw")) }
    }
    private func synchronizeRegistry() async throws {
        let revoked = await authority.enrolledClients().filter(\.revoked).map(\.id)
        guard revoked.count <= 100 else { throw BridgeError("too_large", "The relay registry exceeds its bound.") }
        try await send(RelayEnvelope(kind: "registry", revoked: revoked))
        for (channel, session) in sessions where await session.isRevoked() { sessions[channel] = nil; await session.close() }
    }
    private func accept(_ envelope: RelayEnvelope) async throws {
        if envelope.kind == "ready" { return }
        guard let channel = envelope.channelID, UUID(uuidString: channel) != nil else { throw BridgeError("invalid_response", "Invalid relay channel.") }
        switch envelope.kind {
        case "open":
            guard let client = envelope.clientID, client.count == 64, client.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw BridgeError("invalid_response", "Invalid relay channel.") }
            // A full or duplicate channel is refused alone; other phones keep their links.
            guard sessions[channel] == nil, sessions.count < 20 else { try await send(RelayEnvelope(kind: "close", channelID: channel)); return }
            Logger.relay.debug("relay channel opened channel=\(channel.prefix(8), privacy: .public) client=\(client.prefix(8), privacy: .public)")
            let session = LinkServerSession(router: router, authority: authority, send: { [weak self] data in
                guard let self else { throw CancellationError() }; try await self.send(RelayEnvelope(kind: "data", channelID: channel, data: data))
            }, terminate: { [weak self] in Task { try? await self?.send(RelayEnvelope(kind: "close", channelID: channel)) } }, expectedClientID: client)
            sessions[channel] = session; await session.start()
        case "data":
            guard let bytes = envelope.data, bytes.count <= 2_100_000 else { throw BridgeError("invalid_response", "Invalid relay data.") }
            // Packets can cross a revocation or local close in flight; end only that channel.
            guard let session = sessions[channel] else { try await send(RelayEnvelope(kind: "close", channelID: channel)); return }
            await session.receive(bytes)
        case "close":
            Logger.relay.debug("relay channel closed channel=\(channel.prefix(8), privacy: .public)")
            await sessions.removeValue(forKey: channel)?.close()
        default: throw BridgeError("invalid_response", "Unknown relay operation.")
        }
    }
    /// Runs a socket operation or fails once `limit` passes. A late operation is ended by closing its socket,
    /// since a pending WebSocket receive may not observe task cancellation.
    private static func within<T: Sendable>(_ limit: Duration, orClose socket: any CloudRelayConnecting, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask { try await Task.sleep(for: limit); socket.close(); throw URLError(.timedOut) }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw URLError(.timedOut) }
            return value
        }
    }
    private func send(_ envelope: RelayEnvelope) async throws {
        guard let writer else { throw URLError(.networkConnectionLost) }
        try await writer.write(JSONEncoder().encode(envelope))
    }
    /// Closes without sending first: a send on a dead path never returns, and the relay withdraws a host's
    /// directory entry itself when its Bridge socket closes.
    private func disconnect() async {
        heartbeat?.cancel(); heartbeat = nil
        publisher?.cancel(); publisher = nil
        registry?.cancel(); registry = nil
        let old = sessions; sessions.removeAll()
        let oldWriter = writer; writer = nil; socket?.close(); socket = nil
        await oldWriter?.close()
        for session in old.values { await session.close() }
    }
}
