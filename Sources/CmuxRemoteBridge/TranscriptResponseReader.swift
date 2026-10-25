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
    /// What the records read so far established. A turn may still be open when a chunk ends, so the state
    /// is carried to the next chunk instead of being closed there.
    struct State: Sendable {
        var result = Result()
        var start: Date?
        var runStart: Date?
        var runID: String?
        var response: [ChatMessage] = []
        var lastResponseStamp: Date?
        var finished = false
    }
    func read(lines: [String], messages: [ChatMessage], agent: String) -> Result {
        var state = State()
        consume(lines: lines, startingSeq: 0, messages: messages, agent: agent, into: &state)
        return snapshot(state)
    }
    /// Folds one chunk of records into `state`; chunks must arrive in record order.
    func consume(lines: [String], startingSeq: Int, messages: [ChatMessage], agent: String, into state: inout State) {
        let grouped = Dictionary(grouping: messages, by: \.seq)
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let decoder = JSONDecoder()
        func valid(_ date: Date?) -> Date? { guard let date, date.timeIntervalSince1970 > 0 else { return nil }; return date }
        func finish(at end: Date?, duration: Double?, recorded: Bool, completed: Bool = true) {
            guard !state.finished else { return }
            let elapsed = duration ?? end.flatMap { end in state.start.map { end.timeIntervalSince($0) } }
            let seconds = elapsed.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            if recorded, let seconds {
                state.result.recordedRunSeconds = (state.result.recordedRunSeconds ?? 0) + seconds
                state.result.recordedTurnCount += 1
            }
            state.result.currentTurnCompleted = completed
            state.finished = true
            guard let first = state.response.first, let last = state.response.last else { return }
            state.result.responses.append(ConversationResponse(firstMessageID: first.id, lastMessageID: last.id, startedAt: state.start, completedAt: end, durationSeconds: seconds, recordedDuration: recorded && seconds != nil, completed: completed, firstSeq: first.seq, lastSeq: last.seq))
        }
        for (offset, line) in lines.enumerated() {
            let seq = startingSeq + offset
            guard let data = line.data(using: .utf8), let root = try? decoder.decode(JSONValue.self, from: data), root.object != nil, root["isSidechain"].bool != true else { continue }
            let stamp = root["timestamp"].string.flatMap { fractional.date(from: $0) ?? plain.date(from: $0) }.flatMap(valid)
            let rowMessages = grouped[seq] ?? []
            if agent == "claude", isInterruption(root) {
                // Claude writes its interruption as a synthetic user message.
                // It closes the existing turn; it does not start a new request.
                finish(at: stamp, duration: nil, recorded: false)
                continue
            }
            // A finished background task that finds Claude idle is delivered as its own user record, which the
            // chat hides as meta. Claude answers it in a new turn, so it opens a response like a prompt does;
            // without that, the answer joins the finished turn before it and never gets its own footer.
            if rowMessages.contains(where: { $0.role == .user }) || (agent == "claude" && isTaskNotice(root)) {
                finish(at: state.lastResponseStamp, duration: nil, recorded: false)
                state.response = []; state.start = stamp; state.lastResponseStamp = nil; state.finished = false
                state.result.currentTurnStartedAt = stamp; state.result.currentTurnCompleted = false
            }
            for message in rowMessages where message.role == .agent {
                state.response.append(message); state.lastResponseStamp = stamp
            }
            if agent == "claude", root["type"].string == "system", root["subtype"].string == "turn_duration",
               case .number(let duration) = root["durationMs"], duration.isFinite, duration >= 0 {
                finish(at: stamp, duration: duration / 1000, recorded: true)
            }
            if agent == "codex", root["type"].string == "event_msg", root["payload"].object != nil {
                let payload = root["payload"]
                if payload["type"].string == "task_started" { state.runStart = stamp; state.runID = payload["turn_id"].string }
                if (payload["type"].string == "task_complete" || payload["type"].string == "turn_aborted"),
                   state.runID == payload["turn_id"].string {
                    let elapsed = stamp.flatMap { end in state.runStart.map { end.timeIntervalSince($0) } }
                    finish(at: stamp, duration: elapsed, recorded: elapsed != nil); state.runStart = nil; state.runID = nil
                }
            }
        }
    }
    /// Renders what the state knows without ending its open turn, so a later chunk continues from it.
    /// An unfinished response has no fabricated completion time or running duration.
    func snapshot(_ state: State) -> Result {
        var result = state.result
        guard !state.finished else { return result }
        result.currentTurnCompleted = false
        guard let first = state.response.first, let last = state.response.last else { return result }
        result.responses.append(ConversationResponse(firstMessageID: first.id, lastMessageID: last.id, startedAt: state.start, completedAt: nil, durationSeconds: nil, recordedDuration: false, completed: false, firstSeq: first.seq, lastSeq: last.seq))
        return result
    }
    /// A background-task completion delivered between turns. One delivered mid-turn arrives as an
    /// attachment instead and belongs to the turn already running.
    private func isTaskNotice(_ root: JSONValue) -> Bool {
        root["type"].string == "user" && root["origin"]["kind"].string == "task-notification"
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
