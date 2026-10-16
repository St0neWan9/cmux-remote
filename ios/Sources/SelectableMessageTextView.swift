import SwiftUI
import UIKit

/// UITextView-backed Markdown renderer with inline selection handles and a custom edit menu.
///
/// SwiftUI's `.textSelection` offers only the system menu. A text view's delegate can replace that menu, so a long
/// press selects with handles and the selection offers adding to the chat, copying, sharing and selecting the whole turn.
struct SelectableMessageTextView: UIViewRepresentable {
    let text: String
    /// Where the long press landed; the word there is selected first.
    let start: CGPoint
    let quote: (String) -> Void
    /// The selection was dismissed; the reply goes back to plain text.
    let ended: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(quote: quote, ended: ended) }

    func makeUIView(context: Context) -> UITextView {
        let tv = WindowTextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.dataDetectorTypes = []
        tv.isSelectable = true
        tv.delegate = context.coordinator
        tv.accessibilityIdentifier = "message.text"
        let start = start, coordinator = context.coordinator
        // Selected once the text view is in the window, so its handles and menu have somewhere to appear.
        tv.enteredWindow = { [weak coordinator] tv in
            tv.enteredWindow = nil
            DispatchQueue.main.async { [weak tv] in if let tv { coordinator?.begin(tv, at: start) } }
        }
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let attr = Self.attributedString(for: text, traitCollection: tv.traitCollection)
        if tv.attributedText != attr { tv.attributedText = attr }
        context.coordinator.quote = quote
        context.coordinator.ended = ended
    }

    /// The height the SwiftUI renderer would have used, so a reply does not move when it becomes selectable.
    ///
    /// Two other measurements are close but wrong: `UITextView.sizeThatFits` measures its own text container and
    /// rounds up to a whole extra line at some widths (76 where the text is 71 at 354 points), and
    /// `boundingRect` with `.usesFontLeading` adds the leading again (76). Without that option the same call
    /// agrees with a label's own layout (70.86 against 71), which is what SwiftUI's text comes out at.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        guard let attributed = tv.attributedText, attributed.length > 0 else { return CGSize(width: width, height: 0) }
        let height = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin], context: nil).height
        return CGSize(width: width, height: ceil(height))
    }

    // MARK: – Attributed string

    /// The same paragraph rhythm the SwiftUI renderer uses, so switching a reply into a text view does not move it.
    ///
    /// Block spacing is the gap between the text views in `MarkdownMessageView` (14), code is padded and rounded
    /// there, and a list marker sits 10 points from its text.
    static func attributedString(for text: String, traitCollection: UITraitCollection) -> NSAttributedString {
        let blocks = MarkdownBlock.parse(text)
        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 { result.append(Self.gap(Self.blockSpacing)) }
            result.append(block.toAttributed())
        }
        return result
    }

    /// The line gap between blocks, as an empty paragraph of the block spacing. `lineSpacing` alone is
    /// ignored on a blank line, so the height is carried by the font.
    static func gap(_ points: CGFloat) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = points
        para.maximumLineHeight = points
        return NSAttributedString(string: "\n", attributes: [
            .font: UIFont.systemFont(ofSize: points), .paragraphStyle: para,
        ])
    }

    /// The `VStack` spacing between blocks in `MarkdownMessageView`.
    static let blockSpacing: CGFloat = 14
    /// The padding inside a code block there.
    static let codePadding: CGFloat = 14
}

// MARK: – MarkdownBlock attributed rendering

private extension MarkdownBlock {
    func toAttributed() -> NSAttributedString {
        if code { return codeAttributed() }
        if table != nil { return tableAttributed() }
        if let level = headingLevel { return headingAttributed(level) }
        return paragraphAttributed()
    }

