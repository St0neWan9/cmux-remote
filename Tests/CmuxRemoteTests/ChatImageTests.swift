import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

private actor ImageCmux: CmuxControlling {
    var deliveries: [[String: JSONValue]] = []
    let valid: Bool
    let blocksTyping: Bool
    let fail: Bool
    init(valid: Bool = true, blocksTyping: Bool = false, fail: Bool = false) { self.valid = valid; self.blocksTyping = blocksTyping; self.fail = fail }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "vault.sessions": return .object(["sessions": .array([.object(["session_id": .string("session"), "agent": .string("claude")])])])
        case "chat.sessions.dump": return .object(["sessions": .array([.object(["session_id": .string("session"), "agent": .string("claude"), "workspace_id": .string("workspace"), "surface_id": .string("surface"), "state": .string("idle")])])])
        case "surface.input_state": return .object(["agent": .bool(valid), "workspace_id": .string("workspace"), "surface_id": .string("surface"), "blocks_typing": .bool(blocksTyping)])
        case "mobile.chat.send": deliveries.append(params); if fail { throw BridgeError("outcome_unknown", "Lost response", status: 504) }
        default: break
        }
        return .object(["accepted": .bool(true)])
    }
}

@Suite struct ChatImageTests {
    private let blue = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAKklEQVR4nGPQyrtDU8QwasGoBaMWjFowasGoBaMWjFowasGoBaMWDBULAFSk0ExUjkswAAAAAElFTkSuQmCC")!
    private func service(_ cmux: ImageCmux) -> SessionService { SessionService(cmux: cmux, home: URL(fileURLWithPath: "/fixture/home"), transcriptRoots: []) }
    private func image(id: UUID = UUID(), format: String = "png", data: Data? = nil, name: String = "test.png") -> ChatImagePayload {
        ChatImagePayload(id: id, fileName: name, format: format, data: data ?? blue)
    }
    @Test func imageOnlyAndMixedSendsUseOnlyTheFixedExistingChatMethod() async throws {
        let cmux = ImageCmux(); let service = service(cmux)
        let first = image(); let second = image(name: "second.png")
        _ = try await service.send(id: "session", request: SendRequest(text: "", attachments: [first]))
        _ = try await service.send(id: "session", request: SendRequest(text: "Identify these", attachments: [first, second]))
        let deliveries = await cmux.deliveries
        #expect(deliveries.count == 2)
        #expect(deliveries[0]["text"]?.string == "")
        #expect(deliveries[0]["session_id"]?.string == "session")
        #expect(deliveries[0]["attachments"]?.array?.first?["data_b64"].string == first.dataBase64)
        #expect(deliveries[1]["attachments"]?.array?.count == 2)
        #expect(Set(deliveries[1]["attachments"]?.array?.first?.object?.keys.map { $0 } ?? []) == ["data_b64", "format"])
    }
    @Test func malformedMismatchedOversizedOrUnsafeMetadataNeverReachesTheAgent() async throws {
        let cases = [image(data: Data("not an image".utf8)), image(format: "jpeg"), image(format: "../../file"),
                     image(data: Data(repeating: 1, count: 524_289)), image(name: "../secret.png")]
        for invalid in cases {
            let cmux = ImageCmux()
            do { _ = try await service(cmux).send(id: "session", request: SendRequest(text: "Test", attachments: [invalid])); Issue.record("Expected image rejection") }
            catch { #expect((error as? BridgeError)?.code == "invalid_image") }
            #expect(await cmux.deliveries.isEmpty)
        }
    }
    @Test func countDuplicateIdentityAndCombinedPayloadLimitsAreEnforced() async throws {
        let duplicate = image()
        let countCases = [[duplicate, duplicate], (0..<5).map { image(name: "\($0).png") }]
        for images in countCases {
            let cmux = ImageCmux()
            do { _ = try await service(cmux).send(id: "session", request: SendRequest(text: "Test", attachments: images)); Issue.record("Expected bounded image count") }
            catch { #expect((error as? BridgeError)?.code == "invalid_image") }
            #expect(await cmux.deliveries.isEmpty)
        }
        let padded = blue + Data(repeating: 0, count: 300_000)
        let cmux = ImageCmux()
        do { _ = try await service(cmux).send(id: "session", request: SendRequest(text: "Test", attachments: (0..<3).map { image(data: padded, name: "\($0).png") })); Issue.record("Expected combined limit") }
        catch { #expect((error as? BridgeError)?.code == "too_large") }
        #expect(await cmux.deliveries.isEmpty)
    }
    @Test(arguments: [(false, false, "stale_binding"), (true, true, "input_busy")])
    func imageDeliveryRetainsExistingBindingAndDesktopDraftProtection(_ valid: Bool, _ busy: Bool, _ code: String) async {
        let cmux = ImageCmux(valid: valid, blocksTyping: busy)
        do { _ = try await service(cmux).send(id: "session", request: SendRequest(text: "Test", attachments: [image()])); Issue.record("Expected protected target") }
        catch { #expect((error as? BridgeError)?.code == code) }
        #expect(await cmux.deliveries.isEmpty)
    }
    @Test func readonlyDeviceCannotUploadToTheExistingSession() async {
        let cmux = ImageCmux(); let denied = SessionAccess(principalID: "readonly") { _, _ in throw BridgeError("scope_denied", "Read-only", status: 403) }
        do { _ = try await service(cmux).send(id: "session", request: SendRequest(text: "", attachments: [image()]), access: denied); Issue.record("Expected read-only denial") }
        catch { #expect((error as? BridgeError)?.code == "scope_denied") }
        #expect(await cmux.deliveries.isEmpty)
    }
    @Test func lostImageReceiptIsNotRetriedAndChangingAnImageConflicts() async throws {
        let cmux = ImageCmux(fail: true); let service = service(cmux)
        let request = SendRequest(text: "Image", attachments: [image()])
        for _ in 0..<2 {
            do { _ = try await service.send(id: "session", request: request); Issue.record("Expected unknown receipt") }
            catch { #expect((error as? BridgeError)?.code == "outcome_unknown") }
        }
        do { _ = try await service.send(id: "session", request: SendRequest(text: request.text, operationID: request.operationID, attachments: [image(name: "replacement.png")])); Issue.record("Expected image identity conflict") }
        catch { #expect((error as? BridgeError)?.code == "operation_conflict") }
        #expect(await cmux.deliveries.count == 1)
    }
    @Test func textOnlyWireRequestsRemainBackwardCompatible() throws {
        let uuid = UUID()
        let legacy = Data("{\"text\":\"Legacy\",\"operation_id\":\"\(uuid.uuidString)\"}".utf8)
        let request = try JSONDecoder().decode(SendRequest.self, from: legacy)
        #expect(request.text == "Legacy" && request.operationID == uuid && request.attachments.isEmpty)
        let withImage = SendRequest(text: "Image", attachments: [image()])
        #expect(try JSONDecoder().decode(SendRequest.self, from: JSONEncoder().encode(withImage)).attachments.first?.dataBase64 == image().dataBase64)
    }
}
