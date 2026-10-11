import Foundation
import NIOCore
import CmuxRemoteCore

/// Mutable buffers are confined to this channel's event loop; Tasks capture only Sendable values.
final class OwnerControlHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    private var buffer = Data()
    private let router: OwnerControlRouter
    init(router: OwnerControlRouter) { self.router = router }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var bytes = unwrapInboundIn(data)
        guard let read = bytes.readBytes(length: bytes.readableBytes), buffer.count + read.count <= 65_536 else { context.close(promise: nil); return }
        buffer.append(contentsOf: read)
        guard let newline = buffer.firstIndex(of: 10) else { return }
        guard let request = try? JSONDecoder().decode(JSONValue.self, from: buffer.prefix(upTo: newline)) else { context.close(promise: nil); return }
        buffer.removeAll(); let router = router; let channel = context.channel
        Task {
            let response = await router.respond(request)
            if var data = try? JSONEncoder().encode(response) {
                data.append(10); var output = channel.allocator.buffer(capacity: data.count); output.writeBytes(data)
                try? await channel.writeAndFlush(output).get()
            }
            try? await channel.close().get()
        }
    }
}
