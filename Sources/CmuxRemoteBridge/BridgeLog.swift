import Foundation
import os

/// Connection events written to an owner-only file in the Bridge state directory, so they can be read with
/// `tail -f` while a phone is failing. The resident runs as a helper process, where info and debug unified-log
/// messages are not kept on disk. Lines never contain keys, tokens, grants or request bodies.
public final class BridgeLog: @unchecked Sendable {
    public static let shared = BridgeLog()
    public enum Level: String, Sendable { case debug, info, warning, error }
    /// The file is rotated to `bridge.log.1` past this size, so the log stays bounded.
    private let limit = 4 * 1024 * 1024
    private let lock = NSLock()
    private var file: URL?
    private var handle: FileHandle?
    private var size = 0
    private let formatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; value.timeZone = .current; return value
    }()
    /// Starts writing `bridge.log` in `directory`; until then events only reach the unified log.
    public func configure(directory: URL) {
        lock.withLock {
            try? handle?.close(); handle = nil
            file = directory.appendingPathComponent("bridge.log")
            open()
        }
    }
    public func debug(_ category: String, _ message: String) { write(.debug, category, message) }
    public func info(_ category: String, _ message: String) { write(.info, category, message) }
    public func warning(_ category: String, _ message: String) { write(.warning, category, message) }
    public func error(_ category: String, _ message: String) { write(.error, category, message) }
    private func write(_ level: Level, _ category: String, _ message: String) {
        let logger = Logger(subsystem: "cmux-remote.mac", category: category)
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        lock.withLock {
            guard handle != nil else { return }
            let line = Data((formatter.string(from: Date()) + " " + level.rawValue.uppercased() + " [" + category + "] " + message + "\n").utf8)
            if size + line.count > limit { rotate() }
            do { try handle?.write(contentsOf: line); size += line.count } catch { try? handle?.close(); handle = nil }
        }
    }
    /// Called with the lock held.
    private func open() {
        guard let file else { return }
        let manager = FileManager.default
        if !manager.fileExists(atPath: file.path) { manager.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        guard let opened = try? FileHandle(forWritingTo: file) else { return }
        size = Int((try? opened.seekToEnd()) ?? 0)
        handle = opened
    }
    /// Called with the lock held.
    private func rotate() {
        guard let file else { return }
        try? handle?.close(); handle = nil
        let previous = file.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: file, to: previous)
        open()
    }
}
