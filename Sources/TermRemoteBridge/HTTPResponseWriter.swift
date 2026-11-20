import Foundation
import NIOCore
import NIOHTTP1

/// The context is touched only by closures scheduled on its own event loop.
final class HTTPResponseWriter: @unchecked Sendable {
    private let context: ChannelHandlerContext
    init(context: ChannelHandlerContext) { self.context = context }
    func send(status: Int, data: Data, contentType: String = "application/json; charset=utf-8") {
        context.eventLoop.execute { [self] in
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: contentType)
            headers.add(name: "Content-Length", value: String(data.count))
            headers.add(name: "X-Content-Type-Options", value: "nosniff")
            headers.add(name: "Cache-Control", value: "no-store")
            headers.add(name: "Connection", value: "close")
            context.write(NIOAny(HTTPServerResponsePart.head(HTTPResponseHead(version: .http1_1, status: HTTPResponseStatus(statusCode: status), headers: headers))), promise: nil)
            var buffer = context.channel.allocator.buffer(capacity: data.count); buffer.writeBytes(data)
            context.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil))).whenComplete { [self] _ in context.close(promise: nil) }
        }
    }
}
