import Foundation

/// Background-task notices arrive as user records, so the chat parser would draw them as the person's prompt.
/// Mark them meta, which the parser already drops; one output line per input line keeps line indexes stable.
struct ClaudeTaskNoticeRewriter: Sendable {
    func normalize(_ lines: [String]) -> [String] { lines.map(normalize) }
    func normalize(_ line: String) -> String {
        guard line.utf8.count <= 4_194_304, line.contains("task-notification"),
              let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              object["type"] as? String == "user",
              (object["origin"] as? [String: Any])?["kind"] as? String == "task-notification" else { return line }
        var notice = object
        notice["isMeta"] = true
        guard let data = try? JSONSerialization.data(withJSONObject: notice), let text = String(data: data, encoding: .utf8) else { return line }
        return text
    }
}
