import Foundation

/// The fixed router chooses the media type; no caller-controlled MIME is forwarded.
struct HTTPResourceResponse: Sendable {
    let status: Int
    let data: Data
    let contentType: String
    static func json(_ data: Data) -> HTTPResourceResponse { HTTPResourceResponse(status: 200, data: data, contentType: "application/json; charset=utf-8") }
}
