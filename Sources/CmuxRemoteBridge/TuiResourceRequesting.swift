import CmuxRemoteCore

/// Fixed resource requests against one explicitly selected local daemon.
public protocol TuiResourceRequesting: Sendable {
    func resource(_ operation: String, params: [String: JSONValue], idempotencyKey: String?) async throws -> JSONValue
}
