import Foundation
import Testing
import ImageIO
import CoreGraphics
@testable import CmuxRemoteBridge
import CmuxRemoteCore
import CmuxRemoteClient

private actor HistoricalImageCmux: CmuxControlling {
    let transcript: String
    let project: String
    let workspace = "11111111-1111-1111-1111-111111111111"
    init(transcript: String, project: String) { self.transcript = transcript; self.project = project }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "vault.sessions": return .object(["sessions": .array(["one", "two"].map { .object(["session_id": .string($0), "agent": .string("claude"), "cwd": .string(project), "file": .string(transcript)]) })])
        case "chat.sessions.dump": return .object(["sessions": .array(["one", "two"].map { .object(["session_id": .string($0), "agent": .string("claude"), "workspace_id": .string($0 == "one" ? workspace : "33333333-3333-3333-3333-333333333333"), "surface_id": .string("22222222-2222-2222-2222-222222222222")]) })])
        default: return .object([:])
        }
    }
}

@Suite struct HistoricalImageTests {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAKklEQVR4nGPQyrtDU8QwasGoBaMWjFowasGoBaMWjFowasGoBaMWDBULAFSk0ExUjkswAAAAAElFTkSuQmCC")!
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cmux-image-history-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    private func transcript(_ rows: [[String: Any]]) throws -> Data { try rows.reduce(into: Data()) { $0.append(try JSONSerialization.data(withJSONObject: $1)); $0.append(10) } }
    private func inline() -> [String: Any] { ["type":"image", "source":["type":"base64", "media_type":"image/png", "data":png.base64EncodedString()]] }
    @Test func recordedReadImageAlsoResolvesItsMatchingAttachmentWithoutOpeningOutsideFiles() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let path = "/outside/private/clipboard-2026-10-12-122051-D40DBAF2.png"
        let file = root.appendingPathComponent("chat.jsonl")
        try transcript([
            ["type":"user", "uuid":"attachment", "message":["content":path + " Tell me the color"]],
            ["type":"assistant", "uuid":"read", "message":["content":[["type":"tool_use", "id":"read-call", "name":"Read", "input":["file_path":path]]]]],
            ["type":"user", "uuid":"result", "message":["content":[["type":"tool_result", "tool_use_id":"read-call", "content":[inline()]]]]]
        ]).write(to: file)
        let service = SessionService(cmux: HistoricalImageCmux(transcript: file.path, project: root.path), home: root.appendingPathComponent("home"), transcriptRoots: [root])
        let page = try await service.history(id: "one", beforeSeq: nil, limit: 100)
        #expect(page.images?.count == 2)
        for reference in page.images ?? [] {
            #expect(!reference.requiresProjectRead)
            let bytes = try await service.image(id: "one", referenceID: reference.id, generation: page.generation)
            #expect(bytes.count < 524_288 && bytes.prefix(3) == Data([0xff,0xd8,0xff]))
        }
    }
    @Test func inlineUserBlocksAndCodexDataURLsProduceOpaqueGenerationBoundReferences() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("chat.jsonl")
        let reader = TranscriptReader()
        for agent in ["claude", "codex"] {
            let row: [String:Any] = agent == "claude" ? ["type":"user", "uuid":"inline", "message":["content":[inline()]]] : ["type":"response_item", "payload":["type":"message", "role":"user", "content":[["type":"input_image", "image_url":"data:image/png;base64," + png.base64EncodedString()]]]]
            try transcript([row]).write(to: file, options: .atomic)
            let page = try await reader.history(path: file.path, agent: agent, beforeSeq: nil, limit: 100)
            let reference = try #require(page.images?.first)
            #expect(reference.id.count == 64 && reference.generation == page.generation && page.messages.contains { $0.id == reference.messageID })
            _ = try await reader.image(path: file.path, agent: agent, referenceID: reference.id, generation: page.generation)
            try transcript([row]).write(to: file, options: .atomic)
            do { _ = try await reader.image(path: file.path, agent: agent, referenceID: reference.id, generation: page.generation); Issue.record("Expected replaced transcript denial") }
            catch { #expect((error as? BridgeError)?.code == "stale_detail") }
        }
    }
    @Test func incompleteImageResultsDoNotBecomeReferencesAndUnknownIDsCannotReadAPath() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("chat.jsonl")
        let incomplete = try JSONSerialization.data(withJSONObject: ["type":"user", "uuid":"inline", "message":["content":[inline()]]])
        try (Data("{}\n".utf8) + incomplete).write(to: file)
        let reader = TranscriptReader(); let page = try await reader.history(path: file.path, agent: "claude", beforeSeq: nil, limit: 100)
        #expect(page.images?.isEmpty == true)
        for id in ["/etc/passwd", String(repeating:"a", count:64)] {
            do { _ = try await reader.image(path: file.path, agent: "claude", referenceID: id, generation: page.generation); Issue.record("Expected unrecorded image denial") }
            catch { #expect((error as? BridgeError)?.code == "image_unavailable") }
        }
    }
    @Test func projectImageReadsDenyTraversalSymlinksSecretsOutsidePathsAndOversize() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let reader = ProjectImageReader(policy: ProjectFilePolicy(home: root.deletingLastPathComponent().appendingPathComponent("owner-home-" + UUID().uuidString)))
        try png.write(to: root.appendingPathComponent("photo.png"))
        #expect(try reader.read(root: root.path, referencedPath: "photo.png") == png)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.png"), withDestinationURL: root.appendingPathComponent("photo.png"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".secrets"), withIntermediateDirectories: true)
        try png.write(to: root.appendingPathComponent(".secrets/photo.png"))
        try Data(repeating: 0, count: 1_048_577).write(to: root.appendingPathComponent("big.png"))
        for path in ["../photo.png", "link.png", ".secrets/photo.png", "/etc/photo.png", "big.png", "photo.png/child.png"] {
            do { _ = try reader.read(root: root.path, referencedPath: path); Issue.record("Expected denial for \(path)") }
            catch { #expect((error as? BridgeError)?.code == "file_forbidden" || error is CocoaError) }
        }
        let directory = root.appendingPathComponent("folder"); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("photo.png"))
        let alias = root.appendingPathComponent("alias"); try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        do { _ = try reader.read(root: root.path, referencedPath: "alias/photo.png"); Issue.record("Expected intermediate symlink denial") }
        catch { #expect((error as? BridgeError)?.code == "file_forbidden") }
    }
    @Test func decoderRejectsInvalidBytesAndAlwaysProducesBoundedStaticJPEG() throws {
        let projection = HistoricalImageProjection()
        let bytes = try projection.preview(png)
        let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg" && CGImageSourceGetCount(source) == 1)
        for bad in [Data(), Data("secret text".utf8), Data(repeating:0,count:4_194_305)] {
            do { _ = try projection.preview(bad); Issue.record("Expected invalid media denial") }
            catch { #expect((error as? BridgeError)?.code == "image_unavailable") }
        }
    }
    @Test func projectReferenceNeedsItsOwnCapabilityAndInlineBytesRecheckRevocation() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project"); try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let imageFile = project.appendingPathComponent("photo.png"); try png.write(to: imageFile)
        let file = root.appendingPathComponent("chat.jsonl")
        try transcript([["type":"assistant", "uuid":"read", "message":["content":[["type":"tool_use", "id":"read-call", "name":"Read", "input":["file_path":imageFile.path]]]]]]).write(to: file)
        let service = SessionService(cmux: HistoricalImageCmux(transcript: file.path, project: project.path), home: root.appendingPathComponent("home"), transcriptRoots: [root])
        let page = try await service.history(id:"one",beforeSeq:nil,limit:100); let reference = try #require(page.images?.first)
        #expect(reference.requiresProjectRead)
        let viewing = SessionAccess { capability, _ in if capability == .projectRead { throw BridgeError("scope_denied", "No project grant", status:403) } }
        do { _ = try await service.image(id:"one",referenceID:reference.id,generation:page.generation,access:viewing); Issue.record("Expected separate project authority") }
        catch { #expect((error as? BridgeError)?.code == "scope_denied") }
        #expect(try await service.image(id:"one",referenceID:reference.id,generation:page.generation).count < 524_288)
        try transcript([["type":"user", "uuid":"inline", "message":["content":[inline()]]]]).write(to:file,options:.atomic)
        let inlinePage = try await service.history(id:"one",beforeSeq:nil,limit:100); let inlineRef = try #require(inlinePage.images?.first)
        let revocation = HistoricalImageRevocation()
        let access = SessionAccess { _, _ in try await revocation.check() }
        do { _ = try await service.image(id:"one",referenceID:inlineRef.id,generation:inlinePage.generation,access:access); Issue.record("Expected final revocation check") }
        catch { #expect((error as? BridgeError)?.code == "scope_denied") }
    }
    @Test func reusedClipboardPathDoesNotReplaceEarlierRecordedAttachmentBytes() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("chat.jsonl")
        let path = "/outside/clipboard-2026-10-12-122051-D40DBAF2.png"
        let context = try #require(CGContext(data:nil,width:8,height:8,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red:1,green:0,blue:0,alpha:1); context.fill(CGRect(x:0,y:0,width:8,height:8))
        let red = try #require(context.makeImage()); let output = NSMutableData()
        let encoder = try #require(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, red, nil); #expect(CGImageDestinationFinalize(encoder))
        let second = output as Data
        let secondImage: [String:Any] = ["type":"image", "source":["type":"base64", "media_type":"image/png", "data":second.base64EncodedString()]]
        var rows: [[String:Any]] = []
        for (suffix, image) in [("one", inline()), ("two", secondImage)] {
            rows += [
                ["type":"user", "uuid":"attachment-" + suffix, "message":["content":path + " Inspect this image"]],
                ["type":"assistant", "uuid":"read-" + suffix, "message":["content":[["type":"tool_use", "id":"call-" + suffix, "name":"Read", "input":["file_path":path]]]]],
                ["type":"user", "uuid":"result-" + suffix, "message":["content":[["type":"tool_result", "tool_use_id":"call-" + suffix, "content":[image]]]]]
            ]
        }
        try transcript(rows).write(to:file)
        let reader = TranscriptReader(); let page = try await reader.history(path:file.path,agent:"claude",beforeSeq:nil,limit:100)
        let firstReference = try #require(page.images?.first { $0.messageID == "attachment-one" })
        let first = try await reader.image(path:file.path,agent:"claude",referenceID:firstReference.id,generation:page.generation)
        if case .recorded(let bytes) = first.source { #expect(bytes == png) } else { Issue.record("Expected first turn's recorded image") }
        let nextReference = try #require(page.images?.first { $0.messageID == "attachment-two" })
        let next = try await reader.image(path:file.path,agent:"claude",referenceID:nextReference.id,generation:page.generation)
        if case .recorded(let bytes) = next.source { #expect(bytes == second) } else { Issue.record("Expected later turn's recorded image") }
    }
    @Test func projectReadMustStillBeGrantedAfterDecoding() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project"); try FileManager.default.createDirectory(at:project,withIntermediateDirectories:true)
        let path = project.appendingPathComponent("photo.png"); try png.write(to:path)
        let file = root.appendingPathComponent("chat.jsonl")
        try transcript([["type":"assistant", "uuid":"read", "message":["content":[["type":"tool_use", "id":"call", "name":"Read", "input":["file_path":path.path]]]]]]).write(to:file)
        let service = SessionService(cmux:HistoricalImageCmux(transcript:file.path,project:project.path),home:root.appendingPathComponent("home"),transcriptRoots:[root])
        let page = try await service.history(id:"one",beforeSeq:nil,limit:100); let reference = try #require(page.images?.first)
        let downgrade = HistoricalProjectDowngrade()
        let access = SessionAccess { capability, _ in try await downgrade.check(capability) }
        do { _ = try await service.image(id:"one",referenceID:reference.id,generation:page.generation,access:access); Issue.record("Project image escaped after its project-read grant was removed") }
        catch { #expect((error as? BridgeError)?.code == "scope_denied") }
    }
    @Test func signedPinnedBinaryClientPreservesSessionScopeAndRevocation() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let state = BridgeState(directory: root.appendingPathComponent("state")); try state.initialize(); let authority = try state.authority(name:"Images")
        let file = root.appendingPathComponent("chat.jsonl"); try transcript([["type":"user", "uuid":"inline", "message":["content":[inline()]]]]).write(to:file)
        let cmux = HistoricalImageCmux(transcript:file.path,project:root.path)
        let service = SessionService(cmux:cmux,home:root.appendingPathComponent("home"),transcriptRoots:[root])
        let listening = AsyncThrowingStream<Int,any Error>.makeStream()
        let server = Task {
            do { try await HTTPServer().run(host:"127.0.0.1",port:0,certificate:state.certificate,key:state.key,router:BridgeRouter(service:service,authority:authority),onListening:{ listening.continuation.yield($0); listening.continuation.finish() }) }
            catch { listening.continuation.finish(throwing:error); throw error }
        }
        defer { server.cancel() }
        var ports = listening.stream.makeAsyncIterator(); let port = try #require(try await ports.next())
        let bootstrap = try await authority.open(endpoint:BridgeEndpoint(host:"127.0.0.1",port:port),workspaces:[await cmux.workspace])
        let enrollment = try EnrollmentClient(bootstrap:bootstrap,privateKey:IdentityCryptography().generatePrivateKey(),name:"Photo",kind:"iphone",capabilities:[.conversationRead]); defer { enrollment.close() }
        _ = try await authority.submit(enrollment.request); try await authority.approve(requestID:enrollment.request.value.requestID,scope:enrollment.request.value.scope)
        let connection = try enrollment.connection(from:await authority.status(enrollment.request).value)
        let client = try RemoteClient(connection:connection); defer { client.close() }
        let page = try await client.get("/v1/sessions/one/history",as:ConversationSnapshot.self)
        let reference = try #require(page.images?.first)
        #expect(try await client.image(sessionID:"one",reference:reference).count < 524_288)
        do { _ = try await client.image(sessionID:"two",reference:reference); Issue.record("Expected unapproved session denial") }
        catch { #expect((error as? BridgeError)?.code == "scope_denied") }
        try await authority.revoke(clientID:connection.grant.value.clientID)
        do { _ = try await client.image(sessionID:"one",reference:reference); Issue.record("Expected revoked read denial") }
        catch { #expect((error as? BridgeError)?.code == "unauthorized") }
        server.cancel(); try await server.value
    }
}

private actor HistoricalImageRevocation {
    private var checks = 0
    func check() throws { checks += 1; if checks == 2 { throw BridgeError("scope_denied", "Revoked during decoding", status:403) } }
}

private actor HistoricalProjectDowngrade {
    private var projectChecks = 0
    func check(_ capability: ClientCapability) throws {
        if capability == .projectRead { projectChecks += 1; if projectChecks > 2 { throw BridgeError("scope_denied", "Project grant removed after file read", status:403) } }
    }
}
