# term remote — provider-neutral design

Status: foundation implemented in the working tree, not released. The generic
provider model, `/v3` terminal routes, the cmux and Rex terminal providers, the
`/v3` link transport and isolated tests exist. Conversation binding,
capability-driven phone UI and the staged rename remain proposals.
Updated 2026-11-19. This document supersedes the cmux-first framing in
[DESIGN.md](DESIGN.md); the owner accepted that migration on 2026-11-19.

The project is becoming **term remote**: one phone and one Mac companion for
remote terminals and the Agents running in them, from more than one terminal
provider. cmux (desktop and cmux-tui daemons) is one provider. Rex is another.
The product must not be shaped around cmux's model, and Rex must not be forced
into cmux's vocabulary.

The existing cmux-specific behaviour remains valuable. It becomes an optional,
capability-scoped part of the model rather than the model itself.

## Principles

1. **The provider is an implementation, not the model.** The phone sees
   providers, spaces, terminals and conversations. It does not see cmux
   workspaces, surfaces, panes, Rex sessions, windows or blocks.
2. **The Bridge is the only network-facing component.** Every provider
   connection, credential, transcript read and terminal write happens inside
   the Bridge. Devices never talk to a provider directly.
3. **Provenance is per provider and must be proved.** A conversation is shown
   only when the provider can prove which Agent session runs in which terminal.
   cmux uses its registry/hooks; Rex uses Agent hooks or Claude's process
   registry. Guessing from cwd, title or timing is never enough.
4. **Capabilities drive the UI.** A provider or space advertises what it
   supports. The phone hides actions a provider cannot prove, instead of
   emulating them or failing late.
5. **Fixed operations, no generic proxy.** The Bridge exposes typed resources
   and mutations. It never forwards a caller-chosen provider method.
6. **Same experience, different sources.** The phone keeps its current
   navigation, list, conversation and composer design. Sources are added behind
   it.

## Domain model

| Type | Meaning | Not to be confused with |
| --- | --- | --- |
| `Provider` | One terminal backend instance: official cmux on this Mac, a cmux-tui daemon, or a Rex server. Has a stable id, kind, host identity, status and capability set. | A Bridge; a device; a host record |
| `Host` | The machine a provider runs on. May be this Mac or a remote machine. | A provider instance; a paired device |
| `Space` | A project-level container. The unit of navigation, sharing and grants. | A macOS Space; a phone tab |
| `Terminal` | One terminal screen with an input channel. Has a title, process, cwd, state and a bounded snapshot. | A provider block of a non-terminal kind |
| `Layout` | Optional arrangement of terminals inside a space (splits, tabs, floating layers). Presentation only. | A grant or conversation boundary |
| `Conversation` | One Agent session (Claude or Codex), identified by the Agent's own session id. Bound to the terminal where it runs. | A provider session; a terminal |
| `Binding` | The proof that a conversation currently runs in a terminal: provider, space, terminal, Agent id, transcript locator, proof kind, observation time. | A cached screen; a title match |
| `Capability` | What a provider, space, terminal or conversation supports. | A device grant |
| `Operation` | A durable, idempotent-by-identity mutation recorded before dispatch. | A provider request id |

User-facing vocabulary stays short: a **Source** is a `Provider`, a **Space** is
a project container, and a **Conversation** is an Agent session. The UI never
says "workspace", "surface", "session" or "block" unless it is naming a
provider-specific concept in provider settings.

### Mapping into providers

| term remote | cmux | Rex |
| --- | --- | --- |
| Provider | Official cmux desktop socket; each cmux-tui daemon | A Rex server (host) |
| Host | This Mac | The Rex server's machine |
| Space | Workspace | Session |
| Terminal | Surface (a terminal) | Block (a terminal) |
| Layout | Pane tree | Window/layer split tree |
| Conversation | Agent session bound to workspace + surface | Agent session bound to a block |
| Binding proof | cmux registry / agent hooks | Agent hooks (`REX_SESSION`, `REX_BLOCK`) or Claude's `<pid>.json` registry |
| Transcript | Local JSONL under the configured roots | Local JSONL, or a bounded Rex download |
| Feed | cmux Feed (desktop) | None |
| Model switch | Claude/Codex through cmux | Claude through the terminal in v1 |
| Files/Git | cmux project resources | Local Rex only in v1; remote needs Rex file downloads |

