import Foundation
import CmuxRemoteCore

/// A pending choice tied to one exact blocked Agent and terminal screen revision.
///
/// A permission dialog offers fixed modes; a plain "press enter to continue" dialog offers one key and its
/// escape. Both carry the keys to send so the adapter never derives them from the request text.
struct TuiPendingDecision: Sendable {
    /// How the phone presents the choice: a permission decision with modes, or a question with choices.
    enum Kind: String, Sendable {
        case permissionRequest
        case question
    }
    let id: String
    let binding: TuiSessionSnapshot.Binding
    let generation: String
    let revision: String
    let screenRevision: String
    let screenText: String
    /// A permission choice maps modes to these keys; the first key continues and escape cancels.
    let allowKeys: [String]
    /// Told apart from a permission so the phone can show the dialog's own words rather than a permission card.
    let kind: Kind
    /// The options a question-shaped dialog offers, as (label, key) pairs in display order.
    let choices: [(label: String, key: String)]
    init(id: String, binding: TuiSessionSnapshot.Binding, generation: String, revision: String, screenRevision: String,
         screenText: String, allowKeys: [String], kind: Kind = .permissionRequest, choices: [(label: String, key: String)] = []) {
        self.id = id; self.binding = binding; self.generation = generation; self.revision = revision
        self.screenRevision = screenRevision; self.screenText = screenText; self.allowKeys = allowKeys
        self.kind = kind; self.choices = choices
    }
    var payload: JSONValue {
        let workstream = "cmux-feed-v1:" + Data(binding.provider.utf8).base64EncodedString() + ":" + Data(binding.id.utf8).base64EncodedString()
        switch kind {
        case .permissionRequest:
            return .object(["request_id": .string(id), "kind": .string(kind.rawValue), "status": .string("pending"), "source": .string(binding.provider),
                            "workspace_id": .string(binding.workspaceID), "workstream_id": .string(workstream), "title": .string(binding.title),
                            "body": .string(screenText), "tool_name": .string("Permission"), "tool_input": .string(screenText),
                            "available_modes": .array([.string("once"), .string("deny")])])
        case .question:
            // One question whose options are the dialog's own choices; the phone reuses its question form.
            let options: [JSONValue] = choices.map { .object(["id": .string($0.key), "label": .string($0.label)]) }
            // The dialog has two answers and no others: a free-text reply is not one of them, and skipping would
            // send the Agent nothing while it waits, so both are withheld from the form.
            let question: JSONValue = .object(["id": .string("continue"), "prompt": .string("终端正在等待你的选择"), "multi_select": .bool(false),
                                               "allow_custom": .bool(false), "allow_skip": .bool(false), "options": .array(options)])
            return .object(["request_id": .string(id), "kind": .string(kind.rawValue), "status": .string("pending"), "source": .string(binding.provider),
                            "workspace_id": .string(binding.workspaceID), "workstream_id": .string(workstream), "title": .string(binding.title),
                            "body": .string(screenText), "questions": .array([question])])
        }
    }
}
