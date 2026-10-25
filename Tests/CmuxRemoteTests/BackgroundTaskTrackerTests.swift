import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// A background launch returns a task id at once; completion arrives later as a `<task-notification>`
/// that names the originating tool call. Pairing them is what makes "still running" knowable.
@Suite struct BackgroundTaskTrackerTests {
    private func launch(id: String, tool: String = "Bash", description: String? = nil, command: String? = nil) -> String {
        var input: [String: Any] = ["run_in_background": true]
        if let description { input["description"] = description }
        if let command { input["command"] = command }
        let row: [String: Any] = ["type": "assistant", "message": ["content": [["type": "tool_use", "id": id, "name": tool, "input": input]]]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: row), as: UTF8.self)
    }
    private func completion(toolUseID: String, status: String = "completed") -> String {
        let block = "<task-notification>\n<task-id>t1</task-id>\n<tool-use-id>\(toolUseID)</tool-use-id>\n<status>\(status)</status>\n<summary>done</summary>\n</task-notification>"
        let row: [String: Any] = ["type": "queue-operation", "content": block]
        return String(decoding: try! JSONSerialization.data(withJSONObject: row), as: UTF8.self)
    }
    @Test func aLaunchWithNoCompletionIsRunning() {
        let tasks = BackgroundTaskTracker().running(in: [launch(id: "toolu_a", description: "Wait for the build")], at: Date())
        #expect(tasks.count == 1)
        #expect(tasks.first?.id == "toolu_a")
        #expect(tasks.first?.tool == "Bash")
        #expect(tasks.first?.summary == "Wait for the build")
    }
    @Test func aCompletedTaskIsNoLongerRunning() {
        let rows = [launch(id: "toolu_a", description: "Wait for the build"), completion(toolUseID: "toolu_a")]
        #expect(BackgroundTaskTracker().running(in: rows, at: Date()).isEmpty)
    }
    @Test func onlyTheCompletedTaskLeaves() {
        let rows = [launch(id: "toolu_a", description: "First"), launch(id: "toolu_b", description: "Second"), completion(toolUseID: "toolu_a")]
        let tasks = BackgroundTaskTracker().running(in: rows, at: Date())
        #expect(tasks.map(\.id) == ["toolu_b"])
    }
    @Test func everyDetachingToolIsTracked() {
        let rows = [launch(id: "1", tool: "Bash", description: "b"), launch(id: "2", tool: "Monitor", description: "m"),
                    launch(id: "3", tool: "Agent", description: "a"), launch(id: "4", tool: "Workflow", description: "w")]
        #expect(BackgroundTaskTracker().running(in: rows, at: Date()).map(\.tool) == ["Bash", "Monitor", "Agent", "Workflow"])
    }
    /// Claude Code starts every subagent asynchronously and its input carries no flag; only the launch
    /// result says so. A subagent that ran inline returns its answer instead and is never listed.
    @Test func anAsyncSubagentIsTrackedFromItsLaunchResult() {
        func agentCall(_ id: String) -> String {
            let row: [String: Any] = ["type": "assistant", "message": ["content": [["type": "tool_use", "id": id, "name": "Agent",
                "input": ["description": "Add a log page", "prompt": "…", "subagent_type": "general-purpose"]]]]]
            return String(decoding: try! JSONSerialization.data(withJSONObject: row), as: UTF8.self)
        }
        func result(_ id: String, _ text: String) -> String {
            let row: [String: Any] = ["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": id, "content": [["type": "text", "text": text]]]]]]
            return String(decoding: try! JSONSerialization.data(withJSONObject: row), as: UTF8.self)
        }
        let rows = [agentCall("toolu_async"), result("toolu_async", "Async agent launched successfully. agentId: a2868 (internal ID)"),
                    agentCall("toolu_inline"), result("toolu_inline", "The answer is 42.")]
        let tasks = BackgroundTaskTracker().running(in: rows, at: Date())
        #expect(tasks.map(\.id) == ["toolu_async"])
        #expect(tasks.first?.summary == "Add a log page")
        // Its completion notice names the call, as for any other background task.
        #expect(BackgroundTaskTracker().running(in: rows + [completion(toolUseID: "toolu_async")], at: Date()).isEmpty)
    }

    /// A request payload copy replays rows already folded in; re-reading a launch whose completion came later
    /// would revive a finished task, which is what kept a finished command on the phone.
    @Test func aReplayedRequestBlobDoesNotReviveAFinishedTask() {
        let rows = [launch(id: "toolu_b"), completion(toolUseID: "toolu_b")]
        #expect(BackgroundTaskTracker().running(in: rows, at: Date()).isEmpty)
        let replay = try! String(decoding: JSONSerialization.data(withJSONObject: ["type": "api-request-blob", "message": ["content": [["type": "tool_use", "id": "toolu_b", "name": "Bash", "input": ["run_in_background": true]]]]]), as: UTF8.self)
        #expect(BackgroundTaskTracker().running(in: rows + [replay], at: Date()).isEmpty)
    }

    /// `Monitor` and `Workflow` always detach: their input carries no `run_in_background`, so waiting
    /// for that flag would miss every one of them. Read from a real session's own Monitor calls.
    @Test func aMonitorCallIsDetachedWithoutAnyFlag() {
        let row: [String: Any] = ["type": "assistant", "message": ["content": [["type": "tool_use", "id": "toolu_m", "name": "Monitor",
            "input": ["command": "until grep -q ready build.log; do sleep 2; done", "description": "wait for the build", "timeout_ms": 1_800_000]]]]]
        let line = String(decoding: try! JSONSerialization.data(withJSONObject: row), as: UTF8.self)
        let tasks = BackgroundTaskTracker().running(in: [line], at: Date())
        #expect(tasks.count == 1)
        #expect(tasks.first?.tool == "Monitor")
        #expect(tasks.first?.summary == "wait for the build")
    }
    @Test func aWorkflowCallIsDetachedWithoutAnyFlag() {
        let row: [String: Any] = ["type": "assistant", "message": ["content": [["type": "tool_use", "id": "toolu_w", "name": "Workflow",
            "input": ["name": "review-changes", "description": "Review the diff"]]]]]
        let line = String(decoding: try! JSONSerialization.data(withJSONObject: row), as: UTF8.self)
        #expect(BackgroundTaskTracker().running(in: [line], at: Date()).map(\.tool) == ["Workflow"])
    }
    /// A foreground call of the same tool ends with its own turn, so it is not a detached task.
    @Test func aForegroundCallIsNotTracked() {
        let row: [String: Any] = ["type": "assistant", "message": ["content": [["type": "tool_use", "id": "toolu_f", "name": "Bash", "input": ["command": "ls"]]]]]
        let line = String(decoding: try! JSONSerialization.data(withJSONObject: row), as: UTF8.self)
        #expect(BackgroundTaskTracker().running(in: [line], at: Date()).isEmpty)
    }
    /// A command with no description names the task by its first line, bounded.
    @Test func aLongCommandBecomesABoundedFirstLine() {
        let long = String(repeating: "x", count: 400) + "\nsecond line"
        let tasks = BackgroundTaskTracker().running(in: [launch(id: "toolu_c", command: long)], at: Date())
        #expect(tasks.first?.summary.count == 118)
        #expect(tasks.first?.summary.hasSuffix("…") == true)
    }
    /// A completion notice reaches the record in more than one shape; every one must pair.
    @Test func everyNoticeShapeCompletesTheTask() {
        let attachment: [String: Any] = ["type": "attachment", "attachment": ["type": "queued_command", "prompt": "<task-notification><tool-use-id>toolu_a</tool-use-id><status>completed</status></task-notification>"]]
        let attachmentLine = String(decoding: try! JSONSerialization.data(withJSONObject: attachment), as: UTF8.self)
        #expect(BackgroundTaskTracker().running(in: [launch(id: "toolu_a", description: "Task"), attachmentLine], at: Date()).isEmpty)
        let result: [String: Any] = ["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": "toolu_x", "content": "<task-notification><tool-use-id>toolu_b</tool-use-id><status>completed</status></task-notification>"]]]]
        let resultLine = String(decoding: try! JSONSerialization.data(withJSONObject: result), as: UTF8.self)
        #expect(BackgroundTaskTracker().running(in: [launch(id: "toolu_b", description: "Task"), resultLine], at: Date()).isEmpty)
    }
    /// `TaskStop` ends a task; it never starts one.
    @Test func taskStopIsNotALaunch() {
        let row: [String: Any] = ["type": "assistant", "message": ["content": [["type": "tool_use", "id": "toolu_s", "name": "TaskStop", "input": ["task_id": "x", "run_in_background": true]]]]]
        let line = String(decoding: try! JSONSerialization.data(withJSONObject: row), as: UTF8.self)
        #expect(BackgroundTaskTracker().running(in: [line], at: Date()).isEmpty)
    }
    @Test func malformedAndUnrelatedRowsAreIgnored() {
        #expect(BackgroundTaskTracker().running(in: ["not json", "{\"type\":\"user\"}", ""], at: Date()).isEmpty)
    }
}
