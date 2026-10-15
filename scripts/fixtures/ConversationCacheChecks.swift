import Foundation
import CmuxRemoteCore
import CmuxRemoteClient
import CmuxAgentChat

/// A conversation read before is stored on the phone, so reopening one shows its content at once.
struct ConversationCacheChecks {
    @MainActor static func run() async -> (count: Int, failures: [String]) {
        var failures: [String] = []; var count = 0
        func check(_ condition: Bool, _ description: String) { count += 1; if !condition { failures.append(description) } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ConversationCache(directory: root)
        func message(_ id: String, _ seq: Int) -> ChatMessage {
            ChatMessage(id: id, seq: seq, role: .agent, timestamp: .distantPast, kind: .prose(ChatProse(text: id)))
        }
        func snapshot(_ generation: String, _ id: String) -> ConversationSnapshot {
            ConversationSnapshot(messages: [message(id, 1)], hasMore: false, generation: generation, clipped: false)
        }
        let entry = ConversationCache.Entry(snapshot: snapshot("g1", "first"), preview: PreviewSnapshot(text: "live tail", available: true), storedAt: Date())
        await cache.save(entry, scope: "mac-a", sessionID: "session-1")

        let restored = await cache.load(scope: "mac-a", sessionID: "session-1")
        check(restored?.snapshot.generation == "g1" && restored?.snapshot.messages.first?.id == "first", "A stored conversation was not read back")
        check(restored?.preview?.text == "live tail", "A stored conversation lost its live tail")
        check(await cache.load(scope: "mac-b", sessionID: "session-1") == nil, "One Mac's stored conversation was visible to another")
        check(await cache.load(scope: "mac-a", sessionID: "session-2") == nil, "One session's stored conversation was visible to another")
        check(await cache.load(scope: "mac-a", sessionID: "session-1") != nil, "Reading a stored conversation removed it")

        // A page too large to reopen instantly is not stored at all, so memory is never spent on it.
        let huge = ConversationCache.Entry(snapshot: ConversationSnapshot(messages: (0..<9_000).map { message("m\($0)-" + String(repeating: "x", count: 512), $0) }, hasMore: false, generation: "g-huge", clipped: false), preview: nil, storedAt: Date())
        await cache.save(huge, scope: "mac-a", sessionID: "huge")
        check(await cache.load(scope: "mac-a", sessionID: "huge") == nil, "An oversized conversation was stored")

        // The bound keeps the copies that were used most recently, not the ones written first.
        for index in 0..<30 {
            await cache.save(ConversationCache.Entry(snapshot: snapshot("g\(index)", "m\(index)"), preview: nil, storedAt: Date()), scope: "mac-a", sessionID: "burst-\(index)")
        }
        check(await cache.load(scope: "mac-a", sessionID: "burst-29") != nil, "The newest stored conversation was evicted")
        check(await cache.load(scope: "mac-a", sessionID: "burst-0") == nil, "Stored conversations grew without a bound")

        // Removing a Mac takes its conversations with it.
        await cache.remove(scope: "mac-a")
        check(await cache.load(scope: "mac-a", sessionID: "burst-29") == nil, "Removing a Mac left its conversations stored")

        // The model shows the stored copy, then the read that follows replaces it.
        let client = RemoteClient(pairing: try! PairingConfiguration(host: "localhost", port: 7740, token: String(repeating: "0", count: 32), certificateSHA256: String(repeating: "0", count: 64)))
        let descriptor = SessionDescriptor(id: "session-9", agent: "claude", title: "Stored", cwd: nil)
        let store = ConversationCache(directory: root)
        await store.save(ConversationCache.Entry(snapshot: snapshot("stored-generation", "stored"), preview: nil, storedAt: Date()), scope: client.operationRecoveryScope, sessionID: descriptor.id)
        let freshlyRead = snapshot("fresh-generation", "fresh")
        let model = ConversationModel(session: descriptor, client: client, loadRecovery: { nil }, saveRecovery: { _ in },
            readSessions: { [descriptor] }, readHistory: { _ in freshlyRead }, readPreview: { PreviewSnapshot(text: nil, available: false) }, cache: store)
        await model.restoreStored()
        check(model.messages.map(\.id) == ["stored"] && model.historyGeneration == "stored-generation", "Opening a conversation did not show what was read last")
        await model.refresh()
        check(model.messages.map(\.id) == ["fresh"] && model.historyGeneration == "fresh-generation", "The read that followed did not replace the stored copy")
        return (count, failures)
    }
}
