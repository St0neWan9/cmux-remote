# cmux-remote design

This document describes the companion architecture. The implemented unified connection layer is specified in [Connection v2](CONNECTION-V2.md). The development Mac sidebar/snapshot-mirror implementation is described in [the Mac guide](MAC-EXTENSION.md); live acceptance and remaining continuity work are tracked in [the unified connection plan](UNIFIED-CONNECTION-PLAN.md).

## Scope

One repository contains a Swift Mac CLI/Bridge, shared wire models, a Swift client, and a native SwiftUI iPhone app. The first backend is the installed official cmux Mac app. The phone and Mac are on a reachable LAN. No cloud account, public relay, provider API integration, terminal emulator on the phone, or modification of cmux is required.

The Bridge reads local transcript/project data to fill holes in the official local API. This is distinct from claiming that every value is available over cmux's socket. It never starts a second agent runtime. Provider-format support is pinned and tested.

## Boundaries and layout

`CmuxRemoteCore` contains Sendable Codable DTOs, JSON values and pure policies. It reuses the pinned `CmuxAgentChat` parsing/model library. `CmuxRemoteBridge` owns socket I/O, the local session registry, transcript reads, constrained project file access, Git queries and TLS HTTP serving. `CmuxRemoteClient` owns HTTPS, certificate pinning and response decoding. `CmuxRemoteCLI` is the composition root. `ios/` owns observable app state and SwiftUI screens.

Dependencies form a DAG: executable/server/client/UI -> Core -> upstream parsing/model code. No AppKit or Ghostty dependency enters the phone. The HTTP API is language-neutral; future backends implement the same domain operations with explicit capability differences.

Mac mirrors keep a local ownership registry for their projected surface IDs and
remote producer epochs. A bounded metadata watcher reconciles source split/tab
changes through fixed local `surface.move`, `surface.split_off`, `surface.reorder`,
creation and close operations. It preserves existing viewer processes and never
issues remote structural mutations. Local membership changes and unknown write
outcomes pause the transaction for inspection; no blind layout retry occurs.
Detached producer records are retained only for owned projection cleanup and
cannot receive input. Manual detach pauses updates; a disappeared source may be
removed from the mirror, while a replaced source requires explicit attachment.

The requested Mac navigation preserves the official native sidebar and adds a
native Remote group below local workspaces. It uses local workspace-group APIs;
ExtensionKit replacement sidebars are not the product integration. Default Mac
builds no longer embed that prototype. Native rows use cmux's own styling and
interaction handlers. Scoped metadata creates pending native rows using a fixed
local viewer command. A bounded private owner-channel wait observes native
selection; selection then rechecks the saved grant and local binding before
attaching into that same workspace. Inventory refresh never reads terminal
contents or changes focus. Creation and attachment intents are persisted before
native mutations; unknown results pause without blind retries. Completed
attachments persist bounded owner-only topology/producer metadata without
credentials or terminal content. Restart recovery verifies fresh host authority,
local membership and producer epochs before publishing the same view IDs.
A partial layout transaction removes its recovery checkpoint before writes;
unknown outcomes are not automatically resumed.

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

The event monitor reconnects its dedicated cmux connection with bounded backoff.
It invalidates hook-derived writable bindings on disconnect, refreshes snapshots,
and resumes from a private boot/sequence cursor. Boot changes and replay gaps
clear that cursor and require a fresh snapshot. Cursor persistence follows event
acceptance; no event bodies or credentials enter the cursor file. A cold
subscription refreshes after acknowledgement to cover its snapshot/subscription
boundary. Phone history polling remains independent; bounded phone subscriptions
and their own cursors are still follow-up work.

## Writes and idempotency

The phone generates one operation UUID per logical send, interrupt or decision. Chat, Feed and terminal input share a durable owner-only mutation ledger keyed by approved device identity and operation UUID. Before backend execution, the Bridge appends and flushes an intent containing only a canonical payload digest, target workspace and required capability. Confirmation appends and flushes its receipt. Restart reloads completed receipts; unfinished or outcome-unknown intents remain unknown and are never executed again under the same key. Reading a cached receipt still rechecks current scope/revocation. Different payloads under the same device/operation key are rejected.

The journal is bounded to 16,384 operation keys and 16 MiB, with no automatic eviction that would make old mutations executable again. Full, corrupted, truncated or unavailable storage stops writes. Prompts, terminal input and credentials are not stored in it. No automatic POST retry is added. This is durable protection against repeated attempts, not an atomic exactly-once transaction with cmux or proof that an Agent processed input. Explicit negative backend acknowledgements remain unknown; a lost completion write also retains an unknown intent. Old versions' in-memory receipts cannot be reconstructed by this implementation.

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