    /// Code is padded on every side and sits on its own rounded surface, as the SwiftUI block does.
    private func codeAttributed() -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2
        let inset = SelectableMessageTextView.codePadding
        para.firstLineHeadIndent = inset; para.headIndent = inset; para.tailIndent = -inset
        para.paragraphSpacingBefore = inset; para.paragraphSpacing = inset
        // The block's own surface; the text view's background stays clear.
        let block = NSMutableAttributedString(string: self.text, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular),
            .foregroundColor: UIColor.label,
            .paragraphStyle: para,
        ])
        block.addAttribute(.backgroundColor, value: UIColor.secondarySystemBackground, range: NSRange(location: 0, length: block.length))
        return block
    }

    private func tableAttributed() -> NSAttributedString {
        let para = NSMutableParagraphStyle(); para.lineSpacing = 2
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular),
            .foregroundColor: UIColor.label,
            .paragraphStyle: para,
        ])
    }

    private func headingAttributed(_ level: Int) -> NSAttributedString {
        let style: UIFont.TextStyle = level == 1 ? .title2 : level == 2 ? .title3 : .headline
        let base = UIFont.preferredFont(forTextStyle: style)
        // SwiftUI's heading block is `.bold()`; the markdown parse alone would leave it regular.
        let bold = base.fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: base.pointSize) } ?? base
        let para = NSMutableParagraphStyle(); para.lineSpacing = 2
        return body(rawText: text, font: bold, para: para, indentMarker: false)
    }

    private func paragraphAttributed() -> NSAttributedString {
        let para = NSMutableParagraphStyle(); para.lineSpacing = 5
        guard let marker = listMarker else { return body(rawText: text, font: UIFont.preferredFont(forTextStyle: .body), para: para, indentMarker: false) }
        // A list row hangs its text under a marker 10 points away, as the SwiftUI HStack does.
        para.firstLineHeadIndent = 0
        para.headIndent = markerWidth(marker) + 10
        let line = NSMutableAttributedString(string: marker + "\t", attributes: [
            .font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label, .paragraphStyle: para,
        ])
        line.append(body(rawText: text, font: UIFont.preferredFont(forTextStyle: .body), para: para, indentMarker: true))
        line.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: line.length))
        return line
    }

    private func markerWidth(_ marker: String) -> CGFloat {
        (marker as NSString).size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .body)]).width
    }

    /// Inline markdown inside one block, at the block's own font size.
    private func body(rawText raw: String, font baseFont: UIFont, para: NSMutableParagraphStyle, indentMarker: Bool) -> NSAttributedString {
        guard var parsed = try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: raw, attributes: [.font: baseFont, .foregroundColor: UIColor.label, .paragraphStyle: para])
        }
        // Remap fonts so every run keeps the block's size while retaining bold and italic traits.
        for run in parsed.runs {
            let traits = run.uiKit.font?.fontDescriptor.symbolicTraits ?? []
            let merged = traits.union(baseFont.fontDescriptor.symbolicTraits)
            let newFont = baseFont.fontDescriptor.withSymbolicTraits(merged).map { UIFont(descriptor: $0, size: baseFont.pointSize) } ?? baseFont
            parsed[run.range].uiKit.font = newFont
        }
        let ns = NSMutableAttributedString(parsed)
        ns.addAttributes([.foregroundColor: UIColor.label, .paragraphStyle: para], range: NSRange(location: 0, length: ns.length))
        return ns
    }
}

// MARK: – Coordinator

/// A text view that reports when it is first placed in a window.
final class WindowTextView: UITextView {
    var enteredWindow: ((WindowTextView) -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { enteredWindow?(self) }
    }
}

