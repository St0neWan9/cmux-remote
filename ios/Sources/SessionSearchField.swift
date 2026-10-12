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
        }.modifier(FloatingInput())
    }
}
