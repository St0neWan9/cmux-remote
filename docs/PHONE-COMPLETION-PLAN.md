# Phone completion plan and acceptance ledger

Status: implementation in progress. Baseline: `0a2faff`. This document is a plan,
not a claim that the features or hardware acceptance below have passed.

## Product contract

The iPhone operates existing, explicitly cmux-bound Claude/Codex sessions through
an independent LAN Bridge. Official cmux stays running and unchanged. No cloud
account, provider API, replacement agent runtime or phone terminal is introduced.
The primary checkout contains concurrent Mac mirror work; this phone work uses an
isolated branch and must not publish that task's uncommitted changes.

The requested list has three implementation owners: iOS presentation/input,
Bridge persistence/delivery/file access, and official cmux's fixed local RPCs.
No capability is inferred solely from `system.capabilities` or from a handler in
upstream source. Installed-method availability and an actual end-to-end operation
must be verified before the corresponding feature is declared working.

## Requirements and acceptance

| ID | Requirement | Planned behavior | Evidence required to mark complete |
| --- | --- | --- | --- |
| R01 | Auxiliary screens and recovery states | White floating pairing/device rows, waiting approval, connection failure/retry, files/diffs, Feed forms/history, loading/empty/ended/revoked states | Current iOS build; native tour screenshots with actual transitions and working controls |
| R02 | Reconnect and restore | Keep trusted host/device identity and scope; recover read views after Bridge/endpoint changes; pause in background; explicitly explain revoked or replaced host | Actual model race/cancellation tests, pinned TLS restart/relocation tests, native foreground/background recovery |
| R03 | Bridge-to-phone realtime delivery | Authorized bounded stream of replaceable snapshots/invalidations; committed history stays authoritative; cursors/epoch/gap recovery trigger snapshots | Two independent clients; slow-reader overflow; cancellation, revocation, epoch change and reconnect tests; native growing response |
| R04 | Durable mutation records | Persist a prepared operation before dispatch and the confirmed receipt afterward; recovered prepared/uncertain operations never execute automatically; scope/device/resource checks protect receipt access | Kill/recreate service/store; successful and uncertain send/stop/Feed replay; conflict, concurrency, disk failure, corruption, capacity and revoked-scope tests |
| R05 | Images to existing conversations | Photo/file selection, bounded compression/preview/removal; fixed `mobile.chat.send` attachment schema; same live binding/empty-prompt checks as text; retain draft when outcome unknown | Installed official cmux delivers a tiny test image to the same existing agent; malformed/type/size/read-only/stale-target tests; native picker/send/receipt behavior |
| R06 | Historical image references | Resolve only transcript-derived references belonging to the approved session; binary image route with bounded supported formats; preview/copy/share; no arbitrary host path | Parser/reference tests; traversal/symlink/secret/outside-scope/oversize rejection; actual native image preview and revoked read |
| R07 | Voice input | Optional iOS speech-to-text edits the local draft; explicit start/stop/cancel; never submits automatically; existing text send does the delivery | Permission denied/unavailable/final/partial/cancel model tests; physical microphone transcription and ordinary text submission |
| R08 | Realtime voice conversation | Explicitly unavailable through this independent local interface; no decorative active call control or hidden provider integration | API capability/documentation check and UI does not promise an operational voice call |
| R09 | Camera enrollment | Scan the expiring host-signed QR, verify host/certificate and await exact owner approval; retain manual fallback | Physical iPhone scan/approve/deny/cancel; no token in logs or public artifacts |
| R10 | Device storage and LAN | Device-only Keychain restore, app/Bridge restart, Wi-Fi loss/recovery and LAN discovery relocation | Physical iPhone and reachable LAN; device grant restored without broadening or re-enrollment; wrong identity/certificate fails closed |
| R11 | Verification and delivery | Tests exercise real behavior and every implemented route; complete scoped candidate, iOS build, independent review and open PR | Executed current-source checks, review repair receipts, API coverage matrix and native/hardware acceptance ledger |

Simulator evidence cannot satisfy microphone/camera/Keychain/Wi-Fi requirements.
If hardware is unavailable, those rows remain pending, the full goal stays open,
and completed independent work continues before reporting a hardware blocker.

## Official API findings to verify

- `mobile.chat.send` is dispatched on the local socket and its source accepts
  `attachments: [{data_b64, format}]`. It internally calls image delivery; failure
  of the separate `terminal.paste_image` RPC does not establish that this path is
  unavailable. Test the chat path itself without creating another agent.
