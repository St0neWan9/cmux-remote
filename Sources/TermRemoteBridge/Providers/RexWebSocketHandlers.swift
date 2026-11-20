import Foundation
import NIOCore
import NIOHTTP1
import NIOWebSocket
import TermRemoteCore

/// Sends the control upgrade request once the channel is active. The upgrade
/// handler removes this handler after a successful 101 response.
final class RexHTTPRequestHandler: ChannelInboundHandler, RemovableChannelHandler, Sendable {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private let host: String
    private let subprotocol: String

    init(host: String, subprotocol: String) {
        self.host = host; self.subprotocol = subprotocol
    }

    func channelActive(context: ChannelHandlerContext) {
        var head = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/api/control")
        head.headers.add(name: "Host", value: host)
        head.headers.add(name: "Sec-WebSocket-Protocol", value: subprotocol)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // A response before the upgrade is not a control message.
    }
}

/// Signals that the HTTP upgrade finished before any WebSocket frame is sent.
/// The pipeline must not receive a WebSocketFrame while the HTTP encoder is
/// still installed.
final class RexUpgradeSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: Result<Void, any Error>?
    private var waiter: CheckedContinuation<Void, any Error>?

    func wait(timeout: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let outcome {
                lock.unlock()
                continuation.resume(with: outcome)
                return
            }
            waiter = continuation
            lock.unlock()
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.fail(BridgeError("rex_handshake", "The Rex upgrade timed out.", status: 504))
            }
        }
    }

    func succeed() { finish(.success(())) }

    func fail(_ error: any Error) { finish(.failure(error)) }

    private func finish(_ result: Result<Void, any Error>) {
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        outcome = result
        let waiter = self.waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume(with: result)
    }
}

/// Forwards control text messages and answers pings. It never logs a frame.
final class RexWebSocketHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let onText: @Sendable (String) -> Void
    private let onClose: @Sendable (Int, String) -> Void
    private var closed = false

    init(onText: @escaping @Sendable (String) -> Void, onClose: @escaping @Sendable (Int, String) -> Void) {
        self.onText = onText; self.onClose = onClose
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .text:
            onText(String(buffer: frame.unmaskedData))
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, maskKey: RexWebSocketMask.random(), data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)
        case .pong, .continuation:
            break
        case .connectionClose:
            finish(code: Self.closeCode(frame), reason: Self.closeReason(frame))
        default:
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        finish(code: 1006, reason: "connection error")
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        finish(code: 1006, reason: "connection closed")
    }

    private func finish(code: Int, reason: String) {
        guard !closed else { return }
        closed = true
        onClose(code, reason)
    }

    private static func closeCode(_ frame: WebSocketFrame) -> Int {
        guard frame.data.readableBytes >= 2, let value = frame.unmaskedData.getInteger(at: 0, endianness: .big, as: UInt16.self) else { return 1005 }
        return Int(value)
    }

    private static func closeReason(_ frame: WebSocketFrame) -> String {
        guard frame.data.readableBytes > 2, let text = frame.unmaskedData.getString(at: 2, length: frame.data.readableBytes - 2) else { return "" }
        return String(text.prefix(256))
    }
}

enum RexWebSocketMask {
    static func random() -> WebSocketMaskingKey {
        var generator = SystemRandomNumberGenerator()
        return WebSocketMaskingKey([UInt8.random(in: 0...255, using: &generator),
                                    UInt8.random(in: 0...255, using: &generator),
                                    UInt8.random(in: 0...255, using: &generator),
                                    UInt8.random(in: 0...255, using: &generator)])!
    }
}
