import Foundation
import CmuxAgentChat
import CmuxRemoteCore

/// Enriches upstream parsed messages without modifying the pinned parser or reading extra files.
struct TranscriptResponseReader {
    struct Result {
        var responses: [ConversationResponse] = []
        var recordedRunSeconds: Double?
        var recordedTurnCount = 0
        var currentTurnStartedAt: Date?
        var currentTurnCompleted = false
    }
    func read(lines: [String], messages: [ChatMessage], agent: String) -> Result {
        let grouped = Dictionary(grouping: messages, by: \.seq)
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let decoder = JSONDecoder()
        var result = Result()
        var start: Date?
        var runStart: Date?
        var runID: String?
        var response: [ChatMessage] = []
        var lastResponseStamp: Date?
        var finished = false
        func valid(_ date: Date?) -> Date? { guard let date, date.timeIntervalSince1970 > 0 else { return nil }; return date }
        func finish(at end: Date?, duration: Double?, recorded: Bool, completed: Bool = true) {
            guard !finished else { return }
            let elapsed = duration ?? end.flatMap { end in start.map { end.timeIntervalSince($0) } }
            let seconds = elapsed.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            if recorded, let seconds {
                result.recordedRunSeconds = (result.recordedRunSeconds ?? 0) + seconds
                result.recordedTurnCount += 1
            }
            result.currentTurnCompleted = completed
            finished = true
            guard let first = response.first, let last = response.last else { return }
            result.responses.append(ConversationResponse(firstMessageID: first.id, lastMessageID: last.id, startedAt: start, completedAt: end, durationSeconds: seconds, recordedDuration: recorded && seconds != nil, completed: completed, firstSeq: first.seq, lastSeq: last.seq))
        }
        for (seq, line) in lines.enumerated() {
            guard let data = line.data(using: .utf8), let root = try? decoder.decode(JSONValue.self, from: data), root.object != nil, root["isSidechain"].bool != true else { continue }
            let stamp = root["timestamp"].string.flatMap { fractional.date(from: $0) ?? plain.date(from: $0) }.flatMap(valid)
            let rowMessages = grouped[seq] ?? []
            if agent == "claude", isInterruption(root) {
                // Claude writes its interruption as a synthetic user message.
                // It closes the existing turn; it does not start a new request.
                finish(at: stamp, duration: nil, recorded: false)
                continue
            }
            if rowMessages.contains(where: { $0.role == .user }) {
                finish(at: lastResponseStamp, duration: nil, recorded: false)
                response = []; start = stamp; lastResponseStamp = nil; finished = false
                result.currentTurnStartedAt = stamp; result.currentTurnCompleted = false
            }
            for message in rowMessages where message.role == .agent {
                response.append(message); lastResponseStamp = stamp
            }
            if agent == "claude", root["type"].string == "system", root["subtype"].string == "turn_duration",
               case .number(let duration) = root["durationMs"], duration.isFinite, duration >= 0 {
                finish(at: stamp, duration: duration / 1000, recorded: true)
            }
            if agent == "codex", root["type"].string == "event_msg", root["payload"].object != nil {
                let payload = root["payload"]
                if payload["type"].string == "task_started" { runStart = stamp; runID = payload["turn_id"].string }
                if (payload["type"].string == "task_complete" || payload["type"].string == "turn_aborted"),
                   runID == payload["turn_id"].string {
                    let elapsed = stamp.flatMap { end in runStart.map { end.timeIntervalSince($0) } }
                    finish(at: stamp, duration: elapsed, recorded: elapsed != nil); runStart = nil; runID = nil
                }
            }
        }
        // An unfinished response has no fabricated completion time or running duration.
        finish(at: nil, duration: nil, recorded: false, completed: false)
        return result
    }
    private func isInterruption(_ root: JSONValue) -> Bool {
        guard root["type"].string == "user" else { return false }
        let content = root["message"]["content"]
        let marker = "[Request interrupted by user]"
        if let text = content.string { return text == marker }
        guard let blocks = content.array, blocks.count == 1 else { return false }
        return blocks[0]["type"].string == "text" && blocks[0]["text"].string == marker
    }
}
