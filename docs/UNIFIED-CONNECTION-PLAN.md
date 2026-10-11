# Unified connections for iPhone and Mac clients

Status: target design; connection code and a Mac sidebar/snapshot-mirror prototype
are implemented. Live mirror acceptance remains unverified. Updated 2026-10-12.

The next implementation should let the iPhone app and a Mac sidebar extension
discover the same Bridge on the LAN, enroll with the Mac owner's approval, and
restore their own saved authorization on later connections. A typed binding code
is optional. The installed official cmux app remains unchanged.

This document records the agreed direction for a coordinated implementation.
Editing it does not implement commands, credentials, routes, or clients. The
working tree now includes discovery, enrollment and Mac client work; code presence alone
does not establish verification or a released feature. See [DESIGN.md](DESIGN.md),
[API.md](API.md), and [DEVELOPMENT.md](DEVELOPMENT.md) for implementation details
and recorded evidence.

## QR baseline and target behavior

The baseline column records the initial QR implementation inspected before the
unified enrollment work. It is historical context, not an inventory of the
changing working tree.

| Area | Initial QR baseline | Target behavior |
| --- | --- | --- |
| Discovery | The CLI selects a private LAN IP for its QR; the client does not browse for Bridges. | Bonjour/mDNS advertises and discovers Bridges. Manual address and QR entry remain fallback options. |
| Enrollment | A QR or manual import supplies endpoint, shared bearer token, and certificate fingerprint. | The client requests enrollment; the Mac owner approves that exact client. No typed code is required in the normal LAN flow. |
| Client identity | All enrolled clients use the Bridge's single bearer credential. | Each client has its own persistent identity and separately revocable authorization. |
| Host verification | HTTPS pins the exact certificate supplied during QR enrollment. | Verify the saved host identity independently of changing network addresses; renewal must preserve or explicitly replace that identity. |
| Restore | The phone restores one endpoint and credential from Keychain. | Restore saved trust, rediscover a known Bridge after an address change, and reconnect without another enrollment prompt. |
| Data delivery | The phone polls HTTPS snapshots. The Bridge separately consumes cmux events when permitted. | Common snapshot and subscription contracts, with cursors and explicit recovery after a gap. |
| Mac client | No third-party workspace mirror client is implemented. | A sidebar extension supplies discovery and selection UI; a separate Companion and viewer own transport and local terminal presentation. |
| Revocation | No per-client registry or revoke operation exists. | List enrolled clients and revoke one without invalidating the others. |

The QR baseline connection implementation lives in `BridgeState`,
`PairingConfiguration`, `PairingLinkCodec`, `BridgeRouter`, `RemoteClient`,
`PinnedSessionDelegate`, and the iPhone `PairingStore`/`AppModel`.
`LANAddressResolver` chooses this Mac's address; it is not network service discovery.

## Shared product boundaries

The first host remains official cmux on macOS. Both clients use one independently
installed Swift Bridge, shared wire models, client transport, and enrollment
protocol. Neither client needs a cmux cloud account or a separate provider API
connection. Agents and project files remain on the host.

The iPhone presents conversations, state, supported Feed decisions, files, and
changes. It does not render a terminal. The proposed Mac client presents remote
terminals inside local official cmux workspaces. These are different projections
of the same authorized host resources, not two enrollment services.

Official Mac cmux and cmux-tui have different protocols and capability sets.
Additional platform/back-end adapters are future work; a common Bridge API does
not make the first Mac backend portable or imply that cmux-tui is already supported.

## One executable and command families

Install the same `cmux-remote` executable on both Macs. Extend that executable
with host, client, owner-control, and viewer commands; do not create a second
independent Bridge with another identity store, enrollment protocol, or cache.
Command handlers remain thin composition entrypoints over shared modules.

The intended command layout is below. Commands described as planned do not exist
merely because they appear in this table; final arguments and output contracts
must be specified with their implementation.

