import SwiftUI

/// Tool text follows the conversation's vertical scroll and wraps long lines.
struct ToolCodeBlock: View {
    let text: String
    var body: some View {
        Text(text).font(.system(.callout, design: .monospaced)).lineSpacing(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SelectableTextMenu(text: text, monospaced: true))
    }
}
