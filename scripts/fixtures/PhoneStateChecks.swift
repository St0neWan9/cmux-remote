import Foundation
import CmuxRemoteCore
import CmuxRemoteClient
import CmuxAgentChat

private actor FixtureEnrollment: DeviceEnrolling {
    nonisolated let request: SignedValue<EnrollmentRequest>
    private let delaySubmission: Bool
    private var submitContinuation: CheckedContinuation<EnrollmentStatus, any Error>?
    private var calls = 0
    nonisolated let started = AsyncStream<Void>.makeStream()
    nonisolated let statusCalls = AsyncStream<Int>.makeStream()
    init(request: SignedValue<EnrollmentRequest>, delaySubmission: Bool) { self.request = request; self.delaySubmission = delaySubmission }
    func submit() async throws -> EnrollmentStatus {
        if delaySubmission {
            return try await withCheckedThrowingContinuation { continuation in submitContinuation = continuation; started.continuation.yield(()) }
        }
        started.continuation.yield(()); return EnrollmentStatus(request: request.value, state: "pending")
    }
    func succeedSubmission() { submitContinuation?.resume(returning: EnrollmentStatus(request: request.value, state: "pending")); submitContinuation = nil }
    func finishSubmission() { submitContinuation?.resume(throwing: URLError(.cancelled)); submitContinuation = nil }
    func status() async throws -> EnrollmentStatus {
        calls += 1; statusCalls.continuation.yield(calls)
        if calls == 1 { throw URLError(.networkConnectionLost) }
        return EnrollmentStatus(request: request.value, state: "pending")
    }
    func cancel() async throws {}
    nonisolated func close() {}
    nonisolated func connection(from status: EnrollmentStatus) throws -> AuthorizedConnection { throw BridgeError("not_approved", "Fixture is pending") }
}

private actor DeferredProjectRead {
    private var continuation: CheckedContinuation<TextFileSnapshot, any Error>?
    nonisolated let started = AsyncStream<Void>.makeStream()
    func read() async throws -> TextFileSnapshot {
        try await withCheckedThrowingContinuation { continuation in self.continuation = continuation; started.continuation.yield(()) }
    }
    func finish() { continuation?.resume(returning: TextFileSnapshot(path: "old", text: "Old content", truncated: false)); continuation = nil }
}
private actor FeedModelFixture {
    var calls = 0
    var observedBody: JSONValue?
    let item: JSONValue = .object(["request_id": .string("request"), "kind": .string("exitPlan"), "status": .string("pending")])
    func send(_ body: JSONValue) throws -> MutationReceipt {
        calls += 1; observedBody = body
        throw BridgeError("outcome_unknown", "Lost", status: 504)
    }
    func load() -> [JSONValue] { [item] }
}

private actor DeferredSessionRead {
    var calls = 0
    private var continuation: CheckedContinuation<[SessionDescriptor], any Error>?
    nonisolated let started = AsyncStream<Void>.makeStream()
    func read() async throws -> [SessionDescriptor] {
        calls += 1
        if calls > 1 { return [SessionDescriptor(id: "new", agent: "claude", title: "New", cwd: nil)] }
        return try await withCheckedThrowingContinuation { continuation in self.continuation = continuation; started.continuation.yield(()) }
    }
    func finish() { continuation?.resume(returning: [SessionDescriptor(id: "old", agent: "claude", title: "Old", cwd: nil)]); continuation = nil }
}

