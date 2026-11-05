import Foundation

/// The working directory each session's transcript recorded, read once per session.
///
/// A phone list read asks it for every conversation whose terminal is gone, and reading it means opening the
/// transcript head and parsing it; a session writes that directory once and never changes it, so the answer is
/// kept for as long as the process lives.
final class TranscriptCwdMemo: @unchecked Sendable {
    private let lock = NSLock()
    private var directories: [String: String] = [:]
    private let capacity = 4_096

    func recordedCwd(_ key: String) -> String? { lock.lock(); defer { lock.unlock() }; return directories[key] }
    func remember(_ cwd: String, for key: String) {
        lock.lock(); defer { lock.unlock() }
        if directories.count >= capacity { directories.removeAll(keepingCapacity: true) }
        directories[key] = cwd
    }
}
