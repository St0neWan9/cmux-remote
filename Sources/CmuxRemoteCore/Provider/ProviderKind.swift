import Foundation

/// A terminal backend implementation, independent of its wire protocol.
public enum ProviderKind: String, Codable, Sendable, CaseIterable {
    case cmuxDesktop = "cmux_desktop"
    case cmuxDaemon = "cmux_daemon"
    case rex
    case demo
}

/// What a provider can do. These are provider features, not device grants.
public enum ProviderCapability: String, Codable, Sendable, CaseIterable {
    case spaces
    case layout
    case terminals
    case screen
    case input
    case conversations
    case start
    case feed
    case models
    case projectFiles
    case streaming
}

public enum ProviderStatus: String, Codable, Sendable {
    case available
    case unavailable
    case starting
}
