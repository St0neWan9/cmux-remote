import CmuxRemoteCore

/// Only the local composition root creates a cmux control transport.
public protocol CmuxControlling: Sendable {
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue
}
