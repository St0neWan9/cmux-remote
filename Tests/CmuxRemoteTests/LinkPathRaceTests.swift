import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteClient

/// A phone away from its Mac's LAN falls back to the relay when the LAN address is unreachable.
@Suite struct LinkPathRaceTests {
    @Test(.timeLimit(.minutes(1)))
    func anUnreachableLANFallsBackToRelayAndSubsequentDialsRaceIt() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let dials = Counter(), traces = TraceLines()
        var transport: WebSocketTransport?
        do {
            try await fixture.authority.configureRelay(origin: "https://relay.example.com")
            let admission = try #require(try await fixture.authority.status(fixture.enrollmentRequest).value.relay)
            let bridge = fixture.connection.endpoint
            let pairing = try PairingConfiguration(host: bridge.host, port: bridge.port,
                token: String(repeating: "0", count: 32), certificateSHA256: fixture.connection.host.certificateSHA256)
            // Port 2 is a reserved system port that returns ECONNREFUSED immediately, so the
            // LAN path fails fast and the relay is the only path that can succeed.
            let link = WebSocketTransport(host: fixture.connection.host, key: fixture.connection.privateKey,
                endpoint: BridgeEndpoint(host: "127.0.0.1", port: 2, relay: admission),
                relayDial: { _, _ in
                    dials.increment()
                    var parts = URLComponents()
                    parts.scheme = "wss"; parts.host = bridge.host; parts.port = bridge.port; parts.path = "/v3/link"
                    return LinkSocket(url: parts.url!, delegate: PinnedSessionDelegate(pairing: pairing), timeout: 15)
                }, trace: { traces.append($0) }); transport = link
            // First request: LAN refused, relay succeeds.
            let _: [SessionDescriptor] = try await request(link, connection: fixture.connection, path: "/v2/sessions")
            #expect(dials.value == 1)
            // The diagnostic log says why the LAN path was abandoned and which path took over, never the permit.
            let first = traces.lines
            #expect(first.first == "dial start path=lan lan=127.0.0.1:2 relay=relay.example.com")
            let lanFailure = try #require(first.first { $0.hasPrefix("dial lan failed ") })
            #expect(lanFailure.contains("unreachable=true"))
            #expect(lanFailure.contains("error=URLError(") || lanFailure.contains("error=POSIX("))
            #expect(first.contains("dial fallback path=relay relay=relay.example.com"))
            #expect(first.contains { $0.hasPrefix("dial relay ok ") && $0.hasSuffix("relayed=true") })
            #expect(first.contains("link connected relayed=true"))
            #expect(!first.contains { $0.contains("X-Cmux") || $0.contains("CmuxV2") })
            // Second request (after reconnect): a phone that previously went through the relay
            // dials both LAN and relay at once; relay wins again with one more dial.
            await link.reconnect()
            let _: [SessionDescriptor] = try await request(link, connection: fixture.connection, path: "/v2/sessions")
            #expect(dials.value == 2)
            #expect(traces.lines.contains("reconnect requested: dropping link pending=0"))
            #expect(traces.lines.contains("dial start path=race lan=127.0.0.1:2 relay=relay.example.com"))
            link.close(); await fixture.stop()
        } catch { transport?.close(); await fixture.stop(); throw error }
    }
    private func request<T: Decodable & Sendable>(_ link: WebSocketTransport, connection: AuthorizedConnection, path: String) async throws -> T {
        let crypto = IdentityCryptography()
        let announcement = try await link.request("/v2/identity", method: "GET", as: SignedValue<HostAnnouncement>.self)
        try crypto.verify(announcement, domain: "host", publicKey: connection.host.publicKey)
        return try await link.request(path, method: "GET", authorization: { uri, bytes in
            let proof = RequestProof(epoch: announcement.value.epoch, hostID: connection.host.id,
                clientID: connection.grant.value.clientID, method: "GET", uri: uri,
                bodySHA256: crypto.digest(bytes), nonce: UUID().uuidString, timestamp: Int(Date().timeIntervalSince1970))
            return "CmuxV2 " + (try JSONEncoder().encode(crypto.sign(proof, domain: "request", privateKey: connection.privateKey))).base64EncodedString()
        }, as: T.self)
    }
}

private final class TraceLines: @unchecked Sendable {
    private let lock = NSLock(); private var values: [String] = []
    var lines: [String] { lock.withLock { values } }
    func append(_ line: String) { lock.withLock { values.append(line) } }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
