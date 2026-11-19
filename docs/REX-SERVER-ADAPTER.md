# Rex provider — term remote design

Status: implemented locally in the working tree and covered by isolated
integration tests. `RexEndpoint`, `RexControlClient` (Unix socket, TCP and
TLS), spaces/terminals/layout/screen/input, `/v3` wiring, the
`--rex-endpoint` / `--rex-label` / `--no-rex` options and local socket
auto-detection exist. Claude conversations bind through its process registry;
Codex and Claude can also bind through the opt-in `hooks install` command and
its owner-only spool. The proved rows merge into the existing phone session
routes, and unbound blocks are exposed as terminal rows. Remote registry and
transcript downloads and remote Codex remain unimplemented.
Updated 2026-11-19. Read [TERM-REMOTE.md](TERM-REMOTE.md) for the provider-neutral
model this document implements, and [DESIGN.md](DESIGN.md) for authority rules.

Rex (`rex`, `0.1.0-preview.20` at the time of writing) is a terminal multiplexer
with a long-running server, a documented client API and its own Mac, iOS and CLI
clients. This document describes Rex as a **term remote provider**: how the
Bridge talks to a Rex server, how a Rex block is proved to host an Agent
conversation, and how Rex spaces and terminals appear in the desktop and phone
interfaces. Rex is not mapped onto cmux's vocabulary; both cmux and Rex are
mapped into the generic model.

Decisions taken on 2026-11-19:

- The first release covers **terminal control and Agent conversations**.
- The phone keeps the **same experience as today**: the same source-aware list,
  conversation view, history, composer, stop and model controls.
- The Mac surface starts as a **Sources list** of providers, spaces and
  terminals, with a generic viewer. A native cmux sidebar projection is a later
  presentation of the same model.
- Codex follows the **same hook-based binding as cmux**. Claude also has a
  no-setup fallback through its process registry.
- Remote history uses the **approved whole-file download** strategy: download on
  open and on an explicit pull, with the screen as the live preview.

## Summary

A Rex provider in the Bridge has three parts:

1. **A terminal provider.** The Bridge is the only component that talks to a Rex
   server, using the owner's local Unix-socket authority or the owner's tailnet.
   Phones and the companion never connect to Rex directly. Rex sessions become
   `Space`s, Rex blocks become `Terminal`s, and a Rex window is only a layout
   inside a space. Terminals are read with `terminal.format` and written with
   `terminal.write`.
2. **A binding provider.** A conversation is listed only when the Bridge can
   prove which Agent session runs in a block. Two signals exist: an Agent hook
   running inside the block (Claude and Codex) and Claude Code's own
   `<pid>.json` process registry (Claude only). Rex's live process tree is
   checked in both cases.
3. **A conversation source.** The proved Agent session id feeds the existing
   transcript parser, so the phone receives the same `ConversationSnapshot` as
   any other provider: Markdown, tool cards, timeline, composer, stop and model
   menu. Local hosts read the transcript directly; remote hosts download it
   through Rex into an owner-only cache.

A block with no proved Agent stays a first-class `Terminal`. The phone renders
it as a native text screen, not as a conversation with fabricated history.

For Codex, the adapter uses the same mechanism cmux itself uses: agent hooks.
Rex sets `REX_SESSION` and `REX_BLOCK` in the environment of every terminal it
opens, and the agent and its hooks inherit them. A hook that runs inside a Rex
block can therefore report the exact block together with the agent's own
session/thread id. An opt-in, reversible hook installer, approved by the owner
in the Companion, gives both Claude and Codex the cmux-equivalent binding.
Without it, Claude still binds through its process registry; Codex stays
terminal-only.

Blocks that are not bound to an Agent stay first-class **terminal** rows. The
phone renders them with the same native list/navigation and a text screen view,
not a terminal emulator.

Rex and cmux can both run on one Mac. A conversation is listed once: the
existing cmux binding wins if cmux also proves the same Agent session, and a
Rex binding is used only while its process and hook/registry proof holds.

## Verified Rex behavior

Verified on 2026-11-19 against `rex 0.1.0-preview.20` (commit `e33d2481`,
API revision 16, supported revisions 0–16).

### Transports and identity

- The local server listens on a Unix socket by default:
  `~/Library/Application Support/rex/server.sock`, mode `0600`, admission
  `peer_credentials`. An HTTP request over that socket reaches the API; no
  token is involved.
