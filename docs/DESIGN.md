# cmux-remote design

This document describes the companion architecture. The implemented unified connection layer is specified in [Connection v2](CONNECTION-V2.md). Remaining continuity and mirror feasibility work are tracked in [the unified connection plan](UNIFIED-CONNECTION-PLAN.md).

## Scope

One repository contains a Swift Mac CLI/Bridge, shared wire models, a Swift client, and a native SwiftUI iPhone app. The first backend is the installed official cmux Mac app. The phone and Mac are on a reachable LAN. No cloud account, public relay, provider API integration, terminal emulator on the phone, or modification of cmux is required.

The Bridge reads local transcript/project data to fill holes in the official local API. This is distinct from claiming that every value is available over cmux's socket. It never starts a second agent runtime. Provider-format support is pinned and tested.

## Boundaries and layout

`CmuxRemoteCore` contains Sendable Codable DTOs, JSON values and pure policies. It reuses the pinned `CmuxAgentChat` parsing/model library. `CmuxRemoteBridge` owns socket I/O, the local session registry, transcript reads, constrained project file access, Git queries and TLS HTTP serving. `CmuxRemoteClient` owns HTTPS, certificate pinning and response decoding. `CmuxRemoteCLI` is the composition root. `ios/` owns observable app state and SwiftUI screens.

Dependencies form a DAG: executable/server/client/UI -> Core -> upstream parsing/model code. No AppKit or Ghostty dependency enters the phone. The HTTP API is language-neutral; future backends implement the same domain operations with explicit capability differences.

## Pairing and authority

The Bridge maintains a persistent Ed25519 host identity and separately enrolled device identities. Version 2 QR codes bind an expiring enrollment window to the host public key, exact TLS certificate fingerprint, endpoint and owner-selected workspace IDs; they do not contain a permanent shared credential. Device requests prove possession of their key and need the Mac owner's explicit approval. Signed grants are persisted in an owner-only host registry. Each request proves its identity, exact content, nonce and fresh server epoch; scope and revocation are checked at the resource and final binding boundaries. See [Connection v2](CONNECTION-V2.md) for the cryptographic/wire contract and migration.

Bonjour is reachability metadata, not trust. The iPhone saves device-only Keychain identity and host trust, restores grants, and can relocate a known host after verifying the unchanged identity and TLS pin. Certificate changes require explicit enrollment; there is no unverified renewal shortcut. The local admin Unix socket is separate from HTTPS and owns approval/revocation. Legacy shared-token routes require an explicit `--legacy` opt-in.

There is no generic remote cmux RPC proxy. No browsing operation selects or focuses a desktop workspace. Official CLI requests keep prompt data in private stdin. Under `cmuxOnly`, launch the Bridge inside a cmux terminal; using the bundled CLI does not bypass process ancestry checks. The Bridge never enables `allowAll`.

## Session discovery

List only sessions with cmux provenance: an explicit workspace/surface binding from the local `chat.sessions.dump` registry or an authoritative `agent` hook event. `vault.sessions` also contains conversations started outside cmux; use it only to enrich already identified cmux sessions with titles, history and file locations. Matching cwd, title or chronological proximity does not establish provenance. If the diagnostic method is unavailable and no hook binding was observed, show an empty list rather than global history. Known cmux sessions that ended remain read-only; the app does not launch or resume historical agents. cmux restart/rebind invalidates cached bindings; actions verify that the exact workspace/surface still exists and runs an agent.

The registry excludes unsupported providers and files outside configured transcript roots. The first list is bounded by the underlying Vault API; the response reports this discovery limit. Reading a historical session never creates or resumes an agent.

## History and live preview

Read complete JSONL lines only, retaining an unfinished trailing fragment. Reuse upstream Claude/Codex parsing, including tool-use/result updates and artifact references. Final messages replace matching IDs rather than append duplicates. An inode change or truncation creates a new transcript generation and tells clients to re-anchor. History pages preserve equal-sequence groups and report clipping limits honestly. Large input is capped; no endpoint silently promises infinite history.

The local socket cannot supply official `chat.message` streaming previews. For an open, verified live session, the Bridge reads `surface.read_text` and applies upstream `AgentChatProseScreenExtractor`. It emits a replaceable preview, not token deltas. A missing anchor produces no preview; a terminal/UI change can reduce fidelity. The committed transcript is authoritative. The phone's initial implementation refreshes snapshots on a bounded foreground cadence, so response growth appears without terminal rendering. This polling is a compatibility mechanism for a missing subscription API, is cancellable on navigation/background, and is never a synchronization sleep inside a request.

