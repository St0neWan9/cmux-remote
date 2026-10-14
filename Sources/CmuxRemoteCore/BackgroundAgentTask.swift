import Foundation

/// One task the agent started and has not finished, as its transcript reports it.
public struct BackgroundAgentTask: Codable, Sendable, Equatable, Identifiable {
    /// The tool call that started it, which is also what the completion notice names.
    public let id: String
    /// The tool that runs it: `Bash`, `Monitor`, `Agent`, `Workflow`, …
    public let tool: String
    /// The line the agent wrote for it, e.g. `Wait for the build to finish`.
    public let summary: String
    public init(id: String, tool: String, summary: String) {
        self.id = id; self.tool = tool; self.summary = summary
    }
}