private actor DeferredImageRead {
    nonisolated let started = AsyncStream<Void>.makeStream()
    private var continuation: CheckedContinuation<Data, any Error>?
    func read() async throws -> Data { try await withCheckedThrowingContinuation { continuation = $0; started.continuation.yield(()) } }
    func finish(_ data: Data) { continuation?.resume(returning: data); continuation = nil }
}
private actor DeferredImageSend {
    nonisolated let started = AsyncStream<Void>.makeStream()
    var requests: [SendRequest] = []
    private var continuation: CheckedContinuation<MutationReceipt, any Error>?
    func send(_ request: SendRequest) async throws -> MutationReceipt {
        requests.append(request)
        return try await withCheckedThrowingContinuation { continuation = $0; started.continuation.yield(()) }
    }
    func finish() {
        guard let request = requests.last else { return }
        continuation?.resume(returning: MutationReceipt(operationID: request.operationID, accepted: true)); continuation = nil
    }
}
private actor UncertainImageSend {
    var requests: [SendRequest] = []
    var accepted = false
    func send(_ request: SendRequest) throws -> MutationReceipt {
        requests.append(request); throw BridgeError("outcome_unknown", "Receipt lost", status: 504)
    }
    func status(_ id: UUID) -> OperationStatus { OperationStatus(operationID: id, state: accepted ? .accepted : .outcomeUnknown, recordedAt: Date()) }
    func confirm() { accepted = true }
}

