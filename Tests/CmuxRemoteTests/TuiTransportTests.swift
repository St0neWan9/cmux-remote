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
    private func streamLines(_ items: Int, stream: String = "stream_a", end: String? = "completed", ok: Bool = true) throws -> Data {
        var lines: [JSONValue] = [.object(["protocol": .string("cmux.protocol/2"), "type": .string("response"), "id": .string("fixture"), "ok": .bool(ok),
                                           "result": .object(["stream_id": .string("stream_a")]), "error": .object(["code": .string("cursor.invalid")])])]
        if ok {
            for index in 1...max(items, 1) where items > 0 {
                lines.append(.object(["type": .string("stream_item"), "stream_id": .string(stream), "item": .object(["sequence": .string(String(index))]),
                                      "cursor": .object(["generation": .string("session_a"), "revision": .string(String(index * 10))])]))
            }
            if let end { lines.append(.object(["type": .string("stream_end"), "stream_id": .string("stream_a"), "reason": .string(end), "cursor": .object(["generation": .string("session_a"), "revision": .string("99")])])) }
        }
        var data = Data(); for line in lines { data.append(try JSONEncoder().encode(line)); data.append(10) }; return data
    }
    private func read(_ response: Data, limit: Int) async throws -> TuiStreamRead {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("control.sock").path
        let fixture = try SocketResponseFixture(path: path, response: response); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        defer { _ = fixture }
        return try await TuiResourceSocketClient(path: path, timeout: .seconds(2), requestID: { "fixture" }).stream("session.journal.subscribe", params: [:], limit: limit)
    }
    @Test func aBoundedStreamReadStopsAtItsLimitAndResumesFromTheLastItem() async throws {
        let whole = try await read(try streamLines(3), limit: 10)
        #expect(whole.items.count == 3); #expect(whole.complete); #expect(whole.cursor["revision"].string == "99")
        let cut = try await read(try streamLines(3), limit: 2)
        #expect(cut.items.count == 2); #expect(!cut.complete); #expect(cut.cursor["revision"].string == "20")
        let empty = try await read(try streamLines(0), limit: 10)
        #expect(empty.items.isEmpty); #expect(empty.complete); #expect(empty.cursor["revision"].string == "99")
    }
    @Test func refusedInterleavedOrAbortedStreamsAreNeverTrusted() async throws {
        await #expect(throws: BridgeError.self) { _ = try await read(try streamLines(0, ok: false), limit: 10) }
        await #expect(throws: BridgeError.self) { _ = try await read(try streamLines(2, stream: "stream_b"), limit: 10) }
        await #expect(throws: BridgeError.self) { _ = try await read(try streamLines(2, end: "overflow"), limit: 10) }
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
