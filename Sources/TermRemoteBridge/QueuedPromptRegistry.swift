import Foundation
import CmuxAgentChat
import TermRemoteCore

/// Tracks prompts queued while an agent turn is still running so every connected device sees the
/// same queue above the composer until the transcript records them or the screen clears them.
///
/// Combines two authoritative host signals:
/// 1. Prompts accepted by `SessionService.send` while the conversation is already working (keeps full untruncated text).
/// 2. Prompts rendered in Antigravity's terminal queue hint (`Press <key> to edit queued messages`),
///    capturing messages typed directly on the Mac and dropping items deleted/cancelled locally.
public actor QueuedPromptRegistry {
    private struct TrackedEntry: Sendable {
        let id: String
        let text: String
        let queuedAt: Date
        let afterSeq: Int?
        let generation: String?
        let knownUserIDs: Set<String>
    }

    private struct SessionQueue: Sendable {
        var tracked: [TrackedEntry] = []
        var screenPrompts: [String] = []
        var lastScreenObservedAt: Date?
        var lastScreenHadHint: Bool = false
    }

    private var sessions: [String: SessionQueue] = [:]
    private var order: [String] = []
    private let maxSessions = 64
    private let maxEntriesPerSession = 32
    private let maxTextBytes = 4_096
    private let screenClearGrace: TimeInterval = 4
    private let idleClearGrace: TimeInterval = 10
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Records a prompt that the Bridge submitted while the agent was already running.
    public func recordSend(
        sessionID: String,
        id: String,
        text: String,
        afterSeq: Int?,
        generation: String?,
        knownUserIDs: Set<String>
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let bounded = Self.boundedUTF8(trimmed, limit: maxTextBytes)
        var queue = sessions[sessionID] ?? SessionQueue()
        guard !queue.tracked.contains(where: { $0.id == id }) else { return }
        if queue.tracked.count >= maxEntriesPerSession {
            queue.tracked.removeFirst(queue.tracked.count - maxEntriesPerSession + 1)
        }
        queue.tracked.append(TrackedEntry(
            id: id,
            text: bounded,
            queuedAt: now(),
            afterSeq: afterSeq,
            generation: generation,
            knownUserIDs: knownUserIDs
        ))
        store(queue, for: sessionID)
    }

    /// Updates the session's queue from a live terminal screen extraction (e.g. Antigravity).
    public func observeScreen(sessionID: String, extraction: AntigravityQueuedScreenExtractor.Extraction) {
        let moment = now()
        var queue = sessions[sessionID] ?? SessionQueue()
        queue.lastScreenObservedAt = moment
        queue.lastScreenHadHint = extraction.hasQueueHint
        queue.screenPrompts = Array(extraction.prompts.prefix(maxEntriesPerSession))
        if !extraction.hasQueueHint {
            // Keep very fresh sends briefly until the TUI repaints its queued hint; drop older ones
            // that were edited/cancelled locally on the Mac.
            queue.tracked.removeAll { moment.timeIntervalSince($0.queuedAt) >= screenClearGrace }
        }
        if queue.tracked.isEmpty && queue.screenPrompts.isEmpty {
            remove(sessionID)
        } else {
            store(queue, for: sessionID)
        }
    }

    /// Reconciles tracked and screen-observed queued prompts against the latest transcript page.
    public func reconcile(
        sessionID: String,
        messages: [ChatMessage],
        generation: String?,
        writable: Bool,
        working: Bool
    ) -> [QueuedPrompt] {
        guard writable else {
            remove(sessionID)
            return []
        }
        guard var queue = sessions[sessionID] else { return [] }
        let moment = now()

        let users = messages.compactMap { message -> (message: ChatMessage, text: String)? in
            guard message.role == .user, case .prose(let value) = message.kind else { return nil }
            return (message, Self.normalized(value.text))
        }

        var consumed = Set<String>()
        var remaining: [TrackedEntry] = []
        for entry in queue.tracked {
            let wanted = Self.normalized(entry.text)
            let recordedAfter: (ChatMessage) -> Bool = { message in
                if entry.knownUserIDs.contains(message.id) { return false }
                if let gen = entry.generation, gen == generation, let after = entry.afterSeq {
                    return message.seq > after
                }
                return true
            }
            if !wanted.isEmpty,
               let hit = users.first(where: { !consumed.contains($0.message.id) && recordedAfter($0.message) && $0.text.contains(wanted) }) {
                consumed.insert(hit.message.id)
                continue
            }
            if let gen = entry.generation, gen == generation,
               let hit = users.first(where: { !consumed.contains($0.message.id) && recordedAfter($0.message) }) {
                consumed.insert(hit.message.id)
                continue
            }
            if !working, !queue.lastScreenHadHint, moment.timeIntervalSince(entry.queuedAt) >= idleClearGrace {
                continue
            }
            remaining.append(entry)
        }
        queue.tracked = remaining

        if !working && !queue.lastScreenHadHint {
            queue.screenPrompts = []
        }

        if queue.tracked.isEmpty && queue.screenPrompts.isEmpty {
            remove(sessionID)
            return []
        }
        store(queue, for: sessionID)
        return merged(queue)
    }

    public func hasEntries(sessionID: String) -> Bool {
        guard let queue = sessions[sessionID] else { return false }
        return !queue.tracked.isEmpty || !queue.screenPrompts.isEmpty
    }

    public func clear(sessionID: String) {
        remove(sessionID)
    }

    /// Compact change token included in the history subscription stamp so all devices refresh immediately.
    public func stamp(sessionID: String) -> String {
        guard let queue = sessions[sessionID] else { return "0" }
        let items = merged(queue)
        guard !items.isEmpty else { return "0" }
        let ids = items.map { "\($0.id):\($0.text.utf8.count)" }.joined(separator: ",")
        return "\(items.count):\(IdentityCryptography().digest(Data(ids.utf8)).prefix(16))"
    }

    private func merged(_ queue: SessionQueue) -> [QueuedPrompt] {
        var result: [QueuedPrompt] = queue.tracked.map {
            QueuedPrompt(id: $0.id, text: $0.text, queuedAt: $0.queuedAt)
        }
        let trackedNormalized = queue.tracked.map { Self.normalized($0.text) }
        for (index, raw) in queue.screenPrompts.enumerated() {
            let norm = Self.normalized(raw)
            guard !norm.isEmpty else { continue }
            let trimmedEllipsis = norm.hasSuffix("…") ? String(norm.dropLast()).trimmingCharacters(in: .whitespaces) : norm
            let alreadyTracked = trackedNormalized.contains { candidate in
                candidate == norm
                    || (!trimmedEllipsis.isEmpty && (candidate.hasPrefix(trimmedEllipsis) || trimmedEllipsis.hasPrefix(candidate)))
            }
            if !alreadyTracked {
                let digest = IdentityCryptography().digest(Data("\(index):\(norm)".utf8)).prefix(16)
                result.append(QueuedPrompt(id: "screen-\(digest)", text: raw, queuedAt: queue.lastScreenObservedAt))
            }
            if result.count >= maxEntriesPerSession { break }
        }
        return result
    }

    private func store(_ queue: SessionQueue, for sessionID: String) {
        if sessions[sessionID] == nil {
            if order.count >= maxSessions, let oldest = order.first {
                order.removeFirst()
                sessions[oldest] = nil
            }
            order.append(sessionID)
        }
        sessions[sessionID] = queue
    }

    private func remove(_ sessionID: String) {
        sessions[sessionID] = nil
        order.removeAll { $0 == sessionID }
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func boundedUTF8(_ text: String, limit: Int) -> String {
        guard text.utf8.count > limit else { return text }
        var out = ""
        out.reserveCapacity(limit)
        var bytes = 0
        for scalar in text.unicodeScalars {
            let size = scalar.utf8.count
            if bytes + size > limit { break }
            out.unicodeScalars.append(scalar)
            bytes += size
        }
        return out
    }
}
