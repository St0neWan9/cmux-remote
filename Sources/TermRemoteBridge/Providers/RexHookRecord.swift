import Foundation
import CryptoKit
import TermRemoteCore

/// One Agent hook event recorded inside a Rex terminal. It carries ids only;
/// prompt and transcript bodies never enter the spool.
public struct RexHookRecord: Codable, Sendable, Equatable {
    public let agent: String
    public let event: String
    public let sessionID: String
    public let transcript: String
    public let cwd: String
    public let rexSession: String
    public let rexBlock: String
    public let rexServer: String?
    public let recordedAt: Date
    public init(agent: String, event: String, sessionID: String, transcript: String, cwd: String,
                rexSession: String, rexBlock: String, rexServer: String?, recordedAt: Date = Date()) {
        self.agent = agent; self.event = event; self.sessionID = sessionID; self.transcript = transcript
        self.cwd = cwd; self.rexSession = rexSession; self.rexBlock = rexBlock
        self.rexServer = rexServer; self.recordedAt = recordedAt
    }
}

/// Owner-only hook spool. A hook command writes one bounded file per Rex block;
/// the Bridge reads them without executing anything.
public struct RexHookSpool: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func records() -> [RexHookRecord] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        var result: [RexHookRecord] = []
        for name in names.sorted().prefix(512) where name.hasSuffix(".json") {
            let url = directory.appendingPathComponent(name)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size <= 65_536,
                  let data = try? Data(contentsOf: url), data.count <= 65_536,
                  let record = try? JSONDecoder().decode(RexHookRecord.self, from: data),
                  ["claude", "codex", "antigravity"].contains(record.agent),
                  record.rexBlock.hasPrefix("block:"), record.sessionID.utf8.count <= 256,
                  record.transcript.utf8.count <= 4_096, record.cwd.hasPrefix("/") else { continue }
            result.append(record)
        }
        return result
    }
}

/// Writes one spool record atomically with owner-only permissions.
public enum RexHookWriter {
    public static func write(_ record: RexHookRecord, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let key = record.agent + "|" + record.rexBlock
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
        let data = try JSONEncoder().encode(record)
        guard data.count <= 65_536 else { throw BridgeError("too_large", "The hook record is too large.", status: 413) }
        let target = directory.appendingPathComponent(name)
        let temporary = directory.appendingPathComponent("." + UUID().uuidString + ".tmp")
        try data.write(to: temporary, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary,
                                                  backupItemName: nil, options: [.usingNewMetadataOnly])
    }
}
