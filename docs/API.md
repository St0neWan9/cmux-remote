# API contract and data sources

Resource DTOs below apply to signed `/v2` requests; `/v1` is an explicit legacy mode. See [Connection v2](CONNECTION-V2.md) for implemented discovery, enrollment and authorization. Phone subscriptions remain future work.

Version 2 uses a device-signed `Authorization: CmuxV2` proof and approved workspace/capability scope. Shared bearer authentication is available only in explicit legacy mode. Errors: `{"error":{"code":"...","message":"..."}}`. Requests are bounded to 1 MiB. IDs and paths are URL-encoded by the client. Dates use ISO-8601. `JSONValue` preserves cmux snapshot fields without making them typed guarantees.

| Route | Source | Result |
| --- | --- | --- |
| GET /v1/status | system.ping / system.capabilities | host/protocol/capability status |
| GET /v1/workspaces | workspace.list | cmux workspaces |
| GET /v1/sessions | cmux-bound chat.sessions.dump / agent hooks, enriched by vault.sessions | cmux sessions only; external history excluded; known ended sessions read-only |
| GET /v1/sessions/:id/history?before_seq=&limit= | local transcript, pinned upstream parser | messages, has_more, generation, clipped |
| GET /v1/sessions/:id/preview | surface.read_text + prose extractor | replaceable preview, availability |
| POST /v1/sessions/:id/send | fixed mobile.chat.send | text, optional attachments, and operation_id |
| POST /v1/sessions/:id/interrupt | mobile.chat.interrupt or explicit send_key | hard and operation_id |
| GET /v1/feed | feed.list | captured Feed items; not all provider approvals |
| POST /v1/feed/:request/reply | feed.permission/question/exit_plan.reply | matching kind, decision fields, operation_id |
| GET /v1/sessions/:id/changes | local Git | porcelain change entries |
| GET /v1/sessions/:id/diff?path= | local Git, no external diff/textconv | bounded unified diff |
| GET /v1/sessions/:id/file?path= | constrained local project file | bounded text and relative path |
| GET /v1/operations/:operation_id | owner-only persisted operation journal | current device's scoped accepted/unknown status |

No generic cmux RPC proxy, shell execution endpoint, arbitrary absolute-path fetch or desktop focus endpoint is exposed.

The first phone version polls foreground snapshots; `events.stream` is a Bridge backend seam rather than a claim that local cmux supplies full chat deltas. Mutation error `outcome_unknown` is intentionally not an automatic retry signal. Legacy pairing is endpoint + bearer token + pinned certificate fingerprint and requires explicit server enablement; v2 uses independently identified clients and owner-approved scopes. Neither has a cmux account identity.

## Images and durable operations

`send` accepts optional `attachments`, each with `id` (UUID), `file_name`, `format`
(`png` or `jpeg`) and `data_b64`. Old text-only requests remain valid. Image-only
requests are valid. At most four unique selected images are allowed; each decoded
payload is at most 512 KiB and their total at most 640 KiB. Static decoded images
must match the declared format, be at most 4096 pixels per side and 8 megapixels.
The whole JSON request still fits the 1 MiB transport bound. The Bridge validates
images before mutation, and forwards only `data_b64`/`format` to the fixed existing
session's `mobile.chat.send`. Desktop draft, binding and device scope protections
also apply to image sends. The current image path is materialized by cmux on the
Mac; the existing agent may require approval to read it. Phone selection/preview
UI is a separate acceptance item, not established by the backend route.

Production `serve` persists `operations.json` beneath its owner-only state
directory. Records bind operation ID, device, workspace/capability, resource and
payload digest. Prompt text and image bytes are not persisted there. A prepared
record is flushed before cmux dispatch; only a confirmed and persisted response
becomes accepted. Prepared or uncertain records survive restart and refuse
automatic replay. The journal is bounded to 4096 operations and 4 MiB, failing
closed on corruption, unsafe permissions, write failure or capacity exhaustion.
Restart does not clear deduplication or capacity; no automatic eviction silently
forgets an uncertain operation.

`GET /v2/operations/:operation_id` returns `operation_id`, `state` (`accepted` or
`outcome_unknown`) and ISO-8601 `recorded_at`. It requires the original device's
current capability and workspace grant. Another device cannot inspect or replay
the record. An absent record returns `operation_not_found`; absence is not proof
that an earlier request never executed. Persistence does not provide exactly-once
execution across the cmux/Bridge boundary.
