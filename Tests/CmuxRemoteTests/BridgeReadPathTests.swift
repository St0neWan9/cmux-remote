import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// A local cmux stand-in that counts the expensive reads a subscription tick must not repeat.
private actor ReadPathCmux: CmuxControlling {
    let root: URL
    let transcript: URL
    let unscopedTranscript: URL
    let workspace = "11111111-1111-1111-1111-111111111111"
    let otherWorkspace = "33333333-3333-3333-3333-333333333333"
    let surface = "22222222-2222-2222-2222-222222222222"
    /// One per full discovery: `vault.sessions` is the first of the three daemon reads each one makes.
    private(set) var discoveries = 0
    init(root: URL) {
        self.root = root
        transcript = root.appendingPathComponent("scoped.jsonl")
        unscopedTranscript = root.appendingPathComponent("unscoped.jsonl")
    }
    /// One parseable transcript record, in the shape the Claude parser reads.
    static func transcriptLine(_ id: String, _ text: String) -> Data {
        var line = try! JSONEncoder().encode(JSONValue.object(["type": .string("assistant"), "uuid": .string(id), "message": .object(["content": .array([.object(["type": .string("text"), "text": .string(text)])])])]))
        line.append(10)
        return line
    }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "vault.sessions":
            discoveries += 1
            return .object(["sessions": .array([
                .object(["session_id": .string("scoped"), "agent": .string("claude"), "title": .string("Scoped"), "cwd": .string(root.path), "file": .string(transcript.path)]),
                .object(["session_id": .string("unscoped"), "agent": .string("claude"), "title": .string("Unscoped"), "cwd": .string(root.path), "file": .string(unscopedTranscript.path)])
            ])])
        case "chat.sessions.dump":
            return .object(["sessions": .array([
                .object(["session_id": .string("scoped"), "agent": .string("claude"), "workspace_id": .string(workspace), "surface_id": .string(surface), "state": .string("idle"), "transcript_path": .string(transcript.path)]),
                .object(["session_id": .string("unscoped"), "agent": .string("claude"), "workspace_id": .string(otherWorkspace), "surface_id": .string(surface), "state": .string("idle"), "transcript_path": .string(unscopedTranscript.path)])
            ])])
        case "system.tree":
            return .object(["windows": .array([])])
        case "feed.list":
            // Many keys per item: equal dictionaries iterate in different orders, so unsorted output would differ.
            let fields = Dictionary(uniqueKeysWithValues: (0..<16).map { ("field\($0)", JSONValue.string("value\($0)")) })
            return .object(["items": .array([.object(fields.merging(["request_id": .string("request"), "workspace_id": .string(workspace), "status": .string("pending")]) { _, new in new })])])
        case "surface.read_text":
            return .object(["text": .string("⏺ Working.\nThinking… (esc to interrupt)\n❯")])
        default: return .object([:])
        }
    }
}

/// One enrolled device, its router, and the fixture cmux behind both.
private struct ReadPathFixture {
    let directory: URL
    let cmux: ReadPathCmux
    let service: SessionService
    let router: BridgeRouter
    let authority: ConnectionAuthority
    let clientID: String
    let privateKey: Data
    let epoch: String
    static func create(transcriptLines: Int = 3, unscopedLines: Int = 1, capabilities: [ClientCapability] = [.conversationRead, .terminalRead, .projectRead]) async throws -> ReadPathFixture {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        // The service keys transcripts by their resolved path; /var is a symlink on macOS.
        let directory = temporary.resolvingSymlinksInPath()
        let cmux = ReadPathCmux(root: directory)
        var scoped = Data(); for index in 0..<transcriptLines { scoped.append(ReadPathCmux.transcriptLine("scoped-\(index)", "Line \(index)")) }
        try scoped.write(to: cmux.transcript)
        var unscoped = Data(); for index in 0..<unscopedLines { unscoped.append(ReadPathCmux.transcriptLine("unscoped-\(index)", "Other \(index)")) }
        try unscoped.write(to: cmux.unscopedTranscript)
        let crypto = IdentityCryptography(), hostKey = crypto.generatePrivateKey(), key = crypto.generatePrivateKey()
        let hostPublic = try crypto.publicKey(privateKey: hostKey)
        let host = HostIdentity(id: try crypto.identityID(publicKey: hostPublic), publicKey: hostPublic, certificateSHA256: String(repeating: "a", count: 64), name: "Host")
        let authority = try ConnectionAuthority(host: host, privateKey: hostKey, registryFile: directory.appendingPathComponent("clients.json"), now: { Int(Date().timeIntervalSince1970) })
        let bootstrap = try await authority.open(endpoint: BridgeEndpoint(host: "127.0.0.1", port: 7740), workspaces: [cmux.workspace])
        let clientPublic = try crypto.publicKey(privateKey: key), clientID = try crypto.identityID(publicKey: clientPublic)
        let scope = ClientScope(workspaces: bootstrap.value.workspaces, capabilities: capabilities)
        let enrollment = EnrollmentRequest(hostID: host.id, windowID: bootstrap.value.windowID, requestID: UUID().uuidString, clientID: clientID, clientPublicKey: clientPublic,
                                          clientName: "Phone", clientKind: "iphone", nonce: UUID().uuidString, scope: scope, expiresAt: bootstrap.value.expiresAt)
        _ = try await authority.submit(crypto.sign(enrollment, domain: "enrollment-request", privateKey: key))
        try await authority.approve(requestID: enrollment.requestID, scope: scope)
        let service = SessionService(cmux: cmux, home: directory, transcriptRoots: [directory])
        return ReadPathFixture(directory: directory, cmux: cmux, service: service, router: BridgeRouter(service: service, authority: authority), authority: authority,
                               clientID: clientID, privateKey: key, epoch: authority.epoch)
    }
    func authorization(_ uri: String) throws -> String {
        let crypto = IdentityCryptography()
        let proof = RequestProof(epoch: epoch, hostID: authority.host.id, clientID: clientID, method: "GET", uri: uri, bodySHA256: crypto.digest(Data()), nonce: UUID().uuidString, timestamp: Int(Date().timeIntervalSince1970))
        return "CmuxV2 " + (try JSONEncoder().encode(crypto.sign(proof, domain: "request", privateKey: privateKey))).base64EncodedString()
    }
    /// One authorized `GET`, exactly as a phone sends it over HTTPS or a link request.
    func read(_ uri: String) async throws -> (Int, Data) {
        await router.respond(method: "GET", uri: uri, authorization: try authorization(uri), body: Data())
    }
    func stop() { try? FileManager.default.removeItem(at: directory) }
}

