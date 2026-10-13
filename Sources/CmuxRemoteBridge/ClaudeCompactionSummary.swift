import Foundation
import CmuxAgentChat

/// Claude stores its compaction summary as a user record. It is the agent's own context, not something the person typed,
/// so the record becomes a one-line status row; one output line per input line keeps line indexes stable.
struct ClaudeCompactionSummary: Sendable {
    struct Result { let lines: [String]; let markers: [ChatMessage] }
    func replace(_ lines: [String]) -> Result {
        var output = lines; var markers: [ChatMessage] = []
        for (seq, line) in lines.enumerated() where line.contains("\"isCompactSummary\"") {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  object["type"] as? String == "user", object["isCompactSummary"] as? Bool == true else { continue }
            let id = object["uuid"] as? String ?? "compaction-\(seq)"
            let stamp = (object["timestamp"] as? String).flatMap { try? Date($0, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }
            // A neutral record keeps the line without a user turn the parsers or turn timing would count.
            output[seq] = #"{"type":"compact-summary"}"#
            markers.append(ChatMessage(id: id, seq: seq, role: .system, timestamp: stamp ?? Date(timeIntervalSince1970: 0),
                                       kind: .status(ChatStatusTransition(event: .contextCompacted))))
        }
        return Result(lines: output, markers: markers)
    }
}
