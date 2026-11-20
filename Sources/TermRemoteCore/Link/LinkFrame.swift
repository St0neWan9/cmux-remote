import Foundation

/// Resource requests, ordered response chunks and subscription invalidations share one wire type.
public struct LinkFrame: Codable, Sendable {
    public var kind: String
    public var id: String
    public var method: String?
    public var uri: String?
    public var authorization: String?
    public var data: Data?
    public var status: Int?
    public var contentType: String?
    public var index: Int?
    public var final: Bool?
    public init(kind: String, id: String, method: String? = nil, uri: String? = nil, authorization: String? = nil, data: Data? = nil, status: Int? = nil, contentType: String? = nil, index: Int? = nil, final: Bool? = nil) {
        self.kind = kind; self.id = id; self.method = method; self.uri = uri; self.authorization = authorization; self.data = data; self.status = status; self.contentType = contentType; self.index = index; self.final = final
    }
    public func validate() throws {
        guard UUID(uuidString: id) != nil, ["request", "response", "subscribe", "event", "cancel", "ack"].contains(kind),
              (data?.count ?? 0) <= 1_048_576, (uri?.utf8.count ?? 0) <= 16_384,
              (authorization?.utf8.count ?? 0) <= 4096 else { throw BridgeError("invalid_request", "Invalid link message.") }
    }
}
