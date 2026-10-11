import Foundation

/// A device signs the exact HTTP method, raw URI and body digest for each request.
public struct RequestProof: Codable, Sendable {
    public var epoch: String
    public var hostID: String
    public var clientID: String
    public var method: String
    public var uri: String
    public var bodySHA256: String
    public var nonce: String
    public var timestamp: Int
    public init(epoch: String, hostID: String, clientID: String, method: String, uri: String, bodySHA256: String, nonce: String, timestamp: Int) {
        self.epoch = epoch; self.hostID = hostID; self.clientID = clientID; self.method = method; self.uri = uri; self.bodySHA256 = bodySHA256; self.nonce = nonce; self.timestamp = timestamp
    }
}
