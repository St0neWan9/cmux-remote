import Foundation
import Testing
import CmuxRemoteCore

@Suite struct PhoneFeatureTests {
    @Test func searchAndFiltersPreserveWorkspaceAndHistoryBoundaries() {
        let live = SessionDescriptor(id: "a", agent: "claude", title: "Repair café", cwd: "/projects/cmux", workspaceID: "ABC", surfaceID: "s", state: "working")
        let ended = SessionDescriptor(id: "b", agent: "codex", title: "History", cwd: nil, state: "ended")
        #expect(SessionFilter.all.matches(live, query: "CAFE", workspaceID: "abc"))
        #expect(!SessionFilter.all.matches(live, query: "", workspaceID: "other"))
        #expect(SessionFilter.working.matches(live, query: "cmux", workspaceID: nil))
        #expect(!SessionFilter.working.matches(ended, query: "", workspaceID: nil))
        #expect(SessionFilter.readOnly.matches(ended, query: "codex", workspaceID: nil))
        #expect(!SessionFilter.readOnly.matches(live, query: "", workspaceID: nil))
        // An idle Agent whose terminal is still bound can be talked to, so it is Running, not history.
        let idle = SessionDescriptor(id: "c", agent: "claude", title: "Waiting", cwd: "/projects/cmux", workspaceID: "ABC", surfaceID: "s", state: "idle")
        #expect(SessionFilter.working.matches(idle, query: "", workspaceID: nil))
        #expect(!SessionFilter.readOnly.matches(idle, query: "", workspaceID: nil))
    }
    @Test func questionsSwitchBetweenCustomAndOrderedMultiSelect() {
        var draft = FeedQuestionDraft()
        draft.typeCustom("My answer")
        draft.choose("B", multi: true); draft.choose("A", multi: true)
        #expect(draft.answer(options: ["A", "B", "C"].map { FeedQuestionOption(id: $0, label: $0) }) == "A, B")
        draft.choose("A", multi: true)
        #expect(draft.answer(options: ["A", "B"].map { FeedQuestionOption(id: $0, label: $0) }) == "B")
        draft.typeCustom("  ")
        #expect(draft.answer(options: ["A", "B"].map { FeedQuestionOption(id: $0, label: $0) }) == nil)
        draft.choose("A", multi: false)
        #expect(draft.answer(options: ["A", "B"].map { FeedQuestionOption(id: $0, label: $0) }) == "A")
        draft.typeCustom("  自定义答案  ")
        #expect(draft.answer(options: ["A", "B"].map { FeedQuestionOption(id: $0, label: $0) }) == "自定义答案")
    }
    @Test func stableFeedIdentitySurvivesRemovalOfAnotherCard() {
        let first = FeedEntry(value: .object(["id": .string("first")]), fallbackIndex: 0)
        let second = FeedEntry(value: .object(["request_id": .string("second")]), fallbackIndex: 1)
        let shifted = FeedEntry(value: second.value, fallbackIndex: 0)
        #expect(first.id != second.id)
        #expect(second.id == shifted.id)
    }
    @Test func equalLabelsDoNotBecomeTwoSelections() {
        var draft = FeedQuestionDraft(); draft.choose("first", multi: false)
        #expect(draft.answer(options: [FeedQuestionOption(id: "first", label: "Same"), FeedQuestionOption(id: "second", label: "Same")]) == "Same")
    }
    @Test func porcelainPathsPreserveRenameSpaceAndNewline() {
        let entries: [JSONValue] = [.string(" M file with spaces.txt"), .string("R  new name.txt"), .string("old name.txt"), .string("?? name\nwith newline"), .string("invalid")]
        let changes = ProjectChange.parse(entries: entries)
        #expect(changes.map(\.path) == ["file with spaces.txt", "new name.txt", "name\nwith newline"])
        #expect(changes[1].previousPath == "old name.txt")
    }
    @Test func referencesNeverConvertOutsideProjectToARemotePath() {
        let policy = ProjectReference()
        #expect(policy.relativePath("src/file.swift", root: "/project") == "src/file.swift")
        #expect(policy.relativePath("/project/src/file.swift", root: "/project") == "src/file.swift")
        #expect(policy.relativePath("../secret", root: "/project") == nil)
        #expect(policy.relativePath("/project-other/file", root: "/project") == nil)
        #expect(policy.relativePath("/tmp/image.png", root: "/project") == nil)
        #expect(policy.relativePath("/file", root: "/") == nil)
    }
    @Test func feedBindingUsesExactRegisteredIdentityNotCwdOrTitle() {
        let session = SessionDescriptor(id: "session-with-hyphens", agent: "claude", title: "Same title", cwd: "/same/path", workspaceID: "ABC", surfaceID: "surface")
        let versioned = "cmux-feed-v1:" + Data("claude".utf8).base64EncodedString() + ":" + Data(session.id.utf8).base64EncodedString()
        let policy = FeedWorkspaceBinding()
        #expect(policy.workspace(for: .object(["workstream_id": .string(versioned)]), sessions: [session]) == "abc")
        #expect(policy.workspace(for: .object(["workstream_id": .string("claude-" + session.id)]), sessions: [session]) == "abc")
        #expect(policy.workspace(for: .object(["workstream_id": .string(versioned), "workspace_id": .string("other")]), sessions: [session]) == nil)
        #expect(policy.workspace(for: .object(["workstream_id": .string("claude-unrelated"), "cwd": .string("/same/path"), "title": .string("Same title")]), sessions: [session]) == nil)
        #expect(policy.workspace(for: .object(["workstream_id": .string("cmux-feed-v1:bad:bad")]), sessions: [session]) == nil)
        let conflict = SessionDescriptor(id: session.id, agent: session.agent, title: "Other", cwd: nil, workspaceID: "other", surfaceID: "other")
        #expect(policy.workspace(for: .object(["workstream_id": .string(versioned)]), sessions: [session, conflict]) == nil)
    }
    @Test func codexOnlyOffersDecisionsItCanDeliver() throws {
        let policy = FeedDecisionPolicy()
        let caps = #"{"app_server_method":"item/commandExecution/requestApproval","available_decisions":["accept","decline"]}"#
        let item: JSONValue = .object(["kind": .string("permissionRequest"), "source": .string("codex"), "tool_input_capabilities": .string(caps)])
        #expect(policy.modes(for: item) == [.once, .deny])
        let amend = #"{"app_server_method":"item/commandExecution/requestApproval","available_decisions":["acceptForSession","acceptWithExecpolicyAmendment"],"proposed_execpolicy_amendment":true}"#
        let extended: JSONValue = .object(["kind": .string("permissionRequest"), "source": .string("codex"), "tool_input_capabilities": .string(amend)])
        #expect(policy.modes(for: extended) == [.always, .all, .deny])
        #expect(policy.modes(for: .object(["kind": .string("permissionRequest"), "source": .string("claude")])) == [.once, .always, .all, .deny])
        #expect(policy.modes(for: .object(["kind": .string("permissionRequest"), "source": .string("unknown")])) == [.once, .deny])
        #expect(!FeedDecisionMode.bypass.supports(kind: "exitPlan"))
        #expect(!FeedDecisionMode.manual.supports(kind: "permissionRequest"))
    }
}
