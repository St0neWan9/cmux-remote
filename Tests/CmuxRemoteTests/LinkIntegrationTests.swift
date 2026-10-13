import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
@testable import CmuxRemoteClient

@Suite struct LinkIntegrationTests {
    @Test func largeResponseAndConcurrentReadsRemainOrderedOverWSS() async throws {
        let fixture = try await LinkIntegrationFixture.create(text: String(repeating: "data ", count: 24_000), recordCount: 8)
        let client = try RemoteClient(connection: fixture.connection)
        do {
            let history = try await client.get("/v1/sessions/demo-session/history", as: ConversationSnapshot.self)
            #expect(history.messages.count == 8)
            try await withThrowingTaskGroup(of: Int.self) { group in
                for _ in 0..<6 { group.addTask { try await client.get("/v1/sessions", as: [SessionDescriptor].self).count } }
                for try await count in group { #expect(count == 1) }
            }
            let send = SendRequest(text: "Once")
            let first = try await client.post("/v1/sessions/demo-session/send", body: send, as: MutationReceipt.self)
            let repeatSend = try await client.post("/v1/sessions/demo-session/send", body: send, as: MutationReceipt.self)
            #expect(first.operationID == repeatSend.operationID)
            #expect(try await client.get("/v1/sessions/demo-session/history", as: ConversationSnapshot.self).messages.count == 10)
            client.close(); await fixture.stop()
        } catch { client.close(); await fixture.stop(); throw error }
    }
    @Test func subscriptionSendsInitialInvalidationAndStopsOnRevocation() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let client = try RemoteClient(connection: fixture.connection)
        do {
            let events = client.changes(paths: ["/v1/sessions/demo-session/history"])
            var iterator = events.makeAsyncIterator()
            #expect(await iterator.next() != nil)
            _ = try await client.post("/v1/sessions/demo-session/send", body: SendRequest(text: "Append"), as: MutationReceipt.self)
            #expect(await iterator.next() != nil)
            try await fixture.authority.revoke(clientID: fixture.connection.grant.value.clientID)
            #expect(await iterator.next() != nil)
            #expect(await iterator.next() == nil)
            client.close(); await fixture.stop()
        } catch { client.close(); await fixture.stop(); throw error }
    }
    @Test func changedHostKeyCannotEstablishAnEncryptedResourceLink() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        var host = fixture.connection.host
        let crypto = IdentityCryptography(); host.publicKey = try crypto.publicKey(privateKey: crypto.generatePrivateKey()); host.id = try crypto.identityID(publicKey: host.publicKey)
        let transport = WebSocketTransport(host: host, key: fixture.connection.privateKey, endpoint: fixture.connection.endpoint)
        do {
            _ = try await transport.request("/v2/identity", method: "GET", as: JSONValue.self)
            Issue.record("A wrong host key must not establish the link")
        } catch {}
        transport.close(); await fixture.stop()
    }
}
