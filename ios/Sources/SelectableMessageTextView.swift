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

    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: UITextView, context: Context) -> CGSize? {
        let w = proposal.width ?? UIScreen.main.bounds.width
        var s = tv.sizeThatFits(CGSize(width: w, height: .infinity))
        s.width = w
        return s
    }

    // MARK: – Attributed string

    static func attributedString(for text: String, traitCollection: UITraitCollection) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let blocks = MarkdownBlock.parse(text)
        for (i, block) in blocks.enumerated() {
            if i > 0 { result.append(NSAttributedString(string: "\n\n")) }
            result.append(block.toAttributed())
        }
        return result
    }
}

// MARK: – MarkdownBlock attributed rendering

private extension MarkdownBlock {
    func toAttributed() -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        if code {
            para.lineSpacing = 2
            para.firstLineHeadIndent = 10; para.headIndent = 10; para.tailIndent = -10
            return NSAttributedString(string: text, attributes: [
                .font: UIFont.monospacedSystemFont(
                    ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular),
                .backgroundColor: UIColor.secondarySystemBackground,
                .foregroundColor: UIColor.label,
                .paragraphStyle: para
            ])
        }
        if table != nil {
            return NSAttributedString(string: text, attributes: [
                .font: UIFont.monospacedSystemFont(
                    ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular),
                .foregroundColor: UIColor.label
            ])
        }
        para.lineSpacing = headingLevel != nil ? 2 : 5
        let baseFont: UIFont
        if let level = headingLevel {
            let style: UIFont.TextStyle = level == 1 ? .title2 : level == 2 ? .title3 : .headline
            baseFont = UIFont.preferredFont(forTextStyle: style)
        } else {
            baseFont = UIFont.preferredFont(forTextStyle: .body)
        }
        let rawText = listMarker.map { $0 + " " + text } ?? text
        return inlineMarkdown(rawText, baseFont: baseFont, para: para)
    }

    private func inlineMarkdown(_ raw: String, baseFont: UIFont, para: NSMutableParagraphStyle) -> NSAttributedString {
        // AttributedString.init(markdown:) is the correct iOS 15+ API; NSAttributedString has no markdown init.
        guard var parsed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return NSAttributedString(string: raw, attributes: [
                .font: baseFont, .foregroundColor: UIColor.label, .paragraphStyle: para
            ])
        }
        // Remap fonts so every run inherits baseFont's size and style while keeping bold/italic traits.
        for run in parsed.runs {
            let traits = run.uiKit.font?.fontDescriptor.symbolicTraits ?? []
            let newFont: UIFont
            if let desc = baseFont.fontDescriptor.withSymbolicTraits(traits) {
                newFont = UIFont(descriptor: desc, size: baseFont.pointSize)
            } else {
                newFont = baseFont
            }
            parsed[run.range].uiKit.font = newFont
        }
        let ns = NSMutableAttributedString(parsed)
        ns.addAttributes([.foregroundColor: UIColor.label, .paragraphStyle: para],
                         range: NSRange(location: 0, length: ns.length))
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
        init(quote: @escaping (String) -> Void, ended: @escaping () -> Void) { self.quote = quote; self.ended = ended }

        func begin(_ textView: UITextView, at point: CGPoint) {
            textView.layoutIfNeeded()
            guard let position = textView.closestPosition(to: point) else { ended(); return }
            let word = textView.tokenizer.rangeEnclosingPosition(position, with: .word, inDirection: .storage(.forward))
                ?? textView.tokenizer.rangeEnclosingPosition(position, with: .word, inDirection: .storage(.backward))
                ?? textView.textRange(from: position, to: textView.position(from: position, offset: 1) ?? position)
            textView.becomeFirstResponder()
            textView.selectedTextRange = word
            began = textView.selectedRange.length > 0
            guard began, let range = textView.selectedTextRange else { ended(); return }
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
            if began && textView.selectedRange.length == 0 { began = false; ended() }
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
