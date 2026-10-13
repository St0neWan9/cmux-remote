import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge
@testable import CmuxRemoteClient

@Suite struct LinkRelayIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CMUX_REMOTE_RELAY_TESTS"] == "1"), .timeLimit(.minutes(1)))
    func swiftBridgeAndClientUseRealCloudflareRuntimeWithFallbackAndSameReceipts() async throws {
        let fixture = try await LinkIntegrationFixture.create(text: String(repeating: "relay ", count: 14_000), recordCount: 8)
        var relay: CloudRelayService?, local: LocalRelayProcess?
        var transport: WebSocketTransport?
        do {
            let process = try await LocalRelayProcess.start(root: fixture.root); local = process
            let origin = try #require(URLComponents(string: process.origin)), port = try #require(origin.port)
            let pairing = try process.tls.pairing(host: "127.0.0.1", port: port)
            let service = SessionService(cmux: fixture.cmux, home: fixture.root.appendingPathComponent("home"), transcriptRoots: [fixture.root])
            let ready = AsyncStream<Void>.makeStream()
            let connectedSocket = AsyncStream<CloudRelaySocket>.makeStream()
            let cloud = try CloudRelayService(origin: process.origin, secret: String(repeating: "a", count: 64), router: BridgeRouter(service: service, authority: fixture.authority), authority: fixture.authority,
                dial: { let socket = CloudRelaySocket(url: $0, headers: $1, delegate: PinnedSessionDelegate(pairing: pairing)); connectedSocket.continuation.yield(socket); return socket }, onConnected: { ready.continuation.yield(()); ready.continuation.finish() })
            relay = cloud; try await cloud.start()
            let admission = try #require(try await fixture.authority.status(fixture.enrollmentRequest).value.relay)
            var connection = fixture.connection; connection.endpoint = BridgeEndpoint(host: "127.0.0.1", port: 1, relay: admission); try connection.validate()
            var iterator = ready.stream.makeAsyncIterator(); #expect(await iterator.next() != nil)
            var sockets = connectedSocket.stream.makeAsyncIterator(); let socket = try #require(await sockets.next()); try await socket.ping()
            let link = WebSocketTransport(host: connection.host, key: connection.privateKey, endpoint: connection.endpoint,
                relayDial: { LinkSocket(url: $0, delegate: PinnedSessionDelegate(pairing: pairing), headers: $1) }); transport = link
            let initial: ConversationSnapshot = try await request(link, connection: connection, path: "/v2/sessions/demo-session/history")
            #expect(initial.messages.count == 8)
            let send = SendRequest(text: "Through real relay")
            let first: MutationReceipt = try await request(link, connection: connection, path: "/v2/sessions/demo-session/send", body: JSONEncoder().encode(send))
            let repeated: MutationReceipt = try await request(link, connection: connection, path: "/v2/sessions/demo-session/send", body: JSONEncoder().encode(send))
            #expect(first.operationID == repeated.operationID)
            let history: ConversationSnapshot = try await request(link, connection: connection, path: "/v2/sessions/demo-session/history")
            #expect(history.messages.count == 10)
            let _: MutationReceipt = try await request(link, connection: connection, path: "/v2/sessions/demo-session/interrupt", body: JSONEncoder().encode(InterruptRequest(hard: true)))
            try await fixture.authority.revoke(clientID: connection.grant.value.clientID)
            do { let _: [SessionDescriptor] = try await request(link, connection: connection, path: "/v2/sessions"); Issue.record("Revoked relay must not read resources") } catch {}
            link.close(); await cloud.stop(); local?.stop(); await fixture.stop()
        } catch { transport?.close(); await relay?.stop(); local?.stop(); await fixture.stop(); throw error }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CMUX_REMOTE_RELAY_TESTS"] == "1"), .timeLimit(.minutes(1)))
    func revokingOneBusyRelayedPhoneKeepsTheSharedBridgeConnection() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        var relay: CloudRelayService?, local: LocalRelayProcess?, links: [WebSocketTransport] = []
        do {
            let process = try await LocalRelayProcess.start(root: fixture.root); local = process
            let origin = try #require(URLComponents(string: process.origin)), port = try #require(origin.port)
            let pairing = try process.tls.pairing(host: "127.0.0.1", port: port)
            let service = SessionService(cmux: fixture.cmux, home: fixture.root.appendingPathComponent("home"), transcriptRoots: [fixture.root])
            let ready = AsyncStream<Void>.makeStream(), dialed = Counter()
            let cloud = try CloudRelayService(origin: process.origin, secret: String(repeating: "a", count: 64), router: BridgeRouter(service: service, authority: fixture.authority), authority: fixture.authority,
                dial: { dialed.increment(); return CloudRelaySocket(url: $0, headers: $1, delegate: PinnedSessionDelegate(pairing: pairing)) }, onConnected: { ready.continuation.yield(()) })
            relay = cloud; try await cloud.start()
            var connected = ready.stream.makeAsyncIterator(); #expect(await connected.next() != nil)
            // A second phone enrolls through the same Bridge and receives its own relay admission.
            let bootstrap = try await fixture.authority.open(endpoint: fixture.connection.endpoint, workspaces: ["11111111-1111-1111-1111-111111111111"])
            let enrollment = try EnrollmentClient(bootstrap: bootstrap, privateKey: IdentityCryptography().generatePrivateKey(), name: "Second phone", kind: "iphone")
            _ = try await enrollment.submit()
            try await fixture.authority.approve(requestID: enrollment.request.value.requestID, scope: enrollment.request.value.scope)
            let second = try enrollment.connection(from: await enrollment.status()); enrollment.close()
            func relayed(_ connection: AuthorizedConnection, request: SignedValue<EnrollmentRequest>) async throws -> (AuthorizedConnection, WebSocketTransport) {
                var routed = connection
                routed.endpoint = BridgeEndpoint(host: "127.0.0.1", port: 1, relay: try #require(try await fixture.authority.status(request).value.relay))
                let link = WebSocketTransport(host: routed.host, key: routed.privateKey, endpoint: routed.endpoint,
                    relayDial: { LinkSocket(url: $0, delegate: PinnedSessionDelegate(pairing: pairing), headers: $1) })
                links.append(link); return (routed, link)
            }
            let (first, firstLink) = try await relayed(fixture.connection, request: fixture.enrollmentRequest)
            let (other, otherLink) = try await relayed(second, request: enrollment.request)
            let _: [SessionDescriptor] = try await request(firstLink, connection: first, path: "/v2/sessions")
            let busy = Task {
                // Keep packets in flight from the phone that is about to be revoked.
                while !Task.isCancelled { do { let _: [SessionDescriptor] = try await request(otherLink, connection: other, path: "/v2/sessions") } catch { return } }
            }
            try await Task.sleep(for: .milliseconds(300))
            try await fixture.authority.revoke(clientID: other.grant.value.clientID)
            _ = await busy.value
            try await Task.sleep(for: .seconds(3))
            #expect(dialed.value == 1, "The Bridge relay connection must not restart when one phone is revoked")
            let after: [SessionDescriptor] = try await request(firstLink, connection: first, path: "/v2/sessions")
            #expect(after.count == 1)
            for link in links { link.close() }; await cloud.stop(); local?.stop(); await fixture.stop()
        } catch { for link in links { link.close() }; await relay?.stop(); local?.stop(); await fixture.stop(); throw error }
    }
    private func request<T: Decodable & Sendable>(_ link: WebSocketTransport, connection: AuthorizedConnection, path: String, body: Data? = nil) async throws -> T {
        let crypto = IdentityCryptography()
        let announcement = try await link.request("/v2/identity", method: "GET", as: SignedValue<HostAnnouncement>.self)
        try crypto.verify(announcement, domain: "host", publicKey: connection.host.publicKey)
        let method = body == nil ? "GET" : "POST"
        return try await link.request(path, method: method, body: body, authorization: { uri, bytes in
            let proof = RequestProof(epoch: announcement.value.epoch, hostID: connection.host.id, clientID: connection.grant.value.clientID, method: method, uri: uri, bodySHA256: crypto.digest(bytes), nonce: UUID().uuidString, timestamp: Int(Date().timeIntervalSince1970))
            return "CmuxV2 " + (try JSONEncoder().encode(crypto.sign(proof, domain: "request", privateKey: connection.privateKey))).base64EncodedString()
        }, as: T.self)
    }
}

/// Counts relay dials from a URLSession callback without sharing mutable state unsafely.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