- Remote listeners are explicit: `ssh://user@host` (the CLI runs the system
  `ssh`), built-in Tailscale (`--tailscale`, HTTPS
  `https://rex.<tailnet>.ts.net`), a tailnet Serve socket, a tailnet address
  (`--extra-listen tailnet://:7297`), or plain HTTP
  (`--extra-listen http://host:port --allow-anonymous`).
- Rex identifies a caller only by how it connected: Unix peer credentials, a
  Tailscale login, or anonymous. **Any accepted connection has full control of
  the server**, including starting programs as its account. There is no
  per-session authorization and no application token. The vendor documents a
  full authentication/authorization system as planned.
- Plain HTTP requires `--allow-anonymous` and is described by the vendor as
  "super dangerous" on an open network.

### HTTP and WebSocket endpoints

| Endpoint | Purpose |
| --- | --- |
| `GET /api/control` | WebSocket, subprotocol `rex.control.v1`: every method call and event |
| `GET /api/data` | WebSocket: one block's stream, or one file's bytes |
| `GET /api/help` | every method as JSON Schema |
| `GET /llms.txt` | the complete protocol and method reference, generated by the server |

The protocol is public and self-describing; `llms.txt` is the authoritative
reference for the connected server's revision.

### Control connection

- A client sends one `hello` within 5 s, then only `request` messages. The
  server answers with `welcome`, `response` and unsolicited `event` messages.
- Requests carry a client-chosen string `id` and a `payload`; responses carry
  the same `id`, a `seq`, and either `payload` or a stable `error.code`.
- `welcome` reports `api_revision`, `api_server_revision`, message limits and a
  `reconnect_token`. A dropped connection keeps its client for 60 s; sending
  the token in the next `hello` resumes the same client. Events missed while
  disconnected are lost, so the client re-reads state.
- Messages are at most 1 MiB. A connection that falls 8 MiB behind is closed
  (`event backlog exceeded`). The server pings every 120 s and closes after
  three unanswered pings.
- `session.attach_all` lets one connection call methods on every session and
  receive session events. `session.attach` / `session.bootstrap` are additionally
  required for data tickets and block ownership. **Verified:** one connection
  using only `session.attach_all` successfully called `session.view`,
  `com.superlogical.terminal.format` and `...write`.

### Methods used by this adapter

| Method | Use |
| --- | --- |
| `session.list`, `session.view`, `session.describe_block` | inventory and layouts |
| `com.superlogical.terminal.format` | screen and scrollback as `text`, `html` or `vt`; `trim`, `unwrap`, `max_bytes` + `blob_read` for large output |
| `com.superlogical.terminal.write` | type text (escape sequences allowed); returns `bytes_written` |
| `com.superlogical.terminal.process` | foreground/child processes, ancestor pids, cwd, home, last exit |
| `com.superlogical.terminal.modes` | alternate screen, bracketed paste, mouse reporting |
| `com.superlogical.terminal.title`, `…pwd`, `…size`, `…program_status` | metadata and state |
| `com.superlogical.terminal.download_begin` | open a regular file on the server's machine and get a data-stream ticket |
| `session.new_split`, `session.new_window` | start a fixed Agent command in a new block |
| `block.event` | `key`, `paste`, `mouse`, `wheel`, `focus` input |

Terminal block events include `bell`, `child_exited`, `pwd_changed`,
`title_changed`, `program_status_changed`, `ports_changed`, `resize` and
clipboard/notification events. There is **no terminal-content event**; live
output reaches clients only through a data connection.

The shell flavor accepts `command` (program and arguments), `cwd`, `shell`,
`interactive`, `path_prepend` and `size`. That is how the Bridge starts
`claude` / `codex` in a Rex window without a shell command string.

### Data connections

`data.connect` (or a block method such as `download_begin`) issues a single-use
ticket. The client opens `/api/data` with a subprotocol — `rex.data.terminal.v1`
for terminal output, `rex.data.bytes.v1` for a file — and sends a binary HELLO
containing the 16-byte ticket. After a 32-byte WELCOME the server streams
binary messages.

- A terminal stream starts with a **Ghostty snapshot**, then the program's
  bytes, with Rex messages encoded as APC sequences. Resuming by byte count is
  supported for 60 s. This is the lossless, real-time, color path.
- A bytes stream carries a file; the server closes with status 1000 at EOF.
  **Verified:** an 18-byte fixture file arrived exactly, after a 32-byte
  WELCOME, with no range support.

## Agent binding

Rex itself does not know Agent session ids. A binding is accepted only when
independent signals agree: Rex's live process state for the block, plus either
an agent hook from inside that block or Claude's own process registry.

