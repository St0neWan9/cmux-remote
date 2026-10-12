# Native Remote groups and workspace mirrors

The Mac Companion and resident `cmux-remote` Bridge integrate with the official
cmux **Default Workspaces** sidebar. Local workspaces keep their original rows,
menus, selection and appearance. The Bridge places remote projections in a native
**Remote** group below them, using `workspace.group.*` and a complete group-block
reorder. cmux draws both local and remote rows; this project does not reimplement
or replace the native workspace list.

The public ExtensionKit sidebar scene replaces the workspace-list area rather
than appending a section. The earlier replacement-sidebar prototype remains as
source reference under `mac/Extension`, but is no longer built or embedded in the
Companion. Installing the Companion retires only this project's old extension.
No official cmux binary is modified or restarted. Extensions beta is not required
for the native-group flow.

Discovery and credentials remain in the resident Bridge. The Companion reads
bounded public Bonjour hints through `mac.discovery.list` and resolves selected
observed hosts through `mac.discovery.resolve`. Discovery never approves a peer;
explicit trust and host-side enrollment approval remain required. The iPhone uses
the same host identity and authorization contract.

## Build and install

```sh
scripts/verify.sh
scripts/build-macos.sh
scripts/install-macos.sh
```

The generated project is `mac/CmuxRemoteMac.xcodeproj`. Debug builds use ad-hoc
signatures and the build host's active architecture. The containing Companion is
independent and has no shared App Group containing remote credentials. Public
releases still need Developer ID signing/notarization.

`CMUX_REMOTE_MAC_SIGNING_IDENTITY` selects an existing signing identity and defaults
to `-` (ad-hoc). Keep cmux's sidebar provider set to **Default Workspaces**. If the
old prototype was selected, choose **Sidebar: Default Workspaces** in the Command
Palette. Do not choose the replacement Extension Sidebar for this flow.

The NativeRemoteWorkspaceGroup service creates its own group with the durable
external identity `cmux-remote.native.remote`. A user-created group named Remote
is not adopted merely because the name matches. Repeated grouping does not
create another section. Group placement keeps every other workspace's relative
order and does not focus another window or workspace.

The resident Bridge lists authorized remote workspaces as native rows in this
group after connection. An unopened row runs an owner-only selection waiter.
Selecting it checks current authority and attaches into that same native
workspace; inventory refresh does not read remote terminal contents or select
a workspace. The first viewer reuses the row’s existing terminal; additional
remote panes and tabs use the same owned mirror coordinator.
Previously enrolled hosts stay available under Saved connections when Bonjour
has no nearby services, using their pinned endpoint and existing grant.

## Start both resident Bridges

Build/use the same updated `cmux-remote` executable on both Macs. On each Mac,
start `serve` inside an official cmux terminal when its socket mode is `cmuxOnly`:

On a Mac with no Bridge state yet, run `.build/debug/cmux-remote init` once before
`serve`. Do not reinitialize or replace an existing paired state directory.

```sh
.build/debug/cmux-remote serve --listen 0.0.0.0
```

The server defaults to loopback without this explicit LAN listen option. Bonjour
discovery is enabled unless `--no-discovery` is selected. `--state` chooses a
separate private state directory; the current containing app uses the default
`~/.local/state/cmux-remote/owner.sock`. Its owner-only control socket is not a LAN
endpoint. Using the official cmux CLI does not bypass cmux's ancestry policy.

When adding this Mac, open enrollment on the remote host, optionally confined to
one current workspace:

```sh
.build/debug/cmux-remote enrollment open --workspace <remote-workspace-UUID>
```

Select the host in the Companion opened from the sidebar. Confirm the host identity/certificate
fingerprint explicitly before sending an enrollment request. On the remote host,
inspect the exact request and approve only its requested workspace/capabilities:

```sh
.build/debug/cmux-remote enrollment pending
.build/debug/cmux-remote enrollment approve <request-UUID> \
  --workspace <remote-workspace-UUID> \
  --capability workspaceRead --capability terminalRead --capability terminalInput
```

For a read-only viewer, omit `terminalInput`. Mac enrollment explicitly requests
these terminal capabilities; existing phone permissions do not imply terminal
access. The `--control` convenience flag grants chat/Feed permissions and is not
a substitute for explicitly granting mirror capabilities. Saved host connections
and this Mac's signing key remain in owner-only files outside the repository.

