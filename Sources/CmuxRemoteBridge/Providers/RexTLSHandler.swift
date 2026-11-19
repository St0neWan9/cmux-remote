@preconcurrency import NIOSSL
import NIOCore

/// NIO's TLS handler is not Sendable under strict concurrency. The handler is
/// created and installed on one channel's event loop; the box only carries it
/// across the sendable channel-initializer boundary.
final class RexTLSHandler: @unchecked Sendable {
    let handler: NIOSSLClientHandler

    init(host: String) throws {
        var configuration = TLSConfiguration.makeClientConfiguration()
        configuration.certificateVerification = .fullVerification
        let context = try NIOSSLContext(configuration: configuration)
        handler = try NIOSSLClientHandler(context: context, serverHostname: host)
    }
}