### Source 1 — Rex process state

`com.superlogical.terminal.process` returns, for a block:

- `child`: the process the terminal started (usually a login shell);
- `foreground`: the process actually in front, with `pid`, `name`, `path`,
  `argv0`, `script`, `cwd`;
- `ancestors`: the processes between foreground and child, nearest first;
- `home` and `last_exit`.

A live Agent is bound only while the block's `foreground` is the Agent process
itself (`name`/`argv0` identifies `claude`, and its `cwd` is the project
directory). If the screen has returned to a shell, the conversation is not
writable and not resumable, exactly as DESIGN.md requires for cmux terminals.

### Source 2 — Claude Code's process registry

Claude Code (2.1.x in this environment) writes one owner-only metadata file per
running process: `~/.claude/sessions/<pid>.json`. The fields used here are:

```json
{
  "pid": 84883,
  "sessionId": "0d0b408b-1b6e-4fbc-a684-fb936d9aca9f",
  "cwd": "/Users/example/project",
  "startedAt": 1795067744073,
  "procStart": "Wed Nov 19 13:09:47 2026",
  "status": "idle",
  "kind": "interactive",
  "entrypoint": "cli"
}
```

The file contains no conversation text. The transcript path is derived from
`cwd` and `sessionId`:

```
<home>/.claude/projects/<cwd with every non-alphanumeric character replaced by '-'>/<sessionId>.jsonl
```

**Verified:** this rule matched the live registry and an existing transcript for
16 of 16 local sessions. The rule is an implementation detail of Claude Code and
must be checked at runtime; a missing or mismatched transcript means no binding,
not a guess.

Local verification additionally compares `procStart` with the kernel's start
time for that pid. Remote verification cannot run `ps` on the server, so it
requires agreement on pid, process name, cwd, and a live registry entry. PID
reuse is bounded by Claude overwriting the registry at startup and by requiring
the pid to be the block's current foreground process.

### Remote binding

For a remote Rex host, the registry file is fetched through Rex itself:

1. `terminal.process` gives `home`, the foreground pid and cwd.
2. `download_begin` with `<home>/.claude/sessions/<pid>.json` returns a ticket.
3. The Bridge opens `/api/data` with `rex.data.bytes.v1`, sends the ticket and
   reads the file.
4. The same pid/name/cwd checks apply.
5. The transcript is downloaded from the derived path.

**Verified:** the file-download handshake and byte stream work against the
fixture server. The Bridge never accepts a caller-supplied path: only the
registry and the derived transcript path are fetched.

### Hook binding — the cmux-equivalent path

cmux binds Agent sessions through agent hooks. Rex can use the same mechanism
because Rex sets `REX_SESSION` and `REX_BLOCK` in the environment of every
terminal it opens, and the agent and its hooks inherit them.

- The Bridge offers an **opt-in, reversible hook installer**. In the Companion,
  the owner sees the exact commands that will be added to the Claude and Codex
  hook files and approves them. Existing cmux hooks are left untouched; a
  separate command tagged with this project's path is added, and uninstall
  removes only that command.
- The helper reads the hook JSON from stdin, plus `REX_SESSION`, `REX_BLOCK`
  and `REX_SERVER` from its environment. It records only the event name, its own
  pid and parent chain (so the Bridge can identify the agent process), the
  agent's session/thread id, transcript path, cwd and the Rex ids; prompt and
  transcript bodies never enter the spool.
- The Bridge accepts the binding only when the block exists on that server, the
  recorded agent process is the block's current foreground process, and the
  event belongs to a live agent session. A shell that merely exported the
  variables, an unknown block, a stale event or a block whose foreground has
  returned to the shell is ignored.
- This path works for both Claude and Codex and matches how cmux binds its own
  terminals. The installed Codex version has no pid-to-thread registry
  (`~/.codex/state_5.sqlite` has `threads` with `id`, `rollout_path`, `cwd` and
  timestamps but no pid; the lock files are held by the shared app-server), so
  hooks are the authoritative Codex source found.
- Hook files are user configuration. The installer is explicit, previews the
  diff, and is reversible. Codex may ask the user to trust the changed hook;
  the Companion explains that prompt. An issue pass never changes these files
  on its own.

Without installed hooks, Claude still binds through its pid registry. A Codex
block remains a **terminal** row: viewable and writable, but not presented as a
verified conversation and not resumable by its thread id.

### Remote hook binding

