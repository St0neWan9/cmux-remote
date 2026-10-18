import Foundation
import NIOCore
import NIOWebSocket

/// Channel operations are scheduled on its event loop; no context escapes to a Swift task.
struct LinkWebSocketWriter: Sendable {
    let channel: any Channel
    func send(_ data: Data) async throws {
        // A closed channel's event loop may already be shut down. Submitting there creates a promise NIO can
        // never complete, which it reports as a leaked promise and turns into a crash; fail the send instead.
        guard channel.isActive else { throw CancellationError() }
        try await channel.eventLoop.flatSubmit {
            var buffer = channel.allocator.buffer(capacity: data.count); buffer.writeBytes(data)
            return channel.writeAndFlush(WebSocketFrame(fin: true, opcode: .binary, data: buffer))
        }.get()
    }
    func close() { channel.close(promise: nil) }
}
