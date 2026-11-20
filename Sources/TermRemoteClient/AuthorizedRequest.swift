import Foundation

/// Carries the pinned transport captured before asynchronous identity verification.
struct AuthorizedRequest: Sendable {
    let transport: any ResourceTransport
    let path: String
    let authorization: @Sendable (String, Data) throws -> String
}
