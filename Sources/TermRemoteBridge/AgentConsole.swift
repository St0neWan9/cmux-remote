import Foundation

/// The rendered rows of one verified agent terminal and fixed input written to it, behind whichever backend owns it.
///
/// Each backend rechecks its own binding on every call, so a terminal that changed hands fails instead of
/// receiving input meant for the agent that left it.
struct AgentConsole: Sendable {
    let rows: @Sendable () async throws -> [String]
    /// Writes literal terminal input; `step` names the write so a backend can key its idempotency on it.
    let write: @Sendable (_ text: String, _ step: String) async throws -> Void
}
