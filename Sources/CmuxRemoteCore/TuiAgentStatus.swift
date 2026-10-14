import Foundation

/// The agent's live working line, as the terminal renders it (`✻ Blanching… (54s · ↓ 2.3k tokens)`).
///
/// The gerund and the token count exist only on screen: the transcript carries neither, and the provider
/// exposes no API for them, so they are read back from the terminal exactly as a person sees them.
public struct TuiAgentStatus: Codable, Sendable, Equatable {
    /// The spinner glyph the agent is currently cycling through, e.g. `✻`.
    public let glyph: String
    /// The activity word and its ellipsis, e.g. `Blanching…`; nil before the agent names its work.
    public let activity: String?
    /// Elapsed seconds for the current turn as the terminal printed them.
    public let elapsedSeconds: Int?
    /// The token count as printed, e.g. `2.3k` or `560`, with the arrow the agent used.
    public let tokenCount: String?
    /// Whether the tokens are being sent to the agent (`↑`) rather than streamed back (`↓`).
    public let tokensAscending: Bool?
    /// Whether the turn is compacting its context, which replaces the activity word on the working line.
    public let isCompacting: Bool
    public init(glyph: String, activity: String?, elapsedSeconds: Int?, tokenCount: String?, tokensAscending: Bool?, isCompacting: Bool = false) {
        self.glyph = glyph; self.activity = activity; self.elapsedSeconds = elapsedSeconds
        self.tokenCount = tokenCount; self.tokensAscending = tokensAscending; self.isCompacting = isCompacting
    }
}