- `mobile.task.attachment.upload` has a local chunk-upload handler, gated by the
  mobile-task feature. Staging a task file is not proof of delivering it to an
  existing chat. Do not depend on silently enabling a cmux feature flag.
- Installed ordinary local `mobile.chat.history` and
  `mobile.chat.artifact.fetch` returned `method_not_found` in the earlier probe.
  History continues to use the existing bounded transcript adapter; historical
  images require a separately authorized Bridge file projection.
- `surface.read_text` supplies a best-effort replaceable live preview.
  `events.stream` supplies events and resume metadata, not token-complete chat
  deltas. Bridge push must disclose these source semantics.
- `feed.permission.reply`, `feed.question.reply`, `feed.exit_plan.reply` and
  `mobile.chat.interrupt` keep their current fixed, verified target contracts.

## Architecture and wire changes

Core owns bounded image/attachment values, mutation-status DTOs, stream envelopes
and pure cursor/recovery policies. Bridge owns persistence, transcript-derived
image access, event reconnection and scoped subscriptions. Client owns pinned
stream transport and reconnect without write retries. iOS owns speech/photo
permissions, previews, draft state and white presentation.

Persist only operation identity, principal, resource/workspace, payload digest,
state and receipt; never prompt text, image bytes, private keys or tokens. State
is owner-only outside the repository. A failed durable write prevents dispatch.
Journal corruption fails closed. The journal is bounded and rejects capacity
exhaustion rather than evicting uncertain operations. Persistence cannot establish
exactly-once cmux execution: a crash between dispatch and receipt persistence
leaves `outcome_unknown` and requires inspection.

New binary/stream routes inherit signed v2 authentication, scope and cancellation.
Every read and delivered update rechecks current grant/binding. Image URLs are
session reference IDs, not caller-provided absolute paths. Image request/response
size and format limits are explicit; increasing transport limits must remain
bounded. No new route forwards arbitrary RPC methods.

Streams have independent cursors and bounded client queues. A slow client gets a
gap/resnapshot indication instead of silently losing committed history. Epoch
changes invalidate replay cursors. Cancellation/background/disconnect/revocation
ends subscriptions. Reconnecting a read stream never resubmits a mutation.

## Implementation sequence

1. Publish this plan and pin installed/source API evidence. Probe the image-send
   path in a dedicated existing test conversation using non-sensitive content.
2. Add durable mutation storage and restart/status behavior, then images and
   transcript-authorized image reads with route-level integration tests.
3. Add scoped bounded Bridge streams, reconnect/cursor recovery and cmux event
   reconnection; migrate phone refresh ownership while retaining authoritative
   history snapshots and safe fallback.
4. Add native photo/image/voice UI, unified auxiliary pages and explicit recovery
   actions. Keep attachment and dictated drafts across transient failures.
5. Run isolated package/client/model checks and iOS build; perform independent
   correctness/authority review; fix verified findings and repeat focused checks.
6. Complete the native and physical-device acceptance ledger, publish code and
   exact verification results. No pending requirement is turned into a pass by
   renaming it as a follow-up.

## Progress ledger

All R01–R11 rows are unproven for this continuation until current-source evidence
is recorded. Earlier baseline tests are useful regression evidence, but do not
prove the new image, stream, durable-record or hardware behavior.

### First backend implementation — 2026-10-12

- R04 backend/storage/status route implemented. Current candidate passes 11 new
  journal tests, including signed status reads after authority/service restart,
  another-device/revoked denial, crash-prepared state, failed disk writes,
  digest conflicts, capacity and send/stop/resolved-Feed deduplication. Phone
  status/recovery UX and production-process/native revalidation remain pending.
- R05 backend accepts validated bounded images through the fixed existing chat
  route; seven new test functions exercise delivery, counts/size/format, stale or
  read-only targets, desktop draft protection and unknown-result replay. Native
  image selection/preview/send UI remains pending.
- Installed official cmux accepted a generated 32×32 test PNG in the existing
  dedicated Claude session. With a Mac-side one-time approval, Claude's Read tool
  returned image content and its final reply identified the color as blue.
  This Claude directory-policy approval did not appear in the phone Feed, so the
  evidence does **not** establish phone handling of every terminal policy dialog.
