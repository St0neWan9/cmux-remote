import Foundation
import Security
import CmuxRemoteCore

/// Pairing credentials remain in device-only Keychain storage.
struct PairingStore {
    private let service = "com.st0newan9.cmux-remote.pairing"
    private let protected = SecureDeviceStore(service: "com.st0newan9.cmux-remote.authorized")
    func legacyEnabled() -> Bool { protected.load(account: "explicit-legacy") == Data([1]) }
    func enableLegacy() throws { try protected.save(Data([1]), account: "explicit-legacy") }
    func disableLegacy() { protected.remove(account: "explicit-legacy") }
    /// Every approved Mac, one entry per host identity, in the order they were added.
    func loadConnections() -> [AuthorizedConnection] {
        if let data = protected.load(account: "hosts"), let values = try? JSONDecoder().decode([AuthorizedConnection].self, from: data) {
            return values.filter { (try? $0.validate()) != nil }
        }
        // Earlier builds saved a single Mac; it becomes the first entry of the list.
        guard let data = protected.load(account: "host"), let value = try? JSONDecoder().decode(AuthorizedConnection.self, from: data), (try? value.validate()) != nil else { return [] }
        if (try? write([value])) != nil { protected.remove(account: "host") }
        return [value]
    }
    /// Replaces the entry for the same host identity, keeping its position, or appends a new Mac.
    func saveConnection(_ value: AuthorizedConnection) throws {
        try value.validate()
        var values = loadConnections()
        if let index = values.firstIndex(where: { $0.host.id == value.host.id }) { values[index] = value }
        else { guard values.count < 16 else { throw BridgeError("pairing_capacity", "Remove a Mac before adding another.") }; values.append(value) }
        try write(values)
    }
    func removeConnection(hostID: String) { try? write(loadConnections().filter { $0.host.id != hostID }) }
    private func write(_ values: [AuthorizedConnection]) throws { try protected.save(JSONEncoder().encode(values), account: "hosts") }
    /// Relay origins are public routing information, not credentials.
    func relayOrigins() -> [String] { UserDefaults.standard.stringArray(forKey: "relayOrigins") ?? [] }
    func saveRelayOrigins(_ values: [String]) { UserDefaults.standard.set(Array(values.prefix(8)), forKey: "relayOrigins") }
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
