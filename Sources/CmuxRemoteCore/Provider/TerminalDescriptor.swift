import Foundation

/// One terminal screen with an input channel.
public struct TerminalDescriptor: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let providerID: String
    public let spaceID: String
    public let title: String
    public let kind: String
    public let processName: String?
    public let workingDirectory: String?
    /// "running", "exited" or "unknown"; newer providers may add values.
    public let state: String
    /// The provider's layout node this terminal belongs to, when it has one.
    public let layoutID: String?
    /// The foreground process id on the provider's host, when the provider can prove it.
    public let processID: Int?

    public init(id: String, providerID: String, spaceID: String, title: String, kind: String = "terminal",
                processName: String? = nil, workingDirectory: String? = nil, state: String = "unknown",
                layoutID: String? = nil, processID: Int? = nil) {
        self.id = id; self.providerID = providerID; self.spaceID = spaceID; self.title = title; self.kind = kind
        self.processName = processName; self.workingDirectory = workingDirectory; self.state = state
        self.layoutID = layoutID; self.processID = processID
    }
}
