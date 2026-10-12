import Foundation
import Darwin
import CmuxRemoteCore

/// Stores only the official capability explicitly inherited by a setup command.
public struct MacSetupRepository: Sendable {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func save(environment: [String: String]) throws {
        guard let capability = environment["CMUX_SOCKET_CAPABILITY"], !capability.isEmpty,
              capability.utf8.count <= 8192, !capability.contains(where: { $0.isWhitespace }),
              let socket = environment["CMUX_SOCKET_PATH"], socket.hasPrefix("/"), socket.utf8.count < 104 else {
            throw BridgeError("setup_required", "Run setup in a cmux shell that exports its official socket capability.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("cmux-setup.json")
        let data = try JSONEncoder().encode(["CMUX_SOCKET_CAPABILITY": capability, "CMUX_SOCKET_PATH": socket])
        // Write a private staging file before rename; atomic Data.write can inherit a permissive umask.
        let staging = directory.appendingPathComponent(".setup-" + UUID().uuidString)
        let fd = Darwin.open(staging.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw BridgeError("setup_storage", "The local connection could not be saved.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: staging) }
        try handle.write(contentsOf: data); try handle.synchronize()
        guard rename(staging.path, url.path) == 0 else { throw BridgeError("setup_storage", "The local connection could not be saved.") }
    }
    public func environment() throws -> [String: String] {
        let url = directory.appendingPathComponent("cmux-setup.json")
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw BridgeError("setup_required", "Connect this app to cmux first.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o077 == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_size > 0, info.st_size <= 16384 else {
            throw BridgeError("setup_storage", "The local connection file is not private or valid.")
        }
        let value = try JSONDecoder().decode([String: String].self, from: handle.readToEnd() ?? Data())
        guard Set(value.keys) == ["CMUX_SOCKET_PATH", "CMUX_SOCKET_CAPABILITY"],
              let capability = value["CMUX_SOCKET_CAPABILITY"], !capability.isEmpty,
              !capability.contains(where: { $0.isWhitespace }), let socket = value["CMUX_SOCKET_PATH"], socket.hasPrefix("/") else {
            throw BridgeError("setup_storage", "The saved local connection is invalid.")
        }
        return value
    }
}
