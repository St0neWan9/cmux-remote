import Foundation
import CBridgeDiscovery
import CmuxRemoteCore

/// Owns one DNS-SD registration. The immutable C handle has no Swift callbacks or mutable shared state.
public final class BonjourAdvertisement: @unchecked Sendable {
    private let handle: UnsafeMutableRawPointer
    public init(host: HostIdentity, port: Int) throws {
        try IdentityCryptography().validate(host)
        guard (1...65535).contains(port) else { throw BridgeError("invalid_endpoint", "Invalid service port.") }
        let fields = ["version=2", "hostID=" + host.id, "publicKey=" + host.publicKey, "certificate=" + host.certificateSHA256, "name=" + host.name]
        var txt = Data()
        for field in fields { let bytes = Data(field.utf8); guard bytes.count <= 255 else { throw BridgeError("discovery_failed", "Service metadata is too large.") }; txt.append(UInt8(bytes.count)); txt.append(bytes) }
        var ref: UnsafeMutableRawPointer?
        let error = txt.withUnsafeBytes { bytes in cmux_bonjour_publish("cmux-remote-" + String(host.id.prefix(12)), UInt16(port), bytes.bindMemory(to: UInt8.self).baseAddress, UInt16(txt.count), &ref) }
        guard error == 0, let ref else { throw BridgeError("discovery_failed", "LAN discovery could not be advertised. Manual and QR endpoints remain available.") }
        handle = ref
    }
    deinit { cmux_bonjour_stop(handle) }
}