A Rex **window** is not a `Space`. It is a navigation layer inside a Rex
session (the layout of blocks you see at once). A cmux **pane** is likewise a
layout node, not a terminal. Only spaces and terminals participate in grants,
conversations and the phone list.

### Identity and contracts

- `ProviderID`: a Bridge-generated stable UUID per provider instance. It
  survives restarts through owner-only state and changes only when the provider
  is replaced.
- `SpaceID`: a UUID derived from the provider id and the provider's stable space
  key (`UUIDv5`-style, SHA-256 based). The phone and grants use this UUID;
  provider ids never become API path segments that a caller can forge into a
  method.
- **Compatibility exception:** a cmux provider reuses the existing cmux
  workspace UUID as its `SpaceID`, so current grants, enrollment windows and
  saved host scopes keep working. Other providers derive their own UUID; a
  collision with a live `Space` is rejected rather than merged.
- `TerminalID`: a derived UUID per terminal (cmux surface, Rex block).
- `ConversationID`: the Agent's own session id (Claude/Codex). It is globally
  unique enough to merge providers; a duplicate live binding is an error, never
  a silent choice.
- Every ID used in a grant is a UUID, so `ClientScope` keeps its current
  validation and the enrollment schema does not change. Labels are resolved by
  the owner UI.
- A provider advertises its **capability set** and a protocol/API revision.
  Unknown capabilities are ignored; an unsupported action is never emulated.
  Existing wire names are retained: `workspaceRead` applies to a generic Space,
  and new names are added only with a protocol revision.

## Provider abstraction

### Protocols

Keep the protocols narrow. A provider that cannot do something simply does not
conform to that part, or returns `unsupported`.

```swift
protocol TerminalProvider: Sendable {
    var descriptor: ProviderDescriptor { get async }
    func spaces() async throws -> [SpaceDescriptor]
    func layout(space: SpaceID) async throws -> LayoutSnapshot
    func terminals(space: SpaceID) async throws -> [TerminalDescriptor]
    func terminal(_ id: TerminalID) async throws -> TerminalDescriptor
    func snapshot(_ id: TerminalID) async throws -> TerminalSnapshot
    func send(_ input: TerminalInput, to id: TerminalID, operation: OperationID) async throws -> MutationReceipt
}

protocol BindingProvider: Sendable {
    func bindings() async throws -> [ConversationBinding]
    func revalidate(_ binding: ConversationBinding) async throws -> Bool
}

protocol ConversationProvider: Sendable {
    func history(_ id: ConversationID, page: HistoryPage) async throws -> ConversationSnapshot
    func preview(_ id: ConversationID) async throws -> PreviewSnapshot
    func send(_ id: ConversationID, request: SendRequest) async throws -> MutationReceipt
    func interrupt(_ id: ConversationID, request: InterruptRequest) async throws -> MutationReceipt
}

protocol ConversationStarter: Sendable {
    func start(in space: SpaceID, request: StartConversationRequest) async throws -> MutationReceipt
    func resume(_ id: ConversationID, request: ResumeRequest) async throws -> MutationReceipt
}

protocol OptionalFeatures: Sendable {
    func feed() async throws -> [FeedEntry]                 // cmux desktop
    func models(_ id: ConversationID) async throws -> ModelChoiceList
    func switchModel(_ id: ConversationID, request: ModelSwitchRequest) async throws -> MutationReceipt
    func change(_ id: ConversationID, ...) async throws      // project files, Git, tasks
}
```

`ConversationStarter` and `OptionalFeatures` are capability-gated. A provider
can implement only the parts it can prove.

### Provider registry and directory

- `ProviderRegistry` owns one connection per provider instance and isolates
  failures: a provider that is down contributes a stable `provider_errors`
  entry; other providers keep working.
- `DirectoryService` reads the registry and produces one merged view of spaces,
  terminals and conversations. It deduplicates conversations by Agent session
  id and applies the ambiguity rule: two live bindings for one conversation is
  an error; a cmux binding is not silently replaced by a Rex binding.
- `BindingService` asks each provider for bindings, revalidates them on a
  bounded cadence and before every write, and invalidates them when the
  terminal process changes.
