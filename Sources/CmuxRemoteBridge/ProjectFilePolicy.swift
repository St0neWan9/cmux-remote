import Foundation
import CmuxRemoteCore

/// Constrains remote file reads to an explicit project, after resolving symlinks.
public struct ProjectFilePolicy: Sendable {
    private let home: URL
    public init(home: URL) { self.home = home.resolvingSymlinksInPath().standardizedFileURL }
    public func projectRoot(_ root: String) throws -> URL {
        let base = URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL
        let sensitive = [".ssh", ".aws", ".gnupg", ".codex", ".claude", ".config", "Library"]
        guard base.path != "/", base.path != home.path, !home.path.hasPrefix(base.path + "/"),
              !sensitive.contains(where: { base.path == home.appendingPathComponent($0).path || base.path.hasPrefix(home.appendingPathComponent($0).path + "/") }) else { throw denied() }
        return base
    }
    public func resolve(root: String, relativePath: String) throws -> URL {
        try resolve(root: root, relativePath: relativePath, allowMissing: false)
    }
    public func resolveDiffPath(root: String, relativePath: String) throws -> URL {
        try resolve(root: root, relativePath: relativePath, allowMissing: true)
    }
    private func resolve(root: String, relativePath: String, allowMissing: Bool) throws -> URL {
        let base = try projectRoot(root)
        guard base.path != "/", base.path != home.path, !relativePath.isEmpty, !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else { throw denied() }
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.contains(where: { $0.hasPrefix(".") || ["id_rsa", "id_ed25519", "credentials.json"].contains($0) }),
              !["pem", "key", "p12", "pfx", "mobileprovision"].contains(URL(fileURLWithPath: relativePath).pathExtension.lowercased()) else { throw denied() }
        let file = base.appendingPathComponent(relativePath).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(base.path + "/") else { throw denied() }
        let canonicalRelative = String(file.path.dropFirst(base.path.count + 1))
        guard !canonicalRelative.split(separator: "/").contains(where: { $0.hasPrefix(".") || ["id_rsa", "id_ed25519", "credentials.json"].contains(String($0)) }),
              !["pem", "key", "p12", "pfx", "mobileprovision"].contains(file.pathExtension.lowercased()) else { throw denied() }
        if allowMissing, !FileManager.default.fileExists(atPath: file.path) { return file }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 1_048_576 else { throw denied() }
        return file
    }
    /// A folder inside a project root, chosen by a relative path; empty means the root itself.
    public func directory(root: String, relativePath: String) throws -> URL {
        let base = try projectRoot(root)
        guard relativePath.utf8.count <= 1024, !relativePath.hasPrefix("/"), !relativePath.contains("\u{0}") else { throw directoryDenied() }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.contains(where: { $0 == ".." || $0.hasPrefix(".") }) else { throw directoryDenied() }
        let folder = (components.isEmpty ? base : base.appendingPathComponent(components.joined(separator: "/"))).resolvingSymlinksInPath().standardizedFileURL
        guard folder.path == base.path || folder.path.hasPrefix(base.path + "/") else { throw directoryDenied() }
        // A link inside the root may still land on a hidden or sensitive folder of the root.
        let canonical = folder.path == base.path ? [] : folder.path.dropFirst(base.path.count + 1).split(separator: "/")
        guard !canonical.contains(where: { $0.hasPrefix(".") }) else { throw directoryDenied() }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BridgeError("directory_missing", "The selected folder no longer exists.", status: 404)
        }
        return folder
    }
    private func directoryDenied() -> BridgeError { BridgeError("directory_forbidden", "This folder cannot be used from the selected project.", status: 403) }
    private func denied() -> BridgeError { BridgeError("file_forbidden", "This file cannot be shared from the selected project.", status: 403) }
}
