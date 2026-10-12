import Foundation
import CryptoKit
import CmuxRemoteCore

/// Owner-only mutation intents and receipts. Prompts, input bytes and credentials are never stored.
public actor MutationLedger {
    struct Entry: Codable, Sendable {
        let key: String
        let operationID: UUID
        let fingerprint: String
        let workspaceID: String
        let capability: ClientCapability
        var receipt: MutationReceipt?
    }
    private let directory: URL?
    private let capacity: Int
    private var loaded = false
    private var entries: [String: Entry] = [:]
    public init(directory: URL? = nil, capacity: Int = 16_384) {
        self.directory = directory; self.capacity = min(max(1, capacity), 16_384)
    }
    static func fingerprint(action: String, resource: String, payload: JSONValue) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(JSONValue.object(["action": .string(action), "resource": .string(resource), "payload": payload]))
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    func prior(clientID: String, operationID: UUID, fingerprint: String) throws -> Entry? {
        try load()
        let key = try key(clientID, operationID)
        guard let entry = entries[key] else { return nil }
        guard entry.fingerprint == fingerprint else { throw BridgeError("operation_conflict", "This operation identity was used for different input.", status: 409) }
        return entry
    }
    /// Commits the intent before any backend mutation; one actor serializes all writers.
    func begin(clientID: String, operationID: UUID, fingerprint: String, workspaceID: String, capability: ClientCapability) throws -> Entry? {
        if let existing = try prior(clientID: clientID, operationID: operationID, fingerprint: fingerprint) { return existing }
        guard fingerprint.count == 64, fingerprint.allSatisfy({ $0.isASCII && $0.isHexDigit }), !workspaceID.isEmpty, workspaceID.utf8.count <= 256,
              [.conversationControl, .feedReply, .terminalInput].contains(capability) else { throw BridgeError("invalid_input", "Invalid mutation intent.") }
        guard entries.count < capacity else { throw BridgeError("receipt_capacity", "The durable receipt store is full; this operation was not executed.", status: 503) }
        let entry = Entry(key: try key(clientID, operationID), operationID: operationID, fingerprint: fingerprint, workspaceID: workspaceID.lowercased(), capability: capability, receipt: nil)
        try persist(entry); entries[entry.key] = entry
        return nil
    }
    /// A lost completion write leaves the durable intent unknown rather than executable again.
    func complete(clientID: String, operationID: UUID) throws -> MutationReceipt {
        try load(); let key = try key(clientID, operationID)
        guard var entry = entries[key] else { throw BridgeError("outcome_unknown", "No durable intent exists for this mutation.", status: 409) }
        if let receipt = entry.receipt { return receipt }
        let receipt = MutationReceipt(operationID: operationID, accepted: true)
        entry.receipt = receipt
        do { try persist(entry) } catch { throw BridgeError("outcome_unknown", "The backend replied but its receipt could not be saved; inspect the task.", status: 409) }
        entries[key] = entry; return receipt
    }
    private func key(_ clientID: String, _ operation: UUID) throws -> String {
        guard !clientID.isEmpty, clientID.utf8.count <= 128, clientID.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_" )).contains($0) }) else { throw BridgeError("invalid_input", "Invalid mutation owner.") }
        return clientID + ":" + operation.uuidString
    }
    private func load() throws {
        guard !loaded else { return }
        guard let directory else { loaded = true; return }
        let path = directory.appendingPathComponent("mutation-receipts.ndjson")
        guard FileManager.default.fileExists(atPath: path.path) else { loaded = true; return }
        guard try path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true,
              try path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw BridgeError("invalid_state", "Mutation state must be a regular owner file.") }
        let bytes = try Data(contentsOf: path)
        guard bytes.count <= 16_777_216, bytes.isEmpty || bytes.last == 10 else { throw BridgeError("invalid_state", "Mutation receipt state exceeds its limit.") }
        let lines = bytes.split(separator: 10)
        guard lines.count <= capacity * 2 else { throw BridgeError("invalid_state", "Mutation journal exceeds its record limit.") }
        var next: [String: Entry] = [:]
        for line in lines {
            let entry = try JSONDecoder().decode(Entry.self, from: Data(line))
            guard entry.key.hasSuffix(":" + entry.operationID.uuidString), entry.key.utf8.count <= 166,
                  entry.fingerprint.count == 64, entry.fingerprint.allSatisfy({ $0.isASCII && $0.isHexDigit }),
                  !entry.workspaceID.isEmpty, entry.workspaceID.utf8.count <= 256,
                  [.conversationControl, .feedReply, .terminalInput].contains(entry.capability),
                  entry.receipt.map({ $0.operationID == entry.operationID && $0.accepted }) ?? true else { throw BridgeError("invalid_state", "Invalid durable mutation receipt.") }
            if let old = next[entry.key] {
                guard old.fingerprint == entry.fingerprint, old.workspaceID == entry.workspaceID, old.capability == entry.capability,
                      old.receipt == nil else { throw BridgeError("invalid_state", "Conflicting durable mutation journal.") }
            }
            next[entry.key] = entry
        }
        guard next.count <= capacity else { throw BridgeError("invalid_state", "Mutation journal exceeds its intent limit.") }
        entries = next; loaded = true
    }
    private func persist(_ entry: Entry) throws {
        guard let directory else { return }
        var bytes = try JSONEncoder().encode(entry); bytes.append(10)
        do { try DurablePrivateFile.append(bytes, directory: directory, name: "mutation-receipts.ndjson") }
        catch {
            loaded = false
            if let failure = error as? BridgeError { throw failure }
            throw BridgeError("receipt_storage", "Durable mutation state could not be saved.", status: 503)
        }
    }
}
