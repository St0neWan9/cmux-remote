import SwiftUI
import CmuxRemoteCore

/// The agent and model under the conversation's title; tapped, it switches the model with the agent's own command.
///
/// It is equal to itself while what it shows is unchanged: the conversation page renders again many times a
/// second while a reply streams in, and every render of an open menu rebuilds it, which threw the reader back
/// to its top while they were scrolling through the list. The action is left out of the comparison; it always
/// switches this page's conversation.
struct AgentModelMenu: View, Equatable {
    let subtitle: String
    let current: String?
    let choices: ModelChoiceList?
    let enabled: Bool
    let switchModel: (_ name: String, _ label: String) -> Void
    @State private var customShown = false
    @State private var customName = ""
    var body: some View {
        if let choices {
            Menu {
                // A long configured list would push this out of reach, so typing a name comes first.
                if choices.acceptsCustom {
                    Button { customName = ""; customShown = true } label: { Label(String(localized: "model.custom"), systemImage: "ellipsis.circle") }
                        .accessibilityIdentifier("model.custom")
                }
                Section(note(choices)) {
                    ForEach(choices.choices) { choice in
                        Button { switchModel(choice.id, choice.label) } label: {
                            if selected(choice) { Label(choice.label, systemImage: "checkmark") } else { Text(choice.label) }
                            if let detail = choice.detail { Text(detail) }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(subtitle).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
                }.font(.caption).foregroundStyle(.secondary).contentShape(Rectangle())
            }
            .disabled(!enabled)
            .accessibilityLabel(String(localized: "model.switch"))
            .accessibilityValue(current ?? "")
            .accessibilityIdentifier("model.menu")
            .alert(String(localized: "model.custom"), isPresented: $customShown) {
                TextField(String(localized: "model.custom_placeholder"), text: $customName)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(String(localized: "model.switch")) {
                    let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { switchModel(name, name) }
                }
                Button(String(localized: "pair.cancel"), role: .cancel) {}
            } message: { Text(note(choices)) }
        } else {
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
    nonisolated static func == (lhs: AgentModelMenu, rhs: AgentModelMenu) -> Bool {
        lhs.subtitle == rhs.subtitle && lhs.current == rhs.current && lhs.choices == rhs.choices && lhs.enabled == rhs.enabled
    }
    private func selected(_ choice: ModelChoice) -> Bool {
        guard let current = current?.lowercased() else { return false }
        return current == choice.id.lowercased() || current == choice.label.lowercased()
    }
    private func note(_ choices: ModelChoiceList) -> String {
        String(localized: choices.persistsDefault ? "model.note_default" : "model.note_session")
    }
}
