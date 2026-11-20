import Foundation
import Security
import TermRemoteCore

/// Platform storage: physical-device-only Keychain; isolated Simulator sandbox for development.
struct SecureDeviceStore {
    let service: String
    /// The service name used before the Term Remote identity change. A successful read is copied forward.
    let legacyService: String?

    init(service: String, legacyService: String? = nil) {
        self.service = service; self.legacyService = legacyService
    }

    func load(account: String) -> Data? {
        if let data = load(service: service, account: account) { return data }
        guard let legacyService, let data = load(service: legacyService, account: account) else { return nil }
        try? save(data, account: account)
        return data
    }

    func save(_ data: Data, account: String) throws {
        #if targetEnvironment(simulator)
        let path = file(service, account)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: path, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        #else
        let match = query(service, account)
        let status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = match; insertion[kSecValueData as String] = data; insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw BridgeError("keychain_failed", "Device identity could not be saved.") }
        } else if status != errSecSuccess { throw BridgeError("keychain_failed", "Device identity could not be saved.") }
        #endif
    }

    func remove(account: String) {
        #if targetEnvironment(simulator)
        try? FileManager.default.removeItem(at: file(service, account))
        #else
        SecItemDelete(query(service, account) as CFDictionary)
        #endif
    }

    private func load(service: String, account: String) -> Data? {
        #if targetEnvironment(simulator)
        return try? Data(contentsOf: file(service, account))
        #else
        var lookup = query(service, account); lookup[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
        #endif
    }

    #if targetEnvironment(simulator)
    private func file(_ service: String, _ account: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProtectedConnection/" + service + "/" + account + ".json")
    }
    #else
    private func query(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    #endif
}