Hooks run on the Rex host's machine. In v1 only a local Rex host (the same Mac
as the Bridge) can deliver hook records directly. For a remote host, a later
phase can install a helper that writes one bounded file per block under
`<home>/.local/state/term-remote/rex/`, and the Bridge downloads it through
`rex.data.bytes.v1`; until then remote Codex is terminal-only. Remote Claude
still works through the registry/transcript download described above.

## Rex as a term remote provider

| term remote | Rex | Notes |
| --- | --- | --- |
| Provider | Rex server | One provider per server endpoint (local socket or tailnet) |
| Host | The server's machine | `server.status.host_id`; a local UDS host vs a remote host |
| Space | Session | Grant and navigation unit; its id becomes a derived space UUID |
| Terminal | A `com.superlogical.terminal` block | Owns screen, process, cwd and the Agent binding |
| Layout | Window/layer split tree | Display only; not a grant or conversation boundary |
| Conversation | An Agent session bound to a block | Proved by hooks or Claude's pid registry |
| — | Window (a tab inside a session) | Navigation inside the space; no grant or conversation identity |
| — | Floating layer | Out of scope for v1 |
| — | Tunnel block | Not a terminal; not mapped in v1 |

Consequences for the provider implementation:

1. Rex implements `TerminalProvider` and `ConversationProvider` from
   [TERM-REMOTE.md](TERM-REMOTE.md). It is not a `CmuxControlling` method proxy
   and does not appear in `CmuxBackendRouter`.
2. `SpaceID` and `TerminalID` are UUIDs derived from the provider id and the
   Rex session/block id. `ClientScope` keeps its UUID validation; the owner UI
   resolves labels. The phone never uses a raw `session:` or `block:` id in a
   request.
3. Terminals without a proved conversation are ordinary `Terminal`s in the
   generic model. `/v3` exposes them to clients that advertise the capability;
   the old `/v1` cmux projection never shows them.
4. Remote transcript reads are whole-file downloads into the owner-only cache.
   Live updates use the screen preview; history refreshes on open and on an
   explicit pull.

## Proposed architecture

```
 iPhone / Android                Mac companion
        │  signed /v3 HTTPS + link       │ owner-only Unix channel
        └──────────────┬─────────────────┘
                       ▼
                  term remote Bridge (macOS)
                 ┌─────┴──────────────────┐
      ProviderRegistry                 DirectoryService
      cmux desktop + cmux-tui          grants, dedupe, ledger
      Rex provider ── RexControlClient ──▶ Rex server
            RexAgentBinder                unix socket /
            RexTranscriptSource           tailnet HTTPS
```

### New Swift modules

| Module | Responsibility |
| --- | --- |
| `RexControlClient` | WebSocket framing, hello/welcome, request table, event stream, `seq`, reconnect token, bounded limits. Transport abstraction for Unix socket, TCP and TLS. |
| `RexHostRepository` | Owner-only host list in Bridge state: id, label, endpoint kind/path, added time. No credentials (Rex has none). |
| `RexService` | One control connection per host; `attach_all` with `event_scope: session`; inventory/view cache; screen polling; process metadata; input through the existing `MutationLedger`. |
| `RexAgentBinder` | Binding: hook records for Claude and Codex; Claude's `<pid>.json` registry as the no-setup fallback; local `ps` start-time check; invalidation when the process changes. |
| `RexHookInstaller` | Explicit, reversible install/uninstall of the project's agent hook command in Claude/Codex settings, with a diff preview. Never touches the existing cmux hook. |
| `RexHookSpool` | Owner-only, bounded records written by the hook helper; validates block, session and foreground agent before a binding. |
| `RexTranscriptSource` | Local: reads the transcript path directly. Remote: downloads the registry/transcript, verifies the prefix, and materializes an owner-only cache file for the existing `TranscriptReader`. |
| `RexScreenCache` | Per-block formatted screen, digest and timestamp; polls only while a viewer or conversation is open. Bounded entries/bytes. |
| `RexConversationComposer` | Fixed writes: text+Return, Escape/Ctrl-C, `/model`, fixed `claude`/`codex` start commands. Reuses the existing prompt-safety and model-confirmation policies. |
| `RexClientResources` | Codable DTOs for the provider internals. The phone uses the generic `term remote` DTOs, never a Rex protocol shape. |

Keep the protocol target free of AppKit/SwiftUI. It may live in a new
`Sources/CmuxRemoteRex` package target that depends on `CmuxRemoteCore` and
SwiftNIO; the Bridge and CLI compose it. The iOS target must not link it.

