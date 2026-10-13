import Foundation
import CmuxRemoteCore

/// Maintains outbound relay routing while all Agent and device authority stays on Bridge.
public actor CloudRelayService {
    private let origin: RelayOrigin
    private let secret: String
    private let router: BridgeRouter
    private let authority: ConnectionAuthority
    private let onConnected: (@Sendable () -> Void)?
    private let dial: @Sendable (URL, [String: String]) -> any CloudRelayConnecting
    private var running: Task<Void, Never>?
    private var registry: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var failure: String?
    private var socket: (any CloudRelayConnecting)?
    private var writer: LinkPacketWriter?
    private var sessions: [String: LinkServerSession] = [:]
    private var phase = "stopped"
    private var generation: UUID?
    public init(origin: String, secret: String, router: BridgeRouter, authority: ConnectionAuthority, dial: @escaping @Sendable (URL, [String: String]) -> any CloudRelayConnecting = { CloudRelaySocket(url: $0, headers: $1) }, onConnected: (@Sendable () -> Void)? = nil) throws {
        self.onConnected = onConnected; self.origin = try RelayOrigin(origin); self.secret = secret; self.router = router; self.authority = authority; self.dial = dial
        guard secret.utf8.count >= 32, secret.utf8.count <= 256, !secret.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw BridgeError("invalid_identity", "Invalid private relay registration key.") }
    }
    public func status() -> JSONValue { .object(["state": .string(phase), "origin": .string(origin.value), "error_code": failure.map(JSONValue.string) ?? .null]) }
    public func start() async throws {
        guard running == nil else { return }
        try await authority.configureRelay(origin: origin.value)
        let id = UUID(); generation = id; phase = "connecting"
        running = Task { [weak self] in await self?.run(id) }
    }
    public func stop() async {
        generation = nil; phase = "stopped"; failure = nil
        let task = running; running = nil; task?.cancel()
        await disconnect(); _ = await task?.value
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
                try await synchronizeRegistry()
                let ready = try JSONDecoder().decode(RelayEnvelope.self, from: await socket.receive())
                guard ready.kind == "ready" else { throw BridgeError("invalid_response", "The relay did not acknowledge Bridge registration.") }
                phase = "connected"; failure = nil; attempt = 0; onConnected?()
                heartbeat = Task {
                    do { while !Task.isCancelled { try await Task.sleep(for: .seconds(25)); try await socket.ping() } }
                    catch { if !Task.isCancelled { socket.close() } }
                }
                let changes = try await authority.registryChanges()
                registry = Task { [weak self] in
                    for await _ in changes {
                        guard !Task.isCancelled else { break }
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
            do { try await Task.sleep(for: .seconds(1 << attempt)) } catch { break }
        }
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
            let session = LinkServerSession(router: router, authority: authority, send: { [weak self] data in
                guard let self else { throw CancellationError() }; try await self.send(RelayEnvelope(kind: "data", channelID: channel, data: data))
            }, terminate: { [weak self] in Task { try? await self?.send(RelayEnvelope(kind: "close", channelID: channel)) } }, expectedClientID: client)
            sessions[channel] = session; await session.start()
        case "data":
            guard let bytes = envelope.data, bytes.count <= 2_100_000 else { throw BridgeError("invalid_response", "Invalid relay data.") }
            // Packets can cross a revocation or local close in flight; end only that channel.
            guard let session = sessions[channel] else { try await send(RelayEnvelope(kind: "close", channelID: channel)); return }
            await session.receive(bytes)
        case "close": await sessions.removeValue(forKey: channel)?.close()
        default: throw BridgeError("invalid_response", "Unknown relay operation.")
        }
    }
    private func send(_ envelope: RelayEnvelope) async throws {
        guard let writer else { throw URLError(.networkConnectionLost) }
        try await writer.write(JSONEncoder().encode(envelope))
    }
    private func disconnect() async {
        heartbeat?.cancel(); heartbeat = nil
        registry?.cancel(); registry = nil
        let old = sessions; sessions.removeAll()
        let oldWriter = writer; writer = nil; socket?.close(); socket = nil
        await oldWriter?.close()
        for session in old.values { await session.close() }
    }
}
