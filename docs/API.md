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
| POST /v1/sessions/:id/send | mobile.chat.send or explicit terminal.paste | text and operation_id |
| POST /v1/sessions/:id/interrupt | mobile.chat.interrupt or explicit send_key | hard and operation_id |
| GET /v1/feed | feed.list | captured Feed items; not all provider approvals |
| POST /v1/feed/:request/reply | feed.permission/question/exit_plan.reply | matching kind, decision fields, operation_id |
| GET /v1/sessions/:id/changes | local Git | porcelain change entries |
| GET /v1/sessions/:id/diff?path= | local Git, no external diff/textconv | bounded unified diff |
| GET /v1/sessions/:id/file?path= | constrained local project file | bounded text and relative path |

No generic cmux RPC proxy, shell execution endpoint, arbitrary absolute-path fetch or desktop focus endpoint is exposed.

The first phone version polls foreground snapshots; `events.stream` is a Bridge backend seam rather than a claim that local cmux supplies full chat deltas. Mutation error `outcome_unknown` is intentionally not an automatic retry signal. Legacy pairing is endpoint + bearer token + pinned certificate fingerprint and requires explicit server enablement; v2 uses independently identified clients and owner-approved scopes. Neither has a cmux account identity.
