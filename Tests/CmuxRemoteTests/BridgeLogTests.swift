import Foundation
import Testing
@testable import CmuxRemoteBridge

@Suite struct BridgeLogTests {
    @Test func eventsReachAnOwnerOnlyFileThatRotatesPastItsBound() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = BridgeLog()
        log.configure(directory: directory)
        log.warning("relay", "relay reconnecting attempt=2")
        let file = directory.appendingPathComponent("bridge.log")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("WARNING [relay] relay reconnecting attempt=2"))
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        // Past four MiB the file moves to bridge.log.1 and a fresh file continues, so the log stays bounded.
        let line = String(repeating: "x", count: 1_000)
        for _ in 0..<4_300 { log.debug("link", line) }
        let rotated = directory.appendingPathComponent("bridge.log.1")
        #expect(FileManager.default.fileExists(atPath: rotated.path))
        let current = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0
        #expect(current < 4 * 1024 * 1024)
    }
}
