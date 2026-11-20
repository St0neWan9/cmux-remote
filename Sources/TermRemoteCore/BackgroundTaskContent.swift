import Foundation

/// What a background task has produced: a subagent's own conversation, or a detached command's output.
///
/// The record is read from the agent's local files, so it is bounded and paged like history: a long command's
/// output arrives in offset-ordered pages, and an agent's conversation is a normal snapshot the phone already
/// knows how to read.
public struct BackgroundTaskContent: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case agent, output }
    public let taskID: String
    public let tool: String
    public let summary: String
    public let kind: Kind
    /// Whether the parent conversation still counts this task as running.
    public let running: Bool
    /// The subagent's conversation, for `.agent`.
    public let snapshot: ConversationSnapshot?
    /// The command the task ran, for `.output`, when the record names it.
    public let command: String?
    /// The command output, for `.output`.
    public let text: String?
    /// Where `text` starts, and where the next page starts; nil at the end of the record.
    public let offset: Int?
    public let nextOffset: Int?
    /// The output's size, so a reader can tell how much is left.
    public let totalBytes: Int?
    public init(taskID: String, tool: String, summary: String, kind: Kind, running: Bool, snapshot: ConversationSnapshot? = nil,
                command: String? = nil, text: String? = nil, offset: Int? = nil, nextOffset: Int? = nil, totalBytes: Int? = nil) {
        self.taskID = taskID; self.tool = tool; self.summary = summary; self.kind = kind; self.running = running
        self.snapshot = snapshot; self.command = command; self.text = text
        self.offset = offset; self.nextOffset = nextOffset; self.totalBytes = totalBytes
    }
}
