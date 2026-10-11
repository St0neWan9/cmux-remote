import Foundation
import Testing
import CmuxRemoteBridge

@Suite struct GitPolicyTests {
    @Test func wholeDiffCannotExportFilesDeniedByFilePreviewPolicy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try git(directory, ["init", "-q"])
        let publicFile = directory.appendingPathComponent("public.txt")
        let secret = directory.appendingPathComponent(".env")
        try Data("original".utf8).write(to: publicFile); try Data("original".utf8).write(to: secret)
        try git(directory, ["add", "--", "public.txt", ".env"])
        try git(directory, ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--no-gpg-sign", "-qm", "baseline"])
        try Data("public-value".utf8).write(to: publicFile); try Data("fixture-private-value".utf8).write(to: secret)
        let cmux = DemoCmux(transcript: directory.appendingPathComponent("unused.jsonl").path, project: directory.path)
        let service = SessionService(cmux: cmux, home: URL(fileURLWithPath: "/unrelated/home"), transcriptRoots: [directory])
        let diff = try await service.diff(id: "demo-session", path: nil)
        #expect(!diff.text.contains("fixture-private-value"))
        #expect(diff.text.contains("public-value"))
    }
    private func git(_ directory: URL, _ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git"); process.arguments = ["-C", directory.path] + arguments
        process.environment = ["PATH": "/usr/bin:/bin", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
    }
}
