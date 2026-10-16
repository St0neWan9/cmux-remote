import SwiftUI
import UIKit

/// Read-only text with the system's selection: two handles, a magnifier and the edit menu.
///
/// SwiftUI's selectable `Text` only copies the whole string on iOS; choosing part of a reply needs a text view.
struct SelectableTextView: UIViewRepresentable {
    let text: String
    var monospaced = false
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false; view.isSelectable = true
        view.backgroundColor = .clear; view.dataDetectorTypes = []
        view.textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 32, right: 16)
        view.alwaysBounceVertical = true
        view.accessibilityIdentifier = "select.text"
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        let style = UIFont.TextStyle.body
        let font = monospaced
            ? UIFontMetrics(forTextStyle: style).scaledFont(for: .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize - 2, weight: .regular))
            : UIFont.preferredFont(forTextStyle: style)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: paragraph])
        if view.attributedText != attributed { view.attributedText = attributed }
        view.adjustsFontForContentSizeCategory = true
    }
}
