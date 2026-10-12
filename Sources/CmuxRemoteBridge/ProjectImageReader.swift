import Darwin
import Foundation
import CmuxRemoteCore

/// Walks an authorized project using directory descriptors; symlink replacements fail closed.
struct ProjectImageReader {
    let policy: ProjectFilePolicy
    func read(root: String, referencedPath: String) throws -> Data {
        let base = try policy.projectRoot(root)
        let relative: String
        if referencedPath.hasPrefix("/") {
            guard referencedPath.hasPrefix(base.path + "/") else { throw denied() }
            relative = String(referencedPath.dropFirst(base.path.count + 1))
        } else { relative = referencedPath }
        _ = try policy.resolve(root: base.path, relativePath: relative)
        let parts = relative.split(separator: "/").map(String.init)
        guard !parts.isEmpty, parts.count <= 64, ["png", "jpg", "jpeg"].contains(URL(fileURLWithPath: relative).pathExtension.lowercased()) else { throw denied() }
        var directory = open(base.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw denied() }
        defer { close(directory) }
        for component in parts.dropLast() {
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw denied() }
            close(directory); directory = next
        }
        let file = openat(directory, parts.last!, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard file >= 0 else { throw denied() }
        defer { close(file) }
        var before = stat()
        guard fstat(file, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size > 0, before.st_size <= 1_048_576 else { throw denied() }
        var result = Data(); var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            try Task.checkCancellation()
            let count = Darwin.read(file, &buffer, buffer.count)
            guard count >= 0 else { throw denied() }
            if count == 0 { break }
            guard result.count + count <= 1_048_576 else { throw denied() }
            result.append(contentsOf: buffer.prefix(count))
        }
        var after = stat()
        guard fstat(file, &after) == 0, before.st_size == after.st_size, result.count == Int(after.st_size), before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw denied() }
        return result
    }
    private func denied() -> BridgeError { BridgeError("file_forbidden", "This image cannot be shared from the approved project.", status: 403) }
}
