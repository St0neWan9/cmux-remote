# cmux-remote design

## Scope

One repository contains a Swift Mac CLI/Bridge, shared wire models, a Swift client, and a native SwiftUI iPhone app. The first backend is the installed official cmux Mac app. The phone and Mac are on a reachable LAN. No cloud account, public relay, provider API integration, terminal emulator on the phone, or modification of cmux is required.

The Bridge reads local transcript/project data to fill holes in the official local API. This is distinct from claiming that every value is available over cmux's socket. It never starts a second agent runtime. Provider-format support is pinned and tested.

## Boundaries and layout

`CmuxRemoteCore` contains Sendable Codable DTOs, JSON values and pure policies. It reuses the pinned `CmuxAgentChat` parsing/model library. `CmuxRemoteBridge` owns socket I/O, the local session registry, transcript reads, constrained project file access, Git queries and TLS HTTP serving. `CmuxRemoteClient` owns HTTPS, certificate pinning and response decoding. `CmuxRemoteCLI` is the composition root. `ios/` owns observable app state and SwiftUI screens.

Dependencies form a DAG: executable/server/client/UI -> Core -> upstream parsing/model code. No AppKit or Ghostty dependency enters the phone. The HTTP API is language-neutral; future backends implement the same domain operations with explicit capability differences.

## Pairing and authority

The Bridge initializes a 256-bit random credential and self-signed certificate in an owner-only state directory outside the checkout. A local `pairing` command emits host, port, credential and SHA-256 certificate fingerprint only when explicitly invoked. The phone accepts HTTPS only and stores its pairing in Keychain. The URLSession delegate accepts only the exact pinned certificate for the configured endpoint. A changed certificate requires pairing again; it never silently falls back to trusting an arbitrary certificate. TLS keys, bearer credentials and project content never enter logs or the repository.

All `/v1` routes require the bearer credential. There is no generic remote `rpc(method, params)` endpoint. Routes invoke a fixed list of cmux operations, with explicit IDs and fresh binding checks before terminal writes. No focus/selection RPC is used when browsing a task. Requests prefer the installed official CLI's `rpc` command, with JSON in private stdin, so cmux retains its own capability/password handling. A raw Unix transport is an explicit fallback. The separate raw event connection may be denied under a restrictive policy and then the Bridge relies on snapshots. The Bridge never enables `allowAll` itself.

Initial pairing uses a single device credential encoded in a versioned QR link with endpoint and certificate pin. The CLI picks a private LAN address; the phone validates and connects immediately after scanning. Manual fields remain under advanced settings. Per-device revocation and expiring enrollment tickets are future protocol extensions; `init --rotate` is not implemented and must not overwrite existing state implicitly. Access is the authority of the logged-in Mac user; network access still requires the separate Bridge credential.

## Session discovery

Use `vault.sessions` for known history and file locations. Reconcile the optional local `chat.sessions.dump` diagnostic snapshot and authoritative `agent` hook events for session/workspace/surface bindings. A missing/unsupported diagnostic method is normal. Never infer writable identity solely from cwd, title or chronological proximity. Ended/unbound sessions remain readable but cannot receive input. cmux restart/rebind invalidates cached bindings; actions verify that the exact workspace/surface still exists and runs an agent.

The registry excludes unsupported providers and files outside configured transcript roots. The first list is bounded by the underlying Vault API; the response reports this discovery limit. Reading a historical session never creates or resumes an agent.

## History and live preview

Read complete JSONL lines only, retaining an unfinished trailing fragment. Reuse upstream Claude/Codex parsing, including tool-use/result updates and artifact references. Final messages replace matching IDs rather than append duplicates. An inode change or truncation creates a new transcript generation and tells clients to re-anchor. History pages preserve equal-sequence groups and report clipping limits honestly. Large input is capped; no endpoint silently promises infinite history.

The local socket cannot supply official `chat.message` streaming previews. For an open, verified live session, the Bridge reads `surface.read_text` and applies upstream `AgentChatProseScreenExtractor`. It emits a replaceable preview, not token deltas. A missing anchor produces no preview; a terminal/UI change can reduce fidelity. The committed transcript is authoritative. The phone's initial implementation refreshes snapshots on a bounded foreground cadence, so response growth appears without terminal rendering. This polling is a compatibility mechanism for a missing subscription API, is cancellable on navigation/background, and is never a synchronization sleep inside a request.

`events.stream` uses a separate cmux connection from ordinary RPC. Its boot ID and sequence support reconnect/catch-up. Redacted event payloads trigger snapshot reads; they do not replace chat history. Slow-consumer/replay gaps trigger resynchronization. Do not route chat/project bodies into cmux's telemetry log.

The first event monitor retains explicit live bindings while connected; a dropped stream falls back to diagnostic/snapshot discovery until Bridge restart. Automatic reconnect and durable event cursors remain follow-up work. Phone history polling continues independently of this monitor.

## Writes and idempotency

The phone generates one operation UUID per logical send, interrupt or decision. The Bridge deduplicates requests in its process. It never blindly retries a cmux mutation after disconnect/timeout: a lost response may follow a successful action. The response reports `outcome_unknown`; the UI asks the user to inspect the conversation before sending again. The initial dedup cache is process-local, bounded, and does not establish exactly-once execution across Bridge restart. Durable write receipts are a follow-up before broader distribution.

Feed replies require a currently pending matching request and its supported kind. Ordinary Codex hook telemetry cannot be upgraded into an actionable approval by the Bridge. Unsupported actions remain visibly unsupported; numeric-key answering is not presented as a reliable generic approval adapter.

## Files and changes

Files are read from an explicitly known session project root. Canonical path containment is checked after resolving symlinks; traversal, directories, special files, hidden credential stores, oversized reads and projects rooted at a user's home directory are denied. The route accepts a relative path, never an arbitrary host path. Artifacts outside the root are not exported automatically.

Run Git directly with argument arrays, no shell interpolation, and use `--` for paths. Git execution disables external diff and textconv; responses are bounded. Return changed file metadata and unified diff. The first implementation shows text file previews; media galleries/Quick Look remain an extension. Transcript-derived file edits remain visible as chat cards independently of current Git state.

## API and phone UX

Versioned HTTPS `/v1` endpoints return structured resources and stable errors. Pairing -> sessions -> conversation. Conversation shows prose/Markdown, collapsed tool/thought cards, file-edit diffs, live preview, composer, stop, and links to project changes. A separate pending-actions list renders supported questions, permission and plan decisions. Home refresh and reconnect do not change desktop focus. UI uses native NavigationStack/List/TextField and localized English/Simplified Chinese strings.

HIG references: https://developer.apple.com/design/human-interface-guidelines/navigation-and-search and https://developer.apple.com/design/human-interface-guidelines/text-fields. The web retrieval returned JavaScript-only pages in this environment; native components are used conservatively and a visual/device pass is required before distribution.

## Delivery milestones

1. Pin upstream provenance, define wire schema, document capabilities and authority.
2. Implement authenticated TLS server, socket client, history discovery/parsing, actions, project reads and Git.
3. Implement paired native iPhone app and localized chat/action/file views in the same repository.
4. Exercise synthetic socket + HTTP + phone client integration, adversarial path/pinning/idempotency/history tests, and compile the Simulator app.
5. Verify a real official cmux instance and a physical phone when available; disclose exact missing gates. No official cmux process is restarted or changed for this verification.

Follow-ups: event-driven phone updates, durable receipt/session caching, multi-device credentials, physical-phone camera/network handoff, Windows/Linux backend adapters, Developer ID signing/notarization and release installers. None is reported complete merely because its interface is documented.
