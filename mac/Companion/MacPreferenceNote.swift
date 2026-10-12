import SwiftUI

/// Secondary explanation under a control; indented notes belong to the checkbox title above them.
struct MacPreferenceNote: View {
    let text: String
    var indented = false
    private let design = MacDesignTokens()
    var body: some View {
        // A hanging indent keeps wrapped lines aligned with the first line's text, not the arrow.
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: "↳")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 12)).foregroundStyle(.secondary)
            .padding(.leading, indented ? design.noteIndent : 4)
    }
}
