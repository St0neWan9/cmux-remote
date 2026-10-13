import Foundation
import CmuxRemoteCore

/// A permission choice tied to one exact blocked Agent and terminal screen revision.
struct TuiPendingDecision: Sendable {
    let id: String
    let binding: TuiSessionSnapshot.Binding
    let generation: String
    let revision: String
    let screenRevision: String
    let screenText: String
    let allowKeys: [String]
    var payload: JSONValue {
        .object(["request_id": .string(id), "kind": .string("permissionRequest"), "status": .string("pending"), "source": .string(binding.provider), "workspace_id": .string(binding.workspaceID), "workstream_id": .string("cmux-feed-v1:" + Data(binding.provider.utf8).base64EncodedString() + ":" + Data(binding.id.utf8).base64EncodedString()),
                 "title": .string(binding.title), "body": .string(screenText), "tool_name": .string("Permission"), "tool_input": .string(screenText), "available_modes": .array([.string("once"), .string("deny")])])
    }
}
