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
    /// Whether the agent is compacting its context, as the terminal reports it.
    var compacting = false
    /// Tasks the agent detached and has not finished. They outlive the turn that started them.
    private(set) var backgroundTasks: [BackgroundAgentTask] = []
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
    /// The last read of this conversation, shown on open while the fresh one is on its way.
    private let cache: ConversationCache?
    private let refreshReads = ReadRequestOwner()
    private let olderReads = ReadRequestOwner()
    private var readsEnabled = true
    /// Whether the conversation is on screen and following its own changes.
    private var observing = false
    /// The off-screen follower, replaced by the conversation's own observer while it is on screen.
    private var follower: Task<Void, Never>?
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
         readPreview: (@Sendable () async throws -> PreviewSnapshot)? = nil,
         cache: ConversationCache? = nil) {
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
        self.cache = cache
    }
    /// Shows what was read last, so opening a conversation never starts blank.
    ///
    /// This displays stored content rather than deciding anything: the refresh that follows replaces it
    /// whether or not the conversation changed, and a stored generation the Bridge has replaced is ignored.
    func restoreStored() async {
        guard messages.isEmpty, generation == nil, let cache else { return }
        guard let entry = await cache.load(scope: client.operationRecoveryScope, sessionID: session.id) else { return }
        // The read may have landed while the stored copy was being read; the fresh one wins.
        guard readsEnabled, messages.isEmpty, generation == nil else { return }
        generation = entry.snapshot.generation; hasMore = entry.snapshot.hasMore
        applyStored(entry.snapshot, live: entry.preview)
    }
    /// Displays a stored copy as it was written; merging belongs to reads that arrive from the link.
    private func applyStored(_ history: ConversationSnapshot, live: PreviewSnapshot?) {
        clipped = history.clipped
        messages = history.messages
        images = history.images ?? []
        responses = history.responses ?? []
        backgroundTasks = history.backgroundTasks ?? []
        recordedRunSeconds = history.recordedRunSeconds; recordedTurnCount = history.recordedTurnCount ?? 0
        currentTurnStartedAt = history.currentTurnStartedAt; currentTurnCompleted = history.currentTurnCompleted ?? false
        timelineItems = ConversationTimeline().items(from: messages)
        let committed = messages.reversed().compactMap { message -> String? in
            if message.role == .agent, case .prose(let value) = message.kind { return value.text }; return nil
        }.first
        preview = live?.text == committed ? nil : live?.text; compacting = live?.compacting ?? false
        if stopRequested, messages.last(where: { $0.role == .user })?.id != interruptedUserID { stopRequested = false }
    }
    /// Stores the read that just landed, so the next open of this conversation is immediate.
    private func store(_ history: ConversationSnapshot, live: PreviewSnapshot?) {
        guard let cache else { return }
        let entry = ConversationCache.Entry(snapshot: history, preview: live, storedAt: Date())
        let scope = client.operationRecoveryScope, id = session.id
        Task { await cache.save(entry, scope: scope, sessionID: id) }
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
        // On screen the conversation follows its own changes; an off-screen follower would subscribe to them again.
        observing = true; unfollow(); defer { observing = false }
        let paths = ["/v1/sessions/\(session.id)/history", "/v1/sessions/\(session.id)/preview", "/v1/sessions"]
        for await _ in client.changes(paths: paths) {
            guard !Task.isCancelled, readsEnabled else { return }; await refresh()
        }
    }
    /// Whether an off-screen follower is running for this conversation.
    var following: Bool { follower != nil }
    /// Follows this conversation while it runs off screen, so switching to it shows its latest messages.
    /// Nothing starts while it is on screen, where its own observer already follows it.
    func follow(every interval: Duration) {
        guard follower == nil, !observing else { return }
        follower = Task { [weak self] in await self?.followHidden(every: interval) }
    }
    func unfollow() { follower?.cancel(); follower = nil }
    /// Reads once, then again only after the Bridge reports a change, and at most once per interval: a running turn
    /// changes every few seconds, and waiting lets those changes coalesce into one read.
    ///
    /// Only the history is watched. A Bridge link carries at most eight subscriptions, and the conversation on
    /// screen, the session list and the feed already use some; the live tail is read with the history anyway.
    private func followHidden(every interval: Duration) async {
        await syncHidden()
        for await _ in client.changes(paths: ["/v1/sessions/\(session.id)/history"]) {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await syncHidden()
        }
    }
    /// One read for a conversation not on screen; one that is on screen is kept current by its own observer.
    func syncHidden() async {
        guard !observing, !busy, !Task.isCancelled else { return }
        await refreshReads.run { [self] request in await readLatest(request) }
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
            catch { if refreshReads.isCurrent(request) { logFailure("refresh.recovery", error, shown: true); mutationWarning = ErrorPresentation().message(error) } }
            guard refreshReads.isCurrent(request) else { return }
            let descriptors = try await readSessions()
            guard refreshReads.isCurrent(request) else { return }
            guard let current = descriptors.first(where: { $0.id == session.id }) else { throw BridgeError("read_only", "The cmux session is no longer available.", status: 404) }
            let history = try await readHistory(nil)
            guard refreshReads.isCurrent(request) else { return }
            let live = try? await readPreview()
            guard refreshReads.isCurrent(request) else { return }
            updateSession(current)
            // A page read from a replaced transcript is not merged into the one on screen; it replaces it.
            let continues = generation == history.generation
            if continues, !messages.isEmpty {
                var next = messages
                var positions = [String: Int](minimumCapacity: next.count)
                for (index, message) in next.enumerated() { positions[message.id] = index }
                for message in history.messages {
                    if let index = positions[message.id] { next[index] = message }
                    else { positions[message.id] = next.count; next.append(message) }
                }
                messages = next.sorted { $0.seq < $1.seq }
            } else { olderReads.suspend(); loadingOlder = false; messages = history.messages; responses = []; generation = history.generation; hasMore = history.hasMore }
            clipped = history.clipped
            let updatedIDs = Set(history.messages.map(\.id))
            images = images.filter { $0.generation == history.generation && !updatedIDs.contains($0.messageID) } + (history.images ?? [])
            if stopRequested, messages.last(where: { $0.role == .user })?.id != interruptedUserID { stopRequested = false }
            if continues {
                let incoming = history.responses ?? []
                let anchors = Set(incoming.map(\.firstMessageID))
                responses = responses.filter { !anchors.contains($0.firstMessageID) } + incoming
            }
            // Only a newest-page read carries them, so an earlier page must not clear the set.
            if history.backgroundTasks != nil { backgroundTasks = history.backgroundTasks ?? [] }
            recordedRunSeconds = history.recordedRunSeconds; recordedTurnCount = history.recordedTurnCount ?? 0
            currentTurnStartedAt = history.currentTurnStartedAt; currentTurnCompleted = history.currentTurnCompleted ?? false
            timelineItems = ConversationTimeline().items(from: messages)
            outgoing = OutgoingPromptMatcher().pending(outgoing, messages: messages, generation: generation)
            let committed = messages.reversed().compactMap { message -> String? in
                if message.role == .agent, case .prose(let value) = message.kind { return value.text }; return nil
            }.first
            preview = live?.text == committed ? nil : live?.text; compacting = live?.compacting ?? false; error = mutationWarning
            store(history, live: live)
        } catch {
            // A lost link is shown and retried by the connection bar; the page keeps only errors about the conversation.
            guard refreshReads.isCurrent(request) else { return }
            let shown = !ErrorPresentation().isConnectivity(error)
            logFailure("refresh", error, shown: shown)
            self.error = shown ? ErrorPresentation().message(error) : mutationWarning
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
                guard olderReads.isCurrent(request), generation == sourceGeneration else { return }
                let shown = !ErrorPresentation().isConnectivity(error)
                logFailure("older", error, shown: shown)
                guard shown else { return }
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
            logFailure("send", error, shown: !neverSent)
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
        } catch { logFailure("checkPendingSend", error, shown: true); mutationWarning = ErrorPresentation().message(error); self.error = mutationWarning }
    }
    /// An explicit inspection acknowledgement releases the draft; it never sends it.
    func acknowledgePendingSend() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let released = pendingSend?.operationID
        do { try await saveRecovery(nil); outgoing.removeAll { $0.id == released }; pendingSend = nil; recoveryReady = true; recoveryFailed = false; recoveryTask = nil; mutationWarning = nil; error = nil }
        catch { logFailure("acknowledgePendingSend", error, shown: true); mutationWarning = ErrorPresentation().message(error); self.error = mutationWarning }
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
        catch { logFailure("interrupt", error, shown: true); self.error = ErrorPresentation().message(error) }
    }
    /// One line per failure the page handles: an error when it raises the red line, a warning when the connection bar owns it.
    private func logFailure(_ operation: String, _ error: any Error, shown: Bool) {
        diagLog(shown ? .error : .warning, category: "conversation",
                "op=\(operation) error=\(TraceFormat().describe(error)) session=\(session.id.prefix(8)) shown=\(shown)")
    }
}
