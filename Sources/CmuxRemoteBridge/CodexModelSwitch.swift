import Foundation
import CmuxRemoteCore

/// Switches a running Codex to another model through its own `/model` picker, for this session only.
///
/// Codex takes no model argument, so the picker is walked: open it, move the highlight to the model and then to
/// the reasoning level the session already uses, and confirm with `s`, which applies the choice to this session
/// without saving it as the default. Every move is checked on screen before the next key. Until the final key
/// nothing has changed, so a picker that does not match is closed and reported as not applied.
struct CodexModelSwitch: Sendable {
    let attempts: Int
    let interval: Duration
    private let picker = CodexModelPicker()
    init(attempts: Int = 20, interval: Duration = .milliseconds(150)) {
        self.attempts = max(1, attempts); self.interval = interval
    }
    func run(on console: AgentConsole, candidates: [String], effort: String?) async throws {
        try await console.write("/model", "open")
        try await Task.sleep(for: interval)
        try await console.write("\r", "open-confirm")
        guard let models = try await wait(on: console, until: { $0?.stage == .model && $0?.highlighted != nil }) else {
            throw BridgeError("model_switch_failed", "The Codex model picker did not open; inspect the Agent.", status: 409)
        }
        guard let target = picker.number(matching: candidates, in: models), let label = models.entries.first(where: { $0.number == target })?.label else {
            try await close(console)
            throw BridgeError("model_unavailable", "Codex does not offer this model in its picker.", status: 422)
        }
        guard try await move(console, from: models, to: target, step: "model") != nil else {
            try await close(console)
            throw BridgeError("model_switch_failed", "The Codex model picker did not follow the selection; nothing changed.", status: 409)
        }
        try await console.write("\r", "model-confirm")
        let next = try await wait(on: console, until: { $0 == nil || $0?.stage == .effort })
        // A model without reasoning levels is applied by its own selection.
        guard let efforts = next else { return }
        guard efforts.stage == .effort, efforts.title.lowercased().contains(label.lowercased()) else {
            try await close(console)
            throw BridgeError("model_switch_failed", "The Codex picker opened a different model; nothing changed.", status: 409)
        }
        let level = picker.number(effort: effort, in: efforts) ?? efforts.highlighted
        guard let level, try await move(console, from: efforts, to: level, step: "effort") != nil else {
            try await close(console)
            throw BridgeError("model_switch_failed", "The Codex picker did not follow the selection; nothing changed.", status: 409)
        }
        try await console.write("s", "effort-session")
        guard try await wait(on: console, until: { $0 == nil }) == nil else {
            throw BridgeError("outcome_unknown", "Codex did not confirm the model switch; inspect the Agent.", status: 409)
        }
    }
    /// Moves the highlight with arrow keys and returns the screen once it rests on the target, or nil.
    private func move(_ console: AgentConsole, from screen: CodexModelPicker.Screen, to target: Int, step: String) async throws -> CodexModelPicker.Screen? {
        guard let current = screen.highlighted else { return nil }
        if current == target { return screen }
        let key = target > current ? "\u{1b}[B" : "\u{1b}[A"
        try await console.write(String(repeating: key, count: abs(target - current)), step + "-move")
        return try await wait(on: console, until: { $0?.stage == screen.stage && $0?.highlighted == target })
            .flatMap { $0.highlighted == target ? $0 : nil }
    }
    /// Backs out of the picker one list per Escape while it is still on screen. An Escape at Codex's own prompt
    /// arms "edit previous message", so none is sent once the picker has closed.
    private func close(_ console: AgentConsole) async throws {
        for level in 0..<2 {
            guard picker.screen(try await console.rows()) != nil else { return }
            try await console.write("\u{1b}", "close-\(level)")
            try await Task.sleep(for: interval)
        }
    }
    /// Re-reads until the condition holds or the attempts run out; returns the last screen read either way.
    private func wait(on console: AgentConsole, until condition: (CodexModelPicker.Screen?) -> Bool) async throws -> CodexModelPicker.Screen? {
        var screen: CodexModelPicker.Screen?
        for attempt in 0..<attempts {
            if attempt > 0 { try await Task.sleep(for: interval) }
            screen = picker.screen(try await console.rows())
            if condition(screen) { return screen }
        }
        return screen
    }
}
