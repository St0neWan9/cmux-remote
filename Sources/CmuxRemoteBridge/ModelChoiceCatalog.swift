import Foundation
import CmuxRemoteCore

/// The models an agent's own configuration on this Mac offers, for a phone that cannot read it.
///
/// Claude Code takes its aliases and any `modelPicker` options the owner configured; Codex takes the models its
/// cache lists in its own picker. Only names and labels are read; credentials in the same files are never touched.
struct ModelChoiceCatalog: Sendable {
    private let claudeSettings: URL
    private let codexModels: URL
    static let claudeAliases: [ModelChoice] = [
        ModelChoice(id: "default", label: "Default"), ModelChoice(id: "opus", label: "Opus"), ModelChoice(id: "sonnet", label: "Sonnet"),
        ModelChoice(id: "haiku", label: "Haiku"), ModelChoice(id: "fable", label: "Fable")
    ]
    init(home: URL) {
        claudeSettings = home.appendingPathComponent(".claude/settings.json")
        codexModels = home.appendingPathComponent(".codex/models_cache.json")
    }
    func choices(agent: String) -> ModelChoiceList {
        if agent == "codex" {
            return ModelChoiceList(choices: codexChoices(), acceptsCustom: true, persistsDefault: false)
        }
        return ModelChoiceList(choices: unique(Self.claudeAliases + claudeConfigured()), acceptsCustom: true, persistsDefault: true)
    }
    private func claudeConfigured() -> [ModelChoice] {
        let options = (object(claudeSettings, limit: 1_048_576)?["modelPicker"] as? [String: Any])?["options"] as? [[String: Any]] ?? []
        return options.compactMap { option in
            guard let id = (option["model"] as? String).flatMap({ try? AgentModelName.validated($0) }) else { return nil }
            return ModelChoice(id: id, label: Self.label(option["label"]) ?? id, detail: Self.label(option["description"]))
        }
    }
    private func codexChoices() -> [ModelChoice] {
        let models = object(codexModels, limit: 4_194_304)?["models"] as? [[String: Any]] ?? []
        return unique(models.compactMap { model in
            // Hidden models never appear in the Codex picker, so they could not be selected there.
            guard model["visibility"] as? String == "list", let id = (model["slug"] as? String).flatMap({ try? AgentModelName.validated($0) }) else { return nil }
            return ModelChoice(id: id, label: Self.label(model["display_name"]) ?? id, detail: Self.label(model["description"]))
        })
    }
    private func unique(_ choices: [ModelChoice]) -> [ModelChoice] {
        var seen = Set<String>()
        return Array(choices.filter { seen.insert($0.id.lowercased()).inserted }.prefix(64))
    }
    private func object(_ url: URL, limit: Int) -> [String: Any]? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber, size.intValue <= limit,
              let data = try? Data(contentsOf: url), data.count <= limit else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    private static func label(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let clean = String(text.unicodeScalars.filter { $0.properties.generalCategory != .control })
        return String(clean.prefix(120))
    }
}
