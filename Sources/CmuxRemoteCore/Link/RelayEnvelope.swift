import Foundation

/// Opaque channel data and bounded registry control; cloud sees routing metadata only.
public struct RelayEnvelope: Codable, Sendable {
    public let kind: String
    public let channelID: String?
    public let clientID: String?
    public let data: Data?
    public let revoked: [String]?
    public init(kind: String, channelID: String? = nil, clientID: String? = nil, data: Data? = nil, revoked: [String]? = nil) {
        self.kind = kind; self.channelID = channelID; self.clientID = clientID; self.data = data; self.revoked = revoked
    }
    enum CodingKeys: String, CodingKey { case kind, data, revoked; case channelID = "channel_id", clientID = "client_id" }
}
