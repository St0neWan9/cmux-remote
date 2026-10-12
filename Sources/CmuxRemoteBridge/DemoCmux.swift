import Foundation
import CmuxRemoteCore

/// An explicit development fixture. Never reads or writes the user's cmux sessions.
public actor DemoCmux: CmuxControlling {
    private let transcript: String
    private let project: String
    private let workspace = "11111111-1111-1111-1111-111111111111"
    private let surface = "22222222-2222-2222-2222-222222222222"
    public init(transcript: String, project: String) { self.transcript = transcript; self.project = project }
    public func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "system.ping": return .object(["pong": .bool(true)])
        case "system.capabilities": return .object(["protocol": .string("demo"), "methods": .array([])])
        case "vault.sessions": return .object(["sessions": .array([.object(["session_id": .string("demo-session"), "agent": .string("claude"), "title": .string("Review the local project"), "cwd": .string(project), "file": .string(transcript)])])])
        case "chat.sessions.dump": return .object(["sessions": .array([.object(["session_id": .string("demo-session"), "agent": .string("claude"), "workspace_id": .string(workspace), "surface_id": .string(surface), "state": .string("idle")])])])
        case "workspace.list": return .object(["workspaces": .array([.object(["id": .string(workspace), "title": .string("Demo project")])])])
        case "surface.input_state": return .object(["agent": .bool(true), "workspace_id": .string(workspace), "surface_id": .string(surface), "blocks_typing": .bool(false)])
        case "surface.read_text": return .object(["text": .string("⏺ Checking the files and preparing a summary.\nThinking… (esc to interrupt)\n❯")])
        case "feed.list": return .object(["items": .array([])])
        case "mobile.chat.send":
            let text = params["text"]?.string ?? ""
            let rows: [[String: JSONValue]] = [
                ["type": .string("user"), "uuid": .string(UUID().uuidString), "message": .object(["content": .string(text)])],
                ["type": .string("assistant"), "uuid": .string(UUID().uuidString), "message": .object(["content": .array([.object(["type": .string("text"), "text": .string("Demo reply: your prompt reached the paired Bridge. Real tasks use the existing cmux agent.")])])])]
            ]
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: transcript)); defer { try? handle.close() }; try handle.seekToEnd()
            for row in rows { var data = try JSONEncoder().encode(row); data.append(10); try handle.write(contentsOf: data) }
            return .object(["submitted": .bool(true)])
        case "mobile.chat.interrupt": return .object(["interrupted": .bool(true)])
        default: throw BridgeError("method_not_found", "The demo does not expose this operation.", status: 404)
        }
    }
}
