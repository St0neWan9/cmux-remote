import Foundation
import Darwin
import CryptoKit
import CmuxRemoteCore

/// Private bounded image storage for literal paths pasted into the already running local Agent.
public struct TuiAttachmentStore: Sendable {
    private let root: URL
    public init(directory: URL) { root = directory.appendingPathComponent("tui-images", isDirectory: true) }
    public func save(_ images: [JSONValue], conversation: String, operation: UUID, storageKey: String? = nil) throws -> [String] {
        guard images.count <= 4 else { throw invalid() }
        try ensure(root)
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        var total = 0, count = 0
        while let item = files?.nextObject() as? URL {
            count += 1; guard count <= 4096 else { throw BridgeError("too_large", "The private image store is full.", status: 413) }
            let values = try item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw invalid() }
            if values.isRegularFile == true { guard let size = values.fileSize, size <= 67_108_864 else { throw invalid() }; total += size; guard total <= 67_108_864 else { throw invalid() } }
        }
        let conversationDirectory = root.appendingPathComponent(digest(Data(conversation.utf8)), isDirectory: true)
        let key = storageKey ?? operation.uuidString.lowercased()
        guard key.count <= 64, key.allSatisfy({ $0.isASCII && ($0.isHexDigit || $0 == "-") }) else { throw invalid() }
        let operationDirectory = conversationDirectory.appendingPathComponent(key, isDirectory: true)
        try ensure(conversationDirectory); try ensure(operationDirectory)
        var paths: [String] = [], incoming = 0
        for (index, image) in images.enumerated() {
            guard let encoded = image["data_b64"].string, let data = Data(base64Encoded: encoded), data.count <= 524_288,
                  let format = image["format"].string, ["png", "jpeg"].contains(format) else { throw invalid() }
            _ = try ChatImagePolicy().attachments([ChatImagePayload(fileName: "attachment." + format, format: format, data: data)])
            incoming += data.count
            guard incoming <= 655_360, total + incoming <= 67_108_864 else { throw BridgeError("too_large", "The private image store exceeds its byte limit.", status: 413) }
            let file = operationDirectory.appendingPathComponent(String(index) + "." + format)
            let fd = Darwin.open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            if fd >= 0 {
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
                try handle.write(contentsOf: data); try handle.synchronize()
            } else if errno == EEXIST {
                guard try read(file) == data else { throw invalid() }
            } else { throw invalid() }
            // Same literal escaping used by terminal file paste; never evaluated as a shell command here.
            paths.append("'" + file.path.replacingOccurrences(of: "'", with: "'\\''") + "'")
        }
        return paths
    }
    public func image(conversation: String, path: String) throws -> Data? {
        let allowed = root.appendingPathComponent(digest(Data(conversation.utf8)), isDirectory: true).path + "/"
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path.hasPrefix(allowed), url.resolvingSymlinksInPath().path == url.path else { return nil }
        return try read(url)
    }
    private func read(_ file: URL) throws -> Data {
        let fd = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC); guard fd >= 0 else { throw invalid() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0, info.st_size <= 524_288 else { throw invalid() }
        return try handle.readToEnd() ?? Data()
    }
    private func ensure(_ directory: URL) throws {
        if !FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o077 == 0 else { throw invalid() }
    }
    private func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    private func invalid() -> BridgeError { BridgeError("invalid_image", "The private attachment path or bytes are invalid.", status: 422) }
}
