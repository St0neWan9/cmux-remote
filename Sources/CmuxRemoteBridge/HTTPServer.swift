import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import NIOSSL

/// TLS HTTP service for the versioned mobile API.
public struct HTTPServer: Sendable {
    public init() {}
    public func run(host: String, port: Int, certificate: String, key: String, router: BridgeRouter, onListening: (@Sendable (Int) -> Void)? = nil) async throws {
        let admission = LinkAdmissionPool()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let configuration = TLSConfiguration.makeServerConfiguration(certificateChain: try NIOSSLCertificate.fromPEMFile(certificate).map { .certificate($0) }, privateKey: .privateKey(try NIOSSLPrivateKey(file: key, format: .pem)))
        let tls = try NIOSSLContext(configuration: configuration)
        do {
            let server = try await ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.backlog, value: 128)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    do {
                        // The bootstrap invokes this closure on the channel event loop.
                        try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: tls))
                        let http = BridgeHTTPHandler(router: router)
                        let upgrader = NIOWebSocketServerUpgrader(maxFrameSize: 2_100_000, shouldUpgrade: { channel, request in
                            guard request.uri == "/v3/link", router.linkAuthority != nil,
                                  request.headers.first(name: "Sec-WebSocket-Protocol")?.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).contains("cmux-remote.v3") == true else { return channel.eventLoop.makeSucceededFuture(nil) }
                            let id = ObjectIdentifier(channel)
                            return channel.eventLoop.makeFutureWithTask {
                                guard await admission.reserve(id) else { return nil }
                                channel.closeFuture.whenComplete { _ in Task { await admission.release(id) } }
                                return HTTPHeaders([("Sec-WebSocket-Protocol", "cmux-remote.v3")])
                            }
                        }, upgradePipelineHandler: { channel, _ in
                            guard let authority = router.linkAuthority else { return channel.eventLoop.makeFailedFuture(CancellationError()) }
                            let writer = LinkWebSocketWriter(channel: channel)
                            let session = LinkServerSession(router: router, authority: authority, send: { try await writer.send($0) }, terminate: { writer.close() })
                            return channel.pipeline.addHandler(BridgeWebSocketHandler(session: session))
                        })
                        let upgrade: NIOHTTPServerUpgradeConfiguration = (upgraders: [upgrader], completionHandler: { context in
                            context.pipeline.removeHandler(http, promise: nil)
                        })
                        return channel.pipeline.configureHTTPServerPipeline(withPipeliningAssistance: false, withServerUpgrade: upgrade).flatMapThrowing {
                            try channel.pipeline.syncOperations.addHandler(http)
                        }
                    } catch { return channel.eventLoop.makeFailedFuture(error) }
                }.bind(host: host, port: port).get()
            print("cmux-remote listening on https://\(host):\(port)")
            onListening?(server.localAddress?.port ?? port)
            try await withTaskCancellationHandler {
                try await server.closeFuture.get()
            } onCancel: { server.close(promise: nil) }
            try await group.shutdownGracefully()
        } catch { try? await group.shutdownGracefully(); throw error }
    }
}
