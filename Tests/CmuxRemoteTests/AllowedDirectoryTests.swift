import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// The owner's shared folders are offered to every workspace, in front of that workspace's own, and
/// they are still subject to the same policy: the owner cannot share what the policy always withholds.
@Suite struct AllowedDirectoryTests {
    private func makeStore() throws -> (AllowedDirectoryRepository, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("allowed-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (AllowedDirectoryRepository(directory: root), root)
    }

    @Test func aMissingOrMalformedFileReadsAsNoFolders() throws {
        let (store, root) = try makeStore()
        #expect(store.load().isEmpty)
        try Data("not json".utf8).write(to: root.appendingPathComponent("allowed-directories.json"))
        #expect(store.load().isEmpty)
        // A foreign file is ignored rather than trusted, as with the other owner-only state.
        try Data(#"["/tmp"]"#.utf8).write(to: root.appendingPathComponent("allowed-directories.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: root.appendingPathComponent("allowed-directories.json").path)
        #expect(store.load().isEmpty)
    }

    @Test func savedFoldersComeBackCanonicalAndDeduplicated() throws {
        let (store, root) = try makeStore()
        let folder = root.appendingPathComponent("one/two")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: folder)
        try store.save([folder.path, root.appendingPathComponent("link").path, folder.path + "/"])
        #expect(store.load().map(\.path) == [folder.path])
    }

    @Test func traversalAndRelativePathsAreRefused() throws {
        let (store, _) = try makeStore()
        for path in ["relative/path", "/tmp/../etc", "~/../etc", "", " /tmp/./etc "] {
            #expect(throws: (any Error).self) { try store.save([path]) }
        }
        #expect(store.load().isEmpty)
        #expect(throws: (any Error).self) { try store.save((0...AllowedDirectoryRepository.limit).map { "/tmp/folder\($0)" }) }
    }

    @Test func theDisplayFormWithATildeRoundTrips() throws {
        let (store, _) = try makeStore()
        let home = FileManager.default.homeDirectoryForCurrentUser
        // The settings page reads each folder back as `~` and sends that same string when the list changes.
        try store.save(["~"])
        #expect(store.load().map(\.path) == [home.path])
        try store.save(["~"])
        #expect(store.load().map(\.path) == [home.path])
    }

    @Test func sharedFoldersLeadTheListAndStillPassThePolicy() async throws {
        let fixture = try LaunchFixture()
        let shared = fixture.home.appendingPathComponent("shared")
        let sensitive = fixture.home.appendingPathComponent(".ssh")
        for folder in [shared, sensitive] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let launcher = SessionLauncher(cmux: fixture.cmux, home: fixture.home, mutations: MutationLedger(), sessions: { [] },
                                       sharedRoots: { [shared, sensitive, fixture.home] })
        let roots = try await launcher.directories(workspaceID: LaunchCmux.workspace, access: fixture.access())
        // The workspace's own directory follows the owner's choice, and no withheld folder appears at all.
        #expect(roots.map(\.path) == ["~/shared", "~/projects/app"])
    }

    @Test func aSharedFolderWhoseConversationAlsoUsesItAppearsOnce() async throws {
        let fixture = try LaunchFixture()
        let launcher = SessionLauncher(cmux: fixture.cmux, home: fixture.home, mutations: MutationLedger(),
                                       sessions: { [SessionDescriptor(id: "a", agent: "claude", title: "A", cwd: fixture.other.path, workspaceID: LaunchCmux.workspace, surfaceID: "s1", updatedAt: Date())] },
                                       sharedRoots: { [fixture.other] })
        let roots = try await launcher.directories(workspaceID: LaunchCmux.workspace, access: fixture.access())
        #expect(roots.map(\.path) == ["~/projects/other", "~/projects/app"])
    }

    @Test func aStartedSessionUsesASharedFolder() async throws {
        let fixture = try LaunchFixture()
        let shared = fixture.home.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        let launcher = SessionLauncher(cmux: fixture.cmux, home: fixture.home, mutations: MutationLedger(), sessions: { [] },
                                       sharedRoots: { [shared] })
        let root = try await launcher.directories(workspaceID: LaunchCmux.workspace, access: fixture.access())[0]
        _ = try await launcher.start(workspaceID: LaunchCmux.workspace, request: StartSessionRequest(rootID: root.id, agent: .claude), access: fixture.access())
        #expect(await fixture.cmux.creates.first?["working_directory"]?.string == shared.path)
    }
}
