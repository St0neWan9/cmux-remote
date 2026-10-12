import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

@Suite struct MacSetupTests {
    @Test func inheritedSetupIsPrivateAndRejectsPermissiveOrSymlinkFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MacSetupRepository(directory: root)
        let expected = ["CMUX_SOCKET_CAPABILITY": "fixture-opaque-capability", "CMUX_SOCKET_PATH": "/tmp/fixture.sock"]
        try store.save(environment: expected.merging(["UNRELATED": "must not save"]) { a, _ in a })
        #expect(try store.environment() == expected)
        let file = root.appendingPathComponent("cmux-setup.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(throws: BridgeError.self) { _ = try store.environment() }
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: root.appendingPathComponent("missing"))
        #expect(throws: BridgeError.self) { _ = try store.environment() }
    }
    @Test func noCapabilityDoesNotCreateSetup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = MacSetupRepository(directory: root)
        #expect(throws: BridgeError.self) { try store.save(environment: ["CMUX_SOCKET_PATH": "/tmp/fixture.sock"]) }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}
