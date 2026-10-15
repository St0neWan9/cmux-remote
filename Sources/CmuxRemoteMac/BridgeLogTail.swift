import Foundation
import CmuxRemoteCore

/// Reads the newest complete lines of the Bridge's `bridge.log`, continuing into `bridge.log.1` after a rotation.
///
/// Only a bounded tail is read, never a whole file: `byteLimit` covers both files together. A line cut by that
/// bound and an unfinished line the Bridge is still writing are left out rather than shown in part.
public struct BridgeLogTail: Sendable {
    public let lineLimit: Int
    public let byteLimit: Int
    public init(lineLimit: Int = 2_000, byteLimit: Int = 2 * 1024 * 1024) {
        self.lineLimit = max(1, lineLimit); self.byteLimit = max(1, byteLimit)
    }
    public static func file(in directory: URL) -> URL { directory.appendingPathComponent("bridge.log") }
    /// Oldest first, at most `lineLimit` lines. `nil` when neither file exists: the Bridge has not run with this
    /// state directory, or it is a version that does not write a log file.
    public func read(directory: URL) throws -> [BridgeLogLine]? {
        let current = Self.file(in: directory), previous = current.appendingPathExtension("1")
        // Opening the rotated file first means a rotation between the two opens can drop lines from one read,
        // never repeat them; the next read shows them.
        let older = try open(previous)
        defer { try? older?.close() }
        let newer = try open(current)
        defer { try? newer?.close() }
        guard older != nil || newer != nil else { return nil }
        var texts: [String] = [], budget = byteLimit
        if let newer { let chunk = try tail(newer, budget: budget); texts = chunk.lines; budget -= chunk.bytes }
        if texts.count < lineLimit, budget > 0, let older { texts = try tail(older, budget: budget).lines + texts }
        return BridgeLogLine.parse(Array(texts.suffix(lineLimit)))
    }
    private func open(_ url: URL) throws -> FileHandle? {
        do { return try FileHandle(forReadingFrom: url) } catch {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            throw BridgeError("log_unreadable", "The Bridge log cannot be read.")
        }
    }
    /// The complete lines in the last `budget` bytes, and how many bytes of the budget they used.
    private func tail(_ handle: FileHandle, budget: Int) throws -> (lines: [String], bytes: Int) {
        do {
            let size = try handle.seekToEnd()
            let start = size > UInt64(budget) ? size - UInt64(budget) : 0
            // One byte before the bound shows whether the first line in range starts there or is cut.
            let from = start > 0 ? start - 1 : 0
            try handle.seek(toOffset: from)
            let data = try handle.read(upToCount: Int(size - from)) ?? Data()
            var first = data.startIndex, end = data.startIndex
            if start > 0 { first = data.firstIndex(of: 0x0A).map { data.index(after: $0) } ?? data.endIndex }
            // Only a line ended by a newline is complete; a trailing fragment appears on a later read.
            if let last = data.lastIndex(of: 0x0A), last >= first { end = last } else { end = first }
            let lines: [String] = data[first..<end].split(separator: 0x0A, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
            return (lines, Int(size - start))
        } catch { throw BridgeError("log_unreadable", "The Bridge log cannot be read.") }
    }
}
