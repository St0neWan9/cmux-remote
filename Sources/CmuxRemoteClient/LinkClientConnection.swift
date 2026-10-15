import Foundation
import os
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
        /// The request URI without its query, for a trace line.
        let route: String
        let done: CheckedContinuation<LinkResourceResponse, any Error>
        let deadline: Task<Void, Never>
    }
    private let host: HostIdentity
    private let key: Data
    private var endpoint: BridgeEndpoint
    private let relayDial: @Sendable (URL, [String: String]) -> LinkSocket
    /// How long the LAN handshake may take before the dial counts the LAN as unreachable and tries the relay.
    private let lanDeadline: Duration
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
    private let report: @Sendable (LinkState) -> Void
    /// One short credential-free line per dial, path outcome, heartbeat loss, link loss and timed-out request.
    private let trace: @Sendable (String) -> Void
    /// A pong that does not arrive within this time means the path died without the socket noticing.
    private static let pongDeadline: Duration = .seconds(10)
    init(host: HostIdentity, key: Data, endpoint: BridgeEndpoint, relayDial: @escaping @Sendable (URL, [String: String]) -> LinkSocket = { LinkSocket(url: $0, headers: $1, timeout: 15) },
         report: @escaping @Sendable (LinkState) -> Void = { _ in }, trace: @escaping @Sendable (String) -> Void = { _ in }, lanDeadline: Duration = .seconds(4)) {
        self.host = host; self.key = key; self.endpoint = endpoint; self.relayDial = relayDial; self.report = report; self.trace = trace; self.lanDeadline = lanDeadline
    }
    /// Drops a link the person or the network says may be dead, then dials again.
    ///
    /// A half-open socket otherwise keeps taking requests that each wait out their deadline. An in-flight send
    /// keeps the link: dropping it would turn a write that may have landed into an unknown outcome.
    func reconnect() async {
        guard !closed else { return }
        // A dial already under way is the redial; dropping its empty link would only report a spurious disconnect.
        if socket == nil, preparing != nil { trace("reconnect requested: a dial is already in progress"); try? await connect(); return }
        let methods = pending.values.map(\.method)
        if socket == nil { trace("reconnect requested: no live link, dialing") }
        else if Self.mayDropLink(pendingMethods: methods) { trace("reconnect requested: dropping link pending=\(methods.count)") }
        else { trace("reconnect requested: keeping link, a POST is in flight pending=\(methods.count)") }
        if Self.mayDropLink(pendingMethods: methods) { await failed(URLError(.networkConnectionLost)) }
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
                pending[frame.id] = Pending(method: frame.method ?? "GET", route: TraceFormat().route(frame.uri ?? ""), done: done, deadline: deadline)
                Task { [weak self] in
                    await self?.sendRequested(frame)
                }
            }
        } onCancel: { Task { await self.cancel(frame.id) } }
    }
    func subscribe(_ frame: LinkFrame) async throws -> AsyncThrowingStream<LinkFrame, any Error> {
        try Task.checkCancellation(); try await connect()
        // Matches the Bridge's own limit. Paths are shared on the phone, so this counts distinct paths: the session
        // list, each running agent's history, the open agent's preview and each Mac's pending items.
        guard subscriptions.count < 16 else { throw BridgeError("too_large", "The subscription limit was reached.", status: 429) }
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
            Logger.clientLink.info("link connecting race=\(self.endpoint.relay != nil, privacy: .public)")
            let host = host, key = key, endpoint = endpoint, trace = trace
            let lan = "\(endpoint.host):\(endpoint.port)"
            // With a relay, both paths are dialled at once on every connect: a phone away from home does not wait out
            // the LAN deadline first, and one on the Mac's Wi-Fi still keeps the direct path, which authenticates sooner.
            if let relay = endpoint.relay { trace("dial start path=race lan=\(lan) relay=\(TraceFormat().origin(relay))") }
            else { trace("dial start path=lan lan=\(lan) relay=none") }
            preparing = Task {
                if let relay = endpoint.relay { return try await self.race(host: host, key: key, endpoint: endpoint, relay: relay) }
                do { return try await self.dialDirect(host: host, key: key, endpoint: endpoint) }
                catch {
                    if LinkPathFailure().isUnreachable(error) { trace("dial lan unreachable and no relay is configured") }
                    throw error
                }
            }
        }
        let current = preparing!
        do {
            let ready: Prepared
            do { ready = try await current.value } catch {
                if !closed { report(.disconnected); trace("dial failed error=\(TraceFormat().describe(error))"); Logger.clientLink.warning("link disconnected error=\(String(describing: error), privacy: .public)") }
                throw error
            }
            guard !closed else { ready.socket.close(); throw CancellationError() }
            if socket == nil {
                socket = ready.socket; cipher = ready.cipher; writer = WebSocketSendQueue(socket: ready.socket, cipher: ready.cipher)
                Logger.clientLink.info("link connected relayed=\(ready.relayed, privacy: .public)")
                trace("link connected relayed=\(ready.relayed)")
                report(.connected)
                let trace = trace
                heartbeat = Task { [weak self] in
                    do { while !Task.isCancelled { try await Task.sleep(for: .seconds(25)); try await Self.ping(ready.socket) } }
                    catch {
                        guard !Task.isCancelled else { return }
                        let timedOut = (error as? URLError)?.code == .timedOut
                        trace(timedOut ? "heartbeat ping timeout after 10s error=\(TraceFormat().describe(error))" : "heartbeat ping failed error=\(TraceFormat().describe(error))")
                        await self?.failed(error, source: ready.socket)
                    }
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
    /// `race` is the shared winner while the relay is dialled too: losing to it is reported as a cancellation, not a failure.
    private nonisolated func dialDirect(host: HostIdentity, key: Data, endpoint: BridgeEndpoint, race: LinkRaceWinner? = nil) async throws -> Prepared {
        let handshake = try LinkClientHandshake(host: host, privateKey: key)
        let pairing = try PairingConfiguration(host: endpoint.host, port: endpoint.port, token: String(repeating: "0", count: 32), certificateSHA256: host.certificateSHA256)
        var parts = URLComponents(); parts.scheme = "wss"; parts.host = endpoint.host; parts.port = endpoint.port; parts.path = "/v3/link"
        guard let url = parts.url else { throw BridgeError("invalid_endpoint", "Invalid WebSocket endpoint.") }
        let direct = LinkSocket(url: url, delegate: PinnedSessionDelegate(pairing: pairing)), started = ContinuousClock.now
        do {
            let ready = try await prepare(direct, handshake: handshake, relayed: false, deadline: lanDeadline)
            race?.claim(.lan)
            trace("dial lan ok \(TraceFormat().milliseconds(since: started))ms relayed=false")
            return ready
        } catch {
            direct.close()
            if let lost = Self.lostRace(.lan, race) { trace("dial lan cancelled after \(TraceFormat().milliseconds(since: started))ms: \(lost.rawValue) connected first") }
            else { trace("dial lan failed \(TraceFormat().milliseconds(since: started))ms unreachable=\(LinkPathFailure().isUnreachable(error)) error=\(TraceFormat().describe(error))") }
            throw error
        }
    }
    private nonisolated func dialRelay(host: HostIdentity, key: Data, relay: RelayEndpoint, race: LinkRaceWinner? = nil) async throws -> Prepared {
        let handshake = try LinkClientHandshake(host: host, privateKey: key)
        try relay.validate(host: host, now: Int(Date().timeIntervalSince1970))
        let crypto = IdentityCryptography(), publicKey = try crypto.publicKey(privateKey: key)
        if relay.admission.value.kind == "approved", relay.admission.value.clientPublicKey != publicKey { throw BridgeError("invalid_identity", "The relay admission belongs to another client.") }
        let join = try crypto.sign(RelayJoin(hostID: host.id, clientPublicKey: publicKey, permitDigest: crypto.digest(crypto.bytes(relay.admission, domain: "relay3-permit-envelope"))), domain: "relay3-join", privateKey: key)
        let relayed = relayDial(try RelayOrigin(relay.origin).socketURL(hostID: host.id, role: "client"), ["X-Cmux-Relay-Permit": try JSONEncoder().encode(relay.admission).base64EncodedString(), "X-Cmux-Relay-Join": try JSONEncoder().encode(join).base64EncodedString()])
        let started = ContinuousClock.now
        do {
            let ready = try await prepare(relayed, handshake: handshake, relayed: true, deadline: .seconds(15))
            race?.claim(.relay)
            trace("dial relay ok \(TraceFormat().milliseconds(since: started))ms relayed=true")
            return ready
        } catch {
            relayed.close()
            if let lost = Self.lostRace(.relay, race) { trace("dial relay cancelled after \(TraceFormat().milliseconds(since: started))ms: \(lost.rawValue) connected first") }
            else { trace("dial relay failed \(TraceFormat().milliseconds(since: started))ms error=\(TraceFormat().describe(error))") }
            throw error
        }
    }
    /// The path that beat `path`, when `path` ended only because the race was decided; a real failure returns nil.
    private nonisolated static func lostRace(_ path: LinkRaceWinner.Path, _ race: LinkRaceWinner?) -> LinkRaceWinner.Path? {
        guard Task.isCancelled, let winner = race?.path, winner != path else { return nil }
        return winner
    }
    /// Dials the LAN and the relay together and keeps whichever authenticates first. Only an unreachable LAN
    /// lets the relay decide: a TLS pin or identity failure on the LAN still ends the attempt.
    private nonisolated func race(host: HostIdentity, key: Data, endpoint: BridgeEndpoint, relay: RelayEndpoint) async throws -> Prepared {
        let winner = LinkRaceWinner()
        return try await withThrowingTaskGroup(of: PathResult.self) { group in
            group.addTask {
                do { return .ready(try await self.dialDirect(host: host, key: key, endpoint: endpoint, race: winner)) }
                catch { return LinkPathFailure().isUnreachable(error) ? .lanUnreachable : .lanFailed(error) }
            }
            group.addTask {
                do { return .ready(try await self.dialRelay(host: host, key: key, relay: relay, race: winner)) } catch { return .relayFailed(error) }
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
        let started = ContinuousClock.now
        let acceptance: SignedValue<LinkAcceptance>
        do { acceptance = try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask { try await socket.send(JSONEncoder().encode(handshake.proposal)); return try await socket.receive() }
                group.addTask { try await Task.sleep(for: deadline); socket.close(); throw URLError(.timedOut) }
                defer { group.cancelAll() }
                return try JSONDecoder().decode(SignedValue<LinkAcceptance>.self, from: await group.next()!)
            }
        } onCancel: { socket.close() } }
        catch {
            // Closing the socket at the deadline can surface the receive's "cancelled" before the timeout itself.
            // Report the timeout, so a slow LAN still counts as unreachable and the dial moves on to the relay.
            if !Task.isCancelled, ContinuousClock.now - started >= deadline { throw URLError(.timedOut) }
            throw error
        }
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
                // A Bridge that restarted refuses a subscription signed under the old epoch and names the reason,
                // so the client can fetch the new epoch instead of treating the grant as refused.
                let stale = status == 401 && frame.data.map { String(decoding: $0, as: UTF8.self) } == "invalid_proof"
                let failure = stale ? BridgeError("invalid_proof", "The subscription was signed under an old epoch.", status: 401)
                    : status == 401 || status == 403
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
            if timedOut { trace("request timeout after 20s \(item.method) \(item.route) error=URLError(timedOut)") }
            let failure: any Error
            if item.method == "POST" { failure = BridgeError("outcome_unknown", "Inspect the operation receipt before retrying.", status: 504) }
            else if timedOut { failure = URLError(.timedOut) }
            else { failure = CancellationError() }
            item.done.resume(throwing: failure)
        }
        subscriptions.removeValue(forKey: id)?.finish()
        abandoned.append(id); if abandoned.count > 64 { abandoned.removeFirst() }
        // A read that outlived its deadline points at a dead link: the next request dials again instead of waiting too.
        if timedOut, Self.mayDropLink(pendingMethods: pending.values.map(\.method)) {
            if socket != nil { trace("dropping link after a timed-out request") }
            await failed(URLError(.timedOut)); return
        }
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
        if socket != nil || !pending.isEmpty || !subscriptions.isEmpty {
            let writes = pending.values.filter { $0.method == "POST" }.count
            let counts = "pending=\(pending.count) (post=\(writes)) subscriptions=\(subscriptions.count)"
            trace(closed ? "link closed \(counts)" : "link down error=\(TraceFormat().describe(error)) \(counts)")
        }
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
