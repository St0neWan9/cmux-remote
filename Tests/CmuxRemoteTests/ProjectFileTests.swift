import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

@Suite struct ProjectFileTests {
    @Test func traversalAndSymlinkEscapeAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = directory.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let secret = directory.appendingPathComponent("secret.txt"); try Data("private".utf8).write(to: secret)
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("escape.txt"), withDestinationURL: secret)
        let policy = ProjectFilePolicy(home: directory.appendingPathComponent("home"))
        #expect(throws: BridgeError.self) { try policy.resolve(root: project.path, relativePath: "../secret.txt") }
        #expect(throws: BridgeError.self) { try policy.resolve(root: project.path, relativePath: "escape.txt") }
    }
    @Test func homeAndCredentialFilesAreRejected() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let policy = ProjectFilePolicy(home: home)
        #expect(throws: BridgeError.self) { try policy.projectRoot(home.path) }
        #expect(throws: BridgeError.self) { try policy.projectRoot(home.appendingPathComponent(".ssh").path) }
        #expect(throws: BridgeError.self) { try policy.resolve(root: home.appendingPathComponent("project").path, relativePath: ".env") }
    }
    @Test func symlinkAliasCannotExposeHiddenCredentialFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let secret = directory.appendingPathComponent(".env"); try Data("fixture-secret".utf8).write(to: secret)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("public.txt"), withDestinationURL: secret)
        #expect(throws: BridgeError.self) { try ProjectFilePolicy(home: directory.appendingPathComponent("home")).resolve(root: directory.path, relativePath: "public.txt") }
    }
}
