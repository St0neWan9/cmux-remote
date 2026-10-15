import Foundation

/// The only programs a phone may start; each maps to a fixed command typed into a new terminal.
public enum LaunchAgent: String, Codable, Sendable, CaseIterable {
    case claude, codex
    /// The command line, without a trailing return; never derived from client input.
    public var command: String { rawValue }
}
