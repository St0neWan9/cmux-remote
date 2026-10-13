import SwiftUI
import CmuxRemoteCore

/// The input bar exposes supported project/decision actions and a single send-or-stop control.
/// Focused or holding images, it expands: images, then the text, then a row of actions.
struct ChatComposer: View {
    @Binding var draft: String
    /// Owned by the page so a tap on the conversation can put the keyboard away.
    var focused: FocusState<Bool>.Binding
    let canSend: Bool
    let busy: Bool
    let working: Bool
    var images: [ChatImagePayload] = []
    var removeImage: (UUID) -> Void = { _ in }
    let send: () -> Void
    let stop: () -> Void
    var canReadProject = true
    var canReadFeed = true
    let showProject: () -> Void
    let showFeed: () -> Void
    var hasImages = false
    var sendBlocked = false
    var showPhotos: (() -> Void)?
    var dictating = false
    var startVoice: (() -> Void)?
    var finishVoice: (() -> Void)?
    var showImageFiles: (() -> Void)?
    /// Lines the focused field may grow to before it scrolls; the page derives it from half its free height.
    var maxLines = 6
    // The line box sits below the glyphs it draws; lift it so text and symbols share a center.
    @ScaledMetric(relativeTo: .body) private var textCenterOffset: CGFloat = -1
    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasImages }
    /// A multi-line draft stays open so its text is never hidden behind a one-line bar.
    private var expanded: Bool { focused.wrappedValue || !images.isEmpty || draft.contains("\n") }
    var body: some View {
        // One text field keeps its identity in both layouts; replacing it would drop the focus that expands the bar.
        VStack(alignment: .leading, spacing: 4) {
            if expanded && !images.isEmpty { ImageDraftStrip(images: images, remove: removeImage).equatable() }
            HStack(alignment: .center, spacing: 6) {
                if !expanded { actions }
                textField.offset(y: expanded ? 0 : textCenterOffset).padding(.horizontal, expanded ? 8 : 0)
                if !expanded { voice; sendOrStop }
            }
            if expanded {
                HStack(spacing: 10) {
                    actions
                    Spacer(minLength: 0)
                    voice
                    sendOrStop
                }
            }
        }
        .padding(.horizontal, expanded ? 10 : 6).padding(.top, expanded ? 8 : 5).padding(.bottom, expanded ? 6 : 5)
        .background(Color.white, in: RoundedRectangle(cornerRadius: expanded ? 26 : 30))
        .overlay(RoundedRectangle(cornerRadius: expanded ? 26 : 30).stroke(Color.primary.opacity(0.055), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.075), radius: 18, y: 5)
        // At rest the bar is narrower and lower; focused it takes the full width.
        .padding(.horizontal, expanded ? 0 : 18)
        .animation(.easeInOut(duration: 0.18), value: expanded)
    }
    private var textField: some View {
        TextField(String(localized: "chat.follow_up"), text: $draft, axis: .vertical)
            .font(.body).lineLimit(expanded ? 1...max(2, maxLines) : 1...1).focused(focused).padding(.vertical, expanded ? 11 : 8)
            .accessibilityIdentifier("chat.composer")
    }
    private var actions: some View {
        Menu {
            if let showPhotos { Button(action: showPhotos) { Label(String(localized: "image.select"), systemImage: "photo") }.disabled(busy || !canSend || sendBlocked) }
            if let showImageFiles { Button(action: showImageFiles) { Label(String(localized: "image.select_file"), systemImage: "folder") }.disabled(busy || !canSend || sendBlocked) }
            if canReadProject { Button(action: showProject) { Label(String(localized: "project.title"), systemImage: "doc.text.magnifyingglass") } }
            if canReadFeed { Button(action: showFeed) { Label(String(localized: "feed.title"), systemImage: "checkmark.bubble") } }
        } label: { Image(systemName: "plus").font(.system(size: expanded ? 23 : 20, weight: .medium)).frame(width: expanded ? MobileDesign.controlHeight : 38, height: expanded ? MobileDesign.controlHeight : 38) }
            .tint(.primary).accessibilityLabel(String(localized: "chat.actions")).accessibilityIdentifier("chat.actions")
    }
    @ViewBuilder private var voice: some View {
        if let startVoice {
            Button { if dictating { finishVoice?() } else { focused.wrappedValue = false; startVoice() } } label: {
                Image(systemName: dictating ? "waveform" : "mic").font(.system(size: expanded ? 21 : 19)).foregroundStyle(dictating ? Color.accentColor : Color.primary).frame(width: expanded ? MobileDesign.controlHeight : 38, height: expanded ? MobileDesign.controlHeight : 38)
            }.buttonStyle(.plain).accessibilityLabel(String(localized: dictating ? "voice.finish" : "voice.start")).accessibilityIdentifier("voice.microphone").disabled(busy || !canSend || (sendBlocked && !dictating))
        }
    }
    @ViewBuilder private var sendOrStop: some View {
        if working && !hasDraft {
            Button(action: stop) { Image(systemName: "stop.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(width: expanded ? 40 : 34, height: expanded ? 40 : 34).background(Color.accentColor, in: Circle()) }
                .buttonStyle(.plain).accessibilityLabel(String(localized: "chat.stop")).accessibilityIdentifier("chat.stop").disabled(busy || !canSend)
        } else {
            Button { focused.wrappedValue = false; send() } label: {
                Image(systemName: "arrow.up").font(.system(size: 20, weight: .semibold)).foregroundStyle(hasDraft && canSend ? Color.white : Color.secondary)
                    .frame(width: expanded ? 40 : 34, height: expanded ? 40 : 34).background(hasDraft && canSend ? Color.accentColor : Color(uiColor: .tertiarySystemFill), in: Circle())
            }.frame(width: expanded ? MobileDesign.controlHeight : 38, height: expanded ? MobileDesign.controlHeight : 38).contentShape(Rectangle()).buttonStyle(.plain).accessibilityLabel(String(localized: "chat.send")).accessibilityIdentifier("chat.send").disabled(busy || !canSend || !hasDraft || sendBlocked)
        }
    }
}
