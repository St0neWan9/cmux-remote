import Foundation
import TermRemoteCore
import TermRemoteBridge

/// Explicit, reversible installation of this project's Agent hook command.
/// Existing cmux hooks are preserved; only commands tagged with this project's
/// marker are added or removed. Codex may ask the reader to trust the change.
struct HooksCommand {
    private static let marker = "# term-remote-hook"
    private static let defaultEvents = ["SessionStart", "UserPromptSubmit", "Stop", "SessionEnd", "PermissionRequest"]
    private static let antigravityEvents = ["SessionStart", "PreInvocation", "PostInvocation", "Stop"]
    private static let antigravityHookName = "term-remote"
    private static let agents = ["claude", "codex", "antigravity"]

    func run(options: CLIOptions, state: BridgeState) throws {
        let action = options.args.first ?? "status"
        guard ["status", "install", "remove"].contains(action) else {
            throw BridgeError("invalid_input", "Use hooks status|install|remove [--agent claude|codex|antigravity] [--dry-run].")
        }
        let requested = options.value("agent").map { [$0] } ?? Self.agents
        guard requested.allSatisfy(Self.agents.contains) else { throw BridgeError("invalid_input", "Choose claude, codex or antigravity.") }
        let dryRun = options.contains("dry-run")
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        let statePath = state.directory.path
        let home = options.value("home").map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
        for agent in requested {
            guard let file = Self.configuration(for: agent, home: home) else { continue }
            let exists = FileManager.default.fileExists(atPath: file.path)
            if !exists {
                if agent == "antigravity", action == "status",
                   FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path) {
                    print("\(agent): not installed (\(file.path))")
                    continue
                }
                if agent == "antigravity", action == "install",
                   FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path) {
                    let changes = try modifyAntigravity(file: file, install: true, dryRun: dryRun,
                                                        executable: executable, state: statePath, exists: false)
                    print("\(agent): \(dryRun ? "would change" : "changed") \(changes) hook command\(changes == 1 ? "" : "s") in \(file.path)")
                    continue
                }
                if action != "status" { print("\(agent): no hook configuration at \(file.path); nothing changed.") }
                continue
            }
            if action == "status" {
                let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                print("\(agent): \(text.contains(Self.marker) ? "installed" : "not installed") (\(file.path))")
                continue
            }
            let changes = agent == "antigravity"
                ? try modifyAntigravity(file: file, install: action == "install", dryRun: dryRun,
                                        executable: executable, state: statePath, exists: true)
                : try modify(file: file, agent: agent, install: action == "install", dryRun: dryRun,
                             executable: executable, state: statePath)
            print("\(agent): \(dryRun ? "would change" : "changed") \(changes) hook command\(changes == 1 ? "" : "s") in \(file.path)")
        }
        if action == "install", !dryRun, requested.contains("codex") {
            print("Codex may ask you to trust the changed hook file when it next starts; approve it there.")
        }
    }

    private func modify(file: URL, agent: String, install: Bool, dryRun: Bool,
                        executable: String, state: String) throws -> Int {
        let data = try Data(contentsOf: file)
        guard data.count <= 1_048_576, var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw BridgeError("invalid_config", "The hook configuration is not a JSON object.", status: 422)
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var events = Set(hooks.keys)
        if install { events.formUnion(Self.defaultEvents) }
        var changes = 0
        for event in events.sorted() {
            var groups = hooks[event] as? [[String: Any]] ?? []
            let hasMarker = groups.contains { group in
                (group["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String)?.contains(Self.marker) == true } == true
            }
            if install {
                if hasMarker { continue }
                let command = "'\(Self.quote(executable))' agent-hook --agent \(agent) --event \(Self.quote(event)) --state '\(Self.quote(state))' 2>/dev/null || true; echo {} \(Self.marker)"
                groups.append(["hooks": [["type": "command", "command": command, "timeout": 5]]])
                changes += 1
            } else {
                let before = groups.count
                groups.removeAll { group in
                    (group["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String)?.contains(Self.marker) == true } == true
                }
                changes += before - groups.count
            }
            hooks[event] = groups
        }
        root["hooks"] = hooks
        guard changes > 0 else { return 0 }
        if dryRun {
            let object = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: object, as: UTF8.self))
            return changes
        }
        let backup = file.appendingPathExtension("term-remote-backup")
        if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: file, to: backup) }
        let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        guard output.count <= 1_048_576 else { throw BridgeError("too_large", "The hook configuration is too large.", status: 413) }
        let temporary = file.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString + ".tmp")
        try output.write(to: temporary, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary, backupItemName: nil, options: [.usingNewMetadataOnly])
        return changes
    }

    /// Antigravity's `hooks.json` maps top-level named hooks to flat handler arrays per event
    /// (`SessionStart`, `PreInvocation`, `PostInvocation`, `Stop`), unlike Claude/Codex's matcher groups.
    private func modifyAntigravity(file: URL, install: Bool, dryRun: Bool,
                                   executable: String, state: String, exists: Bool) throws -> Int {
        var root: [String: Any]
        if exists {
            let data = try Data(contentsOf: file)
            guard data.count <= 1_048_576, let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw BridgeError("invalid_config", "The hook configuration is not a JSON object.", status: 422)
            }
            root = parsed
        } else {
            root = [:]
        }
        var changes = 0
        if install {
            var hook = root[Self.antigravityHookName] as? [String: Any] ?? [:]
            for event in Self.antigravityEvents {
                var handlers = hook[event] as? [[String: Any]] ?? []
                if handlers.contains(where: { ($0["command"] as? String)?.contains(Self.marker) == true }) { continue }
                let command = "'\(Self.quote(executable))' agent-hook --agent antigravity --event \(Self.quote(event)) --state '\(Self.quote(state))' 2>/dev/null || true; echo {} \(Self.marker)"
                handlers.append(["type": "command", "command": command, "timeout": 5])
                hook[event] = handlers
                changes += 1
            }
            root[Self.antigravityHookName] = hook
        } else if var hook = root[Self.antigravityHookName] as? [String: Any] {
            for event in Array(hook.keys) {
                guard var handlers = hook[event] as? [[String: Any]] else { continue }
                let before = handlers.count
                handlers.removeAll { ($0["command"] as? String)?.contains(Self.marker) == true }
                changes += before - handlers.count
                if handlers.isEmpty { hook.removeValue(forKey: event) } else { hook[event] = handlers }
            }
            if hook.isEmpty { root.removeValue(forKey: Self.antigravityHookName) } else { root[Self.antigravityHookName] = hook }
        }
        guard changes > 0 else { return 0 }
        let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        if dryRun {
            print(String(decoding: output, as: UTF8.self))
            return changes
        }
        guard output.count <= 1_048_576 else { throw BridgeError("too_large", "The hook configuration is too large.", status: 413) }
        if exists {
            let backup = file.appendingPathExtension("term-remote-backup")
            if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: file, to: backup) }
        }
        let temporary = file.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString + ".tmp")
        try output.write(to: temporary, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if exists {
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary, backupItemName: nil, options: [.usingNewMetadataOnly])
        } else {
            try FileManager.default.moveItem(at: temporary, to: file)
        }
        return changes
    }

    private static func configuration(for agent: String, home: URL) -> URL? {
        switch agent {
        case "claude": return home.appendingPathComponent(".claude/settings.json")
        case "codex": return home.appendingPathComponent(".codex/hooks.json")
        case "antigravity": return home.appendingPathComponent(".gemini/config/hooks.json")
        default: return nil
        }
    }

    private static func quote(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }
}