@Suite struct BridgeReadPathTests {
    /// A tick on an unchanged conversation is answered from metadata: no discovery, so no handler and no parse.
    @Test func anUnchangedSubscriptionTickNeedsNoDiscoveryOrHandler() async throws {
        let fixture = try await ReadPathFixture.create()
        defer { fixture.stop() }
        let uri = "/v2/sessions/scoped/history"
        #expect(try await fixture.read(uri).0 == 200)
        let discoveries = await fixture.cmux.discoveries
        let first = await fixture.router.subscriptionStamp(uri: uri, clientID: fixture.clientID)
        let second = await fixture.router.subscriptionStamp(uri: uri, clientID: fixture.clientID)
        #expect(first != nil)
        #expect(first == second)
        #expect(await fixture.cmux.discoveries == discoveries)
    }
    /// The skip is only for an unchanged source: an appended record makes the next tick run the handler.
    @Test func anAppendedTranscriptChangesTheStamp() async throws {
        let fixture = try await ReadPathFixture.create()
        defer { fixture.stop() }
        let uri = "/v2/sessions/scoped/history"
        let before = try await fixture.read(uri)
        let stamp = try #require(await fixture.router.subscriptionStamp(uri: uri, clientID: fixture.clientID))
        let handle = try FileHandle(forWritingTo: fixture.cmux.transcript)
        try handle.seekToEnd(); try handle.write(contentsOf: ReadPathCmux.transcriptLine("scoped-3", "Line 3")); try handle.close()
        // The cached record no longer matches the file, so nothing is provable until the handler reads it.
        #expect(await fixture.router.subscriptionStamp(uri: uri, clientID: fixture.clientID) == nil)
        let tick = await fixture.router.respondResource(method: "GET", uri: uri, authorization: nil, body: Data(), subscriptionClientID: fixture.clientID)
        #expect(tick.status == 200)
        #expect(tick.data != before.1)
        let after = await fixture.router.subscriptionStamp(uri: uri, clientID: fixture.clientID)
        #expect(after != nil)
        #expect(after != stamp)
    }
    /// The terminal preview and the session list have no local change signal and are rebuilt every tick.
    @Test func previewAndSessionListTicksAreNeverSkipped() async throws {
        let fixture = try await ReadPathFixture.create()
        defer { fixture.stop() }
        #expect(try await fixture.read("/v2/sessions/scoped/history").0 == 200)
        #expect(await fixture.router.subscriptionStamp(uri: "/v2/sessions/scoped/preview", clientID: fixture.clientID) == nil)
        #expect(await fixture.router.subscriptionStamp(uri: "/v2/sessions", clientID: fixture.clientID) == nil)
        #expect(await fixture.router.subscriptionStamp(uri: "/v2/feed", clientID: fixture.clientID) == nil)
    }
    /// A revoked device gets no stamp, so its next tick runs the handler and receives the refusal as before.
    @Test func aRevokedDeviceIsNotHiddenBehindASkippedTick() async throws {
        let fixture = try await ReadPathFixture.create()
        defer { fixture.stop() }
        let uri = "/v2/sessions/scoped/history"
        #expect(try await fixture.read(uri).0 == 200)
        #expect(await fixture.router.subscriptionStamp(uri: uri, clientID: fixture.clientID) != nil)
        try await fixture.authority.revoke(clientID: fixture.clientID)
        #expect(await fixture.router.subscriptionStamp(uri: uri, clientID: fixture.clientID) == nil)
        let tick = await fixture.router.respondResource(method: "GET", uri: uri, authorization: nil, body: Data(), subscriptionClientID: fixture.clientID)
        #expect(tick.status == 401)
    }
    /// A session outside the device's workspaces is refused on every read path, and never stamped.
    @Test func aSessionOutsideTheScopeIsStillRefused() async throws {
        let fixture = try await ReadPathFixture.create()
        defer { fixture.stop() }
        for resource in ["history", "preview"] {
            let uri = "/v2/sessions/unscoped/" + resource
            let result = try await fixture.read(uri)
            #expect(result.0 == 403)
            #expect(String(decoding: result.1, as: UTF8.self).contains("scope_denied"))
            #expect(!String(decoding: result.1, as: UTF8.self).contains("Other 0"))
            #expect(await fixture.router.subscriptionStamp(uri: uri, clientID: fixture.clientID) == nil)
            let tick = await fixture.router.respondResource(method: "GET", uri: uri, authorization: nil, body: Data(), subscriptionClientID: fixture.clientID)
            #expect(tick.status == 403)
        }
        #expect(try await fixture.read("/v2/sessions/scoped/history").0 == 200)
    }
    /// One history or preview read discovers sessions once; the scope check and the read share it.
    @Test(arguments: ["history", "preview"])
    func aSessionReadDiscoversOnce(_ resource: String) async throws {
        let fixture = try await ReadPathFixture.create()
        defer { fixture.stop() }
        #expect(try await fixture.read("/v2/sessions/scoped/" + resource).0 == 200)
        #expect(await fixture.cmux.discoveries == 1)
    }
    /// Subscriptions compare answer bytes, so an unchanged feed must encode to the same bytes every tick.
    @Test func anUnchangedFeedEncodesToIdenticalBytes() async throws {
        let fixture = try await ReadPathFixture.create(capabilities: [.feedRead])
        defer { fixture.stop() }
        var digests = Set<String>()
        for _ in 0..<8 {
            let tick = await fixture.router.respondResource(method: "GET", uri: "/v2/feed", authorization: nil, body: Data(), subscriptionClientID: fixture.clientID)
            #expect(tick.status == 200)
            digests.insert(try LinkObservationDigest().digest(tick.data))
        }
        #expect(digests.count == 1)
    }
    /// A client-supplied small limit is honoured exactly, and reports the older page honestly.
    @Test func aSmallClientLimitReturnsExactlyThatManyMessages() async throws {
        let fixture = try await ReadPathFixture.create(transcriptLines: 12)
        defer { fixture.stop() }
        let result = try await fixture.read("/v2/sessions/scoped/history?limit=3")
        #expect(result.0 == 200)
        let snapshot = try JSONDecoder().decode(ConversationSnapshot.self, from: result.1)
        #expect(snapshot.messages.map(\.id) == ["scoped-9", "scoped-10", "scoped-11"])
        #expect(snapshot.hasMore)
        // Without a limit the default page still holds every one of these twelve.
        let full = try JSONDecoder().decode(ConversationSnapshot.self, from: try await fixture.read("/v2/sessions/scoped/history").1)
        #expect(full.messages.count == 12)
        #expect(!full.hasMore)
    }
}

