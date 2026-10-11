import SwiftUI

/// The input bar exposes supported project/decision actions and a single send-or-stop control.
struct ChatComposer: View {
    @Binding var draft: String
    let canSend: Bool
    let busy: Bool
    let working: Bool
    let send: () -> Void
    let stop: () -> Void
    let showProject: () -> Void
    let showFeed: () -> Void
    @FocusState private var focused: Bool
    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Menu {
                Button(action: showProject) { Label(String(localized: "project.title"), systemImage: "doc.text.magnifyingglass") }
                Button(action: showFeed) { Label(String(localized: "feed.title"), systemImage: "checkmark.bubble") }
            } label: { Image(systemName: "plus").font(.system(size: 23, weight: .medium)).frame(width: 36, height: 42) }
                .tint(.primary).accessibilityLabel(String(localized: "chat.actions")).accessibilityIdentifier("chat.actions")
            TextField(String(localized: "chat.follow_up"), text: $draft, axis: .vertical)
                .font(.body).lineLimit(1...6).focused($focused).padding(.vertical, 11)
                .accessibilityIdentifier("chat.composer")
            if working && !hasDraft {
                Button(action: stop) { Image(systemName: "stop.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(width: 40, height: 40).background(Color.accentColor, in: Circle()) }
                    .buttonStyle(.plain).accessibilityLabel(String(localized: "chat.stop")).accessibilityIdentifier("chat.stop").disabled(busy || !canSend)
            } else {
                Button { focused = false; send() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 20, weight: .semibold)).foregroundStyle(hasDraft && canSend ? Color.white : Color.secondary)
                        .frame(width: 40, height: 40).background(hasDraft && canSend ? Color.accentColor : Color(uiColor: .tertiarySystemFill), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel(String(localized: "chat.send")).accessibilityIdentifier("chat.send").disabled(busy || !canSend || !hasDraft)
            }
        }.padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 30))
            .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.primary.opacity(0.055), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.075), radius: 18, y: 5)
    }
}
