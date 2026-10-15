import Foundation

/// The only programs a phone may start; each maps to a fixed command typed into a new terminal.
public enum LaunchAgent: String, Codable, Sendable, CaseIterable {
    case claude, codex
    /// The fixed program and options; never derived from client input.
    /// Codex otherwise joins a shared background server whose hooks carry the terminal of whichever Codex started it,
    /// so the new terminal's conversation would never be reported.
    public var command: String { self == .codex ? "codex --no-daemon" : "claude" }
    /// Codex reports its conversation only after a first message, so the phone could not open it without one.
    public var requiresPrompt: Bool { self == .codex }
}
