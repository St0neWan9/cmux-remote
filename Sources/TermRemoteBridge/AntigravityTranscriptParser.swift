import Foundation
import CmuxAgentChat

/// Converts Antigravity CLI (`agy`) JSONL transcript lines into ``ChatMessage`` values.
///
/// Reads `~/.gemini/antigravity-cli/brain/<conversation-id>/.system_generated/logs/transcript_full.jsonl`
/// (or `transcript.jsonl`): `USER_INPUT` lines carry user prompts and media, `PLANNER_RESPONSE` lines carry
/// thinking, assistant prose and `tool_calls`, and subsequent `GENERIC` lines carry each tool's output in
/// step order. Internal `SYSTEM_MESSAGE` nudges are skipped. The parser fails open on unknown or malformed
/// rows and carries pending tool calls across incremental reads through ``ChatTranscriptParseState``.
public struct AntigravityTranscriptParser: Sendable {
    private let maxBodyCharacters: Int
    private let maxInputDetailCharacters: Int

    /// Creates an Antigravity transcript parser with bounded text limits matching the upstream parsers.
    public init(maxBodyCharacters: Int = 16_384, maxInputDetailCharacters: Int = 2_048) {
        self.maxBodyCharacters = min(33_554_432, max(1, maxBodyCharacters))
        self.maxInputDetailCharacters = min(33_554_432, max(1, maxInputDetailCharacters))
    }

    public func parse(
        lines: some Sequence<String>,
        startingSeq: Int,
        state: ChatTranscriptParseState = ChatTranscriptParseState()
    ) -> ChatTranscriptParseResult {
        var messages: [ChatMessage] = []
        var updatedMessages: [ChatMessage] = []
        var batchIndexByID: [String: Int] = [:]
        var updatedIndexByID: [String: Int] = [:]
        var pending = state.pendingToolUses
        var pendingOrder = pending.keys.sorted(by: Self.pendingKeyOrder)
        var lastTimestamp = state.lastTimestamp

        func emit(_ message: ChatMessage) {
            batchIndexByID[message.id] = messages.count
            messages.append(message)
        }

        func commitUpdate(_ message: ChatMessage) {
            if let index = batchIndexByID[message.id] {
                messages[index] = message
            } else if let index = updatedIndexByID[message.id] {
                updatedMessages[index] = message
            } else {
                updatedIndexByID[message.id] = updatedMessages.count
                updatedMessages.append(message)
            }
        }

        for (offset, line) in lines.enumerated() {
            let seq = startingSeq + offset
            guard let data = line.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                continue
            }
            if let stamped = Self.parseTimestamp(root["created_at"] as? String ?? root["timestamp"] as? String) {
                lastTimestamp = stamped
            }
            let timestamp = lastTimestamp ?? Date(timeIntervalSince1970: 0)
            let stepIndex = (root["step_index"] as? NSNumber)?.intValue
            let stepID = stepIndex.map { "agy-step-\($0)" } ?? "agy-line-\(seq)"
            let type = root["type"] as? String ?? ""

            switch type {
            case "USER_INPUT":
                appendUserInput(root, stepID: stepID, seq: seq, timestamp: timestamp, emit: emit)
            case "PLANNER_RESPONSE":
                appendPlannerResponse(root, stepID: stepID, stepIndex: stepIndex, seq: seq, timestamp: timestamp,
                                      emit: emit, pending: &pending, pendingOrder: &pendingOrder)
            case "GENERIC":
                resolveGenericToolResult(root, stepIndex: stepIndex, timestamp: timestamp,
                                         pending: &pending, pendingOrder: &pendingOrder, commitUpdate: commitUpdate)
            case "SYSTEM_MESSAGE":
                continue
            default:
                continue
            }
        }

