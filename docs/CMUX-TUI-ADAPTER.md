# Local cmux-tui daemon adapter

## Contract

Mac A opens a managed `cmux ssh` workspace whose terminal processes belong to
Mac B's cmux-tui daemon. The phone connects only to B's Bridge. One Bridge
supports the desktop cmux socket and local daemon sockets together, without
mode selection or phone/Mac page changes. It never connects back to A, starts
a second agent, or changes the official cmux application.

The desktop socket and cmux-tui socket use different wire protocols. The daemon
adapter implements existing `CmuxControlling` domain methods using the public
`cmux.protocol/2` API. It does not expose an arbitrary RPC proxy or use private
protocol-v12 commands. Backend-only SwiftTerm 1.11.2 (MIT) decodes bounded VT
replays to identify faint placeholders; no terminal view or process is created,
and no terminal emulator is added to the phone.

## Startup and discovery

```sh
cmux-remote serve --pair
# Optional exact socket for a daemon using a non-default runtime directory:
cmux-remote serve --tui-socket /absolute/path/to/daemon.sock --pair
```

Daemon sockets are discovered in private same-user `cmux-tui-<uid>` and
`cmux-tui-hashed-<uid>` directories under the process temporary directory and
`/tmp`. Up to sixteen selected/discovered sockets are allowed. Discovery is
refreshed during reads, so a later managed SSH workspace can appear without
restarting the Bridge. Explicit `--tui-socket` paths may be repeated for custom
locations; `--socket` still selects the desktop socket. Only existing private
same-user Unix sockets with a matching peer UID are accepted. The adapter never
starts, upgrades or stops their daemons.

A daemon can be the available backend even if desktop cmux is not running.
The menu app adopts the existing Bridge through the owner channel; a resident
with discovered daemons can start without desktop capability setup. Native
outgoing Mac workspace projections still require a desktop cmux backend.

One phone pairing/approval covers owner-selected workspace UUIDs from all local
backends. Existing grants are never silently expanded; select daemon workspaces
and approve access using the existing pairing interface when adding them.
If a backend is unavailable, its inventory is omitted and stable
`backend_errors` are included; its old action targets never fall through to
another backend. Invalid or replaced daemon identities stop their reads/actions.

## Discovery, history and authorization

Use one bounded `session.snapshot` to resolve daemon identity, workspaces,
screens, panes, tabs, terminals and hook-proven Agent sessions. Accept only
Claude/Codex hook records with an exact provider session UUID and a live terminal
in one unambiguous workspace. Names, cwd and screen text do not prove Agent
ownership. Multiple views in different workspaces are refused for conversation
control rather than selecting an arbitrary authorization scope.

Map typed workspace/terminal IDs to stable Bridge UUIDs derived from daemon
machine/session identity plus the complete typed ID. Phone grants remain explicit
workspace UUID grants. Agent replacement or a moved workspace invalidates old
writes. Desktop/daemon sessions remain distinct even for identical provider IDs.

Locate transcripts by exact provider UUID under configured Claude/Codex roots.
Lookup is bounded, ignores symlink files/directories and refuses ambiguous
matches. Never import global unrelated history. Claude's canonical pending path
can represent a session before its first file exists; it does not create files.
A private metadata archive retains at most 200 known daemon conversations. After
restart/end, archived bindings are read-only unless a fresh daemon snapshot
proves the same Agent and terminal live. The archive contains no transcript or
image bodies; history, tools, images, files and Git use existing local readers.

Foreground phone polling reads fresh metadata/screens, producing the existing
best-effort prose preview. This is not token-level streaming or a new phone event
subscription. Polling never changes A's terminal size, selection or focus.

## Input, attachments and stopping

Every send rechecks Agent/terminal/workspace, a positively empty styled prompt,
and resource revision after reading terminal state. Unknown screens, drafts and
dialogs block typing. Faint placeholders are ignored only with replay style
proof. A mutation carries the device-scoped logical operation identity and a
daemon idempotency key. Lost replies never trigger automatic retries.

