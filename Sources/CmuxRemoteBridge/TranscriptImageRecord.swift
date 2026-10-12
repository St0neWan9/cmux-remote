import Foundation
import CmuxRemoteCore

/// Sources come only from a complete transcript; callers cannot supply a filesystem path.
struct TranscriptImageRecord: Sendable {
    enum Source: Sendable { case recorded(Data), projectPath(String) }
    let messageID: String
    let name: String
    let source: Source
    func reference(generation: String) -> ConversationImageReference {
        let crypto = IdentityCryptography()
        let content: String
        switch source { case .recorded(let data): content = crypto.digest(data); case .projectPath(let path): content = path }
        let id = crypto.digest((try? JSONEncoder().encode([generation, messageID, content])) ?? Data())
        return ConversationImageReference(id: id, messageID: messageID, generation: generation, name: name,
            requiresProjectRead: { if case .projectPath = source { return true }; return false }())
    }
}