| Command family | Responsibility | Implementation status |
| --- | --- | --- |
| `init`, `serve`, `doctor` | Initialize host state, run the resident service, and diagnose local cmux access. | Existing baseline; `serve` is being extended for discovery/enrollment. |
| `pairing` | Explicit enrollment bootstrap/QR entry, including an explicitly selected legacy fallback. | Existing baseline with enrollment migration in progress. |
| `enrollment open/pending/approve/deny/close` | Owner-only control of pending client enrollment. | Present in ongoing implementation; completion depends on verification. |
| `clients list/revoke` | Owner-only inventory and revocation of enrolled clients. | Present in ongoing implementation; completion depends on verification. |
| `discover` | List advertised LAN Bridges as reachability candidates. | Planned CLI entrypoint over shared discovery code. |
| `connect <device>` | Request enrollment or restore a saved authorized remote connection. | Planned Mac client entrypoint. |
| `mirror workspace <device> <workspace>` | Ask the local resident service to create an initial local workspace projection. | Snapshot prototype implemented; see the Mac guide for live verification gaps. |
| `mirror view ...` | Run in one local cmux terminal, display one authorized remote terminal, and forward input. | Snapshot prototype implemented; native/lossless parity is not claimed. |

Use the `clients` owner command family already being implemented rather than
adding a duplicate `devices` registry. Discovery candidates, approved incoming
clients, and saved outgoing host connections are separate resources even when
one CLI can display all three.

`serve` should compose both the local-host backend used by phones and the outgoing
connection/mirror services used by this Mac. The role is not exclusive: a Mac can
serve its own workspaces and view another Mac at the same time. Mirror capture and
input capabilities are additional modules; their existence must not be inferred
from the existing chat/file resource routes.

## Process ownership and local communication

One executable can run as several processes:

| Process | Owned state and lifetime |
| --- | --- |
| `serve` on each participating Mac | One resident service per state directory. Owns enrollment, authenticated connections, resource services, caches, subscriptions, and mirror projections. |
| Short-lived owner/client CLI commands | Submit typed requests to the resident service and return results. They do not start another independent credential registry. |
| One `mirror view` per local terminal | Owns foreground terminal presentation/input for that view. Attaches to the local service and ends when the local view closes. |
| Sidebar extension | Owns UI and selection. Communicates through an authorized app-owned channel; does not host a duplicate daemon or run an unsandboxed helper as its child. |

The initial host implementation already has an owner-only `owner.sock` and a
per-state run lease. Extend the local service boundary deliberately rather than
assuming modules in different processes share memory. Owner operations such as
enrollment approval/revocation remain local-only; do not publish them as ordinary
LAN resource routes.

Viewer attachment needs a restricted local channel/capability for one approved
projection. A viewer does not receive unrestricted owner-control access or the
credentials for every remote device. Pass non-secret projection identifiers on
the command line and keep credentials in protected storage or the authorized
local channel. Terminal stdout carries only VT/ANSI presentation data; diagnostic
logging must not corrupt it or expose pairing credentials. A shared PTY can also
display stderr, so moving logs to stderr alone does not establish that isolation.

Map each local view to the exact remote host/workspace/surface and its runtime
lifetime. Service restart or remote rebind makes a stale view disconnected until
that identity is revalidated. Do not send buffered input to a replacement shell
under a reused surface ID. Closing the viewer releases its local attachment;
remote close/interrupt remain separate authorized operations.

Sharing `serve` centralizes capture, connection reuse, cursors, and cache policy.
It does not automatically make terminal output a chat payload: iPhone and Mac
subscriptions retain separate capabilities and delivery semantics. Neither a
new subcommand nor local IPC bypasses cmux's process-origin/socket policy.

## Module boundaries for the unified executable

- `CmuxRemoteCore`: identities, scopes, capabilities, DTOs, cursors, receipts, and
  pure policies shared by all client kinds.
- `CmuxRemoteBridge`: local cmux access, host resource services, authority,
  persistence, LAN serving, and discovery advertisement.
- `CmuxRemoteClient`: discovery browsing, verified remote transport, enrollment,
  authorization restore, and subscription recovery.
- A dedicated mirror domain: remote/local resource mapping, reconciliation,
  capture/input routing, and per-view lifecycle; composed by `serve`.
- A dedicated viewer module: terminal input and VT/ANSI output for `mirror view`,
  using core contracts and restricted local transport.
- `CmuxRemoteCLI`: composition and argument routing for the command families.
- iPhone UI and Mac extension UI: platform presentation over the shared client
  contracts; no host authority or provider runtime is embedded in these views.

The mirror/viewer implementation currently lives in `CmuxRemoteMac`; those feature
boundaries do not require two separate packages.
Keep one source of truth for credentials, remote connection state, and mutation
receipts. Backend access, mirror state, and transport are tested without launching
the extension UI or a user's cmux instance.

## Discovery, enrollment, and reconnect

The normal user flow is:

1. The host owner starts the Bridge and opens enrollment when adding a device.
2. The iPhone app or Mac extension discovers reachable Bridges and selects one.
3. That client requests enrollment with its own public identity and a fresh nonce.
4. The host owner approves or denies the exact pending client in the Companion UI
   or an explicit local CLI workflow.
5. The client verifies the enrollment response and saves its host identity and
   client-specific authorization. Subsequent connections reuse that trust.

Service advertisements contain only discovery metadata such as protocol version,
host display name, service endpoint, and a non-secret identity hint. They never
contain a bearer token, private key, or enrollment grant. A discovery record is a
reachability hint, not authorization, and display names are not identity.

Enrollment must prove possession of the claimed identities and bind approval to
the pending client, host identity, nonce, requested scope, and expiry. First-use
host trust needs an explicit bootstrap policy; it cannot inherit trust merely
because Bonjour reported a name. A trusted QR or explicit first-use identity
confirmation can supply that bootstrap without requiring a typed binding code.
The exact cryptographic handshake must be specified and tested before implementation
is treated as complete.

Enrollment is bounded, expires, and is closed unless the owner explicitly opens
it. Denial, expiry, and cancellation do not issue credentials. Restoring an
already authorized device does not reopen enrollment. Approving one request must
not authorize a different concurrent requester.

On reconnect, resolve a saved host identity to a current endpoint, then verify the
peer before sending authenticated requests. A changed IP or port must not enroll
a new host silently. An unknown or changed identity requires explicit trust
replacement. Certificate rotation is distinct from identity rotation; until a
verified continuity mechanism exists, a changed certificate still fails closed.

Manual endpoints remain useful when multicast discovery is unavailable. QR
enrollment remains an optional explicit credential/identity exchange, not a
credential published through discovery.

## Client authorization and resource scope

Persist a host-side client registry outside the checkout with owner-only access.
Each record has a stable client ID, verified public identity, display name, client
kind, granted scope, and enrollment/revocation state. Private keys stay with their
owner. The phone stores credentials in device-only Keychain; the Mac client uses
its own protected storage. Copying the same shared token to every client does not
implement this registry.

Enrollment grants distinguish viewing from control and scope access to approved
workspaces. Conversation reads, project-file reads, Feed decisions, terminal
mirroring, terminal input, and remote structural mutations are separate capabilities.
Browsing a task does not select or focus the host's desktop workspace. A display
capability advertised by a host does not grant mutation authority.

Revocation rejects subsequent requests and closes that client's active
subscriptions. It does not revoke another device or stop the host's agents.
Every write rechecks authorization and the current session/workspace/surface
binding. Existing protections against stale targets, arbitrary file access,
caller-selected RPC methods, and outcome-unknown retries remain in force.

This network authorization does not replace cmux's own local socket authority.
With `cmuxOnly`, the Bridge still needs an authorized process origin, including
when it invokes the official CLI. An external LaunchAgent is not automatically
authorized by a successful phone pairing. Never change socket mode or enable
`allowAll` on the user's behalf.

## Common wire contract and recovery

Both client kinds share host identity, enrollment status, capabilities, workspace
and session identifiers, stable errors, and mutation receipts. Terminal and chat
payloads are separate feature families. A Mac client must not need to impersonate
an iPhone to enroll.

The next protocol must version the new enrollment and client-authorization
contract explicitly. Do not document proposed routes as existing `/v1` endpoints.
Compatible resource DTOs may be retained, while authenticated transport and scope
are updated consistently across the Bridge and both clients.

Snapshots are authoritative. Subscriptions carry cursors and replaceable updates;
the client detects epoch changes and replay gaps and requests a fresh snapshot.
Transcript generations, cmux event boot/sequence cursors, and Bridge subscription
cursors are distinct and must not be interchanged. Writes use stable operation
IDs and never acquire automatic retries merely because reconnect succeeded.

Use bounded queues and subscriptions that stop on cancellation, backgrounding,
disconnect, or revocation. A chat preview may replace an older preview. Committed
messages and mutation results cannot be silently dropped under that policy.
Reconnection to cmux's local event stream and durable receipt/cursor persistence
are new implementation work, not behavior supplied by current phone polling.

Existing QR pairings may be offered as an explicit legacy mode during migration.
A shared legacy token cannot be silently promoted into independently revocable
client identities. Re-enroll those clients to obtain the new contract, and make
the enabled legacy authority visible to the owner.

## Mac workspace mirror: proposed peripheral implementation