Images reuse existing PNG/JPEG validation and limits. The Bridge writes them to
private `tui-images/<conversation>/<operation>/` files with server-generated
names, pastes literal quoted paths into the existing Agent input, and submits
with the text. Attachment-only sends are supported. The cache is limited to
4,096 entries / 64 MiB and retained for asynchronous Agent reads and conversation
history. Symlinks, permissive files and cross-conversation cache reads are denied.
No API invokes a shell to interpret the pasted paths. Bound uploaded-image
references can be read with conversation permission; other project images still
require project-read permission.

Bracketed paste is used only when the replay proves it enabled. Unsupported
multiline input is refused; prompt control characters are refused. Paste plus
submission is one terminal write. Stop mirrors the desktop contract: Esc for a
polite interrupt, Ctrl+C for `hard`. It never kills the daemon or closes the
terminal. Cancellation/changed bindings remain errors.

## Agent permission decisions

The daemon resource API has no desktop Feed-equivalent permission-reply RPC.
This pass recognizes only the standard English Claude/Codex runtime command
permission layouts, while the hook proves that Agent is blocked. Once and Deny
reuse the current phone action UI; `available_modes` restricts the existing
policy to those actual modes. Permanent approval, plan modes, startup trust
and arbitrary/multi-step questions are not synthesized.

Each request binds an exact Agent, workspace, daemon generation, screen text and
output revision. Before sending a fixed Enter/y or Escape choice, the adapter
rechecks the binding and exact screen and supplies an expected resource revision.
A durable internal decision intent keyed by this request prevents two devices,
new phone operation IDs or a Bridge restart from answering it twice. Unknown
outcomes stay unknown; no generic number-key approval or automatic permission
acceptance is added. Unrecognized layouts yield no actionable decision.

The resource revision guards graph/Agent changes. The API has no atomic
screen-version-and-input transaction; simultaneous human edits remain a best-
effort screen guard, just as existing terminal controls require avoiding concurrent
composition. This pass does not claim protocol-level exclusive input ownership.

## Verification

Fixtures cover wire protocol/response IDs, private socket discovery, ID mapping,
ended/replaced/moved and ambiguous bindings, exact history lookup, faint
placeholders/drafts/dialogs, attachment boundaries, uncertain input, decision
replay, existing phone routes and mixed backends. Exercise an independent
real daemon with only fixture processes/data. Never send test input to a user's
live Agent. Record executed operations and missing physical-device acceptance.

## Executed evidence — 2026-10-13

- `scripts/verify.sh`: 230 Swift tests in 46 suites, existing phone guards,
  locale parity (214 phone keys / 114 Mac keys), release checks and
  `git diff --check` passed on the final run.
- Native Mac app/helper build and signature verification passed. The existing
  iPhone target compiled with the shared Feed mode policy; no page/layout changes
  or Simulator installation were performed.
- Installed cmux-tui build `c18c5c1243f4b5a7a41dd84b89b113b29749ff43` ran as an
  independent fixture daemon. Its actual public snapshot established the
  `tab.content_kind` / `tab.content_id` binding schema and local socket behavior.
- A real hook-helper event registered a controlled Python PTY fixture. A pinned,
  enrolled HTTPS test client saw exactly its approved fixture workspace/session,
  read its local JSONL history, sent text and PNG attachments, received valid
  receipts for Esc/Ctrl+C, and answered the recognized permission fixture Once.
  The PTY recorded actual delivery for text, both interrupts and the permission
  key. The temporary phone grants were revoked afterward.
- This proves daemon + Bridge + existing client API interoperability; it does not
  claim an actual Claude/Codex runtime, a physical iPhone or a two-Mac SSH pass.
  Agent-specific attachment ingestion and real permission layouts still need
  that physical acceptance. Recognition remains limited to the documented layouts.
