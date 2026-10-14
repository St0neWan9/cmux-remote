import Foundation
import Testing
import Darwin
import CmuxRemoteCore
@testable import CmuxRemoteClient

/// A phone away from its Mac's LAN should not wait out the LAN deadline before every relayed reconnect.
@Suite struct LinkPathRaceTests {
    @Test(.timeLimit(.minutes(1)))
    func aReconnectAfterARelayedLinkDoesNotWaitForTheLANDeadline() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let silent = try SilentListener()
        let dials = Counter()
        var transport: WebSocketTransport?
        do {
            try await fixture.authority.configureRelay(origin: "https://relay.example.com")
            let admission = try #require(try await fixture.authority.status(fixture.enrollmentRequest).value.relay)
            let bridge = fixture.connection.endpoint
            let pairing = try PairingConfiguration(host: bridge.host, port: bridge.port, token: String(repeating: "0", count: 32), certificateSHA256: fixture.connection.host.certificateSHA256)
            // The "relay" reaches the real Bridge link; the LAN address accepts TCP and then never answers.
            let link = WebSocketTransport(host: fixture.connection.host, key: fixture.connection.privateKey,
                endpoint: BridgeEndpoint(host: "127.0.0.1", port: silent.port, relay: admission),
                relayDial: { _, _ in
                    dials.increment()
                    var parts = URLComponents(); parts.scheme = "wss"; parts.host = bridge.host; parts.port = bridge.port; parts.path = "/v3/link"
                    // Production relay sockets allow slow TLS; a loaded test host needs the same allowance.
                    return LinkSocket(url: parts.url!, delegate: PinnedSessionDelegate(pairing: pairing), timeout: 15)
                }); transport = link
            let clock = ContinuousClock()
            let first = clock.now
            let _: [SessionDescriptor] = try await request(link, connection: fixture.connection, path: "/v2/sessions")
            // The first dial only learns the LAN is silent after its deadline.
            #expect(clock.now - first >= .seconds(4))
            #expect(dials.value == 1)
            // The reconnect itself dials; measure it together with the read it serves.
            let second = clock.now
            await link.reconnect()
            let _: [SessionDescriptor] = try await request(link, connection: fixture.connection, path: "/v2/sessions")
            #expect(clock.now - second < .seconds(3))
            #expect(dials.value == 2)
            link.close(); await fixture.stop()
        } catch { transport?.close(); await fixture.stop(); throw error }
    }
    private func request<T: Decodable & Sendable>(_ link: WebSocketTransport, connection: AuthorizedConnection, path: String) async throws -> T {
        let crypto = IdentityCryptography()
        let announcement = try await link.request("/v2/identity", method: "GET", as: SignedValue<HostAnnouncement>.self)
        try crypto.verify(announcement, domain: "host", publicKey: connection.host.publicKey)
        return try await link.request(path, method: "GET", authorization: { uri, bytes in
            let proof = RequestProof(epoch: announcement.value.epoch, hostID: connection.host.id, clientID: connection.grant.value.clientID, method: "GET", uri: uri, bodySHA256: crypto.digest(bytes), nonce: UUID().uuidString, timestamp: Int(Date().timeIntervalSince1970))
            return "CmuxV2 " + (try JSONEncoder().encode(crypto.sign(proof, domain: "request", privateKey: connection.privateKey))).base64EncodedString()
        }, as: T.self)
    }
}

/// Accepts TCP connections into its backlog and never reads or writes, like a LAN address that went quiet.
private final class SilentListener: Sendable {
    let port: Int
    private let descriptor: Int32
    init() throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in(); address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1"); address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, length) } }
        guard bound == 0, listen(listener, 8) == 0 else { close(listener); throw POSIXError(.EADDRINUSE) }
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) } }
        descriptor = listener; port = Int(UInt16(bigEndian: address.sin_port))
    }
    deinit { close(descriptor) }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
