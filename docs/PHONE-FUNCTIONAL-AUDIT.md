# Phone API and presentation acceptance

The user-facing scope is an independent iPhone companion for existing cmux-managed Claude/Codex sessions, with no provider runtime, cloud account, arbitrary shell endpoint or phone terminal. The local Mac mirror implementation is a separate task. This audit covers the phone's usable chat/project/Feed resources, including every published Bridge phone route, rather than treating terminal/browser/cloud administration as a phone chat feature.

## Requirements and evidence

| Requirement | Implementation | Behavioral verification |
| --- | --- | --- |
| White project sidebar, floating controls and project groups | SessionSidebarView, full-screen white presentation | Task-owned Simulator: open/close, project collapse/expand, choose session, return |
| Search, running/read-only filters and approved workspace selection | SessionFilter, scoped workspace API, SessionListView | PhoneFeatureTests; Simulator navigation |
| Status, public trust and granted capabilities | ConnectionDetailView; GET status | Signed connection tests; Simulator status refresh; no private keys shown |
| Historical messages, older pagination and replaceable preview | ConversationModel, TranscriptReader and screen extractor | TranscriptTests, ResponseTimingTests, service/revocation tests; live Claude history |
| Send, soft stop and hard interruption | Verified existing session binding, stable logical receipts; hard stop has explicit control | ServiceTests, API/client checks; live soft send/stop; hard path checked with fixture |
| Reply actions, date and recorded/estimated elapsed time | Final-record copy/share/quote, run label, cumulative sheet | ResponseTimingTests, actual-model checks, live reply actions and timing screenshot |
| File list, exact names, renames, read, per-file/full diff, copy/share | ProjectChange, ProjectModel, ProjectReference, bounded project routes | PhoneFeatureTests, file/Git policy tests, actual-model read-race/path/discovery checks; Simulator files/diff |
| Tool/thought status, input/output, exit code, tool duration, file/attachment references | History cards with bounded details and project-file navigation | Parser/timeline tests; native activity expansion and metadata presentation |
| Feed data without workspace IDs | Exact versioned/legacy workstream identity resolves against cmux's session registry | FeedBindingIntegrationTests: Feed-only grant, owned request visible/actionable, unowned/unregistered/revoked denied; authorization-await move/end/removal blocks replies |
| Permission decisions, plan modes/feedback and questions | FeedDecisionPolicy, FeedDecisionControls, FeedQuestionDraft, fixed reply verbs | FeedReplyTests: every supported mode, parameter filtering, ordered labels, partial/empty answers, duplicate option IDs, denied scope, lost receipt and concurrent/successful dedup; native fixture: partial/multiple/empty replies, custom-to-option, state replacement, confirmation cancellation, once decision and plan feedback |
| Source-specific unsupported permission modes | Mirrors public Claude/Codex decision capabilities; unknown sources limited to once/deny | PhoneFeatureTests: Codex available_decisions/amendments, no unsupported bypass |
| Pending/all Feed records and foreground refresh | FeedModel with stable card IDs, readonly receipts/history, mutation-warning retention | Actual-model checks; signed Feed tests; native fixture pending/history |
| Locale parity and Swift 6 compatibility | Exhaustive UI enum presentations, en/zh-Hans strings | scripts/check-localization.py, plutil string lint, scripts/build-ios.sh |

The native acceptance column is completed only by actual runtime inspection, not by compiling a view. Private receipts and screenshots remain outside Git; the final handoff names the checks which actually executed.

## Available routes and transport limits

The phone exposes `status`, `workspaces`, `sessions`, `history`, `preview`, `send`, `interrupt`, `feed`, `feed/:request/reply`, `changes`, `diff`, and `file`. The client signs v2 paths while using the same version-independent domain resources. Authorization and resource/path constraints remain server-side, independent of UI visibility.

Installed official cmux was probed through its permitted local CLI ancestry with empty parameters (no image, terminal input or user data):

- `mobile.chat.history`: `method_not_found`; the Bridge's bounded transcript parser remains the history source.
- `mobile.chat.artifact.fetch`: `method_not_found`; history attachment metadata is displayed, while supported project references use the constrained file route.
- `terminal.paste_image`: `method_not_found`, despite its name appearing in the capability inventory. No enabled phone upload control promises this unavailable local operation.
- `mobile.panel.artifact.thumbnail`: reaches a handler and returns `invalid_params` without a panel. This API addresses non-terminal preview panels; it is not a chat-session image fetch route.

Capability enumeration alone is not proof of local call availability. Mobile data-plane RPCs requiring cmux's own paired transport are not assumed callable through its ordinary local socket. The companion does not simulate successful image upload/download or enable cloud/mobile pairing to gain those operations.

## Acceptance boundaries

The CLI and phone model/route tests cover all implemented resources and the critical scope, replay, stale binding, path, partial-history, receipt and form-state edges. Native tests additionally inspect actual white presentation, navigation, controls and keyboard paths. Physical camera scanning, hardware Keychain and Wi-Fi/GPU/touch behavior must be recorded separately when an actual phone is available; a Simulator build cannot establish those hardware results.

## Isolated native fixture

Run `swift build --jobs 6`, then `python3 scripts/build-phone-ui-fixture.py`. Start `.build/phone-ui-fixture <private-state-directory>` on loopback port 7745. Its only mutations update in-memory fixture decisions or its private fixture transcript; it never calls the real cmux socket or starts an agent. The setup creates a small dedicated Git repository for file/diff checks.

Install the Simulator app on a separate task-owned device. Launch it with `SIMCTL_CHILD_CMUX_REMOTE_TEST_PAIRING_PATH=<private-state-directory>/phone.json` via simctl; the DEBUG fixture path contains only this local fixture's credentials. Do not print or publish that file. This explicit development-only legacy path does not replace the primary Simulator's live v2 pairing. Native acceptance checks include new-question state reset after partial submission, duplicate labels, multi-select/custom switching, no-option empty submission, extended-decision cancellation, one-off permission, plan feedback, error history, file/diff and pairing fallback.
