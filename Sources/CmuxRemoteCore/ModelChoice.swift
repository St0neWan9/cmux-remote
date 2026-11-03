import Foundation

/// One model the agent's own configuration offers.
public struct ModelChoice: Codable, Sendable, Equatable, Identifiable {
    /// The value a switch sends: an alias or a model id.
    public let id: String
    public let label: String
    public let detail: String?
    public init(id: String, label: String, detail: String? = nil) { self.id = id; self.label = label; self.detail = detail }
}
