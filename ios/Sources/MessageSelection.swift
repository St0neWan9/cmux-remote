import SwiftUI

/// A reply the reader is selecting text in, and where their long press landed in it.
///
/// Timeline rows are drawn through a blur effect that cannot host UIKit views, so a reply is shown as SwiftUI text
/// and becomes a text view only while it is being selected; its row drops the effect for that time.
struct MessageSelection: Equatable {
    let messageID: String
    let point: CGPoint
}

private struct MessageSelectionKey: EnvironmentKey {
    static let defaultValue: MessageSelection? = nil
}

private struct SelectMessageKey: EnvironmentKey {
    /// Only ever set and called from the main actor by SwiftUI views, and never stored beyond the view tree.
    nonisolated(unsafe) static let defaultValue: ((MessageSelection?) -> Void)? = nil
}

private struct QuoteTextKey: EnvironmentKey {
    /// Only ever set and called from the main actor by SwiftUI views, and never stored beyond the view tree.
    nonisolated(unsafe) static let defaultValue: (String) -> Void = { _ in }
}

extension EnvironmentValues {
    /// The reply being selected on this page, if any.
    var messageSelection: MessageSelection? {
        get { self[MessageSelectionKey.self] }
        set { self[MessageSelectionKey.self] = newValue }
    }
    /// Starts or ends selecting a reply; absent where replies cannot be selected in place.
    var selectMessage: ((MessageSelection?) -> Void)? {
        get { self[SelectMessageKey.self] }
        set { self[SelectMessageKey.self] = newValue }
    }
    /// Quotes a selected or full text into the message draft.
    var quoteText: (String) -> Void {
        get { self[QuoteTextKey.self] }
        set { self[QuoteTextKey.self] = newValue }
    }
}
