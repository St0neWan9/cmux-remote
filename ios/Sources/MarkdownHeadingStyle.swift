import SwiftUI
import Textual

/// Conversation headings keep the sizes the timeline used before it moved to Textual.
///
/// Textual's own heading style scales the body font by 2.353 for `#` and 1.882 for `##`, so a
/// two-level heading in a reply runs past 30pt and wraps across four lines. The fonts below are the
/// semantic styles the native timeline drew — `title2`, `title3`, then `headline` for levels three
/// and deeper — so headings keep scaling with the reader's text size.
struct MarkdownHeadingStyle: StructuredText.HeadingStyle {
    private static let fonts: [Font] = [.title2, .title3, .headline, .headline, .headline, .headline]

    func makeBody(configuration: Configuration) -> some View {
        let level = min(max(configuration.headingLevel, 1), Self.fonts.count)
        return configuration.label
            .font(Self.fonts[level - 1].bold())
            .textual.blockSpacing(.fontScaled(top: 1.0, bottom: 0.5))
    }
}
