import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxRemoteClient

@Suite struct DurableMutationHTTPTests {
    @Test(arguments: [false, true])
    func signedClientKeepsItsGrantAndMutationIdentityAcrossHTTPSRestart(failed: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = BridgeState(directory: directory); try state.initialize()
        let workspace = "11111111-1111-1111-1111-111111111111", fixture = DurableMutationFixture(workspace: workspace)
        if failed { await fixture.failWrites() }
        let request = SendRequest(text: "Submit once across restart"), key = IdentityCryptography().generatePrivateKey()
        var port = 0, saved: AuthorizedConnection?
        for iteration in 0..<2 {
            let authority = try state.authority(name: "Durable host")
            let service = SessionService(cmux: fixture, home: directory, transcriptRoots: [], mutations: MutationLedger(directory: directory))
            let ready = AsyncThrowingStream<Int, any Error>.makeStream(), requestedPort = port
            let server = Task {
                do { try await HTTPServer().run(host: "127.0.0.1", port: requestedPort, certificate: state.certificate, key: state.key,
                    router: BridgeRouter(service: service, authority: authority), onListening: { ready.continuation.yield($0); ready.continuation.finish() }) }
                catch { ready.continuation.finish(throwing: error); throw error }
            }
            defer { server.cancel() }
            var readyIterator = ready.stream.makeAsyncIterator(); port = try #require(await readyIterator.next())
            if saved == nil {
                let bootstrap = try await authority.open(endpoint: .init(host: "127.0.0.1", port: port), workspaces: [workspace])
                let enrollment = try EnrollmentClient(bootstrap: bootstrap, privateKey: key, name: "Phone", kind: "iphone", capabilities: [.conversationRead, .conversationControl])
                defer { enrollment.close() }
                _ = try await authority.submit(enrollment.request)
                try await authority.approve(requestID: enrollment.request.value.requestID, scope: .init(workspaces: [workspace], capabilities: [.conversationRead, .conversationControl]))
                saved = try enrollment.connection(from: await authority.status(enrollment.request).value)
            }
            let connection = try #require(saved), client = try RemoteClient(connection: connection)
            defer { client.close() }
            if failed {
                do { _ = try await client.post("/v1/sessions/session/send", body: request, as: MutationReceipt.self); Issue.record("Expected unknown outcome") }
                catch { #expect((error as? BridgeError)?.code == "outcome_unknown") }
            } else {
                let receipt = try await client.post("/v1/sessions/session/send", body: request, as: MutationReceipt.self)
                #expect(receipt.operationID == request.operationID && receipt.accepted)
            }
            #expect(await fixture.writes.count == 1)
            if iteration == 1 {
                let conflict = SendRequest(text: "Different input", operationID: request.operationID)
                do { _ = try await client.post("/v1/sessions/session/send", body: conflict, as: MutationReceipt.self); Issue.record("Expected conflict") }
                catch { #expect((error as? BridgeError)?.code == "operation_conflict") }
                try await authority.revoke(clientID: connection.grant.value.clientID)
                await #expect(throws: BridgeError.self) { _ = try await client.post("/v1/sessions/session/send", body: request, as: MutationReceipt.self) }
                #expect(await fixture.writes.count == 1)
            }
            client.close(); server.cancel(); try await server.value
        }
    }
}
