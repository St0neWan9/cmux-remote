import Foundation
import CmuxRemoteCore

/// Multiplexes bounded requests and subscriptions over one ordered authenticated link.
actor LinkClientConnection {
    private struct Prepared: Sendable { let socket: LinkSocket; let cipher: LinkCipher }
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
    init(host: HostIdentity, key: Data, endpoint: BridgeEndpoint, relayDial: @escaping @Sendable (URL, [String: String]) -> LinkSocket = { LinkSocket(url: $0, headers: $1, timeout: 15) }) { self.host = host; self.key = key; self.endpoint = endpoint; self.relayDial = relayDial }
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
            let host = host, key = key, endpoint = endpoint, relayDial = relayDial
            preparing = Task {
                let handshake = try LinkClientHandshake(host: host, privateKey: key)
                let pairing = try PairingConfiguration(host: endpoint.host, port: endpoint.port, token: String(repeating: "0", count: 32), certificateSHA256: host.certificateSHA256)
                var parts = URLComponents(); parts.scheme = "wss"; parts.host = endpoint.host; parts.port = endpoint.port; parts.path = "/v3/link"
                guard let url = parts.url else { throw BridgeError("invalid_endpoint", "Invalid WebSocket endpoint.") }
                let direct = LinkSocket(url: url, delegate: PinnedSessionDelegate(pairing: pairing))
                do { return try await self.prepare(direct, handshake: handshake) }
                catch {
                    direct.close()
                    guard LinkPathFailure().isUnreachable(error), let relay = endpoint.relay else { throw error }
                    try relay.validate(host: host, now: Int(Date().timeIntervalSince1970))
                    let crypto = IdentityCryptography(), publicKey = try crypto.publicKey(privateKey: key)
                    if relay.admission.value.kind == "approved", relay.admission.value.clientPublicKey != publicKey { throw BridgeError("invalid_identity", "The relay admission belongs to another client.") }
                    let join = try crypto.sign(RelayJoin(hostID: host.id, clientPublicKey: publicKey, permitDigest: crypto.digest(crypto.bytes(relay.admission, domain: "relay3-permit-envelope"))), domain: "relay3-join", privateKey: key)
                    let relayed = relayDial(try RelayOrigin(relay.origin).socketURL(hostID: host.id, role: "client"), ["X-Cmux-Relay-Permit": try JSONEncoder().encode(relay.admission).base64EncodedString(), "X-Cmux-Relay-Join": try JSONEncoder().encode(join).base64EncodedString()])
                    do { return try await self.prepare(relayed, handshake: handshake, deadline: .seconds(15)) } catch { relayed.close(); throw error }
                }
            }
        }
        let current = preparing!
        do {
            let ready = try await current.value
            guard !closed else { ready.socket.close(); throw CancellationError() }
            if socket == nil {
                socket = ready.socket; cipher = ready.cipher; writer = WebSocketSendQueue(socket: ready.socket, cipher: ready.cipher)
                heartbeat = Task { [weak self] in
                    do { while !Task.isCancelled { try await Task.sleep(for: .seconds(25)); try await ready.socket.ping() } }
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
    private nonisolated func prepare(_ socket: LinkSocket, handshake: LinkClientHandshake, deadline: Duration = .seconds(4)) async throws -> Prepared {
        let acceptance: SignedValue<LinkAcceptance> = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await socket.send(JSONEncoder().encode(handshake.proposal)); return try await socket.receive() }
            group.addTask { try await Task.sleep(for: deadline); socket.close(); throw URLError(.timedOut) }
            defer { group.cancelAll() }
            return try JSONDecoder().decode(SignedValue<LinkAcceptance>.self, from: await group.next()!)
        }
        return Prepared(socket: socket, cipher: try handshake.accept(acceptance))
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
                subscriptions[frame.id] = nil; continuation.finish(throwing: BridgeError("unauthorized", "The subscription ended; refresh its authorization.", status: frame.status ?? 401))
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
        try? await send(LinkFrame(kind: "cancel", id: id))
    }
    private func failed(_ error: any Error, source: LinkSocket? = nil) async {
        if let source, socket !== source { return }
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
