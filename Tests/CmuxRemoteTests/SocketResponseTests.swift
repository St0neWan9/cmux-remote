import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

@Suite struct SocketResponseTests {
    @Test(arguments: [false, true])
    func closedResponseIsDistinctFromMalformedResponse(malformed: Bool) async throws {
        let directory = URL(fileURLWithPath: "/tmp/cmux-response-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("rpc.sock").path
        let fixture = try SocketResponseFixture(path: path, response: malformed ? Data("not-json\n".utf8) : nil)
        do {
            _ = try await UnixSocketClient(path: path).request("mirror.replay", params: [:])
            Issue.record("A lost or malformed response cannot succeed")
        } catch {
            #expect((error as? BridgeError)?.code == (malformed ? "invalid_response" : "outcome_unknown"))
        }
        let received = try await fixture.completion.value
        let rpc = try JSONDecoder().decode(JSONValue.self, from: received)
        #expect(rpc["method"].string == "mirror.replay")
    }
}
