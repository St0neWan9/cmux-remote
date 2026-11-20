import Foundation
import Testing
import CmuxAgentChat

/// The agent describes each shell command in one line, which the terminal prints above the command.
/// The card leads with that description; parsing keeps it instead of discarding it.
@Suite struct ToolDescriptionTests {
    private func parse(_ rows: [String]) -> [ChatMessage] {
        ClaudeTranscriptParser().parse(lines: rows, startingSeq: 0).messages
    }
    private func call(id: String, command: String, description: String?) -> String {
        var input: [String: Any] = ["command": command]
        if let description { input["description"] = description }
        let body: [String: Any] = ["type": "assistant", "uuid": id, "message": ["content": [["type": "tool_use", "id": id, "name": "Bash", "input": input]]]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: body), as: UTF8.self)
    }
    private func result(id: String) -> String {
        let body: [String: Any] = ["type": "user", "uuid": id + "-r", "message": ["content": [["type": "tool_result", "tool_use_id": id, "content": "ok"]]]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: body), as: UTF8.self)
    }
    private func captures(_ messages: [ChatMessage]) -> [ChatTerminalCapture] {
        messages.compactMap { message in if case .terminal(let value) = message.kind { return value }; return nil }
    }
    @Test func theDescriptionIsKeptBesideTheCommand() {
        let messages = parse([call(id: "t1", command: "ls -la", description: "List the directory")])
        let capture = captures(messages).first
        #expect(capture?.command == "ls -la")
        #expect(capture?.summary == "List the directory")
    }
    /// A command the agent did not describe still parses, with no summary to show.
    @Test func aCommandWithoutADescriptionStillParses() {
        let messages = parse([call(id: "t2", command: "pwd", description: nil)])
        let capture = captures(messages).first
        #expect(capture?.summary == nil)
        #expect(capture?.command == "pwd")
    }
    /// The description survives the result that completes the call.
    @Test func theDescriptionSurvivesCompletion() {
        let messages = parse([call(id: "t3", command: "make", description: "Build the app"), result(id: "t3")])
        let capture = captures(messages).last
        #expect(capture?.summary == "Build the app")
        #expect(capture?.isRunning == false)
    }
}
