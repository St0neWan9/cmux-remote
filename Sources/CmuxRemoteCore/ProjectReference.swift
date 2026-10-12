import Foundation

/// Converts a transcript reference into a relative project route, never an arbitrary host path.
public struct ProjectReference: Sendable {
    public init() {}
    public func relativePath(_ path: String, root: String?) -> String? {
        guard let root, !root.isEmpty, !path.isEmpty else { return nil }
        let base = URL(fileURLWithPath: root).standardizedFileURL.path
        guard base != "/" else { return nil }
        let target = path.hasPrefix("/") ? URL(fileURLWithPath: path).standardizedFileURL.path : URL(fileURLWithPath: base).appendingPathComponent(path).standardizedFileURL.path
        guard target.hasPrefix(base + "/") else { return nil }
        return String(target.dropFirst(base.count + 1))
    }
}
