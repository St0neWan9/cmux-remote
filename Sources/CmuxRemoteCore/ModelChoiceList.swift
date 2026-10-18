import Foundation

/// The models a conversation's agent can switch to, and what a switch changes.
public struct ModelChoiceList: Codable, Sendable, Equatable {
    public let choices: [ModelChoice]
    /// Whether a typed model name is accepted beside the offered choices.
    public let acceptsCustom: Bool
    /// Claude Code saves a switched model as the default for its new sessions; a Codex switch stays in its session.
    public let persistsDefault: Bool
    public init(choices: [ModelChoice], acceptsCustom: Bool, persistsDefault: Bool) {
        self.choices = choices; self.acceptsCustom = acceptsCustom; self.persistsDefault = persistsDefault
    }
    private enum CodingKeys: String, CodingKey { case choices; case acceptsCustom = "accepts_custom"; case persistsDefault = "persists_default" }
}
