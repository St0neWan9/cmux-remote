import SwiftUI

struct SpeechDraftStrip: View {
    let model: SpeechDraftModel
    let useText: () -> Void
    var body: some View {
        if model.active || !model.text.isEmpty || model.error != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if model.active { ProgressView().controlSize(.mini) }
                    Text(String(localized: model.state == .starting ? "voice.preparing" : model.state == .finishing ? "voice.finishing" : model.state == .recording ? "voice.listening" : "voice.draft")).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "pair.cancel")) { model.cancel() }
                }
                if !model.text.isEmpty { Text(model.text).font(.callout).lineLimit(4).textSelection(.enabled) }
                if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red) }
                ActionRow {
                    if model.state == .recording { Button(String(localized: "voice.finish")) { model.finish() } }
                    if !model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Button(String(localized: "voice.use"), action: useText).buttonStyle(FloatingButtonStyle(prominent: true)) }
                }.font(.footnote).buttonStyle(FloatingButtonStyle())
            }.modifier(FloatingSurface()).accessibilityIdentifier("voice.draft")
        }
    }
}
