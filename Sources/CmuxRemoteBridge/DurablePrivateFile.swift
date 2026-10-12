import Foundation
import Darwin
import CmuxRemoteCore

/// Appends a bounded journal record, flushes its file and directory before backend execution.
struct DurablePrivateFile {
    static func append(_ data: Data, directory: URL, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue + data.count <= 16_777_216 else { throw BridgeError("receipt_capacity", "The durable receipt journal exceeds its size limit.", status: 503) }
        }
        let fd = Darwin.open(destination.path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw failure() }
        defer { Darwin.close(fd) }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw failure() }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw failure() }
        let parent = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw failure() }
        defer { Darwin.close(parent) }
        guard fsync(parent) == 0 else { throw failure() }
    }
    private static func failure() -> BridgeError { BridgeError("receipt_storage", "Durable mutation state could not be saved; no unrecorded mutation is retried.", status: 503) }
}
