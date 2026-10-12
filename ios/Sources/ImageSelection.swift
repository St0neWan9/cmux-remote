import Foundation

/// A native picker supplies bytes; the draft model owns loading and cancellation.
struct ImageSelection: Sendable {
    let name: String
    let load: @Sendable () async throws -> Data
}
