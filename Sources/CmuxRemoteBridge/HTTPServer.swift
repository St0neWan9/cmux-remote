import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL

/// TLS HTTP service for the versioned mobile API.
public struct HTTPServer: Sendable {
    public init() {}
    public func run(host: String, port: Int, certificate: String, key: String, router: BridgeRouter, onListening: (@Sendable (Int) -> Void)? = nil) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let configuration = TLSConfiguration.makeServerConfiguration(certificateChain: try NIOSSLCertificate.fromPEMFile(certificate).map { .certificate($0) }, privateKey: .privateKey(try NIOSSLPrivateKey(file: key, format: .pem)))
        let tls = try NIOSSLContext(configuration: configuration)
        do {
            let server = try await ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.backlog, value: 128)
                .childChannelInitializer { channel in
                    do {
                        // The bootstrap invokes this closure on the channel event loop.
                        try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: tls))
                        return channel.pipeline.configureHTTPServerPipeline(withPipeliningAssistance: false).flatMapThrowing {
                            try channel.pipeline.syncOperations.addHandler(BridgeHTTPHandler(router: router))
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
