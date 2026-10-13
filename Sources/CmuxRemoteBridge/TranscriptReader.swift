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
    }
    private var observations: [String: Observation] = [:]
    /// Long conversations are read from a bounded tail; the window start moves in whole steps so sequence numbers stay stable while the file grows.
    private let windowLimit: Int
    private let windowStep: Int
    public init(windowLimit: Int = 33_554_432, windowStep: Int = 8_388_608) {
        self.windowLimit = max(1, windowLimit); self.windowStep = max(1, min(windowStep, windowLimit))
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
    public func history(path: String, agent: String, beforeSeq: Int?, limit: Int, allowsUncreatedTranscript: Bool = false) throws -> ConversationSnapshot {
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
            return page(previous.messages, images: previous.images, presentation: previous.presentation, beforeSeq: beforeSeq, limit: limit, generation: previous.generation, clipped: previous.windowStart > 0)
        }
        let (data, windowStart) = try window(path: url.path, size: size.intValue)
        // A moved window renumbers records, so clients re-anchor exactly as after truncation.
        let reset = previous == nil || previous?.inode != inode || size.intValue < (previous?.size ?? 0) || previous?.windowStart != windowStart
        let generation = reset ? UUID() : previous!.generation
        guard let end = data.lastIndex(of: 10) else {
            observations[path] = Observation(inode: inode, size: size.intValue, modified: modified, generation: generation, windowStart: windowStart, images: [], messages: [], presentation: .init())
            return page([], images: [], presentation: .init(), beforeSeq: beforeSeq, limit: limit, generation: generation, clipped: windowStart > 0)
        }
        let raw = String(decoding: data[...end], as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
        let compaction = agent == "claude" ? ClaudeCompactionSummary().replace(raw) : .init(lines: raw, markers: [])
        let lines = agent == "claude" ? ClaudeTaskNoticeRewriter().normalize(ClaudeQueuedPromptNormalizer().normalize(compaction.lines)) : raw
        let result = agent == "claude" ? ClaudeTranscriptParser().parse(lines: lines, startingSeq: 0) : CodexTranscriptParser().parse(lines: lines, startingSeq: 0)
        var messages = result.messages
        for update in result.updatedMessages {
            if let index = messages.firstIndex(where: { $0.id == update.id }) { messages[index] = update }
        }
        let imageIndex = try TranscriptImageIndex().read(lines: lines, messages: messages, agent: agent)
        messages.append(contentsOf: imageIndex.supplementalMessages + compaction.markers); messages.sort { $0.seq < $1.seq }
        let presentation = TranscriptResponseReader().read(lines: lines, messages: messages, agent: agent)
        if observations.count >= 32, observations[path] == nil { observations.removeAll() }
        observations[path] = Observation(inode: inode, size: size.intValue, modified: modified, generation: generation, windowStart: windowStart, images: imageIndex.records, messages: messages, presentation: presentation)
        return page(messages, images: imageIndex.records, presentation: presentation, beforeSeq: beforeSeq, limit: limit, generation: generation, clipped: windowStart > 0)
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

    private func page(_ messages: [ChatMessage], images: [TranscriptImageRecord], presentation: TranscriptResponseReader.Result, beforeSeq: Int?, limit: Int, generation: UUID, clipped: Bool) -> ConversationSnapshot {
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
            images: images.filter { ids.contains($0.messageID) }.map { $0.reference(generation: generation.uuidString) })
    }
}
