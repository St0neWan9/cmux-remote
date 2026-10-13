import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxRemoteClient

/// Task-owned TLS listener and enrolled fixture; never touches installed cmux or provider processes.
struct LinkIntegrationFixture: Sendable {
    let root: URL
    let authority: ConnectionAuthority
    let cmux: DemoCmux
    let server: Task<Void, any Error>
    let connection: AuthorizedConnection
    let transcript: URL
    let enrollmentRequest: SignedValue<EnrollmentRequest>
    static func create(text: String = "Ready", recordCount: Int = 1) async throws -> LinkIntegrationFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = BridgeState(directory: root); try state.initialize()
        let authority = try state.authority(name: "Link fixture")
        let transcript = root.appendingPathComponent("history.jsonl")
        var bytes = Data()
        for index in 0..<recordCount {
            let record: JSONValue = .object(["type": .string("assistant"), "uuid": .string("ready-" + String(index)), "message": .object(["content": .array([.object(["type": .string("text"), "text": .string(text)])])])])
            bytes.append(try JSONEncoder().encode(record)); bytes.append(10)
        }
        try bytes.write(to: transcript)
        let cmux = DemoCmux(transcript: transcript.path, project: root.path)
        let service = SessionService(cmux: cmux, home: root.appendingPathComponent("home"), transcriptRoots: [root])
        let ready = AsyncThrowingStream<Int, any Error>.makeStream()
        let server = Task {
            do { try await HTTPServer().run(host: "127.0.0.1", port: 0, certificate: state.certificate, key: state.key, router: BridgeRouter(service: service, authority: authority), onListening: { ready.continuation.yield($0); ready.continuation.finish() }) }
            catch { ready.continuation.finish(throwing: error); throw error }
        }
        do {
            var iterator = ready.stream.makeAsyncIterator(); let port = try #require(try await iterator.next())
            let workspace = "11111111-1111-1111-1111-111111111111"
            let bootstrap = try await authority.open(endpoint: BridgeEndpoint(host: "127.0.0.1", port: port), workspaces: [workspace])
            let enrollment = try EnrollmentClient(bootstrap: bootstrap, privateKey: IdentityCryptography().generatePrivateKey(), name: "Fixture client", kind: "iphone")
            defer { enrollment.close() }
            _ = try await enrollment.submit()
            try await authority.approve(requestID: enrollment.request.value.requestID, scope: enrollment.request.value.scope)
            let connection = try enrollment.connection(from: await enrollment.status())
            return LinkIntegrationFixture(root: root, authority: authority, cmux: cmux, server: server, connection: connection, transcript: transcript, enrollmentRequest: enrollment.request)
        } catch { server.cancel(); _ = try? await server.value; try? FileManager.default.removeItem(at: root); throw error }
    }
    func stop() async { server.cancel(); _ = try? await server.value; try? FileManager.default.removeItem(at: root) }
}
