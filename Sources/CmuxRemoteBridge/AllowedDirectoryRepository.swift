import Foundation
import Darwin
import CmuxRemoteCore

/// The owner's shared project folders, written only through the local owner channel.
/// They are offered to every workspace's new-session list; the workspace's own folders are unchanged.
public struct AllowedDirectoryRepository: Sendable {
    /// Enough for the folders one person works in; the launcher's root list is capped the same way.
    public static let limit = 32
    private let file: URL
    public init(directory: URL) { file = directory.appendingPathComponent("allowed-directories.json") }

    /// The stored folders, canonical and de-duplicated. A missing, foreign, malformed or oversized file
    /// reads as no folders, so a damaged file narrows the list rather than failing a request.
    public func load() -> [URL] {
        var info = stat()
        guard lstat(file.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_mode & 0o077 == 0, info.st_size > 0, info.st_size <= 65_536,
              let data = try? Data(contentsOf: file), let paths = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Self.canonical(paths)
    }

    /// Stores exactly what the owner selected; an unusable entry is refused rather than dropped silently.
    public func save(_ paths: [String]) throws {
        guard paths.count <= Self.limit else {
            throw BridgeError("invalid_input", "Choose at most \(Self.limit) folders.", status: 422)
        }
        let cleaned = try paths.map(Self.validated)
        let data = try JSONEncoder().encode(cleaned)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Staging plus rename, all opened with O_NOFOLLOW, so a link left in the state directory is never followed.
        let staging = file.deletingLastPathComponent().appendingPathComponent(".allowed-" + UUID().uuidString)
        let fd = Darwin.open(staging.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw storage() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: staging) }
        do { try handle.write(contentsOf: data); try handle.synchronize() } catch { throw storage() }
        guard rename(staging.path, file.path) == 0 else { throw storage() }
    }

    /// Absolute, canonical and free of traversal, which is all the launcher needs to treat one as a root.
    /// A leading `~` is expanded, since that is the form the owner's settings page reads back and sends.
    private static func validated(_ path: String) throws -> String {
        var cleaned = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if cleaned == "~" { cleaned = home }
        else if cleaned.hasPrefix("~/") { cleaned = home + cleaned.dropFirst(1) }
        let components = cleaned.split(separator: "/", omittingEmptySubsequences: true)
        guard cleaned.hasPrefix("/"), cleaned.utf8.count <= 4096, !cleaned.contains("\u{0}"),
              !components.contains(where: { $0 == "." || $0 == ".." }) else {
            throw BridgeError("invalid_input", "Choose folders by their absolute path.", status: 422)
        }
        return URL(fileURLWithPath: cleaned).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func canonical(_ paths: [String]) -> [URL] {
        var found: [URL] = []
        for path in paths {
            guard let cleaned = try? validated(path) else { continue }
            let url = URL(fileURLWithPath: cleaned)
            guard !found.contains(where: { $0.path == url.path }) else { continue }
            found.append(url)
            if found.count == limit { break }
        }
        return found
    }

    private func storage() -> BridgeError { BridgeError("state_unavailable", "Could not save the allowed folders.", status: 503) }
}
