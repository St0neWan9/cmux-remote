import Foundation

/// The owner's private Bridge state directory.
///
/// The first run under the Term Remote name copies the old CmuxRemote state once, so
/// existing host identity, grants and relay registration keep working. A custom
/// `--state` path is never touched. Live sockets are skipped: a copied owner socket
/// is a dead endpoint, and copying one aborts the whole migration.
public enum TermRemoteStateLocation {
    public static func directory(home: URL) -> URL {
        let stateRoot = home.appendingPathComponent(".local/state", isDirectory: true)
        let current = stateRoot.appendingPathComponent("term-remote", isDirectory: true)
        let legacy = stateRoot.appendingPathComponent("cmux-remote", isDirectory: true)
        let manager = FileManager.default
        guard !manager.fileExists(atPath: current.path), manager.fileExists(atPath: legacy.path) else { return current }
        let staging = stateRoot.appendingPathComponent("term-remote.migrating", isDirectory: true)
        try? manager.removeItem(at: staging)
        guard (try? manager.createDirectory(at: staging, withIntermediateDirectories: true)) != nil else { return current }
        for name in (try? manager.contentsOfDirectory(atPath: legacy.path)) ?? [] {
            let source = legacy.appendingPathComponent(name)
            guard let type = (try? manager.attributesOfItem(atPath: source.path))?[.type] as? FileAttributeType,
                  type != .typeSocket else { continue }
            try? manager.copyItem(at: source, to: staging.appendingPathComponent(name))
        }
        // Grants were signed under the old protocol domain, so they cannot survive the rename.
        // Keeping them would make the authority reject the whole registry at startup.
        try? manager.removeItem(at: staging.appendingPathComponent("clients.json"))
        try? manager.removeItem(at: staging.appendingPathComponent("mac-connections.json"))
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staging.path)
        do { try manager.moveItem(at: staging, to: current) }
        catch { try? manager.removeItem(at: staging) }
        return current
    }
}
