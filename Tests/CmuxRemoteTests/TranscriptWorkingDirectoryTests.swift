import Foundation
import Testing
@testable import CmuxRemoteBridge

@Suite struct TranscriptWorkingDirectoryTests {
    @Test func newestRecordedDirectoryWinsOverPartialLinesAndCodexPayload() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let claude = [#"{"type":"user","cwd":"/Users/me","message":{"role":"user","content":"a"}}"#,
                      #"{"type":"assistant","cwd":"/Users/me/projects/app","message":{"role":"assistant","content":[]}}"#,
                      #"{"type":"assistant","message":{"role":"assistant","content":[]}}"#].joined(separator: "\n") + "\n"
        try Data(claude.utf8).write(to: file)
        let size = try #require(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber).intValue
        #expect(TranscriptWorkingDirectory().read(path: file.path, size: size) == "/Users/me/projects/app")
        let codex = #"{"type":"turn_context","payload":{"cwd":"/Users/me/codex-repo"}}"# + "\n"
        try Data(codex.utf8).write(to: file)
        #expect(TranscriptWorkingDirectory().read(path: file.path, size: codex.utf8.count) == "/Users/me/codex-repo")
        // A file larger than the read window starts mid-line; that fragment must not be trusted.
        let padding = String(repeating: "x", count: 140_000)
        let large = #"{"cwd":"/wrong","note":""# + padding + "\"}\n" + #"{"cwd":"/Users/me/right"}"# + "\n"
        try Data(large.utf8).write(to: file)
        #expect(TranscriptWorkingDirectory().read(path: file.path, size: large.utf8.count) == "/Users/me/right")
    }
}
