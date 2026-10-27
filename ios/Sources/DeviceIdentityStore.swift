import Foundation
import CmuxRemoteCore

/// A stable private device identity survives disconnects; it is never included in a QR code.
struct DeviceIdentityStore {
    private let store = SecureDeviceStore(service: "cmux-remote.identity", legacyService: "com.st0newan9.cmux-remote.identity")
    func privateKey() throws -> Data {
        if let data = store.load(account: "private-key") { _ = try IdentityCryptography().publicKey(privateKey: data); return data }
        let key = IdentityCryptography().generatePrivateKey(); try store.save(key, account: "private-key"); return key
    }
}
