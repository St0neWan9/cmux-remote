import Foundation

/// A prompt sent while Claude is working is stored as a queued-command attachment, not a user record.
/// Present the person's prompt as the user message it is; one output line per input line keeps line indexes stable.
struct ClaudeQueuedPromptNormalizer: Sendable {
    func normalize(_ lines: [String]) -> [String] { lines.map(normalize) }
    func normalize(_ line: String) -> String {
        guard line.utf8.count <= 4_194_304, line.contains("\"queued_command\""),
              let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              object["type"] as? String == "attachment",
              let attachment = object["attachment"] as? [String: Any], attachment["type"] as? String == "queued_command",
              (attachment["origin"] as? [String: Any])?["kind"] as? String == "human" || attachment["humanTurn"] as? Bool == true,
              let prompt = attachment["prompt"], prompt is String || prompt is [Any] else { return line }
        var user: [String: Any] = ["type": "user", "message": ["role": "user", "content": prompt], "isMeta": false]
        for key in ["uuid", "parentUuid", "timestamp", "sessionId", "cwd", "isSidechain", "userType"] { if let value = object[key] { user[key] = value } }
        guard let data = try? JSONSerialization.data(withJSONObject: user), let text = String(data: data, encoding: .utf8) else { return line }
        return text
    }
}
