import Foundation

/// The model an agent's own transcript last reported, and its reasoning effort when the agent records one.
///
/// Read from the transcript, so it trails a switch the agent has not used yet: Claude Code records a new model
/// at once, Codex only with its next turn.
public struct AgentModelState: Codable, Sendable, Equatable {
    /// The agent's own name for it: a model id, or the label Claude Code printed when the switch happened.
    public let model: String
    public let effort: String?
    public init(model: String, effort: String? = nil) { self.model = model; self.effort = effort }
}
