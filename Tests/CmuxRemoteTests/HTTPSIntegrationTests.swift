import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxRemoteClient

@Suite struct HTTPSIntegrationTests {
    @Test func pinnedClientRunsHistoryAndSendWithoutAProviderConnection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = BridgeState(directory: directory); try state.initialize()
        let transcript = directory.appendingPathComponent("conversation.jsonl")
        try Data((#"{"type":"user","uuid":"initial","message":{"content":"Hello"}}"# + "\n").utf8).write(to: transcript)
        let cmux = DemoCmux(transcript: transcript.path, project: directory.path)
        let service = SessionService(cmux: cmux, home: directory.appendingPathComponent("home"), transcriptRoots: [directory])
        let listening = AsyncStream<Int>.makeStream()
        let server = Task {
            try await HTTPServer().run(host: "127.0.0.1", port: 0, certificate: state.certificate, key: state.key, router: BridgeRouter(service: service, token: state.token()), onListening: { listening.continuation.yield($0); listening.continuation.finish() })
        }
        defer { server.cancel() }
        var iterator = listening.stream.makeAsyncIterator()
        let port = try #require(await iterator.next())
        let pairing = try state.pairing(host: "127.0.0.1", port: port)
        let client = RemoteClient(pairing: pairing); defer { client.close() }
        let sessions = try await client.get("/v1/sessions", as: [SessionDescriptor].self)
        #expect(sessions.count == 1)
        let initial = try await client.get("/v1/sessions/demo-session/history", as: ConversationSnapshot.self)
        #expect(initial.messages.count == 1)
        let request = SendRequest(text: "Review this")
        _ = try await client.post("/v1/sessions/demo-session/send", body: request, as: MutationReceipt.self)
        _ = try await client.post("/v1/sessions/demo-session/send", body: request, as: MutationReceipt.self)
        let next = try await client.get("/v1/sessions/demo-session/history", as: ConversationSnapshot.self)
        #expect(next.messages.count == 3)

        let badToken = try PairingConfiguration(host: pairing.host, port: port, token: String(repeating: "x", count: 64), certificateSHA256: pairing.certificateSHA256)
        let unauthorized = RemoteClient(pairing: badToken); defer { unauthorized.close() }
        do { _ = try await unauthorized.get("/v1/status", as: JSONValue.self); Issue.record("Expected unauthorized") }
        catch { #expect((error as? BridgeError)?.code == "unauthorized") }

        let badPin = try PairingConfiguration(host: pairing.host, port: port, token: pairing.token, certificateSHA256: String(repeating: "0", count: 64))
        let untrusted = RemoteClient(pairing: badPin); defer { untrusted.close() }
        do { _ = try await untrusted.get("/v1/status", as: JSONValue.self); Issue.record("Expected certificate rejection") }
        catch { #expect(error is URLError) }
        server.cancel(); _ = try await server.value
    }
}