### Directory integration

The Rex provider returns `Space`/`Terminal` descriptors and
`ConversationBinding`s to the generic `DirectoryService`; it does not extend a
cmux record dictionary.

- `bindings()` returns only proved bindings. The directory merges them by Agent
  session id with the cmux providers.
- If two providers both claim a live binding for one conversation, the row is
  listed read-only with `binding_ambiguous` and no write is offered. The
  directory never picks a provider by preference order.
- A Rex conversation's `SpaceID` is the derived UUID of its Rex session; its
  `TerminalID` is the derived UUID of its block. That is the generic model, not
  a `workspaceID`/`surfaceID` pair.
- A block with no proved agent is a `Terminal`; it has a screen and an input
  channel, no history and no conversation actions.
- The old `/v1` cmux projection is produced from the cmux provider only. Rex
  conversations and terminals are visible only through `/v3`.

### Grants and enrollment

- Derive a stable UUID from `SHA-256("term-remote.rex" + providerID + rexSessionID)`
  with UUID version/variant bits set. If it ever collides with another live
  `Space` UUID, fail closed and report the conflict.
- The owner UI lists Rex sessions with their labels and derived IDs; the owner
  includes selected spaces when opening enrollment. Approval shows labels, not
  opaque ids.
- Use the generic capabilities: `workspaceRead` (a generic Space),
  `terminalRead`, `terminalInput`, `conversationRead`, `conversationControl`
  and `conversationStart`. A terminal without a conversation needs only
  `terminalRead`/`terminalInput`.
- Grants remain per space and revocable. Every request rechecks the grant and
  the live binding at the final boundary.

### Generic routes and the Rex adapter

The phone routes are the generic `/v3` resources in
[TERM-REMOTE.md](TERM-REMOTE.md). The Rex provider supplies their data; it does
not add `/v2/rex/...` endpoints.

| Generic resource | Rex implementation |
| --- | --- |
| `GET /v3/providers` | provider descriptor from `server.status`, `server.version` |
| `GET /v3/spaces` | `session.list` |
| `GET /v3/spaces/:space/layout` | `session.view` |
| `GET /v3/spaces/:space/terminals` | blocks in the view plus `terminal.process`/`title`/`pwd` |
| `GET /v3/terminals/:terminal/screen` | `terminal.format` (`text` in v1) |
| `POST /v3/terminals/:terminal/input` | `terminal.write` with journaled operations |
| `GET /v3/conversations` | `RexAgentBinder` bindings |
| `GET /v3/conversations/:id/history` | local transcript or downloaded cache |
| `POST /v3/conversations/:id/send` | prompt check + `terminal.write` |
| `POST /v3/conversations/:id/interrupt` | `terminal.write` with Escape/Ctrl-C |
| `POST /v3/spaces/:space/conversations` | `session.new_split`/`new_window` with fixed `command` |
| `POST /v3/conversations/:id/resume` | fixed `claude --resume` / `codex resume` in a new block |

Rules:

- The Bridge never accepts a Rex method name, block id pattern or endpoint from
  the caller. The provider resolves its own ids from the generic UUIDs.
- Input is bounded (16 KiB), journaled before dispatch, and never retried. Rex
  has no idempotency key, so a lost reply is `outcome_unknown`.
- The Bridge never calls `session.own_block`, `terminal.resize`,
  `terminal.set_theme`, `client.action`, `block.close`, `session.destroy`,
  `server.stop`, `hosts.*`, `config_reload` or `set_script` in this phase.
- Screen reads never change focus, size or ownership. Polling is cancellable and
  stops when the last viewer leaves.

## Reading

### Conversation history

Local Rex host:

- Read the transcript path directly with the existing `TranscriptReader`,
  `TranscriptGenerationStore`, archive cursor and tool/image indexing. No new
  format is invented.
- The transcript's cwd is the project directory; project files and Git remain
  subject to the existing `ProjectFilePolicy`. A Rex conversation does not
  inherit cmux-specific project semantics.

Remote Rex host:

- Download the transcript through `rex.data.bytes.v1`, bound to a maximum size
  (32 MiB, matching the local transcript read limit) and a timeout.
- Materialize it under the Bridge's owner-only state
  (`rex-transcripts/<host>/<session>.jsonl`), then feed the same parser. If the
  new download starts with the cached bytes, append in place so the existing
  generation and cursors stay stable; otherwise replace the file and re-anchor
  clients.
