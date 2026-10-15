import AppKit
import SwiftUI
import CmuxRemoteMac

/// The Bridge log window: level and keyword filters over the newest lines, which sit at the bottom.
struct MacLogView: View {
    @Bindable var model: MacLogModel
    let language: MacInterfaceLanguage
    private let design = MacDesignTokens()
    var body: some View {
        VStack(alignment: .leading, spacing: design.rowSpacing) {
            HStack(spacing: design.rowSpacing) {
                Picker(String(localized: "mac.logs.level", bundle: .interface), selection: $model.filter.threshold) {
                    ForEach(BridgeLogFilter.Threshold.allCases, id: \.self) { Text(title($0)).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
                TextField(String(localized: "mac.logs.search", bundle: .interface), text: $model.filter.keyword)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: design.logSearchWidth)
                Spacer(minLength: 0)
                Button(String(localized: model.paused ? "mac.logs.resume" : "mac.logs.pause", bundle: .interface)) { model.paused.toggle() }.fixedSize()
            }
            if model.status == .loaded { Text(caption).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: design.rowSpacing) {
                Button(String(localized: "mac.logs.copyAll", bundle: .interface)) { copy() }.fixedSize().disabled(model.shown.isEmpty)
                Button(String(localized: "mac.logs.reveal", bundle: .interface)) { reveal() }.fixedSize()
                Spacer(minLength: 0)
            }
        }
        .padding(design.logInset)
        .frame(minWidth: design.logMinimumWidth, minHeight: design.logMinimumHeight)
        .id(language).environment(\.locale, language.locale)
        .task(id: model.live) { await model.follow() }
    }
    @ViewBuilder private var content: some View {
        switch model.status {
        case .loaded: MacLogTextView(lines: model.shown)
        case .idle: placeholder(String(localized: "mac.logs.loading", bundle: .interface), detail: nil)
        case .missing: placeholder(String(localized: "mac.logs.missing", bundle: .interface), detail: String(localized: "mac.logs.missing.hint", bundle: .interface))
        case .failed(let code): placeholder(MacErrorPresentation.message(code), detail: nil)
        }
    }
    private func placeholder(_ title: String, detail: String?) -> some View {
        VStack(spacing: design.rowSpacing) {
            Text(title)
            if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            Text(model.file.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
        }.padding(design.logInset).frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(Rectangle().strokeBorder(Color(nsColor: .separatorColor)))
    }
    private var caption: String {
        var text = String(format: String(localized: "mac.logs.count", bundle: .interface), model.shown.count, model.lines.count)
        if model.paused { text += " · " + String(localized: "mac.logs.paused", bundle: .interface) }
        return text
    }
    private func title(_ threshold: BridgeLogFilter.Threshold) -> String {
        switch threshold {
        case .all: return String(localized: "mac.logs.level.all", bundle: .interface)
        case .info: return String(localized: "mac.logs.level.info", bundle: .interface)
        case .warning: return String(localized: "mac.logs.level.warning", bundle: .interface)
        }
    }
    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.exportText(bundle: .main, system: .processInfo), forType: .string)
    }
    /// Selects the log file when it exists, otherwise opens the state directory, so either way Finder shows where it belongs.
    private func reveal() {
        if FileManager.default.fileExists(atPath: model.file.path) { NSWorkspace.shared.activateFileViewerSelecting([model.file]) }
        else if FileManager.default.fileExists(atPath: model.directory.path) { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: model.directory.path) }
        else { NSSound.beep() }
    }
}