## Mirror a workspace

The same flow is also available from the local CLI:

```sh
.build/debug/cmux-remote discover
.build/debug/cmux-remote connect HOST_ID --trust-certificate VERIFIED_SHA256
.build/debug/cmux-remote connect status
.build/debug/cmux-remote connect cancel
.build/debug/cmux-remote connect forget HOST_ID
```

New hosts require explicit fingerprint confirmation and remote owner approval;
saved hosts restore their existing grant without another trust prompt. `forget`
removes only local saved trust and detaches that host's local viewers. Revoke the
device on the host to remove its remote authorization. The Companion exposes the
same local forgetting action in a saved host's context menu.

`connect status` returns `connections` (saved host metadata) and `enrollment`
(the current request, or `{"state":"idle"}` when none exists). Saved metadata
does not assert that a remote host is currently reachable. Owner-channel failures
remain errors; an idle enrollment is a normal state.

After approval, select a remote workspace in the native **Remote** group, or
use **Mirror here** in the Companion. Both select the same recorded native row.
The local Bridge checks terminal replay support before attaching its viewers;
it does not start another remote Agent:

```sh
.build/debug/cmux-remote mirror workspace --host <saved-host-ID> \
  --workspace <remote-workspace-UUID>
.build/debug/cmux-remote mirror catalog
.build/debug/cmux-remote mirror list
.build/debug/cmux-remote mirror status
.build/debug/cmux-remote mirror sync --host <saved-host-ID> --workspace <remote-workspace-UUID>
```

`mirror view --projection <UUID>` is started by the local Bridge inside each
created panel. It uses the local owner channel, not credentials in argv or URLs.
The existing remote shell/Agent remains the producer. Ctrl-] detaches a viewer;
closing it does not send EOF or an interrupt to the remote process. A stale
producer epoch detaches the view rather than typing into its replacement. To
remove a saved host locally, the owner channel supports `mac.forget`; host-side
`clients revoke` remains the authoritative revocation operation.

## Supported behavior and current limits

- Native inventory state is bounded and saved in an owner-only ledger before
  creation/attachment. An unknown mutation result is paused rather than creating
  a duplicate workspace. Pending rows can reconnect to the same ledger after a
  resident restart. Completed attached rows have owner-only metadata checkpoints. On startup,
  the Bridge rechecks the saved grant, exact local membership, absence of a
  repurposed local Agent and every remote runtime epoch before restoring the
  same projection IDs. No terminal is created, focused or restarted by recovery.
  Partial/unknown layout transactions have no restorable checkpoint. Closing a native row
  does not automatically recreate it on the next inventory refresh. Catalog
  status derives from current local windows and mirror bindings. An explicit
  Mirror here/CLI open checks every local window and current remote authority;
  a confirmed closed row gets one new pending workspace under the same catalog
  entry. An existing partial or user-edited mirror remains untouched. A moved
  workspace uses its actual window. Unknown creation outcomes are not repeated.
  Confirmed creation/list publication gaps are bounded read waits, not another
  workspace creation.

- Terminal-only initial layout preserves split orientation/nesting and tabs
  within panes. Precise split proportions are not restored. Older cmux versions
  without a layout tree fall back to ordered panes.
- The output is structured character-grid replay converted to VT/ANSI, not a
  screenshot. The viewer reads snapshots with an intentional 300 ms delay after
  each request; actual cadence also includes network/cmux capture time.
- The public local socket does not supply the official authorized continuous
  terminal output subscription. Changes between captures can be missed. This is
  not claimed as lossless/native mirror parity.
- Browsers, graphics, remote clipboard, full scrollback and shared resizing are
  not supported. Different terminal sizes can clip the producer's content.
- Snapshots publish only after the complete paint: baseline resets and positioned
  TUI rows share one DEC synchronized update. The local Bridge also normalizes
  older peers' early releases, keeping their baseline and paint in one update.
  Current peers also include a positioned repaint and a mode/theme/geometry key.
  Each viewer restores the complete screen once, then repaints in place while that
  key remains unchanged. It restores fully when the screen, geometry or modes
  change. This avoids repeated alternate-screen resets and their visible flashes.
  Both the source Bridge and viewer need this version for in-place updates;
  older peers retain the full-snapshot fallback. The capture cadence is unchanged.
