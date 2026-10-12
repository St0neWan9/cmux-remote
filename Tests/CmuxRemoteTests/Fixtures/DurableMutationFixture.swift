import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

actor DurableMutationFixture: CmuxControlling {
    let workspace: String
    init(workspace: String = "workspace") { self.workspace = workspace }
    var writes: [String] = []
    var failed = false
    var rejected = false
    var directory: URL?
    var loseCompletion = false
    func failWrites() { failed = true }
    func rejectSubmission() { rejected = true }
    func configure(directory: URL, loseCompletion: Bool = false) { self.directory = directory; self.loseCompletion = loseCompletion }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "chat.sessions.dump": return .object(["sessions": .array([.object(["session_id": .string("session"), "agent": .string("claude"), "workspace_id": .string(workspace), "surface_id": .string("surface"), "state": .string("idle")])])])
        case "vault.sessions": return .object(["sessions": .array([])])
        case "surface.input_state": return .object(["workspace_id": .string(workspace), "surface_id": .string("surface"), "agent": .bool(true)])
        case "feed.list": return .object(["items": .array([.object(["request_id": .string("request"), "kind": .string("permissionRequest"), "workspace_id": .string(workspace), "status": .string("pending"), "source": .string("claude")])])])
        case "mobile.chat.send", "mobile.chat.interrupt", "feed.permission.reply":
            if let directory {
                let bytes = try Data(contentsOf: directory.appendingPathComponent("mutation-receipts.ndjson"))
                let rows = try bytes.split(separator: 10).map { try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]) }
                #expect(rows.contains { $0["receipt"] == nil })
                if loseCompletion {
                    let file = directory.appendingPathComponent("mutation-receipts.ndjson")
                    try FileManager.default.moveItem(at: file, to: directory.appendingPathComponent("reserved-backup.json"))
                    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
                }
            }
            writes.append(method)
            if failed { throw BridgeError("outcome_unknown", "Lost backend reply", status: 504) }
            if rejected { return .object(["submitted": .bool(false)]) }
            return .object(["accepted": .bool(true)])
        default: return .object([:])
        }
    }
}
