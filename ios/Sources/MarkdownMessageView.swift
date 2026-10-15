import SwiftUI

/// Native selectable Markdown prose rendered in a UITextView for inline handle selection and a custom menu.
struct MarkdownMessageView: View {
    let text: String
    @Environment(\.quoteText) private var quoteText
    var body: some View {
        SelectableMessageTextView(text: text, quote: quoteText)
    }
}
