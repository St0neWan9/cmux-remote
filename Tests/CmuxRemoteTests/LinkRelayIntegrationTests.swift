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
