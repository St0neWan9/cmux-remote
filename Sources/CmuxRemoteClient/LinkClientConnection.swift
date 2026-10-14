import Foundation
import CmuxRemoteCore

/// Multiplexes bounded requests and subscriptions over one ordered authenticated link.
actor LinkClientConnection {
    private struct Prepared: Sendable { let socket: LinkSocket; let cipher: LinkCipher; let relayed: Bool }
    /// One path's outcome while both are dialled at once.
    private enum PathResult: Sendable { case ready(Prepared), lanUnreachable, lanFailed(any Error), relayFailed(any Error) }
    private struct Pending {
        var index = 0
        var status: Int?
        var contentType: String?
        var data = Data()
        let method: String
        let done: CheckedContinuation<LinkResourceResponse, any Error>
        let deadline: Task<Void, Never>
    }
    private let host: HostIdentity
    private let key: Data
    private var endpoint: BridgeEndpoint
    private let relayDial: @Sendable (URL, [String: String]) -> LinkSocket
    private var socket: LinkSocket?
    private var writer: WebSocketSendQueue?
    private var cipher: LinkCipher?
    private var preparing: Task<Prepared, any Error>?
    private var receiver: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var pending: [String: Pending] = [:]
    private var subscriptions: [String: AsyncThrowingStream<LinkFrame, any Error>.Continuation] = [:]
    /// Recently cancelled IDs; the Bridge may already have frames for them in flight.
    private var abandoned: [String] = []
    private var closed = false
    /// The last link came up over the relay: the next dial tries both paths at once instead of waiting
    /// out the LAN deadline first, so a phone away from home does not pay that wait on every reconnect.
    private var lastRelayed = false
    private let report: @Sendable (LinkState) -> Void
    /// A pong that does not arrive within this time means the path died without the socket noticing.
    private static let pongDeadline: Duration = .seconds(10)
    init(host: HostIdentity, key: Data, endpoint: BridgeEndpoint, relayDial: @escaping @Sendable (URL, [String: String]) -> LinkSocket = { LinkSocket(url: $0, headers: $1, timeout: 15) },
         report: @escaping @Sendable (LinkState) -> Void = { _ in }) {
        self.host = host; self.key = key; self.endpoint = endpoint; self.relayDial = relayDial; self.report = report
    }
    /// Drops a link the person or the network says may be dead, then dials again.
    ///
    /// A half-open socket otherwise keeps taking requests that each wait out their deadline. An in-flight send
    /// keeps the link: dropping it would turn a write that may have landed into an unknown outcome.
    func reconnect() async {
        guard !closed else { return }
        if Self.mayDropLink(pendingMethods: pending.values.map(\.method)) { await failed(URLError(.networkConnectionLost)) }
        try? await connect()
    }
    func updateRelay(_ relay: RelayEndpoint?) { endpoint.relay = relay }
    func exchange(_ frame: LinkFrame) async throws -> LinkResourceResponse {
        try Task.checkCancellation(); try await connect(); try Task.checkCancellation()
        guard pending.count < 8 else { throw BridgeError("too_large", "The concurrent request limit was reached.", status: 429) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { done in
                let deadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(20)); await self?.cancel(frame.id, timedOut: true) } catch {}
                }
                pending[frame.id] = Pending(method: frame.method ?? "GET", done: done, deadline: deadline)
                Task { [weak self] in
                    await self?.sendRequested(frame)
                }
            }
        } onCancel: { Task { await self.cancel(frame.id) } }
    }
    func subscribe(_ frame: LinkFrame) async throws -> AsyncThrowingStream<LinkFrame, any Error> {
        try Task.checkCancellation(); try await connect()
        guard subscriptions.count < 8 else { throw BridgeError("too_large", "The subscription limit was reached.", status: 429) }
        let stream = AsyncThrowingStream<LinkFrame, any Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscriptions[frame.id] = stream.continuation
        stream.continuation.onTermination = { [weak self] _ in Task { await self?.cancel(frame.id) } }
        do { try await send(frame) } catch { subscriptions.removeValue(forKey: frame.id)?.finish(throwing: error); throw error }
        return stream.stream
    }
    func close() async { closed = true; preparing?.cancel(); preparing = nil; await failed(CancellationError()) }
    private func connect() async throws {
        guard !closed else { throw CancellationError() }
        if socket != nil { return }
        if preparing == nil {
            report(.connecting)
            let host = host, key = key, endpoint = endpoint, race = lastRelayed && endpoint.relay != nil
            preparing = Task {
                if race, let relay = endpoint.relay { return try await self.race(host: host, key: key, endpoint: endpoint, relay: relay) }
                do { return try await self.dialDirect(host: host, key: key, endpoint: endpoint) }
                catch {
                    guard LinkPathFailure().isUnreachable(error), let relay = endpoint.relay else { throw error }
                    return try await self.dialRelay(host: host, key: key, relay: relay)
                }
            }
        }
        let current = preparing!
        do {
            let ready: Prepared
            do { ready = try await current.value } catch { if !closed { report(.disconnected) }; throw error }
            guard !closed else { ready.socket.close(); throw CancellationError() }
            if socket == nil {
                socket = ready.socket; cipher = ready.cipher; writer = WebSocketSendQueue(socket: ready.socket, cipher: ready.cipher); lastRelayed = ready.relayed
                report(.connected)
                heartbeat = Task { [weak self] in
                    do { while !Task.isCancelled { try await Task.sleep(for: .seconds(25)); try await Self.ping(ready.socket) } }
                    catch { if !Task.isCancelled { await self?.failed(error, source: ready.socket) } }
                }
                receiver = Task { [weak self] in
                    do {
                        while !Task.isCancelled { let data = try await ready.socket.receive(); try await self?.received(data, source: ready.socket) }
                    } catch { await self?.failed(error, source: ready.socket) }
                }
            }
            preparing = nil
        } catch { preparing = nil; throw error }
    }
    private nonisolated func dialDirect(host: HostIdentity, key: Data, endpoint: BridgeEndpoint) async throws -> Prepared {
        let handshake = try LinkClientHandshake(host: host, privateKey: key)
        let pairing = try PairingConfiguration(host: endpoint.host, port: endpoint.port, token: String(repeating: "0", count: 32), certificateSHA256: host.certificateSHA256)
        var parts = URLComponents(); parts.scheme = "wss"; parts.host = endpoint.host; parts.port = endpoint.port; parts.path = "/v3/link"
        guard let url = parts.url else { throw BridgeError("invalid_endpoint", "Invalid WebSocket endpoint.") }
        let direct = LinkSocket(url: url, delegate: PinnedSessionDelegate(pairing: pairing))
        do { return try await prepare(direct, handshake: handshake, relayed: false) } catch { direct.close(); throw error }
    }
    private nonisolated func dialRelay(host: HostIdentity, key: Data, relay: RelayEndpoint) async throws -> Prepared {
        let handshake = try LinkClientHandshake(host: host, privateKey: key)
        try relay.validate(host: host, now: Int(Date().timeIntervalSince1970))
        let crypto = IdentityCryptography(), publicKey = try crypto.publicKey(privateKey: key)
        if relay.admission.value.kind == "approved", relay.admission.value.clientPublicKey != publicKey { throw BridgeError("invalid_identity", "The relay admission belongs to another client.") }
        let join = try crypto.sign(RelayJoin(hostID: host.id, clientPublicKey: publicKey, permitDigest: crypto.digest(crypto.bytes(relay.admission, domain: "relay3-permit-envelope"))), domain: "relay3-join", privateKey: key)
        let relayed = relayDial(try RelayOrigin(relay.origin).socketURL(hostID: host.id, role: "client"), ["X-Cmux-Relay-Permit": try JSONEncoder().encode(relay.admission).base64EncodedString(), "X-Cmux-Relay-Join": try JSONEncoder().encode(join).base64EncodedString()])
        do { return try await prepare(relayed, handshake: handshake, relayed: true, deadline: .seconds(15)) } catch { relayed.close(); throw error }
    }
    /// Dials the LAN and the relay together and keeps whichever authenticates first. Only an unreachable LAN
    /// lets the relay decide: a TLS pin or identity failure on the LAN still ends the attempt.
    private nonisolated func race(host: HostIdentity, key: Data, endpoint: BridgeEndpoint, relay: RelayEndpoint) async throws -> Prepared {
        try await withThrowingTaskGroup(of: PathResult.self) { group in
            group.addTask {
                do { return .ready(try await self.dialDirect(host: host, key: key, endpoint: endpoint)) }
                catch { return LinkPathFailure().isUnreachable(error) ? .lanUnreachable : .lanFailed(error) }
            }
            group.addTask {
                do { return .ready(try await self.dialRelay(host: host, key: key, relay: relay)) } catch { return .relayFailed(error) }
            }
            var outcome: Result<Prepared, any Error>?, relayFailure: (any Error)?
            while outcome == nil, let next = try await group.next() {
                switch next {
                case .ready(let prepared): outcome = .success(prepared)
                case .lanFailed(let error): outcome = .failure(error)
                case .relayFailed(let error): relayFailure = error
                case .lanUnreachable: break
                }
            }
            // The losing path is abandoned; one that authenticated in the meantime is closed, not leaked.
            group.cancelAll()
            while let late = try await group.next() { if case .ready(let prepared) = late { prepared.socket.close() } }
            return try (outcome ?? .failure(relayFailure ?? URLError(.cannotConnectToHost))).get()
        }
    }
    private nonisolated func prepare(_ socket: LinkSocket, handshake: LinkClientHandshake, relayed: Bool, deadline: Duration = .seconds(4)) async throws -> Prepared {
        // A pending WebSocket receive may not observe cancellation; closing the socket ends a dial that lost a race.
        let acceptance: SignedValue<LinkAcceptance> = try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask { try await socket.send(JSONEncoder().encode(handshake.proposal)); return try await socket.receive() }
                group.addTask { try await Task.sleep(for: deadline); socket.close(); throw URLError(.timedOut) }
                defer { group.cancelAll() }
                return try JSONDecoder().decode(SignedValue<LinkAcceptance>.self, from: await group.next()!)
            }
        } onCancel: { socket.close() }
        try Task.checkCancellation()
        return Prepared(socket: socket, cipher: try handshake.accept(acceptance), relayed: relayed)
    }
    private func sendRequested(_ frame: LinkFrame) async {
        let source = socket
        do { try await send(frame) } catch { await failed(error, source: source) }
    }
    private func send(_ frame: LinkFrame) async throws {
        guard cipher != nil, let writer else { throw URLError(.networkConnectionLost) }
        try await writer.send(frame)
    }
    private func received(_ data: Data, source: LinkSocket) async throws {
        guard socket === source else { return }
        guard cipher != nil else { throw CancellationError() }
        let frame = try cipher!.open(data)
        if pending[frame.id] == nil, subscriptions[frame.id] == nil, abandoned.contains(frame.id) { return }
        if frame.kind == "event", let continuation = subscriptions[frame.id] {
            if frame.status != 200 || frame.final == true {
                // Only a refused grant is final; a missing or failing resource ends this stream and is resubscribed.
                let status = frame.status ?? 401
                let failure = status == 401 || status == 403
                    ? BridgeError("unauthorized", "The subscription ended; refresh its authorization.", status: status)
                    : BridgeError("subscription_ended", "The subscription ended; it will be renewed.", status: status)
                subscriptions[frame.id] = nil; continuation.finish(throwing: failure)
            } else { continuation.yield(frame) }
            return
        }
        guard frame.kind == "response", var item = pending[frame.id], frame.index == item.index, let status = frame.status,
              let contentType = frame.contentType, let bytes = frame.data, bytes.count <= 65_536,
              item.status == nil || item.status == status, item.contentType == nil || item.contentType == contentType,
              pending.values.reduce(0, { $0 + $1.data.count }) + bytes.count <= 8_388_608 else { throw BridgeError("invalid_response", "Unexpected or oversized response chunk.", status: 502) }
        item.status = status; item.contentType = contentType; item.data.append(bytes); item.index += 1
        pending[frame.id] = item
        try await send(LinkFrame(kind: "ack", id: frame.id, index: frame.index))
        if frame.final == true, let completed = pending.removeValue(forKey: frame.id) {
            completed.deadline.cancel(); completed.done.resume(returning: LinkResourceResponse(status: status, data: completed.data, contentType: contentType))
        }
    }
    private func cancel(_ id: String, timedOut: Bool = false) async {
        if let item = pending.removeValue(forKey: id) {
            item.deadline.cancel()
            let failure: any Error
            if item.method == "POST" { failure = BridgeError("outcome_unknown", "Inspect the operation receipt before retrying.", status: 504) }
            else if timedOut { failure = URLError(.timedOut) }
            else { failure = CancellationError() }
            item.done.resume(throwing: failure)
        }
        subscriptions.removeValue(forKey: id)?.finish()
        abandoned.append(id); if abandoned.count > 64 { abandoned.removeFirst() }
        // A read that outlived its deadline points at a dead link: the next request dials again instead of waiting too.
        if timedOut, Self.mayDropLink(pendingMethods: pending.values.map(\.method)) { await failed(URLError(.timedOut)); return }
        try? await send(LinkFrame(kind: "cancel", id: id))
    }
    /// Whether the link may be torn down: never under an in-flight write, which would then have an unknown outcome.
    static func mayDropLink(pendingMethods: [String]) -> Bool { !pendingMethods.contains("POST") }
    /// A ping with a deadline: a lost path never answers, and the socket alone may not report it.
    private static func ping(_ socket: LinkSocket) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await socket.ping() }
            group.addTask { try await Task.sleep(for: pongDeadline); throw URLError(.timedOut) }
            defer { group.cancelAll() }
            try await group.next()
        }
    }
    private func failed(_ error: any Error, source: LinkSocket? = nil) async {
        if let source, socket !== source { return }
        if !closed { report(.disconnected) }
        heartbeat?.cancel(); heartbeat = nil
        receiver?.cancel(); receiver = nil; socket?.close(); socket = nil; cipher = nil
        let oldWriter = writer; writer = nil; await oldWriter?.close()
        let requests = pending; pending.removeAll()
        for item in requests.values {
            item.deadline.cancel()
            item.done.resume(throwing: item.method == "POST" ? BridgeError("outcome_unknown", "Inspect the operation receipt before retrying.", status: 504) : error)
        }
        let streams = subscriptions; subscriptions.removeAll()
        for continuation in streams.values { continuation.finish(throwing: error) }
    }
}