- `ScreenCache` holds one bounded snapshot per viewed terminal. Providers with
  push or replay (cmux) and providers with polling (Rex) sit behind the same
  interface; the cache never claims more freshness than the provider proves.
- `MutationLedger` is shared. Operation ids are scoped by device and bind a
  provider, space, terminal and payload digest.

### Provider kinds in the first release

| Kind | Instance | What it adds |
| --- | --- | --- |
| `cmux-desktop` | The official cmux app socket on this Mac | Workspaces, terminals, conversations, Feed, project files, Git, model switch |
| `cmux-daemon` | Each discovered cmux-tui daemon | Workspaces, terminals, conversations, daemon decisions, model switch where supported |
| `rex` | A Rex server, local Unix socket or tailnet | Sessions, blocks, terminals, hook/registry-bound conversations, terminal input |
| `demo` | Fixture provider | Tests and previews |

| Feature | cmux desktop | cmux daemon | Rex |
| --- | --- | --- | --- |
| Spaces, terminals, layout | Yes | Yes | Yes |
| Screen snapshot | Replay | Replay | `format` polling (v1) |
| Terminal input | Yes | Yes | Yes |
| Conversation history | Local transcript | Local transcript | Local or downloaded |
| Binding proof | cmux registry/hooks | Daemon hooks | Agent hooks / Claude registry |
| Feed | Yes | Recognized decisions only | No |
| Model switch | Claude/Codex | Supported subset | Claude in v1 |
| Start/resume | Yes | Yes | Yes, fixed commands |
| Project files/Git | Yes | Yes | Local Rex in v1 |
| Lossless stream | Replay | Replay | Later (data stream) |

Existing cmux code becomes the first `TerminalProvider`/`ConversationProvider`
implementation. The current `CmuxBackendRouter` can keep its internal role, but
it is registered in the provider registry rather than treated as the product.

## Logic

### Reading a space and its terminals

1. The directory lists providers the device may see.
2. For a provider, `spaces()` returns project containers; the owner's grants
   filter the result.
3. `layout(space:)` and `terminals(space:)` return navigation metadata. Neither
   reads screen contents nor changes focus, size or ownership.
4. A terminal view calls `snapshot(_:)` through the screen cache. The snapshot
   carries a provider, terminal, revision/generation, columns/rows and a bounded
   text or VT payload. The phone renders text; the Mac viewer may render VT.
5. Polling happens only while a view is open, is cancellable, and stops when the
   last viewer leaves.

### Conversations

1. `bindings()` returns proved bindings. A binding names the Agent session, its
   terminal, the transcript source and the proof kind.
2. The directory merges bindings from all providers. A conversation is listed
   once; a stale binding is never used for writes.
3. History is read from the provider's transcript source. Local providers read
   files directly; a remote Rex provider downloads through Rex and materializes
   an owner-only cache file for the same parser.
4. Preview is the provider's current screen, parsed by the existing prose
   extractor. It is replaceable, not token streaming.
5. Send, interrupt, model switch, start and resume are typed operations. Each
   checks the binding, the prompt/screen state and the grant immediately before
   dispatch, then records the operation in the ledger.

### Starting and resuming

- A start request names a space and an Agent (`claude`/`codex`), never a
  provider method or an argv. The provider decides how to open a terminal:
  cmux opens a surface/tab; Rex creates a block with a fixed `command`.
- A resume request names a conversation id. The provider uses the transcript's
  recorded cwd and the Agent's own id to start `claude --resume <id>` or
  `codex resume <id>` in a new terminal.
- Both require `conversationStart` on the space and are journaled; an unknown
  outcome is not retried.

### Capability examples

The wire capability names stay unchanged for enrollment compatibility.
`workspaceRead` now means "read a generic `Space`"; internally the model may
call it `spaceRead`, but the signed enrollment payload and grant keep the old
raw value.

| Action | Requires |
| --- | --- |
| List spaces/terminals | `workspaceRead` (generic space read) |
| Read a screen | `terminalRead` |
| Type into a terminal | `terminalInput` |
| Read history/preview | `conversationRead` |
| Send/stop/model | `conversationControl` |
| Start/resume | `conversationStart` |
| Feed | `feedRead` / `feedReply` and a provider that implements Feed |
| Add/remove a provider | owner-only management; never a device grant |

