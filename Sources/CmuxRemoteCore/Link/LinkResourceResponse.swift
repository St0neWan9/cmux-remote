import Foundation

/// A bounded resource reply independent of HTTP or the encrypted WebSocket transport.
public struct LinkResourceResponse: Sendable {
    public let status: Int
    public let data: Data
    public let contentType: String
    public init(status: Int, data: Data, contentType: String) { self.status = status; self.data = data; self.contentType = contentType }
}
