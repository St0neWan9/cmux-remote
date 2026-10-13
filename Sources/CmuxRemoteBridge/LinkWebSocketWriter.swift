import Foundation
import NIOCore
import NIOWebSocket

/// Channel operations are scheduled on its event loop; no context escapes to a Swift task.
struct LinkWebSocketWriter: Sendable {
    let channel: any Channel
    func send(_ data: Data) async throws {
        try await channel.eventLoop.flatSubmit {
            var buffer = channel.allocator.buffer(capacity: data.count); buffer.writeBytes(data)
            return channel.writeAndFlush(WebSocketFrame(fin: true, opcode: .binary, data: buffer))
        }.get()
    }
    func close() { channel.close(promise: nil) }
}
