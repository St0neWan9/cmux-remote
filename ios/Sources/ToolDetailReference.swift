import Foundation

/// A detail request derives only from a message in the currently loaded history.
struct ToolDetailReference: Identifiable, Sendable {
    let messageID: String
    let generation: String
    let initialField: String
    var id: String { generation + ":" + messageID }
    var fields: [String] { initialField == "diff" ? ["diff"] : ["input", "output"] }
}
