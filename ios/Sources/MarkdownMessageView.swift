import SwiftUI

/// Native selectable Markdown prose with separate code blocks and paragraph rhythm.
struct MarkdownMessageView: View {
    let text: String
    private var blocks: [MarkdownBlock] { MarkdownRenderCache.blocks(for: text) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                if block.code {
                    // Nested code scrolling was blank in the live timeline.
                    // Wrapping keeps the selectable content in the parent layer.
                    Text(block.text).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("markdown.code.\(block.id)")
                } else if let table = block.table {
                    MarkdownTableView(table: table).accessibilityIdentifier("markdown.table.\(block.id)")
                } else if let level = block.headingLevel {
                    Text(block.attributed).font(level == 1 ? .title2 : level == 2 ? .title3 : .headline).bold()
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                } else if let marker = block.listMarker {
                    HStack(alignment: .top, spacing: 10) {
                        Text(marker)
                        Text(block.attributed).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.body).lineSpacing(5)
                } else {
                    Text(block.attributed).font(.body).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Parsed blocks per message text. The text of a message does not change while it streams in, but SwiftUI
/// evaluates a row's body far more often than that, and parsing long Markdown each time stalled scrolling.
enum MarkdownRenderCache {
    private final class Box: NSObject { let blocks: [MarkdownBlock]; init(_ blocks: [MarkdownBlock]) { self.blocks = blocks } }
    // NSCache is thread-safe; the annotation satisfies strict concurrency for the static holder.
    nonisolated(unsafe) private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>(); cache.countLimit = 256; return cache
    }()
    static func blocks(for text: String) -> [MarkdownBlock] {
        let key = text as NSString
        if let cached = cache.object(forKey: key) { return cached.blocks }
        let blocks = MarkdownBlock.parse(text)
        cache.setObject(Box(blocks), forKey: key)
        return blocks
    }
}
