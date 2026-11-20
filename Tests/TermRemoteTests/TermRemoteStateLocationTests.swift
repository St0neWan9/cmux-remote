import Foundation
import Testing
import TermRemoteCore

@Suite struct TermRemoteStateLocationTests {
    @Test func firstRunCopiesTheLegacyStateAndKeepsTheSource() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = home.appendingPathComponent(".local/state/cmux-remote")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: legacy.appendingPathComponent("token"))

        let current = TermRemoteStateLocation.directory(home: home)
        #expect(current.path.hasSuffix("/.local/state/term-remote"))
        #expect(try String(contentsOf: current.appendingPathComponent("token"), encoding: .utf8) == "legacy")
        #expect(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("token").path))
        #expect(try (FileManager.default.attributesOfItem(atPath: current.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }
}