- `download_begin` has no byte range. A changed transcript means a whole-file
  download. Refresh on opening a conversation and on an explicit pull, not on
  every foreground tick. Live growth comes from the screen preview.
- Cache is bounded (for example 200 conversations / 64 MiB). Removing a grant or
  host deletes its cache. No transcript body enters logs.

### Live preview and state

- `format: text` with `trim`/`unwrap` is parsed by the existing
  `AgentChatProseScreenExtractor` and `TuiPromptSafety`; the result is a
  replaceable preview, not token streaming.
- `process` identifies the Agent and its cwd; `program_status` (OSC 7501) and
  the Claude registry's `status` feed the working/idle badge. When a program
  reports `blocked` with a kind, the phone can show it as a pending state in a
  later phase.
- The screen alternate-screen mode is reported by `modes`; a full-screen editor
  has no scrollback. Say so in the UI rather than faking history.

### Terminal-only blocks

The same `format` polling, bounded by `max_bytes` and a small in-memory cache.
No transcript, no tool cards, no Markdown. The phone shows a monospaced screen
with a "jump to latest" control and a composer. The Mac viewer shows the same
text (or `vt`, see below).

## Writing and starting

- **Send:** require a live binding, a positively empty prompt and no draft or
  dialog on the formatted screen, then one `terminal.write` with the text plus
  `\r`. Bracket paste is used only when `modes` proves it; otherwise multiline
  input is refused exactly as the cmux-tui adapter refuses it.
- **Stop:** Escape for a polite interrupt, Ctrl-C for `hard`, through
  `terminal.write`. Cancellation or a changed binding is an error.
- **Model:** Claude in the first phase. Write `/model <name>` and confirm the
  screen with the existing `ClaudeModelConfirmation` policy. Codex's picker
  needs screen-verified arrow-key navigation; it is a later step, so the model
  menu is Claude-only at first.
- **Start a conversation:** `session.new_split` or `session.new_window` with a
  shell block and `options: {command: [...], cwd, interactive: true}`. The
  command is fixed (`claude`, `codex --no-daemon`); no caller text is ever part
  of the argv. The first prompt may be passed as one argument using the same
  quoting rules as the existing start path. This requires `conversationStart` on
  the derived Space UUID.
- **Resume:** `claude --resume <session-id>` or `codex resume <thread-id>` in a
  new block, using the id from the verified binding (hook or registry) and the
  cwd recorded in the transcript/rollout.
- **Feed decisions:** no Rex Feed exists. Recognized Claude/Codex permission
  layouts can be parsed from the formatted screen in a later phase, reusing the
  cmux-tui decision parser. V1 does not claim approval support.

## Desktop (Mac companion)

Rex contributes a **provider card** to the Companion's Sources list. The generic
Sources/tree/viewer design is in [TERM-REMOTE.md](TERM-REMOTE.md).

- The card shows the local server (or saved remote endpoints), status,
  capability set and last error. Add/remove is owner-only.
- It lists Spaces (Rex sessions) → layouts (Rex windows) → Terminals (Rex
  blocks) → bound Conversations. A row shows the Agent badge, foreground
  process, cwd and last error.
- An **Agent binding** control shows whether this project's hook is installed,
  previews the exact commands, and installs or uninstalls it on request. Without
  it, Codex rows stay terminal-only.
- Selecting a terminal opens the generic viewer:
  `term remote view --space <uuid> --terminal <uuid>` in any local terminal, or
  in a native cmux workspace when cmux is available. The viewer is not
  Rex-specific.
- The owner selects spaces to expose to a phone during enrollment.

The viewer follows the existing `mirror view` pattern: raw local input, bounded
`terminal.write` batches, polled `format` output, no ownership or resize of the
Rex block, and a local detach that leaves the Rex process running. A later step
can project a Rex provider's spaces into a native cmux sidebar group (session →
group, window → workspace, block → surface); that is presentation only.

`format: vt` is the preferred desktop presentation once the viewer exists; it
gives colors and styles without a streaming parser. The terminal data stream
and Ghostty snapshot remain the later, lossless option.

## Mobile (iPhone and Android)

Rex is one source in the generic source-aware home described in
[TERM-REMOTE.md](TERM-REMOTE.md). The conversation and terminal views are shared
components, not Rex-specific screens.

- **Same list.** Rex conversations (Claude through its registry or hooks, Codex
  through hooks) appear with the host/space grouping, filters, search,
  pull-to-refresh and status design already in use. A source badge distinguishes
  them; there is no separate navigation stack.
