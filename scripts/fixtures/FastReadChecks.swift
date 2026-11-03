import Foundation
import CmuxRemoteCore
import CmuxRemoteClient
import CmuxAgentChat

/// Refreshing a conversation over the relay: reads go out together, and a refresh soon after a full read
/// fetches only the newest messages.
struct FastReadChecks {
    @MainActor final class Calls { var full = 0; var tail: [Int] = []; var tailPage: [ChatMessage] = [] }

    @MainActor static func run() async -> (count: Int, failures: [String]) {
        var failures: [String] = []; var count = 0
        func check(_ condition: Bool, _ description: String) { count += 1; if !condition { failures.append(description) } }
        let client = RemoteClient(pairing: try! PairingConfiguration(host: "localhost", port: 1, token: String(repeating: "0", count: 32), certificateSHA256: String(repeating: "0", count: 64)))
        let descriptor = SessionDescriptor(id: "fast", agent: "claude", title: "fast", cwd: nil, state: "working")
        func message(_ seq: Int) -> ChatMessage {
            ChatMessage(id: "m\(seq)", seq: seq, role: .agent, timestamp: .distantPast, kind: .prose(ChatProse(text: "m\(seq)")))
        }
        let page = (1...100).map(message)

        // Three reads that each take 200 ms finish in about 200 ms, not 600.
        let slow = ConversationModel(session: descriptor, client: client, loadRecovery: { nil }, saveRecovery: { _ in },
            readSessions: { try? await Task.sleep(for: .milliseconds(200)); return [descriptor] },
            readHistory: { _ in try? await Task.sleep(for: .milliseconds(200)); return ConversationSnapshot(messages: page, hasMore: true, generation: "g", clipped: false) },
            readPreview: { try? await Task.sleep(for: .milliseconds(200)); return PreviewSnapshot(text: nil, available: false) })
        let started = ContinuousClock.now
        await slow.refresh()
        let took = ContinuousClock.now - started
        check(took < .milliseconds(450), "The three reads of a refresh ran one after another (\(took))")

        // A refresh soon after a full read asks for the newest messages only, and joins them to the page.
        let calls = Calls()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ConversationCache(directory: root)
        let model = ConversationModel(session: descriptor, client: client, loadRecovery: { nil }, saveRecovery: { _ in },
            readSessions: { [descriptor] },
            readHistory: { _ in await MainActor.run { calls.full += 1 }; return ConversationSnapshot(messages: page, hasMore: true, generation: "g", clipped: false) },
            readPreview: { PreviewSnapshot(text: nil, available: false) },
            readTail: { limit in
                let tail = await MainActor.run { calls.tail.append(limit); return calls.tailPage }
                return ConversationSnapshot(messages: tail, hasMore: true, generation: "g", clipped: false)
            }, cache: cache)
        await model.refresh()
        check(calls.full == 1 && calls.tail.isEmpty, "The first read was not the full newest page")
        calls.tailPage = (72...101).map(message)
        await model.refresh()
        check(calls.tail == [30] && calls.full == 1, "A refresh soon after a full read did not read only the newest messages")
        check(model.messages.count == 101 && model.messages.last?.id == "m101", "The newest messages were not joined to the page")
        try? await Task.sleep(for: .milliseconds(100))
        let stored = await cache.load(scope: client.operationRecoveryScope, sessionID: descriptor.id)
        check(stored?.snapshot.messages.count == 100, "A tail read replaced the stored full page")

        // Newest messages that do not reach the page leave a gap; the full page is read instead.
        calls.tailPage = (150...179).map(message)
        await model.refresh()
        check(calls.full == 2, "A tail that left a gap was joined instead of reading the full page")
        return (count, failures)
    }
}
