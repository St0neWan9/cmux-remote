import Foundation
import NIOCore
import NIOHTTP1

/// Mutable request state is confined to the channel's event loop.
final class BridgeHTTPHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    private let router: BridgeRouter
    private var head: HTTPRequestHead?
    private var body = Data()
    private var rejected = false
    init(router: BridgeRouter) { self.router = router }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head): self.head = head; body = Data(); rejected = false
        case .body(var chunk):
            if body.count + chunk.readableBytes > 1_048_576 { rejected = true }
            if !rejected, let bytes = chunk.readBytes(length: chunk.readableBytes) { body.append(contentsOf: bytes) }
        case .end:
            guard let head else { context.close(promise: nil); return }
            let writer = HTTPResponseWriter(context: context)
            if rejected { writer.send(status: 413, data: Data()); return }
            let router = router; let body = body
            Task {
                let response = await router.respondResource(method: head.method.rawValue, uri: head.uri, authorization: head.headers.first(name: "Authorization"), body: body)
                writer.send(status: response.status, data: response.data, contentType: response.contentType)
            }
        }
    }
    func errorCaught(context: ChannelHandlerContext, error: any Error) { context.close(promise: nil) }
}
