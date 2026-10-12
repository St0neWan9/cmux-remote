import SwiftUI

struct SessionSearchField: View {
    @Binding var query: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(String(localized: "sessions.search"), text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("sessions.search.field")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel(String(localized: "sessions.clear_search"))
            }
        }.padding(.horizontal, 16).padding(.vertical, 14)
            .background(Color.white, in: Capsule()).overlay(Capsule().stroke(Color.black.opacity(0.05), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 3)
    }
}
