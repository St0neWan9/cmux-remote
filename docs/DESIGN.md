# term remote design

This document is the top-level design for **term remote**, a companion for
remote terminals and the Agents that run in them. The provider-neutral model and
its migration are specified in [TERM-REMOTE.md](TERM-REMOTE.md). The Rex
provider is specified in [REX-SERVER-ADAPTER.md](REX-SERVER-ADAPTER.md). The
implemented connection layer remains specified by
[Connection v2](CONNECTION-V2.md). The Mac companion and native-sidebar
projection are described in [the Mac guide](MAC-EXTENSION.md); live acceptance
and continuity work are tracked in
[the unified connection plan](UNIFIED-CONNECTION-PLAN.md).

The cmux-first framing this document used before 2026-11-19 is superseded.
cmux is now the first terminal provider, not the product model.

Implementation status in this working tree: the provider-neutral Core model,
`/v3` terminal routes, the `cmux` and `Rex` terminal providers, `/v3` link
transport, Rex conversations through Claude's registry or opt-in Agent hooks,
the merged phone session routes, an iOS terminal screen, the owner provider
commands and isolated tests exist. Remote Rex transcripts, the full Sources UI and
the rename are not yet implemented.

## Scope

One repository contains a Swift Mac CLI/Bridge, shared wire models, a Swift
client, a native SwiftUI iPhone app, an Android app and a macOS companion. The
Bridge connects to one or more **terminal providers**:

- the official cmux Mac app's local API;
- cmux-tui daemons discovered on the same Mac;
- Rex servers, local or remote.

The phone and the companion never connect to a provider directly. They speak to
the Bridge over signed `/v3` resources and the existing pinned WebSocket link.
There is no cloud account, public relay requirement, provider API connection or
terminal emulator on the phone.

## Boundaries and layout

`CmuxRemoteCore` contains Sendable Codable DTOs, the provider-neutral model,
JSON values and pure policies. It reuses the pinned `CmuxAgentChat` parser/model
library. `CmuxRemoteBridge` owns provider connections, the provider registry and
directory, transcript reads, constrained project file access, Git queries and
TLS HTTP serving. `CmuxRemoteClient` owns HTTPS, certificate pinning and response
decoding. `CmuxRemoteCLI` is the composition root. `ios/`, `android/` and `mac/`
own app state and screens.

Dependencies form a DAG: executable/server/client/UI -> Core -> upstream
parsing/model code. No AppKit or Ghostty dependency enters the phone. The HTTP
API is language-neutral; providers implement the same generic operations with
explicit capability differences.

## Provider model

The model has one vocabulary for every backend:

| Type | Meaning |
| --- | --- |
| `Provider` | A terminal backend instance: cmux desktop, a cmux-tui daemon or a Rex server |
| `Host` | The machine a provider runs on |
| `Space` | A project-level container; the unit of navigation, sharing and grants |
| `Terminal` | One terminal screen with an input channel |
| `Layout` | A presentation arrangement of terminals inside a space |
| `Conversation` | One Agent session, identified by the Agent's own session id |
| `Binding` | Proof that a conversation currently runs in a terminal |
| `Capability` | What a provider, space, terminal or conversation supports |
| `Operation` | A durable, idempotent-by-identity mutation |

Mapping:

| term remote | cmux | Rex |
| --- | --- | --- |
| Provider | cmux desktop or a cmux-tui daemon | Rex server |
| Space | Workspace | Session |
| Terminal | Surface | Terminal block |
| Layout | Pane tree | Window/layer split tree |
| Conversation | Agent session bound to workspace + surface | Agent session bound to block |
| Binding proof | cmux registry / agent hooks | Agent hooks or Claude's process registry |

A provider's window, pane or layer is a layout node. It is not a grant, a
conversation identity or a phone-list row. A cmux workspace UUID is reused as
the `SpaceID` for compatibility; other providers derive stable UUIDs. All grant
IDs remain UUIDs, so the existing `ClientScope` and enrollment payloads keep
working. Existing wire capability names are retained; `workspaceRead` now means
"read a generic Space".

## Pairing and authority

The Bridge maintains a persistent Ed25519 host identity and separately enrolled
device identities. Version 2 QR codes bind an expiring enrollment window to the
host public key, exact TLS certificate fingerprint, endpoint and owner-selected
space IDs; they do not contain a permanent shared credential. Device requests
prove possession of their key and need the Mac owner's explicit approval. Signed
grants are persisted in an owner-only host registry. Each request proves its
identity, exact content, nonce and fresh server epoch; scope and revocation are
checked at the resource and final binding boundaries. See
[Connection v2](CONNECTION-V2.md) for the cryptographic/wire contract.

