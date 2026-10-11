import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

private actor FakeCmux: CmuxControlling {
    var sendCount = 0
    var screenReadCount = 0
    let validBinding: Bool
    let failSend: Bool
    init(validBinding: Bool = true, failSend: Bool = false) { self.validBinding = validBinding; self.failSend = failSend }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "vault.sessions": return .object(["sessions": .array([.object(["session_id": .string("session"), "agent": .string("claude"), "title": .string("Task")])])])
        case "chat.sessions.dump": return .object(["sessions": .array([.object(["session_id": .string("session"), "agent": .string("claude"), "workspace_id": .string("workspace"), "surface_id": .string("surface"), "state": .string("idle")])])])
        case "surface.input_state": return .object(["agent": .bool(validBinding), "workspace_id": .string("workspace"), "surface_id": .string("surface"), "blocks_typing": .bool(false)])
        case "mobile.chat.send":
            sendCount += 1
            if failSend { throw BridgeError("outcome_unknown", "Response lost", status: 504) }
            return .object(["submitted": .bool(true)])
        case "surface.read_text": screenReadCount += 1; return .object(["text": .string("Other agent output")])
        default: return .object([:])
        }
    }
}

@Suite struct ServiceTests {
    @Test func successfulSendIsNotRepeatedForSameOperation() async throws {
        let cmux = FakeCmux(); let home = URL(fileURLWithPath: "/example/home")
        let service = SessionService(cmux: cmux, home: home, transcriptRoots: [])
        let request = SendRequest(text: "Test")
        _ = try await service.send(id: "session", request: request)
        _ = try await service.send(id: "session", request: request)
        #expect(await cmux.sendCount == 1)
    }
    @Test func staleBindingNeverTypesIntoAnotherAgent() async {
        let cmux = FakeCmux(validBinding: false); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        do { _ = try await service.send(id: "session", request: SendRequest(text: "Test")); Issue.record("Expected stale binding rejection") }
        catch { #expect((error as? BridgeError)?.code == "stale_binding") }
        #expect(await cmux.sendCount == 0)
    }
    @Test func uncertainWriteIsNotRetried() async {
        let cmux = FakeCmux(failSend: true); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        let request = SendRequest(text: "Test")
        for _ in 0..<2 {
            do { _ = try await service.send(id: "session", request: request); Issue.record("Expected unknown outcome") }
            catch { #expect((error as? BridgeError)?.code == "outcome_unknown") }
        }
        #expect(await cmux.sendCount == 1)
    }
    @Test func unauthorizedHTTPDoesNotReachCmux() async throws {
        let cmux = FakeCmux(); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        let router = BridgeRouter(service: service, token: String(repeating: "a", count: 64))
        let result = await router.respond(method: "POST", uri: "/v1/sessions/session/send", authorization: nil, body: try JSONEncoder().encode(SendRequest(text: "Test")))
        #expect(result.0 == 401)
        #expect(await cmux.sendCount == 0)
    }
    @Test func endedSessionNeverReadsAReusedTerminalPreview() async throws {
        let cmux = FakeCmux(); let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/example/home"), transcriptRoots: [])
        _ = try await service.sessions()
        await service.acceptEvent(.object(["type": .string("event"), "category": .string("agent"), "workspace_id": .string("workspace"), "surface_id": .string("surface"), "payload": .object(["session_id": .string("session"), "hook_event_name": .string("SessionEnd")])]))
        let preview = try await service.preview(id: "session")
        #expect(!preview.available)
        #expect(await cmux.screenReadCount == 0)
    }
}
