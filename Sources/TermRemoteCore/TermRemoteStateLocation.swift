import Foundation

/// The owner's private Bridge state directory.
///
/// The first run under the Term Remote name copies the old CmuxRemote state once, so
/// existing host identity, grants and relay registration keep working. A custom
/// `--state` path is never touched.
public enum TermRemoteStateLocation {
    public static func directory(home: URL) -> URL {
        let current = home.appendingPathComponent(".local/state/term-remote", isDirectory: true)
        let legacy = home.appendingPathComponent(".local/state/cmux-remote", isDirectory: true)
        let manager = FileManager.default
        guard !manager.fileExists(atPath: current.path), manager.fileExists(atPath: legacy.path) else { return current }
        try? manager.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.copyItem(at: legacy, to: current)
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: current.path)
        return current
    }
}
