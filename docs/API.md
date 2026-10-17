# API contract and data sources

Resource DTOs below apply to signed `/v2` requests; `/v1` is an explicit legacy mode. See [Connection v2](CONNECTION-V2.md) for implemented discovery, enrollment and authorization. Phone subscriptions remain future work. The Mac snapshot-mirror prototype is documented below and in [the Mac guide](MAC-EXTENSION.md).

Version 2 uses a device-signed `Authorization: CmuxV2` proof and approved workspace/capability scope. Shared bearer authentication is available only in explicit legacy mode. Errors: `{"error":{"code":"...","message":"..."}}`. Requests are bounded to 1 MiB. IDs and paths are URL-encoded by the client. Dates use ISO-8601. `JSONValue` preserves cmux snapshot fields without making them typed guarantees.

| Route | Source | Result |
| --- | --- | --- |
| GET /v1/status | system.ping / system.capabilities | host/protocol/capability status |
| GET /v1/workspaces | workspace.list | cmux workspaces |
| GET /v1/sessions | cmux-bound chat.sessions.dump / agent hooks, enriched by vault.sessions | cmux sessions only; external history excluded; known ended sessions read-only |
| GET /v1/sessions/:id/history?before_seq=&limit= | local transcript, pinned upstream parser | messages, has_more, generation, clipped |
| GET /v1/sessions/:id/tool-detail?message_id=&generation=&field=&offset=&content_id= | complete transcript tool field | bounded revision-bound text page |
| GET /v1/sessions/:id/preview | surface.read_text + prose extractor | replaceable preview, availability |
| POST /v1/sessions/:id/send | fixed mobile.chat.send | text, optional attachments, and operation_id |
| POST /v1/sessions/:id/interrupt | mobile.chat.interrupt or explicit send_key | hard and operation_id |
| GET /v1/feed | feed.list | captured Feed items; not all provider approvals |
| POST /v1/feed/:request/reply | feed.permission/question/exit_plan.reply | matching kind, decision fields, operation_id |
| GET /v1/sessions/:id/changes | local Git | porcelain change entries |
| GET /v1/sessions/:id/diff?path= | local Git, no external diff/textconv | bounded unified diff |
| GET /v1/sessions/:id/file?path= | constrained local project file | bounded text and relative path |
| GET /v1/operations/:operation_id | owner-only persisted operation journal | current device's scoped accepted/unknown status |

No generic cmux RPC proxy, shell execution endpoint, arbitrary absolute-path fetch or desktop focus endpoint is exposed. Starting a conversation (below) types only a fixed agent command chosen from an enum.

The first phone version polls foreground snapshots; `events.stream` is a Bridge backend seam rather than a claim that local cmux supplies full chat deltas. Mutation error `outcome_unknown` is intentionally not an automatic retry signal. Legacy pairing is endpoint + bearer token + pinned certificate fingerprint and requires explicit server enablement; v2 uses independently identified clients and owner-approved scopes. Neither has a cmux account identity.

## Starting conversations

These routes require signed v2 requests and the `conversationStart` capability for the workspace. Legacy clients cannot use them. Both desktop cmux workspaces and cmux-tui daemon workspaces are supported.

| Route | Source | Result |
| --- | --- | --- |
| GET /v1/workspaces/:id/directories | the workspace's `current_directory` and the directories of its own conversations | up to 32 `{id, path}` roots; `id` is opaque, `path` is for display |
| GET /v1/workspaces/:id/directories/:root?path= | visible subfolders of a folder inside that root | `{root_id, path, directories, truncated}`, at most 500 names |
| POST /v1/workspaces/:id/sessions | `{root_id, path, agent: "claude"\|"codex", prompt?, operation_id}` | `{operation_id, accepted, surface_id?}` |

A root is never the home directory, `/`, a parent of home or a credential folder (`ProjectFilePolicy.projectRoot`). `path` is relative to the root; `..`, hidden components and symbolic links that leave the root or land on a hidden folder are refused with `directory_forbidden`. A root that is no longer part of the workspace is `stale_binding`.

The owner's shared folders come first, before the workspace's own directory and the folders of its conversations. They are set on the Mac (`directories.allowed` and `directories.set_allowed` on the owner-only channel) and stored in an owner-only `allowed-directories.json` beside the other Bridge state; the list is machine-wide, so one entry appears in every workspace's new-session list, and it is read per request, so a change needs no Bridge restart. A shared folder is subject to the same `ProjectFilePolicy` check as any other root: the owner cannot share `/`, the home directory, a parent of home or a credential folder, and an unusable entry is refused when it is saved instead of dropped silently. At most 32 folders are stored, matching the root cap.