@Suite struct TranscriptCacheEvictionTests {
    private func write(_ name: String, in directory: URL) throws -> String {
        let file = directory.appendingPathComponent(name + ".jsonl")
        try ReadPathCmux.transcriptLine(name, name).write(to: file)
        return file.path
    }
    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    /// A full cache displaces one cold record per new path; it used to drop every record, the open one too.
    @Test func theHotTranscriptSurvivesABurstOfNewPaths() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = TranscriptReader()
        let hot = try write("hot", in: directory)
        let first = try await reader.history(path: hot, agent: "claude", beforeSeq: nil, limit: 10)
        for index in 0..<31 { _ = try await reader.history(path: try write("fill-\(index)", in: directory), agent: "claude", beforeSeq: nil, limit: 10) }
        // The phone is still reading this conversation: it is the most recently used record.
        _ = try await reader.history(path: hot, agent: "claude", beforeSeq: nil, limit: 10)
        for index in 0..<8 { _ = try await reader.history(path: try write("burst-\(index)", in: directory), agent: "claude", beforeSeq: nil, limit: 10) }
        // A re-parse would have started a new generation and forced the phone to re-anchor.
        #expect(try await reader.history(path: hot, agent: "claude", beforeSeq: nil, limit: 10).generation == first.generation)
        #expect(await reader.stamp(path: hot) != nil)
    }
    /// The least recently read record is the one a new path displaces.
    @Test func theColdestTranscriptIsTheOneDisplaced() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = TranscriptReader()
        let cold = try write("cold", in: directory)
        let first = try await reader.history(path: cold, agent: "claude", beforeSeq: nil, limit: 10)
        for index in 0..<32 { _ = try await reader.history(path: try write("fill-\(index)", in: directory), agent: "claude", beforeSeq: nil, limit: 10) }
        #expect(await reader.stamp(path: cold) == nil)
        #expect(try await reader.history(path: cold, agent: "claude", beforeSeq: nil, limit: 10).generation != first.generation)
    }
}