@main struct PhoneStateChecks {
    @MainActor static func main() async throws {
        let crypto = IdentityCryptography(); let hostKey = crypto.generatePrivateKey(); let publicKey = try crypto.publicKey(privateKey: hostKey)
        let host = HostIdentity(id: try crypto.identityID(publicKey: publicKey), publicKey: publicKey, certificateSHA256: String(repeating: "a", count: 64), name: "Fixture")
        let bootstrap = try crypto.sign(EnrollmentBootstrap(host: host, endpoint: BridgeEndpoint(host: "localhost", port: 7740), workspaces: ["11111111-1111-1111-1111-111111111111"], windowID: UUID().uuidString, expiresAt: Int(Date().timeIntervalSince1970) + 300), domain: "bootstrap", privateKey: hostKey)
        let key = crypto.generatePrivateKey(); let devicePublicKey = try crypto.publicKey(privateKey: key)
        let request = try crypto.sign(EnrollmentRequest(hostID: host.id, windowID: bootstrap.value.windowID, requestID: UUID().uuidString, clientID: crypto.identityID(publicKey: devicePublicKey), clientPublicKey: devicePublicKey, clientName: "Fixture", clientKind: "iphone", nonce: UUID().uuidString, scope: ClientScope(workspaces: bootstrap.value.workspaces, capabilities: [.workspaceRead]), expiresAt: bootstrap.value.expiresAt), domain: "enrollment-request", privateKey: key)
        let qr = try EnrollmentLinkCodec().encode(bootstrap)
        var failures: [String] = []

        let suspended = FixtureEnrollment(request: request, delaySubmission: true)
        let idleTicks = AsyncStream<Void>.makeStream()
        let cancelling = AppModel(identityKey: { key }, makeEnrollment: { _, _, _ in suspended }, enrollmentTicks: { (idleTicks.stream, {}) })
        let submission = Task { @MainActor in await cancelling.enrollQR(qr) }
        var started = suspended.started.stream.makeAsyncIterator(); _ = await started.next()
        await cancelling.cancelEnrollment(); await suspended.finishSubmission(); await submission.value
        if cancelling.loading { failures.append("Cancel left submission loading") }

        let recovering = FixtureEnrollment(request: request, delaySubmission: false)
        let ticks = AsyncStream<Void>.makeStream()
        let pending = AppModel(identityKey: { key }, makeEnrollment: { _, _, _ in recovering }, enrollmentTicks: { (ticks.stream, {}) })
        await pending.enrollQR(qr)
        var calls = recovering.statusCalls.stream.makeAsyncIterator()
        ticks.continuation.yield(()); _ = await calls.next()
        ticks.continuation.yield(())
        let deadline = Task { try await ContinuousClock().sleep(for: .seconds(2)); recovering.statusCalls.continuation.finish() }
        let secondCall = await calls.next(); deadline.cancel(); pending.pauseEnrollment()
        if secondCall != 2 { failures.append("One transient status failure permanently stopped enrollment") }

        let pausedFixture = FixtureEnrollment(request: request, delaySubmission: true)
        let pausedTicks = AsyncStream<Void>.makeStream()
        let paused = AppModel(identityKey: { key }, makeEnrollment: { _, _, _ in pausedFixture }, enrollmentTicks: { (pausedTicks.stream, {}) })
        let pausedSubmit = Task { @MainActor in await paused.enrollQR(qr) }
        var pausedStarted = pausedFixture.started.stream.makeAsyncIterator(); _ = await pausedStarted.next()
        paused.pauseEnrollment(); await pausedFixture.succeedSubmission(); await pausedSubmit.value
        var pausedCalls = pausedFixture.statusCalls.stream.makeAsyncIterator()
        pausedTicks.continuation.yield(())
        let pausedDeadline = Task { try await ContinuousClock().sleep(for: .milliseconds(150)); pausedFixture.statusCalls.continuation.finish() }
        if await pausedCalls.next() != nil { failures.append("Submission completion restarted polling after scene pause") }
        pausedDeadline.cancel(); paused.pauseEnrollment()

        let client = RemoteClient(pairing: try PairingConfiguration(host: "localhost", port: 1, token: String(repeating: "0", count: 32), certificateSHA256: String(repeating: "0", count: 64)))
        defer { client.close() }
        let session = SessionDescriptor(id: "fixture", agent: "claude", title: "Fixture", cwd: nil, workspaceID: "workspace", surfaceID: "surface", state: "working")
        let conversation = ConversationModel(session: session, client: client)
        conversation.markInterrupted()
        var updated = session; updated.state = "idle"; conversation.updateSession(updated)
        updated.state = "working"; conversation.updateSession(updated)
        if !conversation.working { failures.append("An earlier interrupt suppressed a later desktop turn") }
        conversation.markInterrupted(); conversation.updateSession(session)
        if !conversation.working { failures.append("Missed idle transition suppressed a later desktop turn") }
        conversation.stopRequested = false
        conversation.messages = [ChatMessage(id: "answer", seq: 150, role: .agent, timestamp: Date(timeIntervalSince1970: 120), kind: .prose(ChatProse(text: "Answer")))]
        conversation.responses = [ConversationResponse(firstMessageID: "first", lastMessageID: "answer", startedAt: Date(timeIntervalSince1970: 100), completedAt: nil, durationSeconds: nil, recordedDuration: false, firstSeq: 1, lastSeq: 150)]
        conversation.currentTurnStartedAt = Date(timeIntervalSince1970: 100)
        if conversation.runningSince != Date(timeIntervalSince1970: 100) { failures.append("Pagination hid an active turn whose prompt is not loaded") }
        conversation.currentTurnStartedAt = nil
        if conversation.runningSince != nil || !conversation.hasActiveResponse { failures.append("Missing source prompt timestamp lost working fallback or inherited a timestamp") }
        conversation.currentTurnCompleted = true
        if conversation.hasActiveResponse { failures.append("Recorded completion left a stale working banner") }
        let response = ConversationResponse(firstMessageID: "earlier", lastMessageID: "final2", startedAt: nil, completedAt: nil, durationSeconds: nil, recordedDuration: false, completed: true, firstSeq: 1, lastSeq: 150)
        conversation.messages = [
            ChatMessage(id: "earlier", seq: 1, role: .agent, timestamp: .distantPast, kind: .prose(ChatProse(text: "Progress"))),
            ChatMessage(id: "final1", seq: 150, role: .agent, timestamp: .distantPast, kind: .prose(ChatProse(text: "First block"))),
            ChatMessage(id: "final2", seq: 150, role: .agent, timestamp: .distantPast, kind: .prose(ChatProse(text: "Second block")))]
        if conversation.responseText(response) != "First block\n\nSecond block" { failures.append("Reply actions mixed in progress text or omitted a final-record block") }
        let bare = MarkdownBlock.parse("```\nls\npwd\n```").first
        let labeled = MarkdownBlock.parse("```swift\nlet n = 1\n```").first
        if bare?.text != "ls\npwd" || labeled?.text != "let n = 1" { failures.append("Fenced Markdown lost code content") }

        let deferred = DeferredProjectRead()
        let project = ProjectModel(initialPath: " file with trailing space ", read: { resource, query in
            if resource == "file" { return try await deferred.read() }
            if query["path"] != " file with trailing space " { throw BridgeError("invalid_input", "Path changed") }
            return TextFileSnapshot(path: "new", text: "New diff", truncated: true)
        }, list: { [ProjectChange(status: " M", path: "source.swift")] })
        let oldRead = Task { @MainActor in await project.load(.file) }
        var projectStarted = deferred.started.stream.makeAsyncIterator(); _ = await projectStarted.next()
        await project.load(.diff); await deferred.finish(); await oldRead.value
        if project.content != "New diff" || !project.truncated || project.busy { failures.append("An older file read replaced the current diff or filename spaces were lost") }
        await project.load(.changes)
        if project.entries.first?.path != "source.swift" || !project.content.isEmpty { failures.append("Changes view retained previous file content") }
        let feedFixture = FeedModelFixture()
        let feed = FeedModel(fetch: { await feedFixture.load() }, send: { _, body in try await feedFixture.send(body) })
        await feed.refresh()
        let pendingItem = feedFixture.item
        await feed.reply(pendingItem, mode: .manual, feedback: "Please keep tests")
        let warning = feed.error
        await feed.refresh()
        if warning == nil || feed.error != warning || feed.busy { failures.append("Snapshot refresh hid a lost decision receipt") }
        let feedCalls = await feedFixture.calls; let observedBody = await feedFixture.observedBody
        if feedCalls != 1 || observedBody?["feedback"].string != "Please keep tests" { failures.append("Decision was retried or feedback was omitted") }
        let readonly: JSONValue = .object(["request_id": .string("ended"), "kind": .string("exitPlan"), "status": .string("resolved")])
        await feed.reply(readonly, mode: .manual)
        if await feedFixture.calls != 1 { failures.append("A resolved item was submitted again") }

        let sessionsFixture = DeferredSessionRead()
        let browsing = AppModel(fetchSessions: { _ in try await sessionsFixture.read() }, fetchWorkspaces: { _ in [] })
        browsing.client = client
        let staleBrowse = Task { @MainActor in await browsing.refresh() }
        var browseStarted = sessionsFixture.started.stream.makeAsyncIterator(); _ = await browseStarted.next()
        await browsing.refresh(); await sessionsFixture.finish(); await staleBrowse.value
        if browsing.sessions.first?.id != "new" || browsing.loading { failures.append("An older discovery snapshot replaced newer sessions") }
        let feedScope = ClientScope(workspaces: bootstrap.value.workspaces, capabilities: [.workspaceRead, .feedRead, .feedReply])
        let feedGrant = try crypto.sign(EnrollmentGrant(request: request.value, scope: feedScope, issuedAt: 1000), domain: "grant", privateKey: hostKey)
        let feedConnection = AuthorizedConnection(host: host, endpoint: bootstrap.value.endpoint, privateKey: key, grant: feedGrant)
        let feedOnlyClient = try RemoteClient(connection: feedConnection)
        defer { feedOnlyClient.close() }
        let feedOnly = AppModel(fetchSessions: { _ in throw BridgeError("scope_denied", "Should not ask for conversations") }, fetchWorkspaces: { _ in [WorkspaceSummary(id: "allowed", title: "Allowed")] })
        feedOnly.client = feedOnlyClient; await feedOnly.refresh()
        if feedOnly.error != nil || feedOnly.workspaces.first?.id != "allowed" || !feedOnly.sessions.isEmpty { failures.append("A Feed-only grant tried to read conversations or lost its workspace list") }

        var mediaChecks = 0
        func checkMedia(_ condition: Bool, _ message: String) { mediaChecks += 1; if !condition { failures.append(message) } }
        let blue = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAKklEQVR4nGPQyrtDU8QwasGoBaMWjFowasGoBaMWjFowasGoBaMWDBULAFSk0ExUjkswAAAAAElFTkSuQmCC")!
        let photo = try await ImageAttachmentEncoder().encode(blue, name: "Test.png")
        checkMedia(photo.format == "jpeg" && photo.fileName == "Test.jpg" && (Data(base64Encoded: photo.dataBase64)?.count ?? Int.max) <= 131_072, "Actual photo encoder did not produce a bounded JPEG")
        var invalidPhotoRejected = false
        do { _ = try await ImageAttachmentEncoder().encode(Data("invalid".utf8), name: "Bad") }
        catch { invalidPhotoRejected = (error as? BridgeError)?.code == "invalid_image" }
        checkMedia(invalidPhotoRejected, "Actual encoder accepted malformed photo data")
        let fileRoot = FileManager.default.temporaryDirectory.appendingPathComponent("phone-images-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fileRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fileRoot) }
        let selectedFile = fileRoot.appendingPathComponent("selected.png")
        try blue.write(to: selectedFile)
        let selectedBytes = try await ImageFileLoader().load(selectedFile)
        checkMedia(selectedBytes == blue, "Explicit file selection changed image bytes")
        var rejectedDirectory = false
        do { _ = try await ImageFileLoader().load(fileRoot) }
        catch { rejectedDirectory = (error as? BridgeError)?.code == "invalid_image" }
        checkMedia(rejectedDirectory, "File picker accepted a directory as an image")
        let oversized = fileRoot.appendingPathComponent("large.png")
        FileManager.default.createFile(atPath: oversized.path, contents: nil)
        let largeHandle = try FileHandle(forWritingTo: oversized)
        try largeHandle.truncate(atOffset: 33_554_433); try largeHandle.close()
        var rejectedLarge = false
        do { _ = try await ImageFileLoader().load(oversized) }
        catch { rejectedLarge = (error as? BridgeError)?.code == "too_large" }
        checkMedia(rejectedLarge, "File import bypassed the bounded input limit")
        let cancelledFile = Task { try await ImageFileLoader().load(oversized) }; cancelledFile.cancel()
        var rejectedCancelled = false
        do { _ = try await cancelledFile.value }
        catch is CancellationError { rejectedCancelled = true }
        catch {}
        checkMedia(rejectedCancelled, "Cancelled file import continued reading a selected file")
        let unicodePhoto = try await ImageAttachmentEncoder().encode(blue, name: String(repeating: "照片", count: 100) + ".png")
        checkMedia(unicodePhoto.fileName.utf8.count <= 255 && !unicodePhoto.fileName.contains("/"), "Unicode image filename exceeded the server metadata bound")
        let photos = ImageDraftModel(); let imageRead = DeferredImageRead()
        let latePhoto = Task { @MainActor in await photos.load([ImageSelection(name: "Late", load: { try await imageRead.read() })], encode: ImageAttachmentEncoder().encode) }
        var imageStarted = imageRead.started.stream.makeAsyncIterator(); _ = await imageStarted.next()
        photos.cancelLoading(); await imageRead.finish(blue); await latePhoto.value
        checkMedia(!photos.loading && photos.images.isEmpty, "Cancelled photo loading resurrected an image draft")
        await photos.load([ImageSelection(name: "Good", load: { blue })], encode: ImageAttachmentEncoder().encode)
        checkMedia(photos.images.count == 1 && !photos.loading, "Photo selection did not prepare its actual image")
        await photos.load((0..<4).map { index in ImageSelection(name: "\(index)", load: { blue }) }, encode: ImageAttachmentEncoder().encode)
        checkMedia(photos.images.count == 1 && photos.error != nil && !photos.loading, "An over-limit selection changed the existing draft or stayed loading")
        photos.remove(photos.images[0].id)
        checkMedia(photos.images.isEmpty && photos.error == nil, "Removing a selected photo left stale image/error state")

        func makePhotoChat(sender: @escaping @Sendable (SendRequest) async throws -> MutationReceipt,
                           status: (@Sendable (UUID) async throws -> OperationStatus)? = nil,
                           descriptor: SessionDescriptor = session) -> ConversationModel {
            ConversationModel(session: descriptor, client: client, sendRequest: sender, getOperation: status,
                              readSessions: { [descriptor] },
                              readHistory: { _ in ConversationSnapshot(messages: [], hasMore: false, generation: "photo-fixture", clipped: false) },
                              readPreview: { PreviewSnapshot(text: nil, available: false) })
        }
        let sending = DeferredImageSend(); let photoChat = makePhotoChat(sender: { try await sending.send($0) })
        photoChat.imageDraft.images = [photo]; photoChat.draft = "Original caption"
        let sendPhoto = Task { @MainActor in await photoChat.send() }
        var sendStarted = sending.started.stream.makeAsyncIterator(); _ = await sendStarted.next()
        let newPhoto = ChatImagePayload(fileName: "New.jpg", format: photo.format, data: Data(base64Encoded: photo.dataBase64)!)
        photoChat.draft = "New caption"; photoChat.imageDraft.images.append(newPhoto)
        await sending.finish(); await sendPhoto.value
        checkMedia(photoChat.draft == "New caption" && photoChat.imageDraft.images.map(\.id) == [newPhoto.id], "A completed image send erased later draft edits")
        let sentImages = await sending.requests
        checkMedia(sentImages.count == 1 && sentImages[0].text == "Original caption" && sentImages[0].attachments.map(\.id) == [photo.id], "Photo send changed the captured input or image order")
        let lost = UncertainImageSend(); let uncertainChat = makePhotoChat(sender: { try await lost.send($0) }, status: { await lost.status($0) })
        uncertainChat.imageDraft.images = [photo]
        await uncertainChat.send()
        let pendingID = uncertainChat.pendingSend?.operationID
        await uncertainChat.send(); await uncertainChat.refresh()
        checkMedia(await lost.requests.count == 1 && pendingID != nil && uncertainChat.pendingSend?.operationID == pendingID && uncertainChat.imageDraft.images.count == 1 && uncertainChat.error != nil, "An unknown image send was repeated, cleared or hidden by refresh")
        await uncertainChat.checkPendingSend()
        checkMedia(uncertainChat.pendingSend != nil && uncertainChat.imageDraft.images.count == 1, "An unknown operation-status response cleared the draft")
        await lost.confirm(); await uncertainChat.checkPendingSend()
        checkMedia(uncertainChat.pendingSend == nil && uncertainChat.imageDraft.images.isEmpty && uncertainChat.error == nil, "A confirmed persisted receipt did not reconcile the image draft")
        checkMedia(await lost.requests.count == 1, "Receipt reconciliation resent the images")
        let inspect = makePhotoChat(sender: { try await lost.send($0) }, status: { await lost.status($0) })
        inspect.imageDraft.images = [photo]; inspect.draft = "Keep this"
        await inspect.send(); let beforeInspection = await lost.requests.count; inspect.acknowledgePendingSend()
        let afterInspection = await lost.requests.count
        checkMedia(inspect.pendingSend == nil && inspect.draft == "Keep this" && inspect.imageDraft.images.count == 1 && afterInspection == beforeInspection, "Inspection acknowledgement sent or erased the preserved draft")
        var ended = session; ended.state = "ended"
        let readonlyPhoto = makePhotoChat(sender: { try await lost.send($0) }, descriptor: ended)
        readonlyPhoto.imageDraft.images = [photo]; await readonlyPhoto.send()
        checkMedia(await lost.requests.count == beforeInspection, "Read-only image conversation invoked send")

        if !failures.isEmpty { print(failures.joined(separator: "\n")); exit(1) }
        print("Phone state: 17 existing behavioral checks and \(mediaChecks) executed image/draft/receipt checks passed.")
    }
}
