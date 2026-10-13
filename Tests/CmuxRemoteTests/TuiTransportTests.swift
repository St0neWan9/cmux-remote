import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

@Suite struct TuiTransportTests {
    private func directory() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/cr-wire-" + UUID().uuidString.prefix(8)); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]); return url
    }
    @Test func publicEnvelopeIsCorrelatedAndCarriesNoDesktopCapability() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("control.sock").path
        let reply: JSONValue = .object(["protocol": .string("cmux.protocol/2"), "type": .string("response"), "id": .string("fixture"), "ok": .bool(true), "result": .object(["ok": .bool(true)])])
        var data = try JSONEncoder().encode(reply); data.append(10)
        let fixture = try SocketResponseFixture(path: path, response: data); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        let result = try await TuiResourceSocketClient(path: path, requestID: { "fixture" }).resource("terminal.input.keys", params: ["keys": .array([.string("escape")])], idempotencyKey: "operation")
        #expect(result["ok"].bool == true)
        let request = try JSONDecoder().decode(JSONValue.self, from: await fixture.completion.value)
        #expect(request["protocol"].string == "cmux.protocol/2"); #expect(request["operation"].string == "terminal.input.keys")
        #expect(request["method"] == .null); #expect(request["idempotency_key"].string == "operation")
    }
    @Test(arguments: ["wrong-id", "wrong-protocol"])
    func mismatchedResponsesCannotConfirmAWrite(_ kind: String) async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("control.sock").path
        let reply: JSONValue = .object(["protocol": .string(kind == "wrong-protocol" ? "12" : "cmux.protocol/2"), "type": .string("response"), "id": .string(kind == "wrong-id" ? "unrelated" : "fixture"), "ok": .bool(true), "result": .object([:])])
        var data = try JSONEncoder().encode(reply); data.append(10)
        let fixture = try SocketResponseFixture(path: path, response: data); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        await #expect(throws: BridgeError.self) { _ = try await TuiResourceSocketClient(path: path, requestID: { "fixture" }).resource("session.snapshot", params: [:], idempotencyKey: nil) }
        _ = try await fixture.completion.value
    }
    @Test func discoveryDoesNotFollowSocketSymlinksOrAcceptPermissiveSockets() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real.sock"), link = root.appendingPathComponent("link.sock")
        let fixture = try SocketResponseFixture(path: real.path, response: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: real.path)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let discovered = try TuiSocketDiscovery(directories: [root]).sockets()
        #expect(discovered.count == 1)
        #expect(discovered.first.map { URL(fileURLWithPath: $0).lastPathComponent } == real.lastPathComponent)
        await #expect(throws: BridgeError.self) { _ = try await TuiResourceSocketClient(path: link.path).resource("session.snapshot", params: [:], idempotencyKey: nil) }
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: real.path)
        #expect(try TuiSocketDiscovery(directories: [root]).sockets().isEmpty)
        // Consume the listener using the existing desktop transport after discovery assertions.
        _ = try? await UnixSocketClient(path: real.path).request("system.ping", params: [:]); _ = try await fixture.completion.value
    }
}
