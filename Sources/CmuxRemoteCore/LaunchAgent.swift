import Foundation

/// The only programs a phone may start; each maps to a fixed command typed into a new terminal.
public enum LaunchAgent: String, Codable, Sendable, CaseIterable {
    case claude, codex
    /// The fixed program and options; never derived from client input.
    /// Codex otherwise joins a shared background server whose hooks carry the terminal of whichever Codex started it,
    /// so the new terminal's conversation would never be reported.
    public var command: String {
        switch self {
        case .codex: return "codex --no-daemon"
        // The owner's own flags, matching how the desktop starts these agents.
        case .claude: return "claude --chrome --dangerously-skip-permissions"
        }
    }
    /// Codex reports its conversation only after a first message, so the phone could not open it without one.
    public var requiresPrompt: Bool { self == .codex }
    /// Reopens one exact Agent session in a new terminal. The session id is the daemon's own binding, never client
    /// input, and each program spells the call differently: Claude takes a flag, Codex a subcommand.
    public func resumeCommand(sessionID: String) -> String {
        switch self {
        case .claude: return command + " --resume " + sessionID.lowercased()
        case .codex: return command + " resume " + sessionID.lowercased()
        }
    }
}
