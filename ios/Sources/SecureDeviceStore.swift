import Foundation
import Security
import CmuxRemoteCore

/// Platform storage: physical-device-only Keychain; isolated Simulator sandbox for development.
struct SecureDeviceStore {
    let service: String
    func load(account: String) -> Data? {
        #if targetEnvironment(simulator)
        return try? Data(contentsOf: file(account))
        #else
        var lookup = query(account); lookup[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
        #endif
    }
    func save(_ data: Data, account: String) throws {
        #if targetEnvironment(simulator)
        let path = file(account)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: path, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        #else
        let match = query(account)
        let status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = match; insertion[kSecValueData as String] = data; insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw BridgeError("keychain_failed", "Device identity could not be saved.") }
        } else if status != errSecSuccess { throw BridgeError("keychain_failed", "Device identity could not be saved.") }
        #endif
    }
    func remove(account: String) {
        #if targetEnvironment(simulator)
        try? FileManager.default.removeItem(at: file(account))
        #else
        SecItemDelete(query(account) as CFDictionary)
        #endif
    }
    #if targetEnvironment(simulator)
    private func file(_ account: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProtectedConnection/" + service + "/" + account + ".json")
    }
    #else
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    #endif
}
