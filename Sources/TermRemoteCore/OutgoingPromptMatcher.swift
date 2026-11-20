import Foundation
import CmuxAgentChat

/// Drops each outgoing prompt once a user message recorded after it carries its text.
public struct OutgoingPromptMatcher: Sendable {
    public init() {}
    /// The prompts still missing from `messages`, in send order. One transcript message accounts for at most one prompt.
    public func pending(_ prompts: [OutgoingPrompt], messages: [ChatMessage], generation: String?) -> [OutgoingPrompt] {
        guard !prompts.isEmpty else { return [] }
        let users = messages.compactMap { message -> (message: ChatMessage, text: String)? in
            guard message.role == .user, case .prose(let value) = message.kind else { return nil }
            return (message, normalized(value.text))
        }
        var consumed = Set<String>()
        var matched = Set<UUID>()
        // Text first, so two quick prompts each find their own message whatever order the agent records them in.
        for prompt in prompts {
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