The UI renders only actions whose capability is present for the current
provider and space. A missing capability is a normal state, not an error.

## Wire API

New clients use a provider-neutral `/v3`. The existing `/v1`/`/v2` cmux routes
remain as a compatibility projection for older phones and the current Mac
mirror; they are derived from the same directory and never expose Rex unless a
client asks for v3.

| Route | Capability | Result |
| --- | --- | --- |
| `GET /v3/providers` | enrolled device | provider descriptors, status and capabilities |
| `GET /v3/spaces?provider=` | `workspaceRead` per space | spaces the device may see |
| `GET /v3/spaces/:space/layout` | `terminalRead` | layout nodes and terminal metadata |
| `GET /v3/spaces/:space/terminals` | `terminalRead` | terminals with title, process, cwd, state |
| `GET /v3/terminals/:terminal/screen` | `terminalRead` | bounded screen snapshot with revision |
| `POST /v3/terminals/:terminal/input` | `terminalInput` | text/keys + operation id → receipt |
| `GET /v3/conversations?provider=&space=` | `conversationRead` | merged, deduplicated conversations |
| `GET /v3/conversations/:id/history` | `conversationRead` | timeline pages |
| `GET /v3/conversations/:id/preview` | `conversationRead` | replaceable live preview |
| `POST /v3/conversations/:id/send` | `conversationControl` | text/attachments + operation id |
| `POST /v3/conversations/:id/interrupt` | `conversationControl` | polite/hard stop |
| `POST /v3/spaces/:space/conversations` | `conversationStart` | start a fixed Agent command |
| `POST /v3/conversations/:id/resume` | `conversationStart` | reopen the Agent's own session |
| `GET /v3/conversations/:id/models` | `conversationControl` | provider-supported choices |
| `POST /v3/conversations/:id/model` | `conversationControl` | switch where supported |
| `GET /v3/operations/:id` | device-scoped | accepted or outcome-unknown |

Rules:

- Provider, space and terminal ids are scoped to the Bridge that serves them. A
  phone connected to several Bridges namespaces them by the Bridge host id for
  display and caching; the wire request only carries the IDs that Bridge issued.
- All resource ids are UUIDs resolved by the Bridge. No provider method name,
  shell word, arbitrary path or provider-specific id appears in a request.
- Bodies are bounded (1 MiB transport, 16 KiB input, provider-specific transcript
  caps). Screens are bounded and paged.
- Errors keep stable codes. A provider-specific failure becomes a stable
  `provider_*` code, never a provider's raw message.
- Events and subscriptions reuse the existing link with generic resource
  stamps; polling remains the fallback where a provider has no subscription.

### Implemented foundation (2026-11-19)

- Core: `ProviderDescriptor`, `SpaceDescriptor`, `TerminalDescriptor`,
  `TerminalSnapshot`, `LayoutSnapshot`, `TerminalInputRequest` and
  `ConversationBinding` with stable, opaque UUIDs.
- Bridge: `ProviderRegistry`, `ProviderDirectory`, `CmuxProvider`,
  `RexProvider`, `RexControlClient` (Unix socket, TCP and TLS) and
  `ProviderIdentity`.
- `/v3` routes: providers (filtered to providers with at least one granted
  space), spaces, layout, terminals, screen and input. The WebSocket link and
  `RemoteClient` accept `/v3` paths; `/v1`/`/v2` keep their old behaviour.
- CLI: `serve` auto-detects the local Rex socket and accepts
  `--rex-endpoint`, `--rex-label` and `--no-rex`.
- Rex conversations: Claude is bound from its own `<pid>.json` registry plus
  Rex's live process tree; Codex and Claude can also bind through an explicit,
  reversible hook installer (`hooks install`). The proved rows merge into the
  existing `/v1/sessions` list, so the phone's list, history, composer, stop
  and model menu use the same routes as cmux.
- Terminal rows: unbound Rex blocks are listed as `kind: "terminal"` only for
  clients that request `terminalView`. iOS and Android have a bounded text screen
  with `/v3` input.
- Desktop: the Companion lists provider spaces through the owner channel;
  `providers spaces|terminals`, `view --terminal`, `hooks install|remove` and
  `agent-hook` complete the local terminal-viewer and binding path.