`prompt` is the first message, at most 4 KiB. Codex requires one: it reports its conversation only after a first message, so without it the phone could never open the new conversation (`prompt_required`). The message is passed as one argument to the fixed program (`claude <message>` or `codex --no-daemon <message>`), quoted with POSIX single quotes or, when it holds control characters or line breaks, ANSI-C `$'…'` quoting, so it is never interpreted by the shell. A message that is a single word or starts with `-` gets a leading space so it cannot name a subcommand (`codex login`) or an option. The durable record stores only a digest of the message. Codex runs with `--no-daemon` because its shared background server executes hooks with the environment of whichever Codex terminal started it, so a second terminal's conversation would never be reported.

Starting records a durable intent, rechecks the grant and folder, then calls `surface.create` with `type: terminal`, the resolved `working_directory`, `initial_input: "<command line>\r"` and `focus: false`. The new tab opens in the workspace's focused pane; the desktop does not switch workspace or window. Repeating an operation returns its receipt without opening another terminal (`surface_id` is then absent). A failed or unconfirmed `surface.create` is `outcome_unknown` and is never retried under the same identity; the phone offers to check again or to open another terminal with a new identity. The conversation appears in `/v1/sessions` once the agent reports its binding.

In a cmux-tui daemon workspace the roots also include the working directories of the workspace's terminals, since a daemon workspace has no directory of its own. The Bridge calls the daemon's `workspace.run` with the workspace's `ws_` identity, `cwd`, `argv: [<login shell>, "-ic", "<command line>; exec <login shell> -l"]` (the daemon's `-lc` skips interactive startup files where agents are often put on `PATH`, so the owner's interactive shell runs the agent as a typed command would, and a login shell stays open after it exits) and an idempotency and correlation key derived from the device and operation, so a resent write is deduplicated by the daemon too. The daemon keeps the session's focused workspace and pane, but the new tab becomes the visible tab of the workspace's active pane: the daemon offers no background tab creation, and selecting the previous tab again (`tab.focus`) would move session focus, so it is not done.

An older Bridge cannot decode `conversationStart` and closes the link during enrollment; the phone then asks again without it.

## Resuming a conversation

A conversation keeps its identity when its Agent session moves to a new terminal, because the id is derived from the
provider and its session id rather than from a terminal. `GET /v1/sessions` reports `resumable: true` only when the
Bridge has verified all of: the Agent session has a transcript under a configured root, that transcript itself records
the working directory the Agent ran in, the conversation's workspace still exists, and — for a terminal that is still
running — that its rendered screen no longer shows the Agent's prompt. A live conversation is never reported resumable,
and a terminal whose screen cannot be read is neither writable nor resumable.

| Route | Body | Result |
| --- | --- | --- |
| POST /v1/sessions/:id/resume | `{operation_id?}` | `{operation_id, accepted}` |

