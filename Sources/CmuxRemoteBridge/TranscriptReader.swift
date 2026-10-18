import Foundation
import CmuxRemoteCore
import CmuxAgentChat

/// Reads complete, bounded JSONL records; partial trailing lines are not committed.
public actor TranscriptReader {
    private struct Observation {
        let inode: String
        let size: Int
        let modified: Date?
        let generation: UUID
        let windowStart: Int
        let images: [TranscriptImageRecord]
        let messages: [ChatMessage]
        let presentation: TranscriptResponseReader.Result
        let agentModel: AgentModelState?
    }
    private var observations: [String: Observation] = [:]
    /// Last-read order per path; an eviction takes the lowest, which is the least recently read.
    private var observationOrder: [String: Int] = [:]
    private var observationSequence = 0
    /// Long conversations are read from a bounded tail; the window start moves in whole steps so sequence numbers stay stable while the file grows.
    private let windowLimit: Int
    private let windowStep: Int
    /// Detached calls per transcript. Tasks outlive the turn that started them, so they are kept beside the
    /// messages; keyed by path, because one reader serves every conversation and an unchanged record is
    /// answered from this cache.
    private var launches: [String: [BackgroundTaskTracker.Launch]] = [:]
    private static let capacity = 32
    /// A Monitor's deadline passes while its record stays unchanged, so running is decided at read time.
    private let now: @Sendable () -> Date
    public init(windowLimit: Int = 33_554_432, windowStep: Int = 8_388_608, now: @escaping @Sendable () -> Date = { Date() }) {
        self.windowLimit = max(1, windowLimit); self.windowStep = max(1, min(windowStep, windowLimit)); self.now = now
    }

    /// A cheap identity of the record a read of this path would answer from, or nil when unprovable.
    ///
    /// Two equal stamps mean a repeated read answers from the same cached record with the same running
    /// tasks, so a subscription may skip it. Read from file metadata alone: no file read, no parse. Nil
    /// — do the work — when the record is not cached, the file no longer matches it, or the metadata
    /// cannot be read.
    public func stamp(path: String) -> String? {
        guard let cached = observations[path],
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        let inode = "\(attributes[.systemFileNumber] ?? "unknown")"
        guard cached.inode == inode, cached.size == size, cached.modified == modified else { return nil }
        // A Monitor's deadline changes the answer while the file stays still.
        let moment = now()
        let running = (launches[path] ?? []).filter { $0.isRunning(at: moment) }.count
        return "\(cached.generation.uuidString):\(inode):\(size):\(modified.timeIntervalSinceReferenceDate):\(running)"
    }

    private func touch(_ path: String) {
        observationSequence += 1; observationOrder[path] = observationSequence
    }
    /// Evicts the least recently read record, one per insertion, instead of the whole cache: a burst of
    /// new paths used to guarantee a full re-parse of every conversation still open. A record and its
    /// launches leave together, so a cached record never answers without its running tasks.
    private func store(_ observation: Observation, launches scanned: [BackgroundTaskTracker.Launch], for path: String) {
        if observations[path] == nil, observations.count >= Self.capacity,
           let oldest = observationOrder.min(by: { $0.value < $1.value })?.key {
            observations[oldest] = nil; launches[oldest] = nil; observationOrder[oldest] = nil
        }
        observations[path] = observation; launches[path] = scanned; touch(path)
    }
    /// The newest complete lines of a transcript within the read window, and where that window starts.
    private func window(path: String, size: Int) throws -> (data: Data, start: Int) {
        let start = size > windowLimit ? (size - windowLimit + windowStep - 1) / windowStep * windowStep : 0
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)); defer { try? handle.close() }
        // One byte before the window shows whether it begins on a line boundary.
        let readStart = max(0, start - 1)
        try handle.seek(toOffset: UInt64(readStart))
        var data = Data()
        while data.count < size - readStart, let chunk = try handle.read(upToCount: min(1_048_576, size - readStart - data.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            data.append(chunk)
        }
        guard start > 0 else { return (data, 0) }
        // A record cut by the window start is never parsed.
        guard let firstBreak = data.firstIndex(of: 10) else { return (Data(), start) }
        return (Data(data[data.index(after: firstBreak)...]), start)
    }
    /// - Parameter reportsBackgroundTasks: Whether the agent process that owns this record is still running.
    ///   Its detached tasks die with it, so an ended session reports none, whatever its record says.
    public func history(path: String, agent: String, beforeSeq: Int?, limit: Int, allowsUncreatedTranscript: Bool = false,
                        reportsBackgroundTasks: Bool = true) throws -> ConversationSnapshot {
        let url = URL(fileURLWithPath: path)
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: path) }
        catch {
            let failure = error as NSError
            // A newly bound agent may not create its JSONL until the first prompt.
            // Never turn a deleted, previously read transcript into an empty history.
            guard allowsUncreatedTranscript, observations[path] == nil,
                  failure.domain == NSCocoaErrorDomain,
                  [CocoaError.fileNoSuchFile.rawValue, CocoaError.fileReadNoSuchFile.rawValue].contains(failure.code) else { throw error }
            let generation = "pending:" + IdentityCryptography().digest(Data(path.utf8))
            return ConversationSnapshot(messages: [], hasMore: false, generation: generation, clipped: false)
        }
        guard let size = attributes[.size] as? NSNumber else { throw BridgeError("history_unavailable", "The conversation record size is unavailable.", status: 404) }
        let inode = "\(attributes[.systemFileNumber] ?? "unknown")"
        let modified = attributes[.modificationDate] as? Date
        let previous = observations[path]
        if let previous, previous.inode == inode, previous.size == size.intValue, previous.modified == modified {
            touch(path)
            return page(previous.messages, images: previous.images, presentation: previous.presentation, beforeSeq: beforeSeq, limit: limit, generation: previous.generation, clipped: previous.windowStart > 0,
                        backgroundTasks: runningTasks(path, reports: reportsBackgroundTasks), agentModel: previous.agentModel)
        }
        let (data, windowStart) = try window(path: url.path, size: size.intValue)
        // Cheap line scan over the same window the parse reads; a launch and its completion can sit far apart.
        let scanned = scannedLaunches(data)
        // A moved window renumbers records, so clients re-anchor exactly as after truncation.
        let reset = previous == nil || previous?.inode != inode || size.intValue < (previous?.size ?? 0) || previous?.windowStart != windowStart
        let generation = reset ? UUID() : previous!.generation
        guard let end = data.lastIndex(of: 10) else {
            store(Observation(inode: inode, size: size.intValue, modified: modified, generation: generation, windowStart: windowStart, images: [], messages: [], presentation: .init(), agentModel: nil), launches: scanned, for: path)
            return page([], images: [], presentation: .init(), beforeSeq: beforeSeq, limit: limit, generation: generation, clipped: windowStart > 0,
                        backgroundTasks: runningTasks(path, reports: reportsBackgroundTasks))
        }
        let raw = String(decoding: data[...end], as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
        // Read before normalization, which folds away the command output that records a Claude switch.
        let agentModel = TranscriptModelReader().read(lines: raw, agent: agent)
        let compaction = agent == "claude" ? ClaudeCompactionSummary().replace(raw) : .init(lines: raw, markers: [])
        let lines = agent == "claude" ? ClaudeTaskNoticeRewriter().normalize(ClaudeQueuedPromptNormalizer().normalize(compaction.lines)) : raw
        let result = agent == "claude" ? ClaudeTranscriptParser().parse(lines: lines, startingSeq: 0) : CodexTranscriptParser().parse(lines: lines, startingSeq: 0)
        // A record may repeat an id as it develops; one index by id beats a scan per update.
        var positions: [String: Int] = [:]
        for (index, message) in result.messages.enumerated() where positions[message.id] == nil { positions[message.id] = index }
        var messages = result.messages
        for update in result.updatedMessages {
            if let index = positions[update.id] { messages[index] = update }
        }
        let imageIndex = try TranscriptImageIndex().read(lines: lines, messages: messages, agent: agent)
        messages.append(contentsOf: imageIndex.supplementalMessages + compaction.markers); messages.sort { $0.seq < $1.seq }
        let presentation = TranscriptResponseReader().read(lines: lines, messages: messages, agent: agent)
        store(Observation(inode: inode, size: size.intValue, modified: modified, generation: generation, windowStart: windowStart, images: imageIndex.records, messages: messages, presentation: presentation, agentModel: agentModel), launches: scanned, for: path)
        return page(messages, images: imageIndex.records, presentation: presentation, beforeSeq: beforeSeq, limit: limit, generation: generation, clipped: windowStart > 0,
                    backgroundTasks: runningTasks(path, reports: reportsBackgroundTasks), agentModel: agentModel)
    }
    /// The detached calls still open in one window, paired from launches, stops and completion notices.
    private func scannedLaunches(_ data: Data) -> [BackgroundTaskTracker.Launch] {
        guard let end = data.lastIndex(of: 10) else { return [] }
        let lines = String(decoding: data[...end], as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return BackgroundTaskTracker().launches(in: lines)
    }
    /// This record's tasks still running now; none once the agent that owned them has ended.
    private func runningTasks(_ path: String, reports: Bool) -> [BackgroundAgentTask] {
        guard reports else { return [] }
        let moment = now()
        return (launches[path] ?? []).filter { $0.isRunning(at: moment) }.map(\.task)
    }
    /// Read a tool's complete supported text without inflating ordinary history snapshots.
    public func toolText(path: String, agent: String, messageID: String, generation: String,
                         field: String, offset: Int, contentID: String?, limit: Int) throws -> ToolTextPage {
        try Task.checkCancellation()
        let snapshot = try history(path: path, agent: agent, beforeSeq: nil, limit: 1)
        let selectedGeneration = generation == "current" && offset == 0 && contentID == nil ? snapshot.generation : generation
        guard snapshot.generation == selectedGeneration else { throw BridgeError("stale_detail", "The conversation record changed. Reload this detail.", status: 409) }
        guard observations[path]?.messages.contains(where: { $0.id == messageID }) == true else { throw BridgeError("detail_not_found", "This tool record is unavailable.", status: 404) }
        guard let observed = observations[path] else { throw BridgeError("stale_detail", "The conversation record changed. Reload this detail.", status: 409) }
        // The same window as the snapshot keeps message identities aligned.
        let data = try window(path: path, size: observed.size).data
        guard let end = data.lastIndex(of: 10) else { throw BridgeError("detail_not_found", "No complete tool record is available.", status: 404) }
        let raw = String(decoding: data[...end], as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
        let lines = agent == "claude" ? ClaudeTaskNoticeRewriter().normalize(ClaudeQueuedPromptNormalizer().normalize(ClaudeCompactionSummary().replace(raw).lines)) : raw
        try Task.checkCancellation()
        let result = agent == "claude"
            ? ClaudeTranscriptParser(maxBodyCharacters: 33_554_432, maxInputDetailCharacters: 33_554_432).parse(lines: lines, startingSeq: 0)
            : CodexTranscriptParser(maxBodyCharacters: 33_554_432, maxInputDetailCharacters: 33_554_432).parse(lines: lines, startingSeq: 0)
        guard let message = (result.updatedMessages + result.messages).first(where: { $0.id == messageID }) else { throw BridgeError("detail_not_found", "This tool record is unavailable.", status: 404) }
        let text: String
        switch (message.kind, field) {
        case (.toolUse(let tool), "input"): text = tool.inputDetail ?? ""
        case (.toolUse(let tool), "output"): text = tool.output ?? ""
        case (.terminal(let tool), "input"): text = tool.command
        case (.terminal(let tool), "output"): text = tool.output ?? ""
        case (.fileEdit(let tool), "diff"): text = tool.unifiedDiff ?? ""
        default: throw BridgeError("invalid_input", "Select a supported field of a tool record.", status: 422)
        }
        let refreshed = try history(path: path, agent: agent, beforeSeq: nil, limit: 1)
        guard refreshed.generation == selectedGeneration else { throw BridgeError("stale_detail", "The conversation record changed during this read.", status: 409) }
        let digest = IdentityCryptography().digest(Data(text.utf8))
        guard contentID == nil || contentID == digest else { throw BridgeError("stale_detail", "The tool output changed. Reload this detail.", status: 409) }
        try Task.checkCancellation()
        let total = text.unicodeScalars.count
        guard offset >= 0, offset <= total else { throw BridgeError("invalid_input", "The text page offset is invalid.", status: 422) }
        let pageText = String(String.UnicodeScalarView(text.unicodeScalars.dropFirst(offset).prefix(min(16_384, max(1, limit)))))
        let next = offset + pageText.unicodeScalars.count
        return ToolTextPage(messageID: messageID, generation: selectedGeneration, field: field, contentID: digest,
                            text: pageText, offset: offset, nextOffset: next < total ? next : nil, totalCharacters: total)
    }

    func image(path: String, agent: String, referenceID: String, generation: String) throws -> TranscriptImageRecord {
        let current = try history(path: path, agent: agent, beforeSeq: nil, limit: 1)
        guard current.generation == generation else { throw BridgeError("stale_detail", "The image record changed. Reload the conversation.", status: 409) }
        guard let record = observations[path]?.images.first(where: { $0.reference(generation: generation).id == referenceID }) else { throw BridgeError("image_unavailable", "This recorded image is unavailable.", status: 404) }
        return record
    }

    private func page(_ messages: [ChatMessage], images: [TranscriptImageRecord], presentation: TranscriptResponseReader.Result, beforeSeq: Int?, limit: Int, generation: UUID, clipped: Bool, backgroundTasks: [BackgroundAgentTask], agentModel: AgentModelState? = nil) -> ConversationSnapshot {
        let eligible = messages.filter { beforeSeq == nil || $0.seq < beforeSeq! }
        let count = min(max(limit, 1), 200)
        var start = max(0, eligible.count - count)
        while start > 0, eligible[start - 1].seq == eligible[start].seq { start -= 1 }
        let pageMessages = Array(eligible[start...])
        let ids = Set(pageMessages.map(\.id))
        return ConversationSnapshot(messages: pageMessages, hasMore: start > 0, generation: generation.uuidString, clipped: clipped,
            responses: presentation.responses.filter { ids.contains($0.firstMessageID) || ids.contains($0.lastMessageID) },
            recordedRunSeconds: presentation.recordedRunSeconds, recordedTurnCount: presentation.recordedTurnCount,
            currentTurnStartedAt: presentation.currentTurnStartedAt, currentTurnCompleted: presentation.currentTurnCompleted,
            images: images.filter { ids.contains($0.messageID) }.map { $0.reference(generation: generation.uuidString) },
            // Only the newest page reports them; an earlier page must not re-add a task the reader scrolled past.
            backgroundTasks: beforeSeq == nil ? backgroundTasks : nil,
            agentModel: beforeSeq == nil ? agentModel : nil)
    }
}