- Tests: provider directory and identity, endpoint parsing, `/v3` capability
  denial over a real enrolled link, a real isolated Rex server, a verified
  Claude registry binding, a Codex hook binding, and the existing phone routes
  listing and typing into the same rows.
- Not implemented yet: remote Rex registry/transcript downloads (remote Claude
  conversations), a click-through desktop viewer, and the staged rename. The machine-wide Bridge lease still prevents a second
  long-running CLI Bridge; tests start their own in-process server on a random
  port and never touch the owner's instance.

## Desktop (Mac companion)

The Companion is now a **Sources** window, not a cmux settings page.

- **Sources**: provider cards/rows for this Mac's cmux, discovered cmux-tui
  daemons, the local Rex server and any saved remote Rex hosts. An enrolled
  remote Bridge is its own source and brings its provider list with it. Each
  shows status, capability set, host and last error. Add/remove is owner-only.
- **Tree**: Space → Layout → Terminal → bound Conversation. Selecting a terminal
  opens the generic viewer; selecting a conversation shows its metadata and
  opens the same viewer for the Agent's terminal.
- **Sharing**: choose spaces to expose to a phone during enrollment; show the
  derived UUIDs only as labels in the UI. A provider that is down shows a
  stable unavailable state and never falls through to another provider.
- **Agent binding**: per provider, show whether bindings are active. Rex offers
  an explicit, reversible hook installer; cmux uses its existing hooks.
- **Viewer**: `term remote view --space <uuid> --terminal <uuid>` (or a provider
  alias) runs in any local terminal and renders either provider's terminal.
  When cmux is installed, the sidebar projection can host the same viewer in a
  native workspace. It polls a bounded snapshot, forwards local input, and never
  owns or resizes the remote terminal.
- **cmux sidebar projection** becomes optional presentation: project any
  provider's spaces into a native group (one group per provider, or one combined
  Remote group with provider prefixes). The official cmux app is a host for the
  view, not the product model.

The menu bar item shows provider health, connected devices and relay status.
A user who only has Rex can use the Companion and the viewer without cmux.

## Mobile (iPhone and Android)

The existing experience is preserved; the source model behind it changes.

- **Home**: a source-aware list. Sections by provider/host, then spaces or a
  merged conversation list. Filters include provider, space, live/idle and
  conversation kind. Pull-to-refresh and reconnect behaviour stay as today.
- **Conversations**: the same list rows, conversation view, Markdown, tool
  cards, timeline, composer, stop and model controls. The only changes are a
  source/agent badge and capability-driven hiding of actions a provider does not
  support (for example, Feed for Rex).
- **Terminals**: a provider-neutral terminal row for terminals that have no
  proved conversation. The detail view is a native text screen (or VT later)
  with refresh, jump-to-latest, and a composer/key bar. It is never presented as
  a conversation with fabricated history.
- **Space view**: optional navigation into a provider's space to see its layout
  and terminals. It uses the same navigation stack; it is not a second app.
- **Settings**: providers the Bridge exposes, grants, and per-provider status.
  Devices cannot add providers or change hook configuration.
- **Capability-driven UI**: the phone asks for available capabilities; an
  unsupported action is absent rather than disabled with a mystery error.
- **Parity**: Android consumes the same `/v3` DTOs and mirrors the screens; there
  is no separate provider protocol.

"Same experience" means the same components and flow, not the same provider
assumptions. Rex conversations look like cmux conversations because both produce
the same `ConversationSnapshot`; Rex-only terminals look like a native screen,
not like a terminal emulator bolted onto the app.

## Authority and security

- Providers are owner-configured and live behind the Bridge. Device grants are
  per `Space` UUID and per capability. Provider management is owner-only.
- Every provider request is a fixed typed operation. There is no generic RPC
  proxy, no caller-selected method, no shell string and no caller-supplied path.
- Provider isolation: one failing provider cannot hide another provider's data
  or make another provider's target writable.
- A conversation binding is revalidated before every write. A terminal whose
  screen has returned to a shell is read-only.
- The mutation ledger is shared across providers; an operation id binds the
  provider, space, terminal and payload digest. Unknown outcomes are never
  retried.
- Rex's whole-server authority is narrowed by the Bridge: only the operations
  listed here are exposed, and destructive layout/server methods are excluded.
