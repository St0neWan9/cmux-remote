import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge
@testable import CmuxRemoteClient

/// After a Bridge restart a client's cached epoch is stale. A subscription signed with it must be refused on its
/// own: closing the whole link made the client redial and resubscribe under the same epoch without end.
@Suite struct LinkStaleSubscriptionTests {
    @Test(.timeLimit(.minutes(1)))
    func aStaleEpochSubscriptionIsRefusedWithoutClosingTheLink() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        var raw: LinkRawConnection?
        do {
            var connection = try await LinkRawConnection.connect(fixture.connection); raw = connection
            let crypto = IdentityCryptography(), path = "/v2/sessions/demo-session/history", id = UUID().uuidString
            let stale = RequestProof(epoch: UUID().uuidString, hostID: fixture.connection.host.id, clientID: fixture.connection.grant.value.clientID, method: "GET", uri: path,
                                     bodySHA256: crypto.digest(Data()), nonce: UUID().uuidString, timestamp: Int(Date().timeIntervalSince1970))
            let authorization = "CmuxV2 " + (try JSONEncoder().encode(crypto.sign(stale, domain: "request", privateKey: fixture.connection.privateKey))).base64EncodedString()
            try await connection.socket.send(connection.cipher.seal(LinkFrame(kind: "subscribe", id: id, method: "GET", uri: path, authorization: authorization)))
            let refusal = try await connection.next()
            #expect(refusal.id == id); #expect(refusal.kind == "event"); #expect(refusal.status == 401); #expect(refusal.final == true)
            #expect(refusal.data.map { String(decoding: $0, as: UTF8.self) } == "invalid_proof")
            // The same link still answers a correctly signed request.
            let read = try await connection.read("/v2/sessions", connection: fixture.connection)
            let answer = try await connection.next()
            #expect(answer.id == read); #expect(answer.status == 200)
            connection.socket.close(); await fixture.stop()
        } catch { raw?.socket.close(); await fixture.stop(); throw error }
    }
}
