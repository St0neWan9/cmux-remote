import Foundation
import CmuxRemoteCore

/// Exact provider-session lookup under explicit local roots, with one bounded scan per inventory.
public struct TuiTranscriptLocator: Sendable {
    private let claudeRoot: URL
    private let codexRoot: URL
    private let entryLimit: Int
    public init(claudeRoot: URL, codexRoot: URL, entryLimit: Int = 20_000) {
        self.claudeRoot = claudeRoot.resolvingSymlinksInPath().standardizedFileURL
        self.codexRoot = codexRoot.resolvingSymlinksInPath().standardizedFileURL
        self.entryLimit = entryLimit
    }
    public func locate(provider: String, sessionID: String, cwd: String?) throws -> String? {
        guard UUID(uuidString: sessionID) != nil, ["claude", "codex"].contains(provider) else { return nil }
        let result = try search([provider: [sessionID.lowercased()]])
        let key = provider + ":" + sessionID.lowercased()
        guard !result.ambiguous.contains(key) else { throw BridgeError("history_unavailable", "Multiple records match this exact Agent session.", status: 409) }
        return result.paths[key] ?? pending(provider: provider, sessionID: sessionID, cwd: cwd)
    }
    func locate(_ bindings: [TuiSessionSnapshot.Binding]) throws -> [String: String] {
        var wanted: [String: Set<String>] = [:]
        for binding in bindings { wanted[binding.provider, default: []].insert(binding.providerSession) }
        let result = try search(wanted)
        var paths: [String: String] = [:]
        for binding in bindings {
            let key = binding.provider + ":" + binding.providerSession
            if !result.ambiguous.contains(key), let path = result.paths[key] ?? pending(provider: binding.provider, sessionID: binding.providerSession, cwd: binding.cwd) { paths[binding.id] = path }
        }
        return paths
    }
    private func search(_ wanted: [String: Set<String>]) throws -> (paths: [String: String], ambiguous: Set<String>) {
        let roots: [(String, URL)] = [("claude", claudeRoot.appendingPathComponent("projects")), ("codex", codexRoot.appendingPathComponent("sessions")), ("codex", codexRoot.appendingPathComponent("archived_sessions"))]
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]
        var found: [String: String] = [:], ambiguous = Set<String>(), visited = 0
        for (provider, root) in roots where wanted[provider]?.isEmpty == false {
            guard (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
                  let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { continue }
            for case let file as URL in iterator {
                try Task.checkCancellation(); visited += 1
                guard visited <= entryLimit else { throw BridgeError("history_too_large", "The transcript lookup exceeds the discovery limit.", status: 413) }
                let values = try file.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true { iterator.skipDescendants(); continue }
                guard values.isRegularFile == true, file.pathExtension == "jsonl" else { continue }
                let name = file.deletingPathExtension().lastPathComponent.lowercased()
                let id = provider == "claude" ? name : String(name.suffix(36))
                guard wanted[provider]?.contains(id) == true, provider == "claude" || name.hasPrefix("rollout-") && name.hasSuffix("-" + id) else { continue }
                let key = provider + ":" + id
                if found[key] != nil { ambiguous.insert(key) }
                else { found[key] = file.standardizedFileURL.path }
            }
        }
        return (found, ambiguous)
    }
    private func pending(provider: String, sessionID: String, cwd: String?) -> String? {
        guard provider == "claude", let cwd, cwd.hasPrefix("/"), cwd.utf8.count < 4096 else { return nil }
        let encoded = cwd.unicodeScalars.map { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").contains($0) ? String($0) : "-" }.joined()
        let project = claudeRoot.appendingPathComponent("projects").appendingPathComponent(encoded, isDirectory: true)
        if FileManager.default.fileExists(atPath: project.path) {
            guard let values = try? project.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isDirectory == true, values.isSymbolicLink != true else { return nil }
        }
        guard project.resolvingSymlinksInPath().path == project.path else { return nil }
        let path = project.appendingPathComponent(sessionID.lowercased() + ".jsonl")
        guard !FileManager.default.fileExists(atPath: path.path) else { return nil }
        return path.path
    }
}
