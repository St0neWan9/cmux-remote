import Foundation
import CmuxRemoteCore

/// Exact provider-session lookup under explicit local roots, with one bounded scan per inventory.
public struct TuiTranscriptLocator: Sendable {
    private let claudeRoot: URL
    private let codexRoot: URL
    private let entryLimit: Int
    /// The directory each transcript recorded, kept after the first read: a list read asks for it every few seconds.
    private let memo: TranscriptCwdMemo
    public init(claudeRoot: URL, codexRoot: URL, entryLimit: Int = 20_000) {
        self.claudeRoot = claudeRoot.resolvingSymlinksInPath().standardizedFileURL
        self.codexRoot = codexRoot.resolvingSymlinksInPath().standardizedFileURL
        self.entryLimit = entryLimit
        memo = TranscriptCwdMemo()
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
    /// The working directory a session was recorded in, read from its own transcript.
    /// The daemon's terminal cwd drifts with `cd` and is absent once the terminal is gone, so a resume must use the
    /// directory the Agent itself wrote; a wrong directory would reopen the session in the wrong project.
    public func recordedCwd(provider: String, sessionID: String) throws -> String? {
        // The directory is written once, in the session's own header; a list read asks for it every few seconds.
        let key = provider + ":" + sessionID.lowercased()
        if let known = memo.recordedCwd(key) { return known }
        guard let path = (try? locate(provider: provider, sessionID: sessionID, cwd: nil)).flatMap({ $0 }), path.hasPrefix("/") else { return nil }
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)); defer { try? handle.close() }
        // The session header is the first line; read only a bounded prefix so a long transcript cannot stall it.
        let head = try handle.read(upToCount: 262_144) ?? Data()
        for line in head.split(separator: UInt8(ascii: "\n")) {
            guard let object = try? JSONDecoder().decode(JSONValue.self, from: Data(line)) else { continue }
            if let cwd = object["cwd"].string, cwd.hasPrefix("/") { memo.remember(cwd, for: key); return cwd }
            if let cwd = object["payload"]["cwd"].string, cwd.hasPrefix("/") { memo.remember(cwd, for: key); return cwd }
        }
        return nil
    }
    /// Every transcript named `provider:sessionID` under the roots.
    ///
    /// The names are what a lookup is after, so the directories are listed by name and only a file whose name
    /// matches is examined: stat-ing every transcript in the tree made one list read cost a second of file-system
    /// work on a Mac with sixty conversations, and the phone paid it on every refresh.
    private func search(_ wanted: [String: Set<String>]) throws -> (paths: [String: String], ambiguous: Set<String>) {
        var found: [String: String] = [:], ambiguous = Set<String>(), visited = 0
        func record(_ id: String, at url: URL, provider: String) throws {
            guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]))
                .map({ $0.isSymbolicLink != true && $0.isRegularFile == true }) == true else { return }
            let key = provider + ":" + id
            if found[key] != nil { ambiguous.insert(key) } else { found[key] = url.standardizedFileURL.path }
        }
        if let ids = wanted["claude"], !ids.isEmpty {
            let projects = claudeRoot.appendingPathComponent("projects")
            guard (try? projects.resourceValues(forKeys: [.isSymbolicLinkKey])).map({ $0.isSymbolicLink != true }) ?? false else { return (found, ambiguous) }
            for project in (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? [] {
                try Task.checkCancellation(); visited += 1
                guard visited <= entryLimit else { throw BridgeError("history_too_large", "The transcript lookup exceeds the discovery limit.", status: 413) }
                let directory = projects.appendingPathComponent(project, isDirectory: true)
                // A project directory that is a link could name a record outside the roots.
                guard (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]))
                    .map({ $0.isSymbolicLink != true && $0.isDirectory == true }) == true else { continue }
                for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] {
                    try Task.checkCancellation(); visited += 1
                    guard visited <= entryLimit else { throw BridgeError("history_too_large", "The transcript lookup exceeds the discovery limit.", status: 413) }
                    guard name.hasSuffix(".jsonl") else { continue }
                    let id = String(name.dropLast(6)).lowercased()
                    guard ids.contains(id) else { continue }
                    try record(id, at: directory.appendingPathComponent(name), provider: "claude")
                }
            }
        }
        if let ids = wanted["codex"], !ids.isEmpty {
            // Codex keeps its records in dated directories, so the tree is walked; only a rollout name is examined.
            for root in ["sessions", "archived_sessions"].map({ codexRoot.appendingPathComponent($0) }) {
                guard (try? root.resourceValues(forKeys: [.isSymbolicLinkKey])).map({ $0.isSymbolicLink != true }) ?? false,
                      let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: []) else { continue }
                for case let file as URL in iterator {
                    try Task.checkCancellation(); visited += 1
                    guard visited <= entryLimit else { throw BridgeError("history_too_large", "The transcript lookup exceeds the discovery limit.", status: 413) }
                    guard file.pathExtension == "jsonl" else { continue }
                    let name = file.deletingPathExtension().lastPathComponent.lowercased()
                    guard name.hasPrefix("rollout-") else { continue }
                    let id = String(name.suffix(36))
                    guard ids.contains(id) else { continue }
                    try record(id, at: file, provider: "codex")
                }
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
