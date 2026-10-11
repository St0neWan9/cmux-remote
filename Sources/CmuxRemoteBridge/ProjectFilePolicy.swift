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
        let base = try projectRoot(root)
        guard base.path != "/", base.path != home.path, !relativePath.isEmpty, !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else { throw denied() }
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.contains(where: { $0.hasPrefix(".") || ["id_rsa", "id_ed25519", "credentials.json"].contains($0) }),
              !["pem", "key", "p12", "pfx", "mobileprovision"].contains(URL(fileURLWithPath: relativePath).pathExtension.lowercased()) else { throw denied() }
        let file = base.appendingPathComponent(relativePath).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(base.path + "/") else { throw denied() }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 1_048_576 else { throw denied() }
        return file
    }
    private func denied() -> BridgeError { BridgeError("file_forbidden", "This file cannot be shared from the selected project.", status: 403) }
}
