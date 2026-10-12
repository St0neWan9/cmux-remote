import Foundation
import Network
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxRemoteClient

@Suite struct BonjourConnectionTests {
    @MainActor @Test func resolvedIPv6EndpointCanUseThePinnedHTTPSClient() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = BridgeState(directory: directory); try state.initialize()
        let authority = try state.authority(name: "IPv6 fixture")
        let service = SessionService(cmux: DemoCmux(transcript: directory.appendingPathComponent("unused.jsonl").path, project: directory.path), home: directory, transcriptRoots: [directory])
        let listening = AsyncThrowingStream<Int, any Error>.makeStream()
        let server = Task {
            do { try await HTTPServer().run(host: "::1", port: 0, certificate: state.certificate, key: state.key, router: BridgeRouter(service: service, token: state.token()), onListening: { listening.continuation.yield($0); listening.continuation.finish() }) }
            catch { listening.continuation.finish(throwing: error); throw error }
        }
        defer { server.cancel() }
        var iterator = listening.stream.makeAsyncIterator(); let port = try #require(await iterator.next())
        let peer = DiscoveredBridge(host: authority.host, service: .hostPort(host: .ipv6(.loopback), port: NWEndpoint.Port(rawValue: UInt16(port))!))
        let endpoint = try await BridgeDiscovery().resolve(peer)
        #expect(endpoint.host == "[::1]")
        let client = RemoteClient(pairing: try state.pairing(host: endpoint.host, port: endpoint.port)); defer { client.close() }
        _ = try await client.get("/v1/status", as: JSONValue.self)
        server.cancel(); try await server.value
    }
}
