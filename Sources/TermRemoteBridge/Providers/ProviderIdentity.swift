import Foundation
import CryptoKit
import TermRemoteCore

/// Stable, opaque UUIDs for providers and the resources they expose. The
/// derivation is one-way: no provider id or native resource id is recoverable
/// from a UUID a device receives.
public enum ProviderIdentity {
    /// A version-8-style UUID derived from the provider kind and its stable
    /// instance identity. Changing the instance identity creates a new provider.
    public static func providerID(kind: ProviderKind, instance: String) -> String {
        uuid("term-remote.provider|" + kind.rawValue + "|" + instance)
    }

    /// A derived UUID for a provider resource such as a Rex session or block.
    public static func resourceID(providerID: String, kind: String, nativeID: String) -> String {
        uuid("term-remote.resource|" + providerID + "|" + kind + "|" + nativeID)
    }

    static func uuid(_ label: String) -> String {
        var bytes = Array(SHA256.hash(data: Data(label.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])).uuidString.lowercased()
    }
}
