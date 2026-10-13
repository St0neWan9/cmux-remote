import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// The naming order a phone list depends on: tab, vault, the agent's own summary, then the id.
private actor NamingCmux: CmuxControlling {
    let tabTitle: String?
    let vaultTitle: String?
    let transcript: URL
    init(tabTitle: String? = nil, vaultTitle: String? = nil, transcript: URL) {
        self.tabTitle = tabTitle; self.vaultTitle = vaultTitle; self.transcript = transcript
    }
    var tree: JSONValue {
        guard let tabTitle else { return .object(["windows": .array([])]) }
        let surface: JSONValue = .object(["id": .string("surface"), "type": .string("terminal"), "title": .string(tabTitle)])
        let pane: JSONValue = .object(["id": .string("surface"), "surfaces": .array([surface])])
        return .object(["windows": .array([.object(["workspaces": .array([.object(["id": .string("workspace"), "title": .string("Project"), "panes": .array([pane])])])])])])
    }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "system.tree": return tree
        case "vault.sessions":
            var row: [String: JSONValue] = ["session_id": .string("session"), "agent": .string("claude"), "cwd": .string("/example/project"), "file": .string(transcript.path)]
            if let vaultTitle { row["title"] = .string(vaultTitle) }
            return .object(["sessions": .array([.object(row)])])
        case "chat.sessions.dump":
            return .object(["sessions": .array([.object(["session_id": .string("session"), "agent": .string("claude"), "workspace_id": .string("workspace"),
                                                        "surface_id": .string("surface"), "state": .string("idle"), "cwd": .string("/example/project")])])])
        default: return .object([:])
        }
    }
}

@Suite struct ConversationNamingTests {
    /// Each check gets its own directory: suites run in parallel, and a shared one lets the checks overwrite each other.
    private func title(tabTitle: String? = nil, vaultTitle: String? = nil, summary: String?) async throws -> String? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("naming-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let transcript = directory.appendingPathComponent("chat.jsonl")
        var rows = [#"{"type":"user","uuid":"u","timestamp":"2026-10-13T10:00:00Z","cwd":"/example/project","message":{"content":"first prompt"}}"#]
        if let summary { rows.append(#"{"type":"ai-title","aiTitle":"\#(summary)"}"#) }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: transcript)
        let cmux = NamingCmux(tabTitle: tabTitle, vaultTitle: vaultTitle, transcript: transcript)
        let service = SessionService(cmux: cmux, home: directory, transcriptRoots: [directory])
        return try await service.sessions().first?.title
    }
    @Test func aTabNameWinsOverEverything() async throws {
        #expect(try await title(tabTitle: "Renamed tab", vaultTitle: "Agent title", summary: "Summary") == "Renamed tab")
    }
    @Test func aVaultNameOutranksTheAgentsSummary() async throws {
        #expect(try await title(vaultTitle: "Agent title", summary: "Summary") == "Agent title")
    }
    @Test func aBlankVaultNameFallsThroughToTheAgentsSummary() async throws {
        #expect(try await title(vaultTitle: "   ", summary: "Summary") == "Summary")
    }
    @Test func anUnnamedSessionUsesTheAgentsSummaryThenItsID() async throws {
        #expect(try await title(summary: "Summary") == "Summary")
        #expect(try await title(summary: nil) == "session")
    }
    @Test func aDirectoryShapedTabNameIsNotAConversationName() async throws {
        #expect(try await title(tabTitle: "/example/project", summary: "Summary") == "Summary")
    }
}
