import SwiftUI
import CmuxRemoteCore
import CmuxAgentChat

/// A conversation's rows with the timeline's own rhythm: consecutive tool operations touch, and anything else
/// gets a small gap. Every place that lists messages — the timeline's groups, a group's own page, and a
/// background Agent's conversation — uses this, so the spacing cannot drift between them.
struct MessageRows: View {
    let messages: [ChatMessage]
    var projectRoot: String?
    var openFile: ((String) -> Void)?
    var images: [ConversationImageReference] = []
    var openImage: ((ConversationImageReference) -> Void)?
    var openDetail: ((String, String) -> Void)?
    /// A long list builds its rows as they scroll into view; a small one does not need to.
    var lazy = false
    var body: some View {
        if lazy {
            LazyVStack(alignment: .leading, spacing: 0) { rows }
        } else {
            VStack(alignment: .leading, spacing: 0) { rows }
        }
    }
    @ViewBuilder private var rows: some View {
        // Rows are identified by the message, never by its position: a refresh that prepends earlier messages
        // would otherwise re-identify every row below it, and an index captured by a lazily built row can point
        // past the end of the array the next refresh installs.
        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
            let row = MessageRow(message: message, projectRoot: projectRoot, openFile: openFile, images: images,
                                 openImage: openImage, openDetail: openDetail)
            let previousIsOperation = index > 0 && MessageRow(message: messages[index - 1]).isOperation
            row.padding(.top, index == 0 || (row.isOperation && previousIsOperation) ? 0 : 8)
        }
    }
}