- **Same conversation.** History, timeline, Markdown, tool cards, composer, stop
  and model menu are reused because the provider feeds the same
  `ConversationSnapshot` parser.
- **Read-only states are the same.** A stale binding, an Agent that left the
  terminal, an unknown screen or a missing transcript produces the standard
  read-only/error states. No blind input.
- **Terminals** appear as generic terminal rows. Their detail view uses the
  shared design tokens: a monospaced text screen, refresh, jump-to-latest and a
  composer/key bar. It is presented as a live screen, not as a conversation with
  history.
- **Capabilities.** Rex spaces need `workspaceRead`; terminals need
  `terminalRead` (and `terminalInput` to type); conversations need
  `conversationRead`/`conversationControl`. The UI hides unsupported actions.
- **Android** consumes the same `/v3` DTOs and mirrors the screens. There is no
  separate Rex protocol implementation.
- Dictation, image selection and the composer work unchanged for conversations.
  Images recorded in a local transcript resolve through the existing image path;
  remote transcripts may lack their referenced files in v1 and must show them as
  unavailable rather than broken.

## Security and data ownership

- The Bridge remains the only network-facing component. Rex endpoints, block
  ids, screen text and transcript bodies never enter logs, fixtures, crash
  reports or public text.
- A grant is per `Space` (a Rex session). The owner selects spaces in the
  companion; a device cannot enumerate spaces it was not granted. Revocation is
  checked at the final boundary.
- A Rex connection has whole-server authority, so the Bridge exposes only fixed
  operations. It must never proxy arbitrary methods or accept a method name
  from a client.
- The derived `Space` UUID is opaque and stable; the phone never learns raw Rex
  ids, only generic UUIDs through scoped routes.
- File downloads are only the Claude registry and derived transcript paths.
  Caller input is never a path. Downloads are bounded, timed out and cached in
  owner-only storage.
- The hook installer is an explicit user-configuration change: it shows the
  exact diff, adds only this project's command, and removes only that command on
  uninstall. Hook records live in an owner-only bounded spool and contain ids
  and event names, never prompt or transcript text.
- Input is the highest-risk operation: it runs inside the owner's shell. The
  fixed text+Return, capability check, prompt check, operation journal and
  no-retry rule are the same protections used for every provider's terminal
  input.
- Do not call Rex methods that change layout, ownership, focus, configuration or
  the server itself in this phase, even though the API allows them.
- Plain HTTP with `--allow-anonymous` gives every caller full server access.
  Refuse it by default; an explicit opt-in must show a warning, and Tailscale or
  a private VPN is the recommended path.

## Rejected or deferred alternatives

| Alternative | Why not |
| --- | --- |
| Phone/Mac connect directly to Rex | Bypasses device identity, per-device revocation, pinned transport and the single-network-surface rule; requires the phone to be on the tailnet; plain HTTP is full access. |
| Treat every block running an Agent as a conversation | Provenance would rest on cwd/title/timing. A hook or the Claude registry plus Rex's process tree is the accepted proof; no proof means no conversation. |
| Bind Codex by cwd or the newest rollout file | Explicitly excluded by DESIGN.md's provenance rule. Codex uses the hook binding; without installed hooks it stays terminal-only. |
| Run the `rex` CLI per request | Process-per-call latency, an installed-CLI dependency, no events or streaming, and a shell/argument surface this project avoids. |
| Implement the data stream first | Requires a Ghostty snapshot decoder before any screen can be shown; `format` already returns the screen. |
| Generic Rex RPC proxy | Gives a device whole-server authority, including process execution, and violates the "no generic remote RPC proxy" rule. |

## Local commands

```sh
# Provider spaces and terminals (owner-only socket)
term-remote providers spaces
term-remote providers terminals --space <derived-uuid>

# A plain-text viewer; polls the screen and forwards lines
term-remote view --terminal <derived-uuid>
term-remote view --space <derived-uuid>        # its first terminal

# Explicit, reversible Agent hook installation. Nothing changes until this runs.
term-remote hooks status
term-remote hooks install --dry-run
term-remote hooks install
term-remote hooks remove
```

`hooks install` adds only commands tagged with `term-remote-hook`, leaves the
existing cmux hooks untouched, backs up each changed file, and never runs by
itself. Codex may ask the reader to trust the new hook when it next starts.
`agent-hook` is the helper the installed command calls; it records ids and paths
only and prints no prompt or transcript text.

## Phases and effort

Indicative, not a schedule commitment.