extension SelectableMessageTextView {
    /// Replaces the text view's own edit menu, so a selection shows one menu with this page's actions.
    @MainActor final class Coordinator: NSObject, UITextViewDelegate, UIEditMenuInteractionDelegate {
        var quote: (String) -> Void
        var ended: () -> Void
        /// Set once the first word is selected; a collapsed selection before then is the text view starting up.
        private var began = false
        /// The first selection is reported by `textViewDidChangeSelection` as well as by `begin`, so the press
        /// itself takes the firmer tap and the callback that follows it stays quiet.
        private var pressedFeedback = false
        /// iOS's own text selection ticks as the handles move; the press itself gets a firmer tap, as it does in
        /// the system's text views. Prepared on the press, which is the moment before the feedback is fired.
        private let selectionFeedback = UISelectionFeedbackGenerator()
        private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        init(quote: @escaping (String) -> Void, ended: @escaping () -> Void) { self.quote = quote; self.ended = ended }

        func begin(_ textView: UITextView, at point: CGPoint) {
            textView.layoutIfNeeded()
            // Prepared before the change lands: the generators are ready by the time the finger stops.
            selectionFeedback.prepare(); impactFeedback.prepare()
            guard let position = textView.closestPosition(to: point) else { ended(); return }
            let word = textView.tokenizer.rangeEnclosingPosition(position, with: .word, inDirection: .storage(.forward))
                ?? textView.tokenizer.rangeEnclosingPosition(position, with: .word, inDirection: .storage(.backward))
                ?? textView.textRange(from: position, to: textView.position(from: position, offset: 1) ?? position)
            textView.becomeFirstResponder()
            textView.selectedTextRange = word
            began = textView.selectedRange.length > 0
            guard began, let range = textView.selectedTextRange else { ended(); return }
            pressedFeedback = true
            impactFeedback.impactOccurred()
            showMenu(for: textView)
        }

        /// The text view shows its own menu only when its selection is tapped; this one opens it straight away.
        private func showMenu(for textView: UITextView) {
            guard let range = textView.selectedTextRange else { return }
            let rect = textView.firstRect(for: range)
            let interaction = UIEditMenuInteraction(delegate: self)
            textView.addInteraction(interaction)
            interaction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: rect.midX, y: rect.minY)))
        }

        nonisolated func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                                             suggestedActions: [UIMenuElement]) -> UIMenu? {
            MainActor.assumeIsolated {
                guard let textView = interaction.view as? UITextView else { return nil }
                return menu(textView, range: textView.selectedRange)
            }
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            menu(textView, range: range)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if began && textView.selectedRange.length == 0 { began = false; ended(); return }
            guard began else { return }
            if pressedFeedback { pressedFeedback = false; return }
            selectionFeedback.selectionChanged()
        }

        private func menu(_ textView: UITextView, range: NSRange) -> UIMenu? {
            guard range.length > 0 else { return nil }
            let selected = (textView.text as NSString).substring(with: range)
            let quote = quote
            return UIMenu(options: .displayInline, children: [
                UIAction(title: String(localized: "chat.selection.add_to_chat"), image: UIImage(systemName: "text.quote")) { _ in
                    quote(selected); textView.selectedRange = NSRange(location: range.location, length: 0)
                },
                UIAction(title: String(localized: "chat.copy_text"), image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = selected
                },
                UIAction(title: String(localized: "chat.selection.share"), image: UIImage(systemName: "square.and.arrow.up")) { [weak textView] _ in
                    guard let textView, let presenter = textView.window?.rootViewController?.topMost else { return }
                    let sheet = UIActivityViewController(activityItems: [selected], applicationActivities: nil)
                    sheet.popoverPresentationController?.sourceView = textView
                    presenter.present(sheet, animated: true)
                },
                UIAction(title: String(localized: "chat.selection.select_all"), image: UIImage(systemName: "selection.pin.in.out")) { [weak self, weak textView] _ in
                    textView?.selectAll(nil)
                    // A select all dismisses the menu; it comes back over the whole selection.
                    DispatchQueue.main.async { if let textView { self?.showMenu(for: textView) } }
                },
            ])
        }
    }
}

private extension UIViewController {
    var topMost: UIViewController { presentedViewController?.topMost ?? self }
}
