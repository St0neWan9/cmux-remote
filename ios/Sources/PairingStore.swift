import Foundation
import Security
import CmuxRemoteCore

/// Pairing credentials remain in device-only Keychain storage.
struct PairingStore {
    private let service = "com.st0newan9.cmux-remote.pairing"
    func load() -> PairingConfiguration? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let value = try? JSONDecoder().decode(PairingConfiguration.self, from: data) else { return nil }
        return try? PairingConfiguration(host: value.host, port: value.port, token: value.token, certificateSHA256: value.certificateSHA256)
    }
    func save(_ value: PairingConfiguration) throws {
        remove()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "paired-host", kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, kSecValueData as String: try JSONEncoder().encode(value)]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw BridgeError("keychain_failed", "Pairing could not be saved.") }
    }
    func remove() { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
}
