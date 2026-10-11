import Foundation

/// Owner approval binds one pending request to its exact client and host.
public struct EnrollmentGrant: Codable, Sendable, Equatable {
    public var hostID: String
    public var clientID: String
    public var requestID: String
    public var nonce: String
    public var scope: ClientScope
    public var issuedAt: Int
    public init(request: EnrollmentRequest, scope: ClientScope, issuedAt: Int) {
        hostID = request.hostID; clientID = request.clientID; requestID = request.requestID; nonce = request.nonce; self.scope = scope; self.issuedAt = issuedAt
    }
}
