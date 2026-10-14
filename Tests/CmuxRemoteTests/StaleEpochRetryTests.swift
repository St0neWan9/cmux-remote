import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxRemoteClient

/// A restarted Bridge starts a new epoch, but a link that stayed up keeps the client's cached one. One
/// client lives across the restart here, as a phone does: it must recover on its own, and a write must
/// still reach the agent exactly once.
@Suite struct StaleEpochRetryTests {
    @Test func oneClientRecoversAcrossABridgeRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = BridgeState(directory: directory); try state.initialize()
        let workspace = "11111111-1111-1111-1111-111111111111", fixture = DurableMutationFixture(workspace: workspace)
        let key = IdentityCryptography().generatePrivateKey()
        var port = 0, client: RemoteClient?
        var epochs: [String] = []
        for iteration in 0..<2 {
            let authority = try state.authority(name: "Restarting host")
            epochs.append(authority.epoch)
            let service = SessionService(cmux: fixture, home: directory, transcriptRoots: [], mutations: MutationLedger(directory: directory))
            let ready = AsyncThrowingStream<Int, any Error>.makeStream(), requestedPort = port
            let server = Task {
                do { try await HTTPServer().run(host: "127.0.0.1", port: requestedPort, certificate: state.certificate, key: state.key,
                    router: BridgeRouter(service: service, authority: authority), onListening: { ready.continuation.yield($0); ready.continuation.finish() }) }
                catch { ready.continuation.finish(throwing: error); throw error }
            }
            var readyIterator = ready.stream.makeAsyncIterator(); port = try #require(await readyIterator.next())
            if client == nil {
                let bootstrap = try await authority.open(endpoint: .init(host: "127.0.0.1", port: port), workspaces: [workspace])
                let enrollment = try EnrollmentClient(bootstrap: bootstrap, privateKey: key, name: "Phone", kind: "iphone", capabilities: [.conversationRead, .conversationControl])
                _ = try await authority.submit(enrollment.request)
                try await authority.approve(requestID: enrollment.request.value.requestID, scope: .init(workspaces: [workspace], capabilities: [.conversationRead, .conversationControl]))
                client = try RemoteClient(connection: try enrollment.connection(from: await authority.status(enrollment.request).value))
                enrollment.close()
            }
            let phone = try #require(client)
            // A read signed under the epoch cached before the restart is rejected once, then retried.
            _ = try await phone.get("/v1/sessions", as: [SessionDescriptor].self)
            // The rejected attempt never ran, so the retried write is the only one.
            let receipt = try await phone.post("/v1/sessions/session/send", body: SendRequest(text: "turn \(iteration)"), as: MutationReceipt.self)
            #expect(receipt.accepted)
            #expect(await fixture.writes.count == iteration + 1)
            server.cancel(); try? await server.value
        }
        #expect(epochs[0] != epochs[1])
        client?.close()
    }
}
