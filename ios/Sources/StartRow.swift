import SwiftUI

/// A tappable list row with a leading symbol and a trailing chevron.
struct StartRow: View {
    let title: String
    var detail: String? = nil
    let symbol: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body).foregroundStyle(.primary).lineLimit(2)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(.vertical, 10).contentShape(Rectangle())
    }
}
