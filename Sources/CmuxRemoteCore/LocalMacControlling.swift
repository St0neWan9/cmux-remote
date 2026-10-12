/// Owner-only Companion operations; never published on the remote HTTPS router.
public protocol LocalMacControlling: Sendable {
    func request(_ method: String, params: JSONValue) async throws -> JSONValue
}
