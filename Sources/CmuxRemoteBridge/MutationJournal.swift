import Foundation
import CryptoKit
import Darwin
import CmuxRemoteCore

/// A single SessionService owns this journal under the host's BridgeRunLease.
/// Persisted records contain digests and scope metadata, never prompt or image content.
public struct MutationJournal: Sendable {
    struct Entry: Codable, Sendable {
        enum State: String, Codable, Sendable { case prepared, accepted, uncertain }
        let id: UUID
        let digest: String
        let principal: String
        let resource: String
        let workspace: String
        let capability: ClientCapability
        var state: State
        var updatedAt: Date
        var status: OperationStatus {
            OperationStatus(operationID: id, state: state == .accepted ? .accepted : .outcomeUnknown, recordedAt: updatedAt)
        }
    }
    private let file: URL?
    private let capacity: Int
    private var entries: [String: Entry]
    private static let maximumBytes = 4_194_304

    /// An ephemeral journal for explicitly isolated tests/demos.
    public init() { file = nil; capacity = 4096; entries = [:] }

    /// Restores receipts and unresolved preparations from owner-only host state.
    /// Corruption or an unsafe state file prevents serving new mutations.
    public init(file: URL, capacity: Int = 4096) throws {
        guard (1...4096).contains(capacity) else { throw Self.unavailable() }
        self.file = file; self.capacity = capacity
        if FileManager.default.fileExists(atPath: file.path) {
            try Self.validateFile(file)
            let data = try Data(contentsOf: file)
            guard data.count <= Self.maximumBytes,
                  let loaded = try? JSONDecoder().decode([String: Entry].self, from: data), loaded.count <= capacity,
                  loaded.allSatisfy({ key, entry in
                      key == entry.id.uuidString && entry.digest.count == 64 && entry.digest.allSatisfy({ $0.isHexDigit }) &&
                      !entry.principal.isEmpty && entry.principal.utf8.count <= 128 &&
                      !entry.resource.isEmpty && entry.resource.utf8.count <= 512 &&
                      !entry.workspace.isEmpty && entry.workspace.utf8.count <= 128 && entry.updatedAt.timeIntervalSince1970.isFinite
                  }) else { throw Self.unavailable() }
            entries = loaded
        } else { entries = [:] }
    }

    func entry(id: UUID, principal: String) throws -> Entry? {
        guard let entry = entries[id.uuidString] else { return nil }
        guard entry.principal == principal else { throw BridgeError("scope_denied", "This operation belongs to another device.", status: 403) }
        return entry
    }
    func existing(id: UUID, signature: String, principal: String) throws -> Entry? {
        guard let entry = try entry(id: id, principal: principal) else { return nil }
        guard entry.digest == Self.digest(signature) else { throw BridgeError("operation_conflict", "This operation identity was already used for different input.", status: 409) }
        return entry
    }
    mutating func begin(id: UUID, signature: String, principal: String, resource: String, workspace: String, capability: ClientCapability) throws {
        guard entries[id.uuidString] == nil else { throw BridgeError("operation_conflict", "This operation is already in progress.", status: 409) }
        guard entries.count < capacity else { throw BridgeError("receipt_capacity", "The operation journal is full. Ask the host owner to inspect it.", status: 503) }
        guard !principal.isEmpty, principal.utf8.count <= 128, !resource.isEmpty, resource.utf8.count <= 512,
              !workspace.isEmpty, workspace.utf8.count <= 128 else { throw Self.unavailable() }
        var updated = entries
        updated[id.uuidString] = Entry(id: id, digest: Self.digest(signature), principal: principal, resource: resource,
                                      workspace: workspace, capability: capability, state: .prepared, updatedAt: Date())
        try persist(updated); entries = updated
    }
    mutating func complete(id: UUID) throws -> MutationReceipt {
        guard var entry = entries[id.uuidString] else { throw Self.unavailable() }
        entry.state = .accepted; entry.updatedAt = Date()
        var updated = entries; updated[id.uuidString] = entry
        try persist(updated); entries = updated
        return MutationReceipt(operationID: id, accepted: true)
    }
    mutating func uncertain(id: UUID) {
        guard var entry = entries[id.uuidString] else { return }
        entry.state = .uncertain; entry.updatedAt = Date()
        var updated = entries; updated[id.uuidString] = entry
        // A persisted prepared record is already fail-closed if this update fails.
        try? persist(updated); entries = updated
    }
    private func persist(_ updated: [String: Entry]) throws {
        guard let file else { return }
        do {
            let parent = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let directory = try FileManager.default.attributesOfItem(atPath: parent.path)
            guard directory[.type] as? FileAttributeType == .typeDirectory,
                  (directory[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
                  ((directory[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0 else { throw Self.unavailable() }
            if FileManager.default.fileExists(atPath: file.path) { try Self.validateFile(file) }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(updated)
            guard data.count <= Self.maximumBytes else { throw Self.unavailable() }
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
            try handle.synchronize()
            // Flush the atomic rename as well as its file contents before dispatch.
            let fd = open(parent.path, O_RDONLY | O_DIRECTORY)
            guard fd >= 0 else { throw Self.unavailable() }; defer { close(fd) }
            guard fsync(fd) == 0 else { throw Self.unavailable() }
        } catch { throw Self.unavailable() }
    }
    private static func validateFile(_ file: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0,
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= maximumBytes else { throw unavailable() }
    }
    private static func digest(_ signature: String) -> String { SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined() }
    private static func unavailable() -> BridgeError { BridgeError("journal_unavailable", "The host cannot safely record this operation. Ask the owner to inspect private state.", status: 503) }
}