Bonjour is reachability metadata, not trust. The iPhone saves device-only
Keychain identity and host trust, restores grants, and can relocate a known host
after verifying the unchanged identity and TLS pin. Certificate changes require
explicit enrollment; there is no unverified renewal shortcut. The local admin
Unix socket is separate from HTTPS and owns approval/revocation, provider
management and hook installation. Legacy shared-token routes require an explicit
`--legacy` opt-in.

There is no generic provider RPC proxy. No browsing operation selects or focuses
a desktop space. Provider methods are fixed, typed operations. The Bridge never
enables cmux `allowAll`, starts a second Agent runtime or gives a device a
provider's raw method surface.

## Providers and discovery

Each provider instance has a stable `ProviderID` and a declared capability set.
The provider registry isolates failures: an unavailable provider contributes a
stable `provider_errors` entry and never falls through to another provider's
resources.

- **cmux desktop** uses the local socket and the existing authenticated domain
  methods. Its spaces are workspaces, its terminals are terminal surfaces and
  its history is the local transcript.
- **cmux-tui** daemons use their public protocol and their own identity. Existing
  workspace UUID grants and the daemon adapter remain valid.
- **Rex** uses a Unix socket or a tailnet endpoint. Its spaces are sessions and
  its terminals are terminal blocks. The Bridge is the only Rex client; it never
  exposes a Rex method, endpoint or raw id to a device.

Provider-specific discovery never grants authority. The owner selects the spaces
to share, and approval records exact capabilities.

## Conversations and provenance

A conversation is listed only with an authoritative binding: an explicit
workspace/surface binding (cmux) or a verified Agent process (cmux-tui), an
Agent hook that carries the provider terminal identity (Rex), or Claude Code's
own process registry plus the provider's live process tree. Matching cwd, title
or chronological proximity does not establish provenance.

For a Rex block, a hook runs inside the block with `REX_SESSION` and `REX_BLOCK`
in its environment; the hook helper records ids only. Without hooks, Claude
binds through `<pid>.json`; Codex remains terminal-only. A conversation whose
Agent has exited is resumable only when the transcript under a configured root
records the Agent's own directory, the space still exists, and a running
terminal no longer shows that Agent's prompt. A screen that cannot be read
proves nothing. Resuming starts a fixed `<agent> --resume <session-id>` (Codex:
`codex resume <session-id>`) in a new terminal in that space, with the session
id taken from the Bridge's binding and never from the client. It requires
`conversationStart`.

Starting a conversation requires `conversationStart` and opens a fixed `claude`
or `codex` command in an approved space through the provider's own start
operation. The Agent still runs inside the provider; no separate Agent runtime
or provider connection is created.

## History and live preview

Read complete JSONL lines only, retaining an unfinished trailing fragment. Reuse
upstream Claude/Codex parsing, including tool-use/result updates and artifact
references. Final messages replace matching IDs rather than append duplicates.
An inode change or truncation creates a new transcript generation and tells
clients to re-anchor. History pages preserve equal-sequence groups and report
clipping limits honestly. The archive reads one bounded byte chunk ending at the
requested cursor.

Local providers read the transcript path directly. A remote Rex provider
downloads the transcript through Rex into an owner-only bounded cache, verifies
the prefix before appending, and feeds the same parser. A whole-file download is
the only remote strategy in the first phase; history refreshes on open and on an
explicit pull, not on every foreground tick.

The archive cursor binds the transcript path's generation. Tool details and
images resolve through the ordinary bounded history window; a record outside
that window is not re-read by the archive.

A live bound session can appear before its first prompt creates the JSONL file.
If its approved transcript path has never been observed and is still absent,
return an empty history with a stable pending generation. Do not create files,
synthesize messages, or treat permission failures, ended sessions, or deletion
of an already observed transcript as a new empty conversation.

The Bridge reads the provider's current screen and applies the upstream
`AgentChatProseScreenExtractor` for a replaceable preview, not token deltas. A
missing anchor produces no preview. The committed transcript is authoritative.
Phone polling is a bounded, cancellable compatibility mechanism, not a
synchronization sleep. Android's opt-in foreground service is the one background
exception and stops with the task.

`events.stream` and provider subscriptions use a separate connection from
ordinary RPC where the provider supports them. Boot IDs and sequences support
reconnect and catch-up. Slow-consumer/replay gaps trigger resynchronization. No
chat or project body enters telemetry.

## Writes and idempotency

The phone generates one operation UUID per logical send, interrupt or decision.
Chat, Feed and terminal input share one durable owner-only mutation ledger keyed
by approved device identity and operation UUID. Before provider execution, the
Bridge appends and flushes an intent containing only a canonical payload digest,
target space and required capability. Confirmation appends and flushes its
receipt. Restart reloads completed receipts; unfinished or outcome-unknown
intents remain unknown and are never executed again under the same key. Reading
a cached receipt still rechecks current scope/revocation. Different payloads
under the same device/operation key are rejected.