- No provider credential, screen body or transcript body enters logs, fixtures,
  crash reports or public text. Remote transcripts live in owner-only bounded
  cache storage.
- Agent hook installation is an explicit, previewed, reversible owner action.
  Existing cmux hooks are preserved; only this project's command is added.

## Migration and rename

The product name becomes **term remote**. The wire and code migration is
staged so the installed app, signing identity, Keychain items, TestFlight and
App Store records are not silently broken.

| Stage | Work | Compatibility |
| --- | --- | --- |
| 0 | Introduce generic models and wrap the existing cmux backend as the first provider. No UI change. | `/v1`/`/v2` unchanged; all current tests pass |
| 1 | Add the Rex provider and the directory. Serve `/v3` alongside the old routes. | Old phones see cmux only; new clients see all providers |
| 2 | Companion Sources UI, generic viewer, optional cmux sidebar projection. | Existing mirror flows keep working |
| 3 | Phone source-aware lists, terminal view, capability-driven actions. | Same conversation experience for cmux |
| 4 | Remote Rex, hook installer, Codex, VT/streaming, Feed decisions where supported. | Provider-specific opt-ins |

Naming:

- Design docs, UI strings and user-facing copy use **term remote**.
- Swift target/library names, bundle identifiers, App Group identifiers,
  Keychain services and release automation are **not** renamed in the same
  change. A rename of those is a separate release decision with the owner,
  because it affects installed apps, signatures, provisioning and saved
  credentials.
- New generic types use provider-neutral names (`Provider`, `Space`, `Terminal`,
  `Conversation`, `Binding`). Existing `Cmux*` types remain where they are cmux
  implementations.

Rename map, staged so nothing installed breaks:

| Current | Proposed | When |
| --- | --- | --- |
| Repo docs, README, UI copy | term remote | Stage 0 (now) |
| CLI binary | `term-remote` | Stage 0 (now) |
| Swift targets `CmuxRemote*` | `TermRemote*`, with typealias/import shims | Stage 1 |
| Bundle IDs, App Group, Keychain services | new `term remote` IDs with a one-time read-old/write-new migration | Major release, owner-approved |
| State directory `~/.local/state/cmux-remote` | `~/.local/state/term-remote`, importing the old directory | Major release, with rollback |
| Bonjour service type / relay identity | new identity, advertising the old one during transition | Later, after both ends can upgrade |
| Website and release tags | term remote branding | Later |

The first stages are reversible. The bundle/Keychain/state rename is not
something an issue pass performs silently: it changes what an installed app can
read and must be released with an explicit migration and rollback path.

## Risks and non-goals

- **Lowest-common-denominator risk.** The generic model must not erase cmux
  capabilities; optional feature protocols keep them available without making
  them universal.
- **Identity stability.** A provider instance must keep its id across restarts;
  a replaced daemon or server is a new provider, not a silent rebind.
- **Ambiguity.** One live conversation bound to two providers is an error; the
  directory never picks one by preference order.
- **Rex preview software.** The API revision can change; the provider pins a
  supported revision and fails closed.
- **Codex binding.** Rex has no pid-to-thread registry; Codex conversations need
  the opt-in hook installer. Without it, Codex terminals are shown as terminals.
- **Remote history cost.** Rex file downloads are whole-file; remote history is
  refreshed on open and on an explicit pull, with the screen as the live view.
- **Non-goals in this pass:** changing bundle IDs, replacing the official cmux
  app, becoming a terminal emulator on the phone, or exposing a generic provider
  proxy.

## Verification

- Provider conformance tests for each provider: spaces, layout, terminals,
  snapshots, input, binding, history, deduplication and capability hiding.
- Directory tests: provider isolation, stable errors, grant enforcement,
  ambiguous bindings, restart recovery and ID stability.
- Conversation tests across providers: the same DTO from cmux and Rex, correct
  provenance, no cross-provider write and no automatic retry after an unknown
  outcome.
- Compatibility tests: `/v1`/`/v2` cmux responses unchanged for old clients.
- Rex-specific tests are listed in [REX-SERVER-ADAPTER.md](REX-SERVER-ADAPTER.md).
- `scripts/verify.sh`; `scripts/build-ios.sh` after client changes; Android build
  and unit tests after Android changes. State plainly what was not checked.
