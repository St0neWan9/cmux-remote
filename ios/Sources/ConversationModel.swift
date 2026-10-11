import Foundation
import Observation
import CmuxRemoteCore
import CmuxRemoteClient
import CmuxAgentChat

@MainActor @Observable
final class ConversationModel {
    var session: SessionDescriptor
    let client: RemoteClient
    var canSend: Bool { session.writable && client.canControlConversations }
    var messages: [ChatMessage] = []
    var timelineItems: [ConversationTimelineItem] = []
    var jumpToLatest = 0
    var working: Bool { session.state.hasPrefix("working") }
    var latestMessageText: String? {
        guard let message = messages.last else { return nil }
        if case .prose(let value) = message.kind { return value.text }; return nil
    }
    var preview: String?
    var error: String?
    var draft = ""
    var busy = false
    var hasMore = false
    private var generation: String?
    init(session: SessionDescriptor, client: RemoteClient) { self.session = session; self.client = client }
    func updateSession(_ current: SessionDescriptor) {
        session = current
    }
    func markInterrupted() { session.state = "idle" }
    func refresh() async {
        do {
            let descriptors = try await client.get("/v1/sessions", as: [SessionDescriptor].self)
            guard let current = descriptors.first(where: { $0.id == session.id }) else { throw BridgeError("read_only", "The cmux session is no longer available.", status: 404) }
            updateSession(current)
            let history = try await client.get("/v1/sessions/\(session.id)/history", as: ConversationSnapshot.self)
            let live = try? await client.get("/v1/sessions/\(session.id)/preview", as: PreviewSnapshot.self)
            if generation == history.generation {
                var next = messages
                for message in history.messages {
                    if let index = next.firstIndex(where: { $0.id == message.id }) { next[index] = message }
                    else { next.append(message) }
                }
                messages = next.sorted { $0.seq < $1.seq }
            } else { messages = history.messages; generation = history.generation; hasMore = history.hasMore }
            timelineItems = ConversationTimeline().items(from: messages)
            let committed = messages.reversed().compactMap { message -> String? in
                if message.role == .agent, case .prose(let value) = message.kind { return value.text }; return nil
            }.first
            preview = live?.text == committed ? nil : live?.text; error = nil
        } catch { if !Task.isCancelled { self.error = ErrorPresentation().message(error) } }
    }
    func older() async {
        guard let seq = messages.first?.seq else { return }
        do {
            let page = try await client.get("/v1/sessions/\(session.id)/history", query: ["before_seq": String(seq)], as: ConversationSnapshot.self)
            guard page.generation == generation else { await refresh(); return }
            let existing = Set(messages.map(\.id)); messages.insert(contentsOf: page.messages.filter { !existing.contains($0.id) }, at: 0); timelineItems = ConversationTimeline().items(from: messages); hasMore = page.hasMore
        } catch { self.error = ErrorPresentation().message(error) }
    }
    func send() async {
        guard !busy, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true; defer { busy = false }
        let input = draft
        do {
            _ = try await client.post("/v1/sessions/\(session.id)/send", body: SendRequest(text: input), as: MutationReceipt.self)
            draft = ""; await refresh(); jumpToLatest += 1
        } catch { self.error = ErrorPresentation().message(error) }
    }
    func interrupt() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { _ = try await client.post("/v1/sessions/\(session.id)/interrupt", body: InterruptRequest(), as: MutationReceipt.self); markInterrupted(); await refresh() }
        catch { self.error = ErrorPresentation().message(error) }
    }
}
