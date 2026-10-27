import Foundation
import Security
import CmuxRemoteCore

/// Platform storage: physical-device-only Keychain; isolated Simulator sandbox for development.
struct SecureDeviceStore {
    let service: String
    /// Where an earlier build kept this item. Its value moves to `service` the first time it is read, so renaming a
    /// service does not cost the person their pairing.
    var legacyService: String? = nil
    func load(account: String) -> Data? {
        #if targetEnvironment(simulator)
        if let data = try? Data(contentsOf: file(account)) { return data }
        guard let legacyService, let data = try? Data(contentsOf: file(account, service: legacyService)) else { return nil }
        migrate(data, account: account, from: legacyService)
        return data
        #else
        if let data = read(service, account) { return data }
        guard let legacyService, let data = read(legacyService, account) else { return nil }
        migrate(data, account: account, from: legacyService)
        return data
        #endif
    }
    /// Copies an item read under a retired service name to the current one, then deletes the old copy. A failed
    /// copy still returns what the person had; the move is retried on the next read.
    private func migrate(_ data: Data, account: String, from legacyService: String) {
        #if targetEnvironment(simulator)
        guard (try? save(data, account: account)) != nil else { return }
        try? FileManager.default.removeItem(at: file(account, service: legacyService))
        #else
        guard (try? save(data, account: account)) != nil else { return }
        SecItemDelete(query(legacyService, account) as CFDictionary)
        #endif
    }
    func save(_ data: Data, account: String) throws {
        #if targetEnvironment(simulator)
        let path = file(account)
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
        try? FileManager.default.removeItem(at: file(account))
        #else
        SecItemDelete(query(service, account) as CFDictionary)
        #endif
    }
    #if targetEnvironment(simulator)
    private func file(_ account: String, service: String? = nil) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProtectedConnection/" + (service ?? self.service) + "/" + account + ".json")
    }
    #else
    private func query(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    private func read(_ service: String, _ account: String) -> Data? {
        var query = query(service, account); query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    #endif
}