- Local focus and mouse reports stay disabled in replayed terminals. Switching
  between the mirror and other windows does not send synthetic focus bytes into
  the remote prompt. Keyboard and bracketed-paste modes remain available; exiting
  a viewer resets its input-reporting modes before returning to the local shell.
- The local owner checks scoped topology snapshots on a two-second metadata
  cadence. Source additions create local viewers; removals close only their owned
  local projections. Split nesting and tab order are rebuilt by moving existing
  viewers, preserving their surface IDs and processes. Exact ratios are omitted.
  A title-only update renames views without rebuilding the split tree.
- Completed-view restart recovery retains the same local workspace, surfaces and
  viewer processes. A response lost during owner-channel restart stays a transport
  error so snapshot reads can reconnect; malformed received JSON remains an error.
  Input mutations never retry. Failed checkpoint validation appears in `mirror
  status` as a paused entry with a stable error code and `restore.<stage>` detail;
  it does not silently disappear from status or recreate terminals.
- Before mutation, the owner verifies local membership and retained producer
  epochs. A manually detached/replaced view, a foreign local tab, a local Agent
  replacing a removed viewer, or an unknown mutation outcome pauses structural
  synchronization. The Companion reports the failure; `mirror status` lists it.
  `mirror sync` requests an immediate check, and cannot silently resume a paused
  transaction. Inspect a partial layout and explicitly recreate its views.
  No remote terminal is closed when a local projection closes.
  A confirmed new local tab may require bounded read-only snapshot publication
  checks before layout writes. If a source is already removed and its local
  foreground viewer has exited, synchronization accepts only that removed
  binding's absence; a missing retained viewer or extra foreign tab still pauses.
  A late replay response cannot resurrect a deliberately removed projection.
- Hibernated terminals are refused before replay, because upstream replay can
  wake an Agent. Wake it explicitly on the host first.
- Input is ordered per viewer and deduplicated by device/operation in a durable
  owner-only host journal. Completed receipts and unknown intents survive host
  restart; unknown writes are not repeated. This does not establish an atomic
  exactly-once transaction with cmux. Full/unavailable journals stop new writes.
- Producer validation and input are separate official cmux calls, not an atomic
  compare-and-send operation. Observed runtime changes are rejected, but a host
  rebind between those calls remains a compatibility gap; do not claim native
  atomic binding guarantees.
- Remote revocation is rechecked on requests. Completed mirrors retain view IDs
  through a resident restart after fresh authority/producer checks. Transient
  owner-channel or remote Bridge read failures keep the existing screen and
  bindings while reconnecting, with four-second remote read deadlines and bounded
  viewer backoff up to three seconds. The open viewer owns retry lifetime;
  closing it cancels the reconnect task. Input writes never retry. Fresh GETs
  recheck identity, pin, scope and the server epoch; permission, identity, content
  and producer failures remain final. Local membership changes and partial
  transactions still need explicit recovery. Failed cold-start checkpoints stay
  visible and retained while healthy mirrors save their own state; explicit
  forget removes them.
- Without the needed cmux methods, permissions, or live bindings, the UI reports
  a stable failure instead of falling back to another terminal or unscoped RPC.

## Verification

Behavior tests cover terminal scope before cmux access, signed TLS replay/input,
Unicode and control-sequence handling, hibernated reads, stale producer epochs,
duplicate input, unknown outcomes, independent view detach and safe navigation
URLs. Fake cmux responders exercise the new protocol without touching user Agents.
Mac build/signature/registration checks and iPhone compilation are separate gates.
Record real official-cmux replay, typing latency and layout observations before
claiming live mirror acceptance. A successful build or fake TLS test alone does
not prove a physical two-Mac mirror.

Apple HIG pages consulted: [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
and [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy).
The identity confirmation also uses a native [sheet](https://developer.apple.com/design/human-interface-guidelines/sheets).
They returned JavaScript-only pages during this implementation; the UI uses native
lists, navigation and explicit trust prompts, with visual verification recorded separately.

Pinned public SDK and replay-source provenance live in `Vendor/CmuxExtensionKit/UPSTREAM.md`
and `Vendor/CmuxTerminalReplay/UPSTREAM.md`. Their upstream GPL notices are retained.
