# API contract and data sources

Resource DTOs below apply to signed `/v2` requests; `/v1` is an explicit legacy mode. See [Connection v2](CONNECTION-V2.md) for implemented discovery, enrollment and authorization. Phone subscriptions remain future work. The Mac snapshot-mirror prototype is documented below and in [the Mac guide](MAC-EXTENSION.md).

Version 2 uses a device-signed `Authorization: CmuxV2` proof and approved workspace/capability scope. Shared bearer authentication is available only in explicit legacy mode. Errors: `{"error":{"code":"...","message":"..."}}`. Requests are bounded to 1 MiB. IDs and paths are URL-encoded by the client. Dates use ISO-8601. `JSONValue` preserves cmux snapshot fields without making them typed guarantees.

| Route | Source | Result |
| --- | --- | --- |
| GET /v1/status | system.ping / system.capabilities | host/protocol/capability status |
| GET /v1/workspaces | workspace.list | cmux workspaces |
| GET /v1/sessions | cmux-bound chat.sessions.dump / agent hooks, enriched by vault.sessions | cmux sessions only; external history excluded; known ended sessions read-only |
| GET /v1/sessions/:id/history?before_seq=&limit= | local transcript, pinned upstream parser | messages, has_more, generation, clipped |
| GET /v1/sessions/:id/preview | surface.read_text + prose extractor | replaceable preview, availability |
| POST /v1/sessions/:id/send | mobile.chat.send or explicit terminal.paste | text and operation_id |
| POST /v1/sessions/:id/interrupt | mobile.chat.interrupt or explicit send_key | hard and operation_id |
| GET /v1/feed | feed.list | captured Feed items; not all provider approvals |
| POST /v1/feed/:request/reply | feed.permission/question/exit_plan.reply | matching kind, decision fields, operation_id |
| GET /v1/sessions/:id/changes | local Git | porcelain change entries |
| GET /v1/sessions/:id/diff?path= | local Git, no external diff/textconv | bounded unified diff |
| GET /v1/sessions/:id/file?path= | constrained local project file | bounded text and relative path |

No generic cmux RPC proxy, shell execution endpoint, arbitrary absolute-path fetch or desktop focus endpoint is exposed.

The first phone version polls foreground snapshots; `events.stream` is a Bridge backend seam rather than a claim that local cmux supplies full chat deltas. Mutation error `outcome_unknown` is intentionally not an automatic retry signal. Legacy pairing is endpoint + bearer token + pinned certificate fingerprint and requires explicit server enablement; v2 uses independently identified clients and owner-approved scopes. Neither has a cmux account identity.

## Terminal mirror resources

These routes require signed v2 requests. Legacy shared-token clients cannot use
them, and none accepts a caller-selected cmux method.

| Route | Required capability | Result/source |
| --- | --- | --- |
| GET /v2/workspaces/:id/mirror | terminalRead on :id | Scoped terminal-only `system.tree` projection; commands/env/paths omitted |
| GET /v2/workspaces/:id/terminals/:surface/replay | terminalRead on :id | Full validated character-grid replay encoded as VT bytes, exact IDs and producer epoch; optional presentationKey/repaintBytes for subsequent in-place updates |
| POST /v2/workspaces/:id/terminals/:surface/input | terminalInput on :id | text, runtimeEpoch, operationID; membership/runtime checks and durable per-device operation intents/receipts |

Replay includes `allowsInput` for the client. Read-only viewers ignore typing
except their local detach key. Hibernated producers are refused before upstream
replay can wake them. Input is not retried automatically. Producer validation and
input are separate official cmux calls, not an atomic compare-and-send operation.
The updated Bridge stores intent/receipt metadata in an owner-only journal before
acknowledging writes. A completed duplicate returns its recorded receipt after
current authorization; an unfinished duplicate returns `outcome_unknown` even
after restart. There is no automatic eviction or automatic write retry.

The owner-only Unix channel additionally handles fixed `mac.connections`,
`mac.enrollment.start/status/cancel`, `mac.workspaces`, `mac.forget`, and
`mirror.workspace/list/status/sync/replay/input/detach` operations. Structural
sync uses scoped snapshots and fixed operations against owned local viewers.
`mirror.status` reports watching/paused state and stable errors; an unknown layout
write is never retried automatically. It is not exposed by the
HTTPS router. Metadata responses omit client private keys. Containing-app
navigation URLs carry at most a host identity, never credentials or commands.

Mac discovery is also owner-only. `mac.discovery.refresh` restarts the resident
browse without cancelling enrollment; `--no-discovery` keeps it disabled.
`mac.discovery.list` returns up to 64 public
host identities and Bonjour service descriptors, excluding this Bridge itself.
`mac.discovery.resolve` accepts only the identity of a currently observed peer;
it cannot resolve an arbitrary caller-provided hostname. Neither operation is
available through HTTPS, grants authority, or returns client keys. The Companion
refreshes these metadata snapshots on a cancellable two-second cadence.