These phases slot into the term remote stages in [TERM-REMOTE.md](TERM-REMOTE.md).
The cmux provider must exist in the generic model first; Rex is the second
provider.

| Phase | Work | Rough size |
| --- | --- | --- |
| A | `RexControlClient` (UDS + TCP/TLS WebSocket, framing, reconnect), fixture server and protocol tests | 2–3 weeks |
| B | Rex implements `TerminalProvider`/`ConversationProvider`: `RexService`, Claude registry binding, hook spool/installer, `RexScreenCache`, directory integration and `/v3` | 3 weeks |
| C | Companion Rex provider card, hook toggle, generic viewer, enrollment selection; phone source-aware path for Claude and hook-bound Codex | 3 weeks |
| D | Remote hosts, remote registry/transcript downloads and cache; remote Codex hook-spool design | 3 weeks |
| E | `format: "vt"` viewer, optional data stream + Ghostty snapshot, screen-based Feed decisions | 3–4 weeks |

Phase A and the first half of Phase B answer the riskiest questions: a native
WebSocket client over a Unix socket inside the Bridge, and a binding that is
provable rather than inferred. A fixture protocol server keeps CI independent
of an installed Rex binary.

## Verification plan

- Unit tests for hello/welcome, request ids, error codes, `seq` ordering,
  attach requirements, reconnect/resume, message and backlog limits, close
  reasons and event ordering.
- Binding tests: a fixture process named `claude` with a matching registry file
  and transcript binds; a reused/foreign pid, a cwd mismatch, a missing
  registry, a stale entry and a shell foreground do not.
- Hook tests: an event whose `REX_SESSION`/`REX_BLOCK` names a live block whose
  foreground is the reporting agent binds; a forged env from a shell, an unknown
  block, a stale or duplicate event, and another account's block are ignored.
- Installer tests: only this project's command is added, the existing cmux hook
  is byte-identical, uninstall restores the original file, and a malformed
  config is refused without writing.
- Remote download tests: a fixture bytes stream, an oversized file, a timeout,
  a truncated stream, a changed transcript (prefix append vs replace) and a
  cache eviction.
- Conversation tests: history/tool cards/preview from the same parser, send
  prompt checks, interrupt, model confirmation, resume/start commands, and
  deduplication against a cmux binding for the same Agent session.
- Authorization tests: a grant for one space cannot read or type into another;
  revocation is checked at the final boundary; input without `terminalInput` is
  refused; a terminal row requires only `terminalRead`.
- Durable-operation tests: a lost reply is `outcome_unknown`, a duplicate
  operation id returns the receipt, and a different payload under the same id
  is rejected.
- Integration, when a Rex binary is available: an isolated
  `rex server run --listen 127.0.0.1:0 --allow-anonymous --restore=false
  --state-dir <temporary>`; create a fixture session, attach, format, write a
  marker, download a fixture file, read the marker back and destroy only that
  fixture session. Never use the owner's server, sessions or terminals. Assert
  `terminal.size` is unchanged before and after reads.
- A real Agent acceptance pass uses an owner-created Rex block and a real
  Claude Code process, with the owner present. It is never part of CI and never
  targets a user's existing conversation.
- `scripts/verify.sh`; `scripts/build-ios.sh` after client changes; the Android
  build and unit tests after Android changes. State plainly what was not checked
  (a physical phone, a real Rex server on another machine, a real Codex
  binding, an actual Ghostty snapshot stream).

## Open decisions and risks

1. **Hook installation UX:** Codex matches cmux only when the hook is installed.
   The release needs an explicit owner approval, a diff preview, a reversible
   uninstall and an explanation of Codex's trust prompt. Without this UI,
   Codex stays terminal-only even though the binding design is ready.
2. **Remote Codex:** terminal-only until the remote hook-spool design is
   accepted; remote Claude already has the registry/transcript download path.
3. **Feed decisions:** the phone's pending-actions UI has no Rex source. Screen
   recognition is possible later, but it must not be presented as a reliable
   approval adapter.
4. **Files, Git and images** for a remote Rex host need Rex file downloads and
   cannot run Git remotely without executing a command; v1 should hide these
   actions rather than degrade silently.
5. **Preview software:** Rex is `0.1.0-preview.20`; API revisions change. Pin a
   supported revision, fail closed on unknown methods, and surface
   `rex_update_required` instead of guessing.
6. **No Rex-side authorization:** the Bridge is the security boundary. A
   compromise of the Bridge's account already equals full local access, but the
   adapter must not widen that to devices.