        return ChatTranscriptParseResult(
            messages: messages,
            updatedMessages: updatedMessages,
            state: ChatTranscriptParseState(pendingToolUses: pending, lastTimestamp: lastTimestamp)
        )
    }

    // MARK: - User Input

    private func appendUserInput(
        _ root: [String: Any],
        stepID: String,
        seq: Int,
        timestamp: Date,
        emit: (ChatMessage) -> Void
    ) {
        if let media = root["media"] as? [[String: Any]] {
            for (index, item) in media.enumerated() {
                guard let uri = item["uri"] as? String, !uri.isEmpty else { continue }
                let mime = (item["mime_type"] as? String ?? "").lowercased()
                let category: ChatAttachment.Media = mime.hasPrefix("image/") ? .image : .file
                let path = uri.hasPrefix("file://") ? (URL(string: uri)?.path ?? uri) : uri
                let name = URL(fileURLWithPath: path).lastPathComponent
                emit(ChatMessage(
                    id: "\(stepID)#media-\(index)",
                    seq: seq,
                    role: .user,
                    timestamp: timestamp,
                    kind: .attachment(ChatAttachment(media: category, displayName: name.isEmpty ? nil : name, hostPath: path))
                ))
            }
        }
        guard let rawContent = root["content"] as? String else { return }
        let cleaned = Self.extractUserRequest(from: rawContent)
        guard !cleaned.isEmpty else { return }
        emit(ChatMessage(
            id: stepID,
            seq: seq,
            role: .user,
            timestamp: timestamp,
            kind: .prose(ChatProse(text: truncateBody(cleaned)))
        ))
    }

    // MARK: - Planner Response

    private func appendPlannerResponse(
        _ root: [String: Any],
        stepID: String,
        stepIndex: Int?,
        seq: Int,
        timestamp: Date,
        emit: (ChatMessage) -> Void,
        pending: inout [String: [ChatMessage]],
        pendingOrder: inout [String]
    ) {
        if let thinking = (root["thinking"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !thinking.isEmpty {
            emit(ChatMessage(
                id: "\(stepID)#thought",
                seq: seq,
                role: .agent,
                timestamp: timestamp,
                kind: .thought(ChatThought(text: truncateBody(thinking)))
            ))
        }

        if let content = (root["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            emit(ChatMessage(
                id: "\(stepID)#prose",
                seq: seq,
                role: .agent,
                timestamp: timestamp,
                kind: .prose(ChatProse(text: truncateBody(content)))
            ))
        }

        guard let calls = root["tool_calls"] as? [[String: Any]], !calls.isEmpty else { return }
        for (callIndex, call) in calls.enumerated() {
            let name = call["name"] as? String ?? "tool"
            let args = call["args"] as? [String: Any] ?? [:]
            let baseID = "\(stepID)#tool-\(callIndex)"
            let expectKey: String
            if let stepIndex {
                expectKey = String(format: "agy:%09d", stepIndex + 1 + callIndex)
            } else {
                expectKey = String(format: "agy:seq-%09d-%04d", seq, callIndex)
            }

            let emitted = buildToolMessages(name: name, args: args, baseID: baseID, seq: seq, timestamp: timestamp)
            for message in emitted { emit(message) }
            if !emitted.isEmpty {
                if pending.count >= 512, let oldest = pendingOrder.first {
                    pendingOrder.removeFirst()
                    pending.removeValue(forKey: oldest)
                }
                pending[expectKey] = emitted
                if !pendingOrder.contains(expectKey) { pendingOrder.append(expectKey) }
            }
        }
    }

    private func buildToolMessages(
        name: String,
        args: [String: Any],
        baseID: String,
        seq: Int,
        timestamp: Date
    ) -> [ChatMessage] {
        switch name {
        case "run_command":
            let command = (args["CommandLine"] as? String) ?? (args["command"] as? String) ?? ""
            let summary = (args["toolSummary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let capture = ChatTerminalCapture(
                command: truncateBody(command),
                summary: summary.flatMap { $0.isEmpty ? nil : $0 },
                output: nil,
                exitCode: nil,
                durationSeconds: nil,
                isRunning: true,
                completedAt: nil
            )
            return [ChatMessage(id: baseID, seq: seq, role: .agent, timestamp: timestamp, kind: .terminal(capture))]

        case "edit_file":
            if let path = (args["Path"] as? String) ?? (args["path"] as? String), !path.isEmpty {
                let target = (args["Target"] as? String) ?? ""
                let replacement = (args["Replacement"] as? String) ?? ""
                let diff = Self.replacementDiff(oldText: target, newText: replacement)
                let edit = ChatFileEdit(
                    filePath: path,
                    operation: .edit,
                    additions: diff.additions,
                    deletions: diff.deletions,
                    unifiedDiff: truncateBody(diff.diff)
                )
                return [ChatMessage(id: baseID, seq: seq, role: .agent, timestamp: timestamp, kind: .fileEdit(edit))]
            }

        case "write_file":
            if let path = (args["Path"] as? String) ?? (args["path"] as? String), !path.isEmpty {
                let content = (args["Content"] as? String) ?? ""
                let diff = Self.creationDiff(content: content)
                let edit = ChatFileEdit(
                    filePath: path,
                    operation: .write,
                    additions: diff.additions,
                    deletions: 0,
                    unifiedDiff: truncateBody(diff.diff)
                )
                return [ChatMessage(id: baseID, seq: seq, role: .agent, timestamp: timestamp, kind: .fileEdit(edit))]
            }

        case "ask_question":
            if let questions = args["questions"] as? [[String: Any]], !questions.isEmpty {
                var result: [ChatMessage] = []
                for (qIndex, q) in questions.enumerated() {
                    guard let prompt = q["question"] as? String, !prompt.isEmpty else { continue }
                    let rawOptions = q["options"] as? [String] ?? []
                    let options = rawOptions.map { ChatQuestion.Option(label: $0) }
                    result.append(ChatMessage(
                        id: qIndex == 0 ? baseID : "\(baseID)#q-\(qIndex)",
                        seq: seq,
                        role: .agent,
                        timestamp: timestamp,
                        kind: .question(ChatQuestion(prompt: truncateBody(prompt), options: options))
                    ))
                }
                if !result.isEmpty { return result }
            }

        default:
            break
        }

        let summary = Self.toolSummary(name: name, args: args)
        let inputDetail = Self.prettyJSON(args).map { truncateInputDetail($0) }
        let paths = Self.referencedPaths(in: args)
        let toolUse = ChatToolUse(
            toolName: Self.displayToolName(name),
            summary: summary,
            inputDetail: inputDetail,
            output: nil,
            status: .running,
            referencedPaths: paths.isEmpty ? nil : paths,
            completedAt: nil
        )
        return [ChatMessage(id: baseID, seq: seq, role: .agent, timestamp: timestamp, kind: .toolUse(toolUse))]
    }

    // MARK: - Tool Result Resolution

    private func resolveGenericToolResult(
        _ root: [String: Any],
        stepIndex: Int?,
        timestamp: Date,
        pending: inout [String: [ChatMessage]],
        pendingOrder: inout [String],
        commitUpdate: (ChatMessage) -> Void
    ) {
        let matchedKey: String?
        if let stepIndex {
            let exact = String(format: "agy:%09d", stepIndex)
            if pending[exact] != nil {
                matchedKey = exact
            } else {
                matchedKey = pendingOrder.first { pending[$0] != nil }
            }
        } else {
            matchedKey = pendingOrder.first { pending[$0] != nil }
        }

        guard let key = matchedKey, let pendingMessages = pending[key] else { return }
        let rawStatus = (root["status"] as? String ?? "DONE").uppercased()
        let isRunning = rawStatus == "RUNNING"
        let isError = rawStatus == "ERROR" || rawStatus == "CANCELED"
        if !isRunning {
            pending.removeValue(forKey: key)
            pendingOrder.removeAll { $0 == key }
        }

        let rawOutput = (root["content"] as? String) ?? ""
        let cleanedOutput = Self.stripToolOutputHeader(rawOutput)

        for original in pendingMessages {
            switch original.kind {
            case .terminal(let capture):
                let parsed = Self.parseCommandOutput(cleanedOutput)
                let outputText = parsed.output.isEmpty ? nil : truncateBody(parsed.output)
                let exitCode = parsed.exitCode ?? (isError ? 1 : nil)
                let updated = ChatTerminalCapture(
                    command: capture.command,
                    summary: capture.summary,
                    output: outputText,
                    exitCode: exitCode,
                    durationSeconds: capture.durationSeconds,
                    isRunning: isRunning,
                    completedAt: isRunning ? nil : timestamp
                )
                commitUpdate(ChatMessage(
                    id: original.id, seq: original.seq, role: original.role,
                    timestamp: original.timestamp, kind: .terminal(updated)
                ))

            case .toolUse(let tool):
                let status: ChatToolUse.Status = isRunning ? .running : (isError ? .failed : .succeeded)
                let outputText = cleanedOutput.isEmpty ? nil : truncateBody(cleanedOutput)
                let updated = ChatToolUse(
                    toolName: tool.toolName,
                    summary: tool.summary,
                    inputDetail: tool.inputDetail,
                    output: outputText,
                    status: status,
                    referencedPaths: tool.referencedPaths,
                    completedAt: isRunning ? nil : timestamp
                )
                commitUpdate(ChatMessage(
                    id: original.id, seq: original.seq, role: original.role,
                    timestamp: original.timestamp, kind: .toolUse(updated)
                ))

            case .fileEdit, .question, .prose, .thought, .permissionRequest, .status, .attachment, .unsupported:
                continue
            }
        }
    }

    // MARK: - Formatting & Extraction Helpers

    static func extractUserRequest(from raw: String) -> String {
        if let open = raw.range(of: "<USER_REQUEST>"),
           let close = raw.range(of: "</USER_REQUEST>", range: open.upperBound..<raw.endIndex) {
            return String(raw[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var text = raw
        for tag in ["ADDITIONAL_METADATA", "USER_SETTINGS_CHANGE", "EPHEMERAL_MESSAGE", "SYSTEM_MESSAGE"] {
            while let open = text.range(of: "<\(tag)>"),
                  let close = text.range(of: "</\(tag)>", range: open.upperBound..<text.endIndex) {
                text.removeSubrange(open.lowerBound..<close.upperBound)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripToolOutputHeader(_ raw: String) -> String {
        var lines = raw.components(separatedBy: "\n")
        var cursor = 0
        while cursor < lines.count {
            let line = lines[cursor]
            if line.hasPrefix("Created At: ") || line.hasPrefix("Completed At: ") {
                cursor += 1
            } else {
                break
            }
        }
        if cursor > 0 { lines.removeFirst(cursor) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseCommandOutput(_ text: String) -> (exitCode: Int?, output: String) {
        var exitCode: Int?
        var body = text
        let lines = text.components(separatedBy: "\n")
        if let first = lines.first, first.hasPrefix("Command exited with code "), first.hasSuffix(".") {
            let numberPart = first.dropFirst("Command exited with code ".count).dropLast()
            exitCode = Int(numberPart.trimmingCharacters(in: .whitespaces))
            let remainder = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if remainder.hasPrefix("Command output:\n") {
                body = String(remainder.dropFirst("Command output:\n".count))
            } else if remainder == "Command output:" {
                body = ""
            } else {
                body = remainder
            }
        } else if body.hasPrefix("Command output:\n") {
            body = String(body.dropFirst("Command output:\n".count))
        }
        return (exitCode, body)
    }

    private static func displayToolName(_ raw: String) -> String {
        switch raw {
        case "read_file": return "Read"
        case "edit_file": return "Edit"
        case "write_file": return "Write"
        case "run_command": return "Bash"
        case "search_web": return "WebSearch"
        case "invoke_subagent": return "Subagent"
        case "call_mcp_tool": return "MCP"
        case "manage_task": return "Task"
        case "send_message": return "Message"
        case "run_workflow": return "Workflow"
        default: return raw
        }
    }

    private static func toolSummary(name: String, args: [String: Any]) -> String {
        switch name {
        case "read_file":
            if let path = args["Path"] as? String {
                return "Read \(URL(fileURLWithPath: path).lastPathComponent)"
            }
        case "search_web":
            if let query = args["query"] as? String, !query.isEmpty {
                return "Search \(String(query.prefix(80)))"
            }
        case "invoke_subagent":
            if let role = args["Role"] as? String, !role.isEmpty {
                return "Subagent: \(String(role.prefix(80)))"
            }
        case "call_mcp_tool":
            let server = args["ServerName"] as? String ?? ""
            let tool = args["ToolName"] as? String ?? ""
            if !server.isEmpty && !tool.isEmpty { return "\(server).\(tool)" }
        case "manage_task":
            if let action = args["Action"] as? String, !action.isEmpty {
                return "Task \(action)"
            }
        case "run_workflow":
            if let desc = args["Description"] as? String, !desc.isEmpty {
                return "Workflow: \(String(desc.prefix(80)))"
            }
        default:
            break
        }
        for key in ["Path", "path", "Description", "Role", "query", "CommandLine", "ToolName", "Action"] {
            if let value = args[key] as? String, !value.isEmpty {
                let compact = value.split(separator: "\n").first.map(String.init) ?? value
                return "\(displayToolName(name)) \(String(compact.prefix(80)))"
            }
        }
        return displayToolName(name)
    }

    private static func referencedPaths(in args: [String: Any]) -> [String] {
        var found: [String] = []
        for key in ["Path", "path", "ScriptPath", "Cwd"] {
            if let value = args[key] as? String, value.hasPrefix("/"), !found.contains(value) {
                found.append(value)
            }
        }
        return found
    }

    private static func prettyJSON(_ object: [String: Any]) -> String? {
        guard !object.isEmpty, JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func replacementDiff(oldText: String, newText: String) -> (diff: String, additions: Int, deletions: Int) {
        let oldLines = oldText.isEmpty ? [] : oldText.components(separatedBy: "\n")
        let newLines = newText.isEmpty ? [] : newText.components(separatedBy: "\n")
        let rendered = (oldLines.map { "-" + $0 } + newLines.map { "+" + $0 }).joined(separator: "\n")
        return (rendered, newLines.count, oldLines.count)
    }

    private static func creationDiff(content: String) -> (diff: String, additions: Int) {
        let newLines = content.isEmpty ? [] : content.components(separatedBy: "\n")
        let rendered = newLines.map { "+" + $0 }.joined(separator: "\n")
        return (rendered, newLines.count)
    }

    private func truncateBody(_ text: String) -> String {
        Self.truncate(text, limit: maxBodyCharacters)
    }

    private func truncateInputDetail(_ text: String) -> String {
        Self.truncate(text, limit: maxInputDetailCharacters)
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.unicodeScalars.count > limit else { return text }
        let suffix = "\n… [truncated]"
        let kept = max(0, limit - suffix.unicodeScalars.count)
        return String(String.UnicodeScalarView(text.unicodeScalars.prefix(kept))) + suffix
    }

    private static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty, raw.utf8.count <= 64 else { return nil }
        return (try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(raw, strategy: .iso8601))
    }

    private static func pendingKeyOrder(_ lhs: String, _ rhs: String) -> Bool {
        lhs < rhs
    }
}
