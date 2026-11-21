import Foundation
import CmuxAgentChat

/// Drops each outgoing prompt once a user message recorded after it carries its text.
public struct OutgoingPromptMatcher: Sendable {
    public init() {}
    /// The prompts still missing from `messages` and not yet tracked in `queuedPrompts`, in send order.
    /// One transcript message accounts for at most one prompt.
    public func pending(
        _ prompts: [OutgoingPrompt],
        messages: [ChatMessage],
        generation: String?,
        queuedPrompts: [QueuedPrompt] = []
    ) -> [OutgoingPrompt] {
        guard !prompts.isEmpty else { return [] }
        let users = messages.compactMap { message -> (message: ChatMessage, text: String)? in
            guard message.role == .user, case .prose(let value) = message.kind else { return nil }
            return (message, normalized(value.text))
        }
        let queuedIDs = Set(queuedPrompts.map(\.id))
        let queuedTexts = queuedPrompts.map { normalized($0.text) }.filter { !$0.isEmpty }
        var consumed = Set<String>()
        var matched = Set<UUID>()
        // Prompts confirmed in the Bridge's synced queue move to the queue bar immediately instead of staying stuck in the timeline.
        for prompt in prompts {
            if queuedIDs.contains(prompt.id.uuidString) {
                matched.insert(prompt.id)
                continue
            }
            let text = normalized(prompt.text)
            if !text.isEmpty, queuedTexts.contains(where: { $0 == text || $0.hasPrefix(text) || text.hasPrefix($0) }) {
                matched.insert(prompt.id)
            }
        }
        // Text first, so two quick prompts each find their own message whatever order the agent records them in.
        for prompt in prompts where !matched.contains(prompt.id) {
            let text = normalized(prompt.text)
            guard !text.isEmpty, let hit = users.first(where: { !consumed.contains($0.message.id) && recordedAfter(prompt, $0.message, generation: generation) && $0.text.contains(text) }) else { continue }
            consumed.insert(hit.message.id); matched.insert(prompt.id)
        }
        // An agent may rewrite a prompt (image placeholders, a paste summary); a new user message in the same history is then
        // still this phone's prompt. A changed history is only trusted on text, since its old messages look new.
        for prompt in prompts where !matched.contains(prompt.id) && prompt.generation == generation {
            guard let hit = users.first(where: { !consumed.contains($0.message.id) && recordedAfter(prompt, $0.message, generation: generation) }) else { continue }
            consumed.insert(hit.message.id); matched.insert(prompt.id)
        }
        return prompts.filter { !matched.contains($0.id) }
    }
    private func recordedAfter(_ prompt: OutgoingPrompt, _ message: ChatMessage, generation: String?) -> Bool {
        guard !prompt.knownUserIDs.contains(message.id) else { return false }
        guard prompt.generation == generation, let afterSeq = prompt.afterSeq else { return true }
        return message.seq > afterSeq
    }
    private func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
