import Foundation
import NIOCore
import NIOWebSocket

/// NIO owns handler state on one event loop; the session consumes a bounded ordered stream.
final class BridgeWebSocketHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    private let session: LinkServerSession
    // Bursts of requests, subscriptions and acknowledgements are legitimate; the budget bounds memory instead.
    private let input = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)
    private let budget = LinkInputBudget()
    private var consumer: Task<Void, Never>?
    private var fragmented = Data()
    private var assembling = false
    init(session: LinkServerSession) { self.session = session }
    func handlerAdded(context: ChannelHandlerContext) {
        let session = session, stream = input.stream, budget = budget
        consumer = Task {
            await session.start()
            for await data in stream {
                guard !Task.isCancelled else { break }
                await session.receive(data); budget.release(data.count)
            }
            await session.close()
        }
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        guard frame.data.readableBytes <= 2_100_000 else { context.close(promise: nil); return }
        switch frame.opcode {
        case .binary, .continuation:
            guard frame.opcode == .binary ? !assembling : assembling else { context.close(promise: nil); return }
            var payload = frame.unmaskedData
            guard fragmented.count + payload.readableBytes <= 2_100_000,
                  let bytes = payload.readBytes(length: payload.readableBytes) else { context.close(promise: nil); return }
            fragmented.append(contentsOf: bytes); assembling = !frame.fin
            if frame.fin {
                let complete = fragmented; fragmented = Data()
                guard budget.admit(complete.count) else { context.close(promise: nil); return }
                input.continuation.yield(complete)
            }
        case .ping:
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .pong, data: frame.unmaskedData)), promise: nil)
        case .pong: break
        default: context.close(promise: nil)
        }
    }
    func channelInactive(context: ChannelHandlerContext) { input.continuation.finish(); consumer?.cancel(); consumer = nil; context.fireChannelInactive() }
    func errorCaught(context: ChannelHandlerContext, error: any Error) { context.close(promise: nil) }
}
