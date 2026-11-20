import Foundation

/// The Codex `/model` picker as a state machine, rendered the way Codex 0.162 draws it, without a Codex process.
struct CodexPickerEmulator {
    enum Stage: Equatable { case prompt, models(Int), efforts(model: Int, Int) }
    static let models = ["GPT-6.1-Sol", "GPT-6-Astra", "GPT-6-Sol", "GPT-6-Luna"]
    static let efforts = ["Low", "Medium (default)", "High", "Extra high"]
    var stage = Stage.prompt
    var typed = ""
    /// False models a picker that ignores arrow keys.
    var follows = true
    /// False models a picker that stays open after `s`.
    var closesOnSession = true
    /// Escapes that reached the agent's own prompt rather than the picker.
    var promptEscapes = 0
    private(set) var applied: (model: String, effort: String, sessionOnly: Bool)?
    mutating func input(_ text: String) {
        var rest = Substring(text)
        while !rest.isEmpty {
            for key in ["\u{1b}[B", "\u{1b}[A", "\u{1b}", "\r"] + [String(rest.first!)] where rest.hasPrefix(key) {
                press(key); rest = rest.dropFirst(key.count); break
            }
        }
    }
    private mutating func press(_ key: String) {
        switch (stage, key) {
        case (.prompt, "\r"): if typed == "/model" { stage = .models(0) }; typed = ""
        case (.prompt, "\u{1b}"): promptEscapes += 1
        case (.prompt, _): typed += key
        case (.models(let index), "\u{1b}[B"): if follows { stage = .models(min(index + 1, Self.models.count - 1)) }
        case (.models(let index), "\u{1b}[A"): if follows { stage = .models(max(index - 1, 0)) }
        case (.models(let index), "\r"): stage = .efforts(model: index, 1)
        case (.models, "\u{1b}"): stage = .prompt
        case (.efforts(let model, let index), "\u{1b}[B"): if follows { stage = .efforts(model: model, min(index + 1, Self.efforts.count - 1)) }
        case (.efforts(let model, let index), "\u{1b}[A"): if follows { stage = .efforts(model: model, max(index - 1, 0)) }
        case (.efforts(let model, _), "\u{1b}"): stage = .models(model)
        case (.efforts(let model, let index), "s"):
            applied = (Self.models[model], Self.efforts[index], true)
            if closesOnSession { stage = .prompt }
        case (.efforts(let model, let index), "\r"): applied = (Self.models[model], Self.efforts[index], false); stage = .prompt
        default: break
        }
    }
    var rows: [String] {
        switch stage {
        case .prompt:
            return ["  >_ OpenAI Codex (v0.162.1)", "", "› " + (typed.isEmpty ? "Ask Codex to do anything" : typed), "", "  GPT-6.1-Sol high · /project"]
        case .models(let highlighted):
            return ["  Select Model and Effort", ""] + Self.models.enumerated().map { index, name in
                (index == highlighted ? "› " : "  ") + "\(index + 1). \(name)\(index == 0 ? " (current)" : "")  A model for coding."
            } + ["", "  enter select · esc back"]
        case .efforts(let model, let highlighted):
            return ["  Select Reasoning Level for \(Self.models[model])", ""] + Self.efforts.enumerated().map { index, name in
                (index == highlighted ? "› " : "  ") + "\(index + 1). \(name)  Reasoning depth."
            } + ["", "  enter default · s session · esc back"]
        }
    }
}
