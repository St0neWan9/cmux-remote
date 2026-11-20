import Foundation
import Testing
@testable import TermRemoteBridge

@Suite struct ClaudeProcessRegistryTests {
    /// A long conversation used to fall outside the registry's size bound, so its Rex block
    /// stayed a shell and the conversation disappeared from the phone.
    @Test func aLongTranscriptStillBinds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root
        defer { try? FileManager.default.removeItem(at: root) }
        let pid = 4242
        let session = UUID().uuidString
        let cwd = "/Users/fixture/project"
        let sessions = home.appendingPathComponent(".claude/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let record = try JSONSerialization.data(withJSONObject: ["pid": pid, "sessionId": session, "cwd": cwd, "status": "idle"])
        try record.write(to: sessions.appendingPathComponent("\(pid).json"))

        let registry = ClaudeProcessRegistry(home: home)
        let transcript = URL(fileURLWithPath: registry.transcriptPath(cwd: cwd, sessionID: session))
        try FileManager.default.createDirectory(at: transcript.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: transcript.path, contents: nil)
        let handle = try FileHandle(forWritingTo: transcript)
        try handle.truncate(atOffset: 40 * 1024 * 1024)
        try handle.close()

        #expect(registry.binding(pid: pid, cwd: cwd, roots: [home.appendingPathComponent(".claude")]) != nil)
    }
}
