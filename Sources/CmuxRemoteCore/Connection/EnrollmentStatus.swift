import Foundation

/// Poll responses are host-signed and bound to the client's original request and nonce.
public struct EnrollmentStatus: Codable, Sendable {
    public var hostID: String
    public var clientID: String
    public var requestID: String
    public var nonce: String
    public var state: String
    public var relay: RelayEndpoint?
    public var grant: SignedValue<EnrollmentGrant>?
    public init(request: EnrollmentRequest, state: String, grant: SignedValue<EnrollmentGrant>? = nil, relay: RelayEndpoint? = nil) {
        hostID = request.hostID; clientID = request.clientID; requestID = request.requestID; nonce = request.nonce; self.state = state; self.grant = grant; self.relay = relay
    }
}
