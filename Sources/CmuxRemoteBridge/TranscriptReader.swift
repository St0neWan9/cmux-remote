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
        let messages: [ChatMessage]
    }
    private var observations: [String: Observation] = [:]
    public init() {}
    public func history(path: String, agent: String, beforeSeq: Int?, limit: Int) throws -> ConversationSnapshot {
        let url = URL(fileURLWithPath: path)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= 32 * 1024 * 1024 else {
            throw BridgeError("history_too_large", "This conversation exceeds the initial history reader limit.", status: 413)
        }
        let inode = "\(attributes[.systemFileNumber] ?? "unknown")"
        let modified = attributes[.modificationDate] as? Date
        let previous = observations[path]
        let reset = previous == nil || previous?.inode != inode || size.intValue < (previous?.size ?? 0)
        let generation = reset ? UUID() : previous!.generation
        if let previous, !reset, previous.size == size.intValue, previous.modified == modified {
            return page(previous.messages, beforeSeq: beforeSeq, limit: limit, generation: generation)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let end = data.lastIndex(of: 10) else {
            observations[path] = Observation(inode: inode, size: size.intValue, modified: modified, generation: generation, messages: [])
            return page([], beforeSeq: beforeSeq, limit: limit, generation: generation)
        }
        let lines = String(decoding: data[...end], as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
        let result = agent == "claude" ? ClaudeTranscriptParser().parse(lines: lines, startingSeq: 0) : CodexTranscriptParser().parse(lines: lines, startingSeq: 0)
        var messages = result.messages
        for update in result.updatedMessages {
            if let index = messages.firstIndex(where: { $0.id == update.id }) { messages[index] = update }
        }
        if observations.count >= 32, observations[path] == nil { observations.removeAll() }
        observations[path] = Observation(inode: inode, size: size.intValue, modified: modified, generation: generation, messages: messages)
        return page(messages, beforeSeq: beforeSeq, limit: limit, generation: generation)
    }
    private func page(_ messages: [ChatMessage], beforeSeq: Int?, limit: Int, generation: UUID) -> ConversationSnapshot {
        let eligible = messages.filter { beforeSeq == nil || $0.seq < beforeSeq! }
        let count = min(max(limit, 1), 200)
        var start = max(0, eligible.count - count)
        while start > 0, eligible[start - 1].seq == eligible[start].seq { start -= 1 }
        return ConversationSnapshot(messages: Array(eligible[start...]), hasMore: start > 0, generation: generation.uuidString, clipped: false)
    }
}
