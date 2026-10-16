import SwiftUI
import Textual

/// Selectable Markdown prose: paragraphs, lists, code blocks and tables in one text selection.
///
/// SwiftUI's own `.textSelection` only offers a menu for a whole `Text` before iOS 27; Textual draws the same
/// SwiftUI text and lays a selection interaction over it, so a long press shows handles that reach across blocks.
/// Wide code and tables wrap rather than scroll: a nested scroll view is UIKit, which the timeline's layer effect
/// draws as an empty box. Menu actions and selection coordination come from the timeline's environment.
struct MarkdownMessageView: View {
    let text: String
    var body: some View {
        StructuredText(markdown: text)
            .font(.body)
            .textual.headingStyle(MarkdownHeadingStyle())
            .textual.overflowMode(.wrap)
            .textual.textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
