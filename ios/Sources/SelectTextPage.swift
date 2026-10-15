import SwiftUI

/// A message's text on its own page, where any part of it can be selected and copied.
struct SelectTextPage: View {
    struct Request: Identifiable { let id = UUID(); let text: String; let monospaced: Bool }
    let request: Request
    var body: some View {
        WhitePage(title: String(localized: "chat.select_text"), dismissal: .close) {
            SelectableTextView(text: request.text, monospaced: request.monospaced)
        }
    }
    // Not presented from the conversation anymore; inline selection handles it.
}

private struct SelectTextKey: EnvironmentKey {
    /// Only ever set and called from the main actor by SwiftUI views, and never stored beyond the view tree.
    nonisolated(unsafe) static let defaultValue: (String, Bool) -> Void = { _, _ in }
}

extension EnvironmentValues {
    /// Opens a text, monospaced or not, on a page where part of it can be selected.
    var selectText: (String, Bool) -> Void {
        get { self[SelectTextKey.self] }
        set { self[SelectTextKey.self] = newValue }
    }
}

private struct QuoteTextKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: (String) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Quotes a selected or full text into the message draft.
    var quoteText: (String) -> Void {
        get { self[QuoteTextKey.self] }
        set { self[QuoteTextKey.self] = newValue }
    }
}

/// Long-press to copy a whole block of text; inline selection covers picking part of it.
struct SelectableTextMenu: ViewModifier {
    let text: String
    func body(content: Content) -> some View {
        content.contextMenu {
            Button { UIPasteboard.general.string = text } label: { Label(String(localized: "chat.copy_text"), systemImage: "doc.on.doc") }
        }
    }
}
