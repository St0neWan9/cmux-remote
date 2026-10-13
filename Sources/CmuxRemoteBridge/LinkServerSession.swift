import Foundation
import CryptoKit
import CmuxRemoteCore

/// One ordered encrypted session; authorization remains in the fixed resource router.
actor LinkServerSession {
    private let router: BridgeRouter
    private let authority: ConnectionAuthority
    private let expectedClientID: String?
    private let writer: LinkPacketWriter
    private var cipher: LinkCipher?
    private var clientID: String?
    private var closed = false
    private var requests: [String: Task<Void, Never>] = [:]
    private var subscriptions: [String: Task<Void, Never>] = [:]
    private var acknowledgements: [String: (index: Int, final: Bool, continuation: AsyncThrowingStream<Void, any Error>.Continuation)] = [:]
    private var handshakeDeadline: Task<Void, Never>?
    init(router: BridgeRouter, authority: ConnectionAuthority, send: @escaping @Sendable (Data) async throws -> Void, terminate: @escaping @Sendable () -> Void, expectedClientID: String? = nil) {
        self.expectedClientID = expectedClientID; self.router = router; self.authority = authority; writer = LinkPacketWriter(send: send, terminate: terminate)
    }
    func start() {
        guard handshakeDeadline == nil else { return }
        handshakeDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)); await self?.close() } catch {}
        }
    }
    func receive(_ data: Data) async {
        guard !closed else { return }
        do {
            if cipher == nil {
                guard data.count <= 8192 else { throw BridgeError("too_large", "Invalid handshake size.") }
                let proposal = try JSONDecoder().decode(SignedValue<LinkProposal>.self, from: data)
                let key = P256.KeyAgreement.PrivateKey()
                let acceptance = try await authority.acceptLink(proposal, key: key)
                guard !closed else { throw CancellationError() }
                cipher = try LinkCipher(key: key, peerKey: proposal.value.agreementKey, proposal: proposal, acceptance: acceptance, server: true)
                await writer.setCipher(cipher!)
                clientID = try IdentityCryptography().identityID(publicKey: proposal.value.clientPublicKey)
                guard expectedClientID == nil || expectedClientID == clientID else { throw BridgeError("unauthorized", "The relay channel belongs to another device.") }
                try await writer.write(JSONEncoder().encode(acceptance)); handshakeDeadline?.cancel(); handshakeDeadline = nil
                return
            }
            let frame = try cipher!.open(data)
            switch frame.kind {
            case "ack":
                guard let item = acknowledgements[frame.id], frame.index == item.index else { throw BridgeError("invalid_request", "Unexpected response acknowledgement.") }
                acknowledgements[frame.id] = nil
                // The client frees its slot on the final chunk; free ours in the same ordered step, not when the
                // delivering task next runs, or a loaded Bridge rejects the client's next legitimate request.
                if item.final { requests[frame.id] = nil }
                item.continuation.yield(()); item.continuation.finish()
            case "cancel":
                subscriptions.removeValue(forKey: frame.id)?.cancel()
                requests.removeValue(forKey: frame.id)?.cancel()
                acknowledgements.removeValue(forKey: frame.id)?.continuation.finish(throwing: CancellationError())
            case "request", "subscribe":
                guard requests[frame.id] == nil, subscriptions[frame.id] == nil, requests.count < 8,
                      let method = frame.method, ["GET", "POST"].contains(method), let uri = frame.uri,
                      uri.hasPrefix("/v2/"), let clientID else { throw BridgeError("invalid_request", "Invalid resource request or full link.") }
                try router.verifyChannelIdentity(frame, clientID: clientID)
                if frame.kind == "subscribe" {
                    guard subscriptions.count < 8 else { throw BridgeError("too_large", "The subscription limit was reached.") }
                    let identity = try await router.subscriptionIdentity(frame, clientID: clientID)
                    subscriptions[frame.id] = Task { [weak self] in await self?.observe(frame, clientID: identity) }
                } else {
                    requests[frame.id] = Task { [weak self] in
                        guard let self else { return }
                        let baseline = try? await authority.currentClient(clientID)
                        let response = await router.respondResource(method: method, uri: uri, authorization: frame.authorization, body: frame.data ?? Data())
                        await self.finish(frame.id, response: response, baseline: uri.hasPrefix("/v2/enrollment/") || uri == "/v2/identity" ? nil : baseline)
                    }
                }
            default: throw BridgeError("invalid_request", "Unexpected client link message.")
            }
        } catch { await close() }
    }
    func isRevoked() async -> Bool {
        guard let clientID else { return false }
        return await authority.enrolledClients().contains { $0.id == clientID && $0.revoked }
    }
    func close() async {
        guard !closed else { return }; closed = true
        handshakeDeadline?.cancel(); handshakeDeadline = nil
        for task in requests.values { task.cancel() }; requests.removeAll()
        for task in subscriptions.values { task.cancel() }; subscriptions.removeAll()
        for item in acknowledgements.values { item.continuation.finish(throwing: CancellationError()) }; acknowledgements.removeAll()
        cipher = nil; await writer.close()
    }
    private func finish(_ id: String, response: HTTPResourceResponse, baseline: EnrolledClient?) async {
        defer { requests[id] = nil }
        do {
            guard response.data.count <= 8_388_608 else { throw BridgeError("too_large", "The resource response exceeds its bound.") }
            let count = max(1, (response.data.count + 65_535) / 65_536)
            for index in 0..<count {
                try Task.checkCancellation()
                if let baseline {
                    let current = try await authority.currentClient(baseline.id)
                    guard current.grant.signature == baseline.grant.signature, current.scope == baseline.scope else { throw BridgeError("scope_denied", "The grant changed during response delivery.", status: 403) }
                }
                let start = min(index * 65_536, response.data.count), end = min(start + 65_536, response.data.count)
                let ack = AsyncThrowingStream<Void, any Error>.makeStream(bufferingPolicy: .bufferingOldest(1))
                acknowledgements[id] = (index, index == count - 1, ack.continuation)
                try await send(LinkFrame(kind: "response", id: id, data: response.data.subdata(in: start..<end), status: response.status, contentType: response.contentType, index: index, final: index == count - 1))
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { var iterator = ack.stream.makeAsyncIterator(); guard try await iterator.next() != nil else { throw CancellationError() } }
                    group.addTask { try await Task.sleep(for: .seconds(20)); throw BridgeError("socket_unavailable", "The link consumer timed out.", status: 504) }
                    defer { group.cancelAll() }; try await group.next()
                }
            }
        } catch is CancellationError {
            // The client cancelled this request only; the link and its other requests continue.
        } catch { await close() }
    }
    private func observe(_ frame: LinkFrame, clientID: String) async {
        defer { subscriptions[frame.id] = nil }
        var digest: String?, sequence = 0
        do {
            while !Task.isCancelled && !closed {
                let response = await router.respondResource(method: "GET", uri: frame.uri!, authorization: nil, body: Data(), subscriptionClientID: clientID)
                guard response.status == 200 else {
                    try await send(LinkFrame(kind: "event", id: frame.id, status: response.status, final: true)); return
                }
                let next = try LinkObservationDigest().digest(response.data)
                if next != digest {
                    _ = try await authority.currentClient(clientID)
                    sequence += 1; digest = next
                    try await send(LinkFrame(kind: "event", id: frame.id, data: Data(authority.epoch.utf8), status: 200, index: sequence, final: false))
                }
                // Intended cadence of observation for snapshot-only backends; cancelled with the subscription.
                try await Task.sleep(for: .seconds(2))
            }
        } catch { if !Task.isCancelled { await close() } }
    }
    private func send(_ frame: LinkFrame) async throws {
        guard !closed, cipher != nil else { throw CancellationError() }
        try await writer.write(frame)
    }
}