The journal is bounded to 16,384 operation keys and 16 MiB, with no automatic
eviction that would make old mutations executable again. Prompts, terminal input
and credentials are not stored in it. No automatic POST retry is added. This is
durable protection against repeated attempts, not an exactly-once transaction
with a provider.

A model switch uses the Agent's own command and the same ledger. Claude Code
receives `/model <name>` as a send; Codex's picker is walked with each move
verified on screen. Only an Agent waiting at its prompt is switched. No model,
provider or credential setting is written by the Bridge.

Feed replies require a currently pending matching request, its supported kind
and a provider that implements Feed. Ordinary provider telemetry cannot be
upgraded into an actionable approval. Unsupported actions remain visibly
unsupported.

## Files, changes and images

Files are read from an explicitly known conversation project root. Canonical
path containment is checked after resolving symlinks; traversal, directories,
special files, hidden credential stores, oversized reads and projects rooted at
a user's home directory are denied. The route accepts a relative path, never an
arbitrary host path. Artifacts outside the root are not exported automatically.

Run Git directly with argument arrays, no shell interpolation, and use `--` for
paths. Git execution disables external diff and textconv; responses are bounded.
Return changed file metadata and unified diff. Transcript-derived file edits
remain visible as chat cards independently of current Git state. A remote
provider that cannot prove local project access hides these actions instead of
degrading silently.

Images are validated, bounded and scoped like the existing conversation
attachments. Recorded transcript images resolve through the bounded history
window; a remote transcript's referenced files may be unavailable and must be
shown as unavailable rather than broken.

## API and UX

Signed, scoped `/v3` endpoints return structured providers, spaces, terminals,
layouts, screens and conversations with stable errors. The existing `/v1`/`/v2`
routes remain a cmux-provider compatibility projection for older clients.
Pairing -> sources -> spaces -> conversation/terminal is the navigation model.
Conversation shows prose/Markdown, collapsed tool/thought cards, file-edit
diffs, live preview, composer, stop, and links to project changes when the
provider supports them. A separate pending-actions list renders supported
questions, permission and plan decisions. Home refresh and reconnect do not
change provider focus. The phone uses native NavigationStack, a selectable
scrollable conversation, trailing user bubbles, full-width agent Markdown,
collapsed activity groups, a latest-message jump button and a floating send/stop
composer. Terminals without a conversation use a native text screen. English and
Simplified Chinese strings are localized.

The Mac companion is Sources-first: provider cards, a space/terminal tree, a
generic viewer, sharing and enrollment, and an optional native cmux sidebar
projection. A user with only Rex does not need cmux. The viewer polls a bounded
snapshot and never owns or resizes the remote terminal.

HIG references: https://developer.apple.com/design/human-interface-guidelines/navigation-and-search and https://developer.apple.com/design/human-interface-guidelines/text-fields.

## Security

- The Bridge is the only network-facing component. Providers are owner-configured.
- Device grants are per space UUID and capability; provider management and hook
  installation are owner-only.
- Fixed operations only. No generic RPC proxy, shell string, arbitrary path or
  caller-selected provider method.
- A binding is revalidated before every write. A terminal whose screen has
  returned to a shell is read-only.
- A provider failure is isolated; it cannot make another provider's target
  writable or hide another provider's data.
- No provider credential, screen body or transcript body enters logs, fixtures,
  crash reports or public text.
- Rex's whole-server authority is narrowed to the operations listed in its
  provider specification; destructive layout/server methods are excluded.
- Plain anonymous HTTP provider endpoints are refused unless the owner opts in
  with a warning; a private VPN or tailnet is the recommended path.

## Delivery stages

1. Introduce the generic model and wrap the existing cmux backend as the first
   provider. `/v1`/`/v2` stay unchanged.
2. Add the Rex provider and the directory. Serve `/v3` alongside the old routes.
3. Sources-first companion, generic viewer, optional cmux sidebar projection.
4. Source-aware phone lists, terminal view, capability-driven actions.
5. Remote Rex, hook installer, Codex, VT/streaming, Feed decisions where
   supported.

The product name is term remote. Bundle identifiers, App Group identifiers,
Keychain services and release automation are renamed only in a separate,
owner-approved migration with a read-old/write-new path; see
[TERM-REMOTE.md](TERM-REMOTE.md).

In progress: the provider-neutral model, the `/v3` API, the Rex provider,
source-aware phone UI and the staged rename. Physical-phone camera/network
handoff, remote Rex on another machine and Windows/Linux server behaviour need
their own acceptance. None is reported complete merely because its interface is
documented.
