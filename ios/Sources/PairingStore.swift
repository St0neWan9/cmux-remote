import Foundation
import Security
import CmuxRemoteCore

/// Pairing credentials remain in device-only Keychain storage.
struct PairingStore {
    private let service = "com.st0newan9.cmux-remote.pairing"
    private let protected = SecureDeviceStore(service: "com.st0newan9.cmux-remote.authorized")
    func loadConnection() -> AuthorizedConnection? {
        guard let data = protected.load(account: "host"), let value = try? JSONDecoder().decode(AuthorizedConnection.self, from: data), (try? value.validate()) != nil else { return nil }
        return value
    }
    func saveConnection(_ value: AuthorizedConnection) throws { try value.validate(); try protected.save(JSONEncoder().encode(value), account: "host") }
    func removeConnection() { protected.remove(account: "host") }
    func load() -> PairingConfiguration? {
        #if targetEnvironment(simulator)
        // Simulator verification has no provisioning profile. Keep fixture state inside its sandbox.
        guard let data = try? Data(contentsOf: simulatorFile), let value = try? JSONDecoder().decode(PairingConfiguration.self, from: data) else { return nil }
        return try? PairingConfiguration(host: value.host, port: value.port, token: value.token, certificateSHA256: value.certificateSHA256)
        #else
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let value = try? JSONDecoder().decode(PairingConfiguration.self, from: data) else { return nil }
        return try? PairingConfiguration(host: value.host, port: value.port, token: value.token, certificateSHA256: value.certificateSHA256)
        #endif
    }
    func save(_ value: PairingConfiguration) throws {
        #if targetEnvironment(simulator)
        try FileManager.default.createDirectory(at: simulatorFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: simulatorFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: simulatorFile.path)
        #else
        remove()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "paired-host", kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, kSecValueData as String: try JSONEncoder().encode(value)]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw BridgeError("keychain_failed", "Pairing could not be saved.") }
        #endif
    }
    func remove() {
        #if targetEnvironment(simulator)
        try? FileManager.default.removeItem(at: simulatorFile)
        #else
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
        #endif
    }
    #if targetEnvironment(simulator)
    private var simulatorFile: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SimulatorPairing/pairing.json") }
    #endif
}