- The initial isolated candidate passed 88 tests in 21 suites, 17 actual phone-model
  checks and 174 matching localized keys. The iOS Simulator build passes. These
  checks do not complete R01–R11 or replace physical-device acceptance.

Independent review reproduced two defects: a successful RPC envelope with
`submitted:false` became an accepted image receipt, and signed replay depended on
the original session/Feed item still being listed. The dedicated regression commit
`dd67c02` fails both tests with six expectations. The repair retains an unknown
record for unconfirmed submission and authorizes cached receipts against stored
scope; fresh mutations still authorize/check live targets. Tests now inject
rebind/revocation at an actual backend await rather than an incidental discovery
call count. The repaired candidate passes 89 tests in 21 suites plus the same
17 actual-model checks and 174 locale keys. Fresh independent review at `a180433` (tree `17e7333`) found no verified remaining backend defect and independently passed 40 focused tests across six suites. This does not complete the remaining phone/hardware requirements.

### Phone media, drawer and tool details — 2026-10-12

- R05 phone implementation now includes system photo/file selection, bounded
  file-backed importing and off-main JPEG preparation, image preview/removal,
  captured send inputs and visible receipt/inspection actions. Actual image
  encoding, bounded file imports, cancellation, later draft edits and no-resend
  recovery are exercised in the phone-model harness. Native picker/preview/send
  acceptance is still pending; the retained live Bridge must be updated to this
  candidate before claiming the phone upload flow works end to end.
- R04 phone pending requests are prepared in owner-only, bounded device-local
  storage before dispatch. Physical iOS files use data protection and are excluded
  from backup. The scope binds host/device and session; endpoint relocation does
  not change it. Restoring a request blocks sending until a confirmed receipt or
  explicit inspection. Tests recreate models/stores and exercise corrupt storage,
  failed preparation, private permissions and cross-scope isolation. Physical
  protection, production-process restart and native receipt actions remain pending.
- R01 session sidebar now reveals a left drawer while the main page slides right
  with rounded corners and shadow. Opening, closing via the exposed-page control,
  project expansion and conversation selection were exercised on the original
  retained paired Simulator. Edge swipe and VoiceOver acceptance remain pending.
  Expanded tool details now use pale rounded cards, leading titles/code/output,
  horizontal/vertical overflow scrolling and a quiet trailing result. Native tool
  card visual acceptance remains pending.
- The original paired Simulator is retained; the extra task-owned UI Simulator
  was shut down. Other tasks' devices and the installed official cmux are untouched.

Independent review reproduced loss of unknown-send state on conversation
recreation; commit `81f1ff0` fails two expectations before the persistent repair.
A file-backed photo representation also removes the previous whole-asset Data
allocation before its input-size check; actual system-picker behavior still needs
native acceptance. Fresh review then reproduced blocked history/hidden inspection
for corrupt storage and cache eviction of later edits on an unresolved send.
Commit `28ee2a1` fails those two expectations. The final repair preserves authorized
history and reachable inspection while sends stay blocked, and retains unresolved
models during cache pruning. Fresh repair review at tree `b761fea` found no concrete
repair defect and independently confirmed the same red/green discriminator.

Current candidate passes 89 package tests in 21 suites, 17 existing phone checks
and 31 executed media/draft/recovery checks, 188 matching locale keys, and the iOS
Simulator build. These results cover this slice only. R02/R03/R06/R07, complete
auxiliary/native tours and physical R09/R10 acceptance remain pending; the full
R01–R11 goal is not complete.

### Tool-content correction — 2026-10-12

The first tool-code renderer used a hidden two-axis scroll area capped at 264
points. Native inspection reproduced a Read card showing its title/status while
hiding a recorded 106-character input. It now renders wrapping, natural-height
text under the conversation's own scroll. The same native Read card shows its
complete `file_path` input after the repair; its result is an image, not textual
file contents. Actual text-result/large-record route acceptance remains required.

The explicit full-record route and bounded native detail pages supplement the
upstream history parser's 2,048/16,384-character text budgets. The local vendored
parser patch is documented in UPSTREAM.md; its default history behavior is
unchanged. Tests cover complete long input/output, Unicode page reassembly,
partial JSONL results, content/generation invalidation, fixed supported fields
and final scope revocation. Current deployed live Bridge still needs updating to
this candidate and native full-record acceptance before the correction is marked
fully accepted.