`events.stream` uses a separate cmux connection from ordinary RPC. Its boot ID and sequence support reconnect/catch-up. Redacted event payloads trigger snapshot reads; they do not replace chat history. Slow-consumer/replay gaps trigger resynchronization. Do not route chat/project bodies into cmux's telemetry log.

The first event monitor retains explicit live bindings while connected; a dropped stream falls back to diagnostic/snapshot discovery until Bridge restart. Automatic reconnect and durable event cursors remain follow-up work. Phone history polling continues independently of this monitor.

## Writes and idempotency

The phone generates one operation UUID per logical send, interrupt or decision. Production `serve` persists digest-only scoped mutation records in owner-only host state under its run lease. Preparation is flushed before dispatch; a confirmed receipt is saved afterward. Successful and unresolved operations survive Bridge restart. It never blindly retries a cmux mutation after disconnect/timeout: a lost response may follow a successful action. The response reports `outcome_unknown`; the UI asks the user to inspect the conversation before sending again. Current device/workspace/capability authorization protects receipt reads and replay. A failed or corrupted journal prevents dispatch, and bounded capacity never evicts an unresolved record. This cannot establish exactly-once execution across the external cmux boundary. See [API.md](API.md) for limits and status queries; phone recovery UI remains in progress.

Feed replies require a currently pending matching request and its supported kind. Ordinary Codex hook telemetry cannot be upgraded into an actionable approval by the Bridge. Unsupported actions remain visibly unsupported; numeric-key answering is not presented as a reliable generic approval adapter.

## Files and changes

Files are read from an explicitly known session project root. Canonical path containment is checked after resolving symlinks; traversal, directories, special files, hidden credential stores, oversized reads and projects rooted at a user's home directory are denied. The route accepts a relative path, never an arbitrary host path. Artifacts outside the root are not exported automatically.

Run Git directly with argument arrays, no shell interpolation, and use `--` for paths. Git execution disables external diff and textconv; responses are bounded. Return changed file metadata and unified diff. The first implementation shows text file previews; media galleries/Quick Look remain an extension. Transcript-derived file edits remain visible as chat cards independently of current Git state.

## API and phone UX

Signed, scoped HTTPS `/v2` endpoints return structured resources and stable errors. Pairing -> sessions -> conversation. Conversation shows prose/Markdown, collapsed tool/thought cards, file-edit diffs, live preview, composer, stop, and links to project changes. A separate pending-actions list renders supported questions, permission and plan decisions. Home refresh and reconnect do not change desktop focus. The phone uses native NavigationStack, a selectable scrollable conversation, trailing user bubbles, full-width agent Markdown, collapsed activity groups, a latest-message jump button and a floating send/stop composer. Files and Feed actions remain in native menus. English/Simplified Chinese strings are localized.

HIG references: https://developer.apple.com/design/human-interface-guidelines/navigation-and-search and https://developer.apple.com/design/human-interface-guidelines/text-fields. The web retrieval returned JavaScript-only pages in this environment; native components are used conservatively and a visual/device pass is required before distribution.

## Delivery milestones

1. Pin upstream provenance, define wire schema, document capabilities and authority.
2. Implement authenticated TLS server, socket client, history discovery/parsing, actions, project reads and Git.
3. Implement paired native iPhone app and localized chat/action/file views in the same repository.
4. Exercise synthetic socket + HTTP + phone client integration, adversarial path/pinning/idempotency/history tests, and compile the Simulator app.
5. Verify a real official cmux instance and a physical phone when available; disclose exact missing gates. No official cmux process is restarted or changed for this verification.

In progress: image selection/history preview, event-driven phone updates and receipt recovery UI, tracked by [PHONE-COMPLETION-PLAN.md](PHONE-COMPLETION-PLAN.md). Physical-phone camera/network handoff, Windows/Linux backend adapters, Developer ID signing/notarization and release installers need their own acceptance. The [unified connection plan](UNIFIED-CONNECTION-PLAN.md) sequences shared discovery/enrollment and the proposed Mac mirror feasibility gate. None is reported complete merely because its interface is documented.