This requires `conversationControl` and `conversationStart` for the conversation's workspace. The caller names only
the conversation: the Agent, its session id and the working directory all come from the Bridge's own binding and the
Agent's transcript, never from the request, so a device cannot choose what command runs or where. The directory is the
one the Agent recorded itself, not the daemon's terminal `cwd`, which tracks `cd` and is absent once the terminal is
gone. The Bridge starts `<agent> --resume <session-id>` (Claude, with the owner's fixed flags) or
`codex resume <session-id>` in a new terminal of that workspace through the same `surface.create`/`workspace.run`
path as a new conversation, and the phrase is deduplicated by the operation identity, so a retry cannot open a second
terminal. A conversation that is not resumable is `read_only`; an unconfirmed start is `outcome_unknown` and is never
retried under the same identity.

A desktop cmux has no resume RPC, so the Bridge performs the start itself with `surface.create`; a cmux-tui
daemon runs `mobile.chat.resume` and keeps its own deduplication key. One limitation remains on the desktop:
cmux records the Agent's terminal only when its hook reports there, and a terminal the Bridge opened is not
rewritten into that record by the resumed process. Until cmux updates the binding, its own `mobile.chat.send`
answers `not_found` ("The agent's terminal moved") for both the old and the new surface, so a conversation
reopened this way is readable but still not writable from the phone. Opening it once on the Mac, or waiting for
the next Agent hook after a turn started in that terminal, does not change that record in cmux 0.65.2.

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
becomes accepted. A send result with `submitted:false` remains uncertain rather
than confirming an unsubmitted image/prompt. Prepared or uncertain records survive restart and refuse
automatic replay. The journal is bounded to 4096 operations and 4 MiB, failing
closed on corruption, unsafe permissions, write failure or capacity exhaustion.
Restart does not clear deduplication or capacity; no automatic eviction silently
forgets an uncertain operation.

`GET /v2/operations/:operation_id` returns `operation_id`, `state` (`accepted` or
`outcome_unknown`) and ISO-8601 `recorded_at`. It requires the original device's
current capability and workspace grant. Another device cannot inspect or replay
the record. Identical accepted replay returns its saved receipt even after the
original session or Feed item disappears; this does not issue another mutation.
Fresh operations still need a current authorized target. An absent record returns `operation_not_found`; absence is not proof
that an earlier request never executed. Persistence does not provide exactly-once
execution across the cmux/Bridge boundary.

## Full tool records

Ordinary history preserves the upstream 2,048-character input-detail and
16,384-character body/output/diff budgets. The inline card wraps all received text
and uses the conversation's vertical scroll. `View full record` opens an explicit
paged read of the underlying committed transcript field.

`GET /v2/sessions/:id/tool-detail` requires `message_id`, the current history
`generation`, and a supported `field`: `input`/`output` for a tool or terminal
capture, or `diff` for an edit. `offset` defaults to zero; `limit` defaults to and
is capped at 16,384 Unicode scalars (at most 64 KiB UTF-8). Offsets and totals also count Unicode scalars, so even an oversized combining sequence can be traversed in bounded pages. The response includes `message_id`, `generation`,
`field`, `content_id`, `text`, `offset`, `next_offset`, and `total_characters`.
The client sends `content_id` on later pages. A changed field/replaced transcript
returns `stale_detail`, requiring an explicit refresh instead of combining text
from different revisions. Only an explicit first-page re-anchor may use
`generation=current` with offset zero and no content revision; the response
returns the current concrete generation for subsequent pages. Complete JSONL lines only; the 32 MiB transcript read
limit still applies. Tool-detail parsing uses an explicit bounded larger budget;
it does not increase ordinary conversation snapshots or export arbitrary files.

Reads require current `conversationRead` for the bound workspace and recheck it
before returning. The message must exist in that session's parsed history, and
unsupported fields/message kinds are rejected. Each native detail page stays
bounded and earlier/later controls can traverse the complete supported record.
An older Bridge without this route produces a visible update-required message.

## Recorded image previews

`GET /v2/sessions/:id/image?reference_id=:opaque_id&generation=:generation`
returns a static `image/jpeg` preview (at most 512 KiB, longest side 1600 px).
The history page's optional `images` array binds each opaque reference to its
message and transcript generation. The client cannot submit a host filename.
A replaced record or unknown reference fails closed. JSON errors use the usual
stable codes; all responses are `no-store` with `nosniff`.

Recorded Claude user/Read-result image blocks and Codex user data URLs are read
from complete bounded transcript lines. A matching recorded Read result can
also back an attachment's path metadata without opening that outside file.
Referenced PNG/JPEG files require both conversation-read and project-read grants
and must pass the project policy and descriptor-based no-symlink walk. File
previews read the current approved project file; they do not recreate an archived
file version. Missing outside-project attachments without recorded bytes remain
unavailable. Supported input is one static PNG/JPEG within 4 MiB and 32 megapixels;
project file reads additionally retain the existing 1 MiB limit. Preview encoding
strips source metadata. Current grant and session binding are rechecked after
reading/decoding and before returning bytes.

## iPhone dictation

The microphone prepares a bounded local text draft through Apple's on-device
Speech framework. Both microphone and Speech permission are explicit. A device or
locale without on-device recognition fails with an unavailable state; no audio
falls back to a provider, Apple server, Bridge upload or agent call. The request
requires on-device recognition and checks support before recording. Partial text
is replaceable; Finish, Cancel and Use text are separate actions. Use text appends
to the current typed draft and never sends automatically. Ordinary send remains
the only agent submission path. Recording is bounded to 60 seconds, finalization
to five seconds, recognized text to 8 KiB. Navigation/background stops audio while
preserving recognized words; explicit Cancel discards them. Physical microphone
acceptance remains required. This interface does not implement a realtime voice
conversation with the agent.

Implementation references: [Apple on-device recognition](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)
and [on-device support](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition).

## Combined milestone storage

Production chat, Feed and Mac terminal mutations use one shared MutationLedger.
On first access under the Bridge run lease, existing owner-only `operations.json`
phone records are imported into the bounded append-only ledger. Confirmed receipts
remain confirmed; prepared/uncertain records remain unknown and cannot dispatch.
Import is flushed, restartable and does not delete the prior file. Corruption,
conflicting metadata or capacity exhaustion blocks writes. Receipt lookup keeps
current device/workspace/capability authorization and never requires a vanished
session to become live again. Injected standalone phone journals remain available
for compatibility checks. Production fingerprint checks accept the recorded old
phone format only for an identical request; new content still conflicts.
