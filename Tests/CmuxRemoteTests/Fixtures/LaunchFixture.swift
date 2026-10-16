import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

/// One workspace to launch in, with its own folders, sessions and a recorded `surface.create`.
actor LaunchCmux: CmuxControlling {
    static let workspace = "11111111-1111-1111-1111-111111111111"
    static let daemonWorkspace = "33333333-3333-3333-3333-333333333333"
    let current: String
    var creates: [[String: JSONValue]] = []
    var failCreate = false
    init(current: String) { self.current = current }
    func setFailure(_ value: Bool) { failCreate = value }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "workspace.list":
            return .object(["workspaces": .array([
                .object(["id": .string(Self.workspace.uppercased()), "title": .string("App"), "current_directory": .string(current)]),
                .object(["id": .string(Self.daemonWorkspace), "title": .string("Daemon"), "backend": .string("cmux-tui")])])])
        case "surface.create":
            creates.append(params)
            if failCreate { throw BridgeError("outcome_unknown", "fixture", status: 503) }
            return .object(["surface_id": .string("44444444-4444-4444-4444-44444444444" + String(creates.count))])
        default: return .object([:])
        }
    }
}

struct LaunchFixture {
    let home: URL
    let root: URL
    let other: URL
    let cmux: LaunchCmux
    let launcher: SessionLauncher
    let ledger: MutationLedger
    init(currentIsHome: Bool = false, ledgerDirectory: Bool = false, sharedRoots: [URL] = []) throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("launch-" + UUID().uuidString).resolvingSymlinksInPath()
        root = home.appendingPathComponent("projects/app"); other = home.appendingPathComponent("projects/other")
        let fm = FileManager.default
        for folder in ["src/core", ".git", "docs", "../other", "../../secret"] { try fm.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true) }
        try fm.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: home.appendingPathComponent("secret"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("inside"), withDestinationURL: root.appendingPathComponent("src"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("hidden"), withDestinationURL: root.appendingPathComponent(".git"))
        try Data("x".utf8).write(to: root.appendingPathComponent("README.md"))
        cmux = LaunchCmux(current: currentIsHome ? home.path : root.path)
        let state = home.appendingPathComponent("state")
        if ledgerDirectory { try fm.createDirectory(at: state, withIntermediateDirectories: true) }
        ledger = MutationLedger(directory: ledgerDirectory ? state : nil)
        let other = other, home = home
        launcher = SessionLauncher(cmux: cmux, home: home, mutations: ledger, sessions: {
            [SessionDescriptor(id: "a", agent: "claude", title: "A", cwd: other.path, workspaceID: LaunchCmux.workspace, surfaceID: "s1", updatedAt: Date()),
             SessionDescriptor(id: "b", agent: "codex", title: "B", cwd: home.appendingPathComponent("projects").path, workspaceID: "55555555-5555-5555-5555-555555555555", surfaceID: "s2")]
        }, sharedRoots: { sharedRoots })
    }
    /// Approves exactly the fixture workspace for the given capabilities.
    func access(_ capabilities: Set<ClientCapability> = [.conversationStart], client: String = "phone") -> SessionAccess {
        SessionAccess(clientID: client) { capability, workspace in
            guard capabilities.contains(capability), workspace.lowercased() == LaunchCmux.workspace else { throw BridgeError("scope_denied", "fixture", status: 403) }
        }
    }
    func code<T>(_ body: () async throws -> T) async -> String? {
        do { _ = try await body(); return nil } catch { return (error as? BridgeError)?.code ?? "\(error)" }
    }
}
