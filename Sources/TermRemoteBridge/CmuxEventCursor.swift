import Foundation

/// A sequence is meaningful only inside its cmux event boot namespace.
public struct CmuxEventCursor: Codable, Sendable, Equatable {
    public let bootID: String
    public let sequence: Int
    public init(bootID: String, sequence: Int) { self.bootID = bootID; self.sequence = sequence }
}
