import SwiftUI
import TermRemoteCore

/// Prompts waiting in the agent's input queue while a turn runs, shown quietly above the composer.
///
/// Mirrors `BackgroundTasksBar` in layout and tone so every connected device sees the same queue
/// without turning queued prompts into stuck timeline bubbles.
struct QueuedPromptsBar: View {
    let prompts: [QueuedPrompt]
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy(duration: 0.18)) { expanded.toggle() } } label: {
                HStack(spacing: 7) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward").font(.footnote)
                    Text(headerTitle).font(.footnote)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
                }.foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.queued")

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text("\(index + 1).").font(.caption2.monospacedDigit())
                            Text(prompt.text).font(.caption).lineLimit(2)
                            Spacer(minLength: 4)
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("chat.queued.item")
                    }
                }
                .padding(.leading, 2)
                .accessibilityIdentifier("chat.queued.list")
            }
        }
        .padding(.horizontal, 12)
    }

    private var headerTitle: String {
        if prompts.count == 1 {
            return String(localized: "chat.queued.one")
        }
        return String.localizedStringWithFormat(String(localized: "chat.queued.count"), prompts.count)
    }
}
