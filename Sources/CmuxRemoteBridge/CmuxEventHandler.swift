import Foundation
import NIOCore
import CmuxRemoteCore

/// All mutable framing/authentication state belongs to the channel event loop.
final class CmuxEventHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    private let subscription: JSONValue
    private let password: String?
    private let continuation: AsyncThrowingStream<JSONValue, any Error>.Continuation
    private var buffer = Data()
    private var awaitingPassword: Bool
    init(subscription: JSONValue, password: String?, continuation: AsyncThrowingStream<JSONValue, any Error>.Continuation) {
        self.subscription = subscription; self.password = password; self.continuation = continuation; self.awaitingPassword = password != nil
    }
    func channelActive(context: ChannelHandlerContext) {
        if let password {
            guard !password.contains("\n"), !password.contains("\r") else { fail(context); return }
            write(Data(("auth " + password + "\n").utf8), context: context)
        } else { subscribe(context) }
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var incoming = unwrapInboundIn(data)
        if let bytes = incoming.readBytes(length: incoming.readableBytes) { buffer.append(contentsOf: bytes) }
        guard buffer.count <= 1_048_576 else { fail(context); return }
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
            if awaitingPassword {
                guard String(decoding: line, as: UTF8.self).hasPrefix("OK") else { fail(context); return }
                awaitingPassword = false; subscribe(context); continue
            }
            guard let frame = try? JSONDecoder().decode(JSONValue.self, from: line) else { fail(context); return }
            if case .dropped = continuation.yield(frame) { fail(context); return }
        }
    }
    func channelInactive(context: ChannelHandlerContext) { continuation.finish() }
    func errorCaught(context: ChannelHandlerContext, error: any Error) { fail(context) }
    private func subscribe(_ context: ChannelHandlerContext) {
        guard var payload = try? JSONEncoder().encode(subscription) else { fail(context); return }
        payload.append(10); write(payload, context: context)
    }
    private func write(_ data: Data, context: ChannelHandlerContext) {
        var bytes = context.channel.allocator.buffer(capacity: data.count); bytes.writeBytes(data)
        context.writeAndFlush(wrapOutboundOut(bytes), promise: nil)
    }
    private func fail(_ context: ChannelHandlerContext) {
        continuation.finish(throwing: BridgeError("event_resync", "The cmux event connection requires a snapshot refresh.", status: 503))
        context.close(promise: nil)
    }
}
