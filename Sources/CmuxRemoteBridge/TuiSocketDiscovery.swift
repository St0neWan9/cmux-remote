import Foundation
import Darwin
import CmuxRemoteCore

/// Finds only existing same-user private sockets in cmux-tui's documented runtime directories.
public struct TuiSocketDiscovery: Sendable {
    private let directories: [URL]
    private let explicit: [String]
    public init(temporaryDirectory: URL = FileManager.default.temporaryDirectory, explicit: [String] = []) {
        let names = ["cmux-tui-", "cmux-tui-hashed-"]
        directories = [temporaryDirectory, URL(fileURLWithPath: "/tmp")].flatMap { base in names.map { base.appendingPathComponent($0 + String(getuid()), isDirectory: true) } }
        self.explicit = explicit
    }
    public init(directories: [URL], explicit: [String] = []) { self.directories = directories; self.explicit = explicit }
    private func canonical(_ path: String) -> String {
        let file = URL(fileURLWithPath: path)
        guard let parent = Darwin.realpath(file.deletingLastPathComponent().path, nil) else { return file.standardizedFileURL.path }
        defer { free(parent) }
        return URL(fileURLWithPath: String(cString: parent)).appendingPathComponent(file.lastPathComponent).path
    }
    public func sockets() throws -> [String] {
        guard explicit.count <= 16, explicit.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }) else { throw BridgeError("invalid_socket", "Select at most sixteen absolute daemon socket paths.") }
        var found = Set(explicit.map(canonical))
        for directory in directories {
            var metadata = stat()
            guard lstat(directory.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR,
                  metadata.st_uid == getuid(), metadata.st_mode & 0o077 == 0 else { continue }
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            guard files.count <= 1024 else { throw BridgeError("too_large", "The daemon socket discovery directory is too large.", status: 413) }
            for file in files where file.pathExtension == "sock" {
                var socketMetadata = stat()
                if lstat(file.path, &socketMetadata) == 0, socketMetadata.st_mode & S_IFMT == S_IFSOCK,
                   socketMetadata.st_uid == getuid(), socketMetadata.st_mode & 0o077 == 0 { found.insert(file.path) }
            }
        }
        guard found.count <= 16 else { throw BridgeError("too_large", "Too many local daemon sessions are available.", status: 413) }
        return found.sorted()
    }
}
