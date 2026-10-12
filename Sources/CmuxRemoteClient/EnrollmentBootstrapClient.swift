import Foundation
import CmuxRemoteCore

/// Only invoke after QR trust or explicit identity confirmation; Bonjour alone does not establish trust.
public struct EnrollmentBootstrapClient: Sendable {
    public init() {}
    public func fetch(endpoint: BridgeEndpoint, trustedHost: HostIdentity) async throws -> SignedValue<EnrollmentBootstrap> {
        try endpoint.validate(); try IdentityCryptography().validate(trustedHost)
        let transport = PinnedTransport(pairing: try PairingConfiguration(host: endpoint.host, port: endpoint.port, token: String(repeating: "0", count: 32), certificateSHA256: trustedHost.certificateSHA256))
        defer { transport.close() }
        let bootstrap = try await transport.request("/v2/enrollment/bootstrap", method: "GET", as: SignedValue<EnrollmentBootstrap>.self)
        try EnrollmentLinkCodec().validate(bootstrap, now: Int(Date().timeIntervalSince1970))
        guard bootstrap.value.host.id == trustedHost.id, bootstrap.value.host.publicKey == trustedHost.publicKey, bootstrap.value.host.certificateSHA256 == trustedHost.certificateSHA256 else { throw BridgeError("host_changed", "The enrollment belongs to a different host.") }
        // Reach the exact endpoint just verified; the signed bootstrap may advertise another LAN address.
        return bootstrap
    }
}
