import Foundation

/// The client signs all requested identity, scope and nonce fields before requesting owner approval.
public struct EnrollmentRequest: Codable, Sendable, Equatable {
    public var hostID: String
    public var windowID: String
    public var requestID: String
    public var clientID: String
    public var clientPublicKey: String
    public var clientName: String
    public var clientKind: String
    public var nonce: String
    public var scope: ClientScope
    public var expiresAt: Int
    public init(hostID: String, windowID: String, requestID: String, clientID: String, clientPublicKey: String, clientName: String, clientKind: String, nonce: String, scope: ClientScope, expiresAt: Int) {
        self.hostID = hostID; self.windowID = windowID; self.requestID = requestID; self.clientID = clientID; self.clientPublicKey = clientPublicKey; self.clientName = clientName; self.clientKind = clientKind; self.nonce = nonce; self.scope = scope; self.expiresAt = expiresAt
    }
}
