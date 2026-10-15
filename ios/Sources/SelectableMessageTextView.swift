import SwiftUI
import UIKit

/// UITextView-backed Markdown renderer with inline selection handles and a custom edit menu.
///
/// SwiftUI `.textSelection(.enabled)` on a VStack already provides selection handles but only the
/// system menu. Replacing the content with UITextView lets UIEditMenuInteraction inject custom
/// items — 添加到聊天, 分享, 全选 — alongside the system Copy action.
struct SelectableMessageTextView: UIViewRepresentable {
    let text: String
    let quote: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(quote: quote) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.dataDetectorTypes = []
        tv.isSelectable = true
        tv.delegate = context.coordinator
        let interaction = UIEditMenuInteraction(delegate: context.coordinator)
        tv.addInteraction(interaction)
        context.coordinator.textView = tv
        context.coordinator.editMenuInteraction = interaction
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let attr = Self.attributedString(for: text, traitCollection: tv.traitCollection)
        if tv.attributedText != attr { tv.attributedText = attr }
        context.coordinator.quote = quote
        context.coordinator.fullText = text
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

@MainActor
final class SelectableMessageTextView_Coordinator: NSObject, UITextViewDelegate, UIEditMenuInteractionDelegate {
    var quote: (String) -> Void
    var fullText: String = ""
    weak var textView: UITextView?
    var editMenuInteraction: UIEditMenuInteraction?
    private var debounce: DispatchWorkItem?

    init(quote: @escaping (String) -> Void) { self.quote = quote }

    // Present the custom menu after selection settles.
    func textViewDidChangeSelection(_ textView: UITextView) {
        debounce?.cancel()
        guard textView.selectedRange.length > 0 else { return }
        let work = DispatchWorkItem { [weak self, weak textView] in
            guard let self, let tv = textView, tv.selectedRange.length > 0 else { return }
            guard let range = tv.selectedTextRange else { return }
            let rects = tv.selectionRects(for: range)
            let mid = rects.first.map { CGPoint(x: $0.rect.midX, y: $0.rect.minY) } ?? .zero
            let cfg = UIEditMenuConfiguration(identifier: nil, sourcePoint: mid)
            self.editMenuInteraction?.presentEditMenu(with: cfg)
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    nonisolated func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                              menuFor configuration: UIEditMenuConfiguration,
                              suggestedActions: [UIMenuElement]) -> UIMenu? {
        MainActor.assumeIsolated {
            guard let tv = textView, tv.selectedRange.length > 0 else { return nil }
            let sel = (tv.text as NSString).substring(with: tv.selectedRange)

            let addToChat = UIAction(title: String(localized: "chat.selection.add_to_chat")) { [weak self] _ in
                self?.quote(sel)
            }
            let copy = UIAction(title: String(localized: "chat.copy_text")) { _ in
                UIPasteboard.general.string = sel
            }
            let share = UIAction(title: String(localized: "chat.share")) { [weak tv] _ in
                let vc = UIActivityViewController(activityItems: [sel], applicationActivities: nil)
                tv?.window?.rootViewController?.topMost.present(vc, animated: true)
            }
            let selectAll = UIAction(title: String(localized: "chat.selection.select_all")) { [weak tv] _ in
                tv?.selectAll(nil)
            }
            return UIMenu(children: [addToChat, copy, share, selectAll])
        }
    }
}

extension SelectableMessageTextView {
    typealias Coordinator = SelectableMessageTextView_Coordinator
}

private extension UIViewController {
    var topMost: UIViewController {
        presentedViewController?.topMost ?? self
    }
}
