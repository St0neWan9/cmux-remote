import Foundation

/// A stable protocol error with a bounded, non-sensitive user-facing description.
public struct BridgeError: Error, Codable, Sendable, Equatable, LocalizedError {
    public let code: String
    public let message: String
    public let status: Int
    public init(_ code: String, _ message: String, status: Int = 400) {
        self.code = code; self.message = message; self.status = status
    }
    public var errorDescription: String? { message }
}
