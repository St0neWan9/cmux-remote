import AppKit
import SwiftUI
import CmuxRemoteMac

/// A read-only, selectable monospaced log. New lines are followed only while the view is already scrolled to
/// the end, and they wait while the user has text selected so a refresh never drops a selection.
struct MacLogTextView: NSViewRepresentable {
    let lines: [BridgeLogLine]
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
        guard let text = scroll.documentView as? NSTextView else { return scroll }
        text.isEditable = false; text.isSelectable = true; text.isRichText = false; text.usesFindBar = true
        text.textContainerInset = NSSize(width: 4, height: 4)
        text.font = Coordinator.font; text.delegate = context.coordinator
        context.coordinator.textView = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.show(lines) }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        weak var textView: NSTextView?
        private var shown: [BridgeLogLine]?
        private var pending: [BridgeLogLine]?
        func show(_ lines: [BridgeLogLine]) {
            guard lines != shown else { pending = nil; return }
            guard let textView, textView.selectedRange().length == 0 else { pending = lines; return }
            apply(lines, to: textView)
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let pending, let textView, textView.selectedRange().length == 0 else { return }
            self.pending = nil; apply(pending, to: textView)
        }
        private func apply(_ lines: [BridgeLogLine], to textView: NSTextView) {
            let follow = shown == nil || atEnd(textView)
            let text = NSMutableAttributedString()
            for line in lines {
                text.append(NSAttributedString(string: line.text + "\n", attributes: [.font: Self.font, .foregroundColor: color(line)]))
            }
            textView.textStorage?.setAttributedString(text)
            shown = lines
            if follow { textView.scrollToEndOfDocument(nil) }
        }
        private func color(_ line: BridgeLogLine) -> NSColor {
            switch line.level {
            case .error: return .systemRed
            case .warning: return .systemOrange
            case .debug: return .secondaryLabelColor
            default: return .labelColor
            }
        }
        private func atEnd(_ textView: NSTextView) -> Bool {
            guard let clip = textView.enclosingScrollView?.contentView else { return true }
            return clip.bounds.maxY >= textView.frame.height - Self.font.boundingRectForFont.height * 2
        }
    }
}
