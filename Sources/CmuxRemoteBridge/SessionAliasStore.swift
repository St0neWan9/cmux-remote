import Foundation

/// Maps a phone conversation onto the live Agent session a desktop resume produced: `claude --resume`
/// forks a new session id, so the conversation keeps its identity while the Agent session behind it
/// changes. Only session ids, surface ids and timestamps are persisted, never conversation content.
public actor SessionAliasStore {
    private struct Entry: Codable {
        var surface: String
        var at: Date
    }
    private struct Map: Codable {
        var targets: [String: Entry] = [:]
        var aliases: [String: String] = [:]
    }
    private var map = Map()
    private let url: URL?
    /// A resume that produced no Agent session within this window never will; the phone can retry it.
    private static let targetLifetime: TimeInterval = 15 * 60

    public init(directory: URL?) {
        guard let directory else { url = nil; return }
        let path = directory.appendingPathComponent("session-aliases.json")
        if let bytes = try? Data(contentsOf: path), bytes.count <= 65_536,
           let stored = try? JSONDecoder().decode(Map.self, from: bytes) {
            map = stored
        }
        url = path
    }

    /// The surface a desktop resume opened for this conversation and still waits to see an Agent on.
    public func target(conversationID: String) -> String? {
        guard let entry = map.targets[conversationID], entry.at.timeIntervalSinceNow > -Self.targetLifetime else {
            if map.targets[conversationID] != nil { Task { await self.setTarget(nil, conversationID: conversationID) } }
            return nil
        }
        return entry.surface
    }

    public func setTarget(_ surface: String?, conversationID: String) {
        if let surface { map.targets[conversationID] = Entry(surface: surface, at: Date()) } else { map.targets[conversationID] = nil }
        save()
    }

    /// The live Agent session behind a conversation, or nil when the conversation is its own session.
    public func liveSessionID(conversationID: String) -> String? { map.aliases[conversationID] }

    /// Every conversation this store tracks, whether aliased or still waiting for its resume.
    public func trackedConversationIDs() -> [String] { Array(Set(map.aliases.keys).union(map.targets.keys)) }

    /// The conversation-to-live-session pairs, for folding the inventory.
    public func aliasPairs() -> [(conversationID: String, sessionID: String)] {
        map.aliases.map { (conversationID: $0.key, sessionID: $0.value) }
    }

    /// The conversation a live session answers for, so the resumed row folds into the original.
    public func conversationID(sessionID: String) -> String? {
        map.aliases.first { $0.value == sessionID }?.key
    }

    public func setAlias(conversationID: String, sessionID: String) {
        map.aliases[conversationID] = sessionID
        map.targets[conversationID] = nil
        save()
    }

    private func save() {
        guard let url else { return }
        let current = map
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let bytes = try? JSONEncoder().encode(current) {
            try? bytes.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}