The public `CmuxExtensionKit` SDK supplies sidebar metadata and typed workspace,
surface, and URL actions. It cannot register an internal device provider, attach
the built-in native mirror session, seed arbitrary shell commands, or acquire
broader filesystem/socket access. The extension remains sandboxed. Communication
with its separately installed Companion must use an explicitly authorized
app-owned channel; launching a child inside the extension is not a sandbox escape.

The candidate implementation is:

1. The remote Bridge reads `system.tree` and a selected workspace's surface IDs.
   Current upstream source includes split direction, ratio, and nesting when the
   layout is available; installed versions need a capability/response check.
2. The local Companion creates an owned projection through the local cmux socket,
   maintaining explicit remote-to-local ID mappings.
3. Each local terminal runs an installed viewer command through the ordinary
   terminal startup mechanism. The viewer writes VT/ANSI to stdout; official cmux
   renders that output. It captures input and forwards it through the Bridge.
4. The remote Bridge requests `terminal.replay` / `mobile.terminal.replay` snapshots
   where supported. It encodes render-grid frames into VT/ANSI using the upstream
   replay logic or an equivalent tested adapter.
5. Known topology events trigger reconciliation. Initial work should follow the
   remote layout; arbitrary two-way layout editing requires its own conflict policy.

This uses existing remote terminals; it does not restart, migrate, or wrap their
already-running agents in tmux. Closing a local viewer detaches that projection.
Closing a remote terminal is a separate explicit, authorized action. Disconnect
must never send EOF or an interrupt to the remote agent merely because the viewer
was torn down.

This is structured character-grid synchronization, not screenshots or OCR.
The official mobile/native mirror path restores a replay and then receives pushed
render-grid updates or continuous terminal bytes. The ordinary local socket does
not expose those authenticated Mobile Host subscriptions to a custom LAN pairing.
Periodic replay is therefore the initial candidate; it is not lossless PTY streaming.
The cmux event stream carries topology and telemetry, not all terminal output.
Do not use its event cursor or the replay byte sequence as proof that every
screen change was captured.

Validate responsiveness, hidden panes, cursor/style/mode replay, alternate-screen
TUIs, local/remote size differences, history preservation, and multiple terminals.
Transitions between two snapshots may be lost. Images, full scrollback, browser
surfaces, clipboard, mouse behavior, and concurrent input are not complete merely
because a text-grid replay renders. Do not claim parity with native mirroring.

The one-terminal replay/input proof must pass on installed official cmux before
the Mac workspace mirror is committed as a supported product feature. tmux-based
attachment is a separate possible backend, not a prerequisite silently imposed
on the user's existing ordinary cmux terminals.

## Coordinated implementation order and acceptance

1. **Connection contract:** define discovery metadata, bootstrap trust, enrollment,
   per-client grants/storage, versioning, and migration. Test wrong-host identity,
   concurrent enrollment, denial, expiry, changed endpoint, and revocation.
2. **Common client:** move discovery, identity verification, authorization restore,
   and reconnect behind shared client APIs. Keep platform secure storage and UI
   separate. Verify an iPhone and a Mac client can enroll independently.
3. **Phone migration:** use discovery and owner approval, retain manual/QR fallback,
   and verify persisted trust across app/Bridge restarts and LAN address changes.
4. **Data continuity:** add bounded subscriptions and durable receipts/cursors.
   Verify cmux restart, event gaps, lost mutation responses, and transcript replacement.
5. **Mac feasibility gate:** attach one already-running ordinary Agent terminal,
   render its grid, send input to the same surface, reconnect, and detach without
   affecting its process. Record observed latency/load and fidelity gaps.
6. **Mac extension and workspaces:** add discovery/selection UI and Companion
   reconciliation for multiple panes. Verify closing local projections, remote
   structural changes, sizing, scope checks, and concurrent viewing.

For the unified executable, additionally verify that simultaneous phone access
and Mac viewing reuse the same resident service; a second `serve` for the same
state is rejected; owner CLI commands cannot be invoked from the LAN; a revoked
remote grant stops the relevant viewers; and closing one viewer leaves the other
views and remote agents running. Verify command behavior as well as shared module
tests. These checks are future implementation acceptance, not tests run by this
documentation change.

No phase is completed by this documentation change. Existing verification in
[DEVELOPMENT.md](DEVELOPMENT.md) proves only the recorded baseline. New network,
physical-device, and mirror evidence must identify the tested revision and
installed official cmux version.
