import Foundation
import Observation
import CmuxRemoteCore
import CmuxRemoteClient
import CmuxAgentChat

@MainActor @Observable
final class ConversationModel {
    var session: SessionDescriptor
    let client: RemoteClient
    var canSend: Bool { session.writable && client.canControlConversations }
    var messages: [ChatMessage] = []
    var images: [ConversationImageReference] = []
    var timelineItems: [ConversationTimelineItem] = []
    var responses: [ConversationResponse] = []
    var recordedRunSeconds: Double?
    var recordedTurnCount = 0
    var currentTurnStartedAt: Date?
    var currentTurnCompleted = false
    var jumpToLatest = 0
    var stopRequested = false
    private var interruptedUserID: String?
    var working: Bool { session.state.hasPrefix("working") }
    var hasActiveResponse: Bool { working && !stopRequested && !currentTurnCompleted }
    var runningSince: Date? { hasActiveResponse ? currentTurnStartedAt : nil }
    func responseText(_ response: ConversationResponse) -> String {
        messages.filter { $0.seq == response.lastSeq && $0.role == .agent }
            .compactMap { message -> String? in if case .prose(let value) = message.kind { return value.text }; return nil }.joined(separator: "\n\n")
    }
    var latestMessageText: String? {
        guard let message = messages.last else { return nil }
        if case .prose(let value) = message.kind { return value.text }; return nil
    }
    var preview: String?
    /// The agent's own working line from the terminal, as it renders it.
    var liveStatus: TuiAgentStatus?
    var error: String?
    var draft = ""
    let imageDraft = ImageDraftModel()
    let speech: SpeechDraftModel
    private(set) var pendingSend: SendRequest?
    /// Prompts shown at the bottom of the page from the moment they are sent until the transcript records them.
    private(set) var outgoing: [OutgoingPrompt] = []
    private var mutationWarning: String?
    private let loadRecovery: @Sendable () async throws -> SendRequest?
    private let saveRecovery: @Sendable (SendRequest?) async throws -> Void
    private var recoveryTask: Task<SendRequest?, any Error>?
    private var recoveryReady = false
    private(set) var recoveryFailed = false
    var recoveryBlocked: Bool { !recoveryReady || pendingSend != nil }
    private let sendRequest: @Sendable (SendRequest) async throws -> MutationReceipt
    private let getOperation: @Sendable (UUID) async throws -> OperationStatus
    private let readSessions: @Sendable () async throws -> [SessionDescriptor]
    private let readHistory: @Sendable (Int?) async throws -> ConversationSnapshot
    private let readPreview: @Sendable () async throws -> PreviewSnapshot
    private let refreshReads = ReadRequestOwner()
    private let olderReads = ReadRequestOwner()
    private var readsEnabled = true
    private(set) var loadingOlder = false
    var busy = false
    var hasMore = false
    /// The Bridge read only the newest part of a very long record; earlier messages cannot be paged in.
    var clipped = false
    private var generation: String?
    var historyGeneration: String? { generation }
    init(session: SessionDescriptor, client: RemoteClient, speechInput: (any SpeechInputServing)? = nil,
         loadRecovery: (@Sendable () async throws -> SendRequest?)? = nil,
         saveRecovery: (@Sendable (SendRequest?) async throws -> Void)? = nil,
         sendRequest: (@Sendable (SendRequest) async throws -> MutationReceipt)? = nil,
         getOperation: (@Sendable (UUID) async throws -> OperationStatus)? = nil,
         readSessions: (@Sendable () async throws -> [SessionDescriptor])? = nil,
         readHistory: (@Sendable (Int?) async throws -> ConversationSnapshot)? = nil,
         readPreview: (@Sendable () async throws -> PreviewSnapshot)? = nil) {
        self.session = session; self.client = client; speech = SpeechDraftModel(input: speechInput ?? UnavailableSpeechInput())
        let id = session.id
        let recovery = PendingSendStore(); let scope = client.operationRecoveryScope
        self.loadRecovery = loadRecovery ?? { try await recovery.load(scope: scope, sessionID: id) }
        self.saveRecovery = saveRecovery ?? { try await recovery.save($0, scope: scope, sessionID: id) }
        self.sendRequest = sendRequest ?? { try await client.post("/v1/sessions/\(id)/send", body: $0, as: MutationReceipt.self) }
        self.getOperation = getOperation ?? { try await client.get("/v1/operations/\($0.uuidString)", as: OperationStatus.self) }
        self.readSessions = readSessions ?? { try await client.get("/v1/sessions", as: [SessionDescriptor].self) }
        self.readHistory = readHistory ?? { before in try await client.get("/v1/sessions/\(id)/history", query: before.map { ["before_seq": String($0)] } ?? [:], as: ConversationSnapshot.self) }
        self.readPreview = readPreview ?? { try await client.get("/v1/sessions/\(id)/preview", as: PreviewSnapshot.self) }
    }
    func updateSession(_ current: SessionDescriptor) {
        if current.state != session.state { stopRequested = false }
        session = current
    }
    func markInterrupted() {
        stopRequested = true
        interruptedUserID = messages.last(where: { $0.role == .user })?.id
    }
    /// Suspending reads leaves durable mutations and their captured drafts intact.
    func observeChanges() async {
        let paths = ["/v1/sessions/\(session.id)/history", "/v1/sessions/\(session.id)/preview", "/v1/sessions"]
        for await _ in client.changes(paths: paths) {
            guard !Task.isCancelled, readsEnabled else { return }; await refresh()
        }
    }
    func suspendReads() { readsEnabled = false; refreshReads.suspend(); olderReads.suspend(); loadingOlder = false }
    func resumeReads() { readsEnabled = true }
    func refresh() async {
        guard readsEnabled, !Task.isCancelled else { return }
        await refreshReads.run { [self] request in await readLatest(request) }
    }
    private func readLatest(_ request: UUID) async {
        do {
            do { try await restorePendingSend() }
            catch { if refreshReads.isCurrent(request) { mutationWarning = ErrorPresentation().message(error) } }
            guard refreshReads.isCurrent(request) else { return }
            let descriptors = try await readSessions()
            guard refreshReads.isCurrent(request) else { return }
            guard let current = descriptors.first(where: { $0.id == session.id }) else { throw BridgeError("read_only", "The cmux session is no longer available.", status: 404) }
            let history = try await readHistory(nil)
            guard refreshReads.isCurrent(request) else { return }
            let live = try? await readPreview()
            guard refreshReads.isCurrent(request) else { return }
            updateSession(current)
            if generation == history.generation {
                var next = messages
                for message in history.messages {
                    if let index = next.firstIndex(where: { $0.id == message.id }) { next[index] = message }
                    else { next.append(message) }
                }
                messages = next.sorted { $0.seq < $1.seq }
            } else { olderReads.suspend(); loadingOlder = false; messages = history.messages; responses = []; generation = history.generation; hasMore = history.hasMore }
            clipped = history.clipped
            let updatedIDs = Set(history.messages.map(\.id))
            images = images.filter { $0.generation == history.generation && !updatedIDs.contains($0.messageID) } + (history.images ?? [])
            if stopRequested, messages.last(where: { $0.role == .user })?.id != interruptedUserID { stopRequested = false }
            if generation == history.generation {
                let incoming = history.responses ?? []
                let anchors = Set(incoming.map(\.firstMessageID))
                responses = responses.filter { !anchors.contains($0.firstMessageID) } + incoming
            }
            recordedRunSeconds = history.recordedRunSeconds; recordedTurnCount = history.recordedTurnCount ?? 0
            currentTurnStartedAt = history.currentTurnStartedAt; currentTurnCompleted = history.currentTurnCompleted ?? false
            timelineItems = ConversationTimeline().items(from: messages)
            outgoing = OutgoingPromptMatcher().pending(outgoing, messages: messages, generation: generation)
            let committed = messages.reversed().compactMap { message -> String? in
                if message.role == .agent, case .prose(let value) = message.kind { return value.text }; return nil
            }.first
            preview = live?.text == committed ? nil : live?.text; liveStatus = live?.status; error = mutationWarning
        } catch {
            // A lost link is shown and retried by the connection bar; the page keeps only errors about the conversation.
            guard refreshReads.isCurrent(request) else { return }
            self.error = ErrorPresentation().isConnectivity(error) ? mutationWarning : ErrorPresentation().message(error)
        }
    }
    func older() async {
        guard readsEnabled, !Task.isCancelled, let seq = messages.first?.seq, let sourceGeneration = generation else { return }
        var reanchor: UUID?
        await olderReads.run { [self] request in
            loadingOlder = true
            defer { if olderReads.revision == request { loadingOlder = false } }
            do {
                let page = try await readHistory(seq)
                guard olderReads.isCurrent(request), generation == sourceGeneration else { return }
                guard page.generation == sourceGeneration else { reanchor = request; return }
                let responseIDs = Set(responses.map(\.firstMessageID))
                responses.insert(contentsOf: (page.responses ?? []).filter { !responseIDs.contains($0.firstMessageID) }, at: 0)
                let existing = Set(messages.map(\.id))
                messages.insert(contentsOf: page.messages.filter { !existing.contains($0.id) }, at: 0)
                let imageIDs = Set(images.map(\.id)); images += (page.images ?? []).filter { !imageIDs.contains($0.id) }
                timelineItems = ConversationTimeline().items(from: messages); hasMore = page.hasMore
            } catch {
                guard olderReads.isCurrent(request), generation == sourceGeneration, !ErrorPresentation().isConnectivity(error) else { return }
                self.error = ErrorPresentation().message(error)
            }
        }
        if let reanchor, readsEnabled, olderReads.isCurrent(reanchor), generation == sourceGeneration { await refresh() }
    }
    func useSpeechDraft() { if let text = speech.takeText() { draft += (draft.isEmpty ? "" : "\n") + text } }
    func send() async {
        guard canSend, !busy, !speech.active, !imageDraft.loading, pendingSend == nil,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageDraft.images.isEmpty else { return }
        busy = true; defer { busy = false }
        var sent: SendRequest?
        do {
            try await restorePendingSend()
            guard pendingSend == nil else { return }
            let request = SendRequest(text: draft, attachments: imageDraft.images)
            pendingSend = request; sent = request
            // The prompt moves into the conversation at once; the composer is free while the agent catches up.
            outgoing.append(OutgoingPrompt(request: request, after: messages, generation: generation))
            draft = ""; imageDraft.removeSubmitted(Set(request.attachments.map(\.id))); jumpToLatest += 1
            try await saveRecovery(request)
            let receipt = try await sendRequest(request)
            guard receipt.accepted, receipt.operationID == request.operationID else { throw BridgeError("outcome_unknown", "The send receipt could not be verified.", status: 504) }
            try await confirmSend(request); await refresh(); jumpToLatest += 1
        } catch {
            let safeRejections = ["unauthorized", "scope_denied", "read_only", "stale_binding", "input_busy", "invalid_image", "invalid_input", "too_large", "journal_unavailable", "receipt_capacity"]
            // The client reports any failure after the write left as outcome_unknown; a bare network error means the
            // link was down before it (the identity check failed), so nothing reached the Mac.
            let neverSent = !(error is BridgeError) && ErrorPresentation().isConnectivity(error)
            if neverSent || (error as? BridgeError).map({ safeRejections.contains($0.code) }) == true {
                // Nothing reached the agent: the prompt leaves the conversation.
                if let sent { outgoing.removeAll { $0.id == sent.operationID } }
                do { try await saveRecovery(nil); pendingSend = nil; mutationWarning = nil }
                catch { mutationWarning = ErrorPresentation().message(error) }
            }
            else { if let sent { setDelivery(.unconfirmed, for: sent.operationID) }; mutationWarning = ErrorPresentation().message(error) }
            // The composer gets the prompt back for a retry, as it kept it before the prompt left it.
            if let sent {
                if draft.isEmpty { draft = sent.text }
                if imageDraft.images.isEmpty { imageDraft.images = sent.attachments }
            }
            // The connection bar reports a lost link; the returned draft says the send did not happen.
            self.error = neverSent ? nil : ErrorPresentation().message(error)
        }
    }
    func checkPendingSend() async {
        guard !busy, let request = pendingSend else { return }
        busy = true; defer { busy = false }
        do {
            let status = try await getOperation(request.operationID)
            guard status.operationID == request.operationID else { throw BridgeError("invalid_response", "The operation identity changed.", status: 502) }
            if status.state == .accepted { try await confirmSend(request); await refresh(); jumpToLatest += 1 }
            else { mutationWarning = String(localized: "error.outcome_unknown"); error = mutationWarning }
        } catch { mutationWarning = ErrorPresentation().message(error); self.error = mutationWarning }
    }
    /// An explicit inspection acknowledgement releases the draft; it never sends it.
    func acknowledgePendingSend() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let released = pendingSend?.operationID
        do { try await saveRecovery(nil); outgoing.removeAll { $0.id == released }; pendingSend = nil; recoveryReady = true; recoveryFailed = false; recoveryTask = nil; mutationWarning = nil; error = nil }
        catch { mutationWarning = ErrorPresentation().message(error); self.error = mutationWarning }
    }
    private func restorePendingSend() async throws {
        guard !recoveryReady else { return }
        if recoveryTask == nil { let load = loadRecovery; recoveryTask = Task { try await load() } }
        do {
            let pending = try await recoveryTask?.value
            guard !recoveryReady else { return }
            pendingSend = pending
            if let pending {
                if draft.isEmpty { draft = pending.text }
                if imageDraft.images.isEmpty { imageDraft.images = pending.attachments }
                mutationWarning = String(localized: "error.outcome_unknown"); error = mutationWarning
            }
            recoveryReady = true; recoveryFailed = false; recoveryTask = nil
        } catch { recoveryTask = nil; recoveryFailed = true; throw error }
    }
    private func confirmSend(_ request: SendRequest) async throws {
        try await saveRecovery(nil)
        if draft == request.text { draft = "" }
        imageDraft.removeSubmitted(Set(request.attachments.map(\.id)))
        setDelivery(.sent, for: request.operationID)
        pendingSend = nil; mutationWarning = nil; error = nil; stopRequested = false
    }
    private func setDelivery(_ delivery: OutgoingPrompt.Delivery, for id: UUID) {
        if let index = outgoing.firstIndex(where: { $0.id == id }) { outgoing[index].delivery = delivery }
    }
    func interrupt(hard: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { _ = try await client.post("/v1/sessions/\(session.id)/interrupt", body: InterruptRequest(hard: hard), as: MutationReceipt.self); markInterrupted(); await refresh() }
        catch { self.error = ErrorPresentation().message(error) }
    }
}
