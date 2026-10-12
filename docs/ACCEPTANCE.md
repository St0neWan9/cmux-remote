# Full acceptance audit

Objective: test every designed feature, repair failures and show the full UI flow.
The immediate convergence milestone is [Mac-to-Mac Alpha](MAC-MILESTONE.md):
freeze the current candidate and close its three focused exit gates. Other rows
remain historical evidence or later milestones, not automatic scope expansion.
Current thread scope, as clarified by the owner on 2026-10-12: Mac client,
Bridge and workspace mirroring only. Do not implement phone features or operate
the Simulator in this thread. Existing phone evidence below is historical and
does not define remaining work for this thread.
The source contracts are DESIGN.md, CONNECTION-V2.md, API.md and
UNIFIED-CONNECTION-PLAN.md. Passing a build or a fake responder is not live UI
acceptance. The existing implementation's limitations do not remove target-design
requirements from this audit.

| Requirement | Required evidence | Current evidence / remaining work |
| --- | --- | --- |
| Installed official cmux stays running and unmodified | Stable host process; same socket policy | Previous live checks preserved it; recheck throughout |
| Shared resident Bridge and private administration | Simultaneous client access; second serve refused; owner routes unavailable on LAN | Two independent Mac clients viewed the same source; duplicate serve refused; LAN owner-route check pending |
| Discovery and host verification | Actual peer list; selected endpoint verified; no auto-trust from TXT | Mac UI discovered two services; full invalid-identity and relocation checks pending |
| Enrollment approve/deny/cancel/expire | Exact pending request, no unintended grants, UI screenshots | Actual CLI approval/cancel/deny/30-second expiry passed; full GUI sequence pending |
| Independent phone/Mac identities and scope | Two clients, different grants, narrow scopes | Synthetic TLS coverage; shared-host live check pending |
| Restore after client/Bridge restart and endpoint change | Same trust and grant restored without enrollment | Previously observed partly; cold-start/deep-link and all restart cases pending |
| Revocation and read-only access | Only selected client loses access; no input for read-only grant | Four read-only viewers ignored typed input; revocation removed their attachments, another client still read, source PIDs stayed alive |
| Phone conversation/history/live preview/send/stop | Real cmux-bound session, foreground/background recovery and full UI artifacts | Dedicated existing Claude session: real history, phone send and Stop passed. Cold app launch restored its existing authorization; interrupted history now shows Send without a stale Stop (phone-07/08). One further controlled prompt reached the same session and returned PHONE_MARKDOWN_OK_1012. Background/foreground retained that reply and the same app PID; active-turn background gaps and broader reconnect cases remain pending |
| Phone Feed/files/changes/diffs/Markdown/activity | Supported decision kinds, scoped paths, user-visible flows | Actual project changes, README preview and Git diff passed (phone-09/10/11). Path traversal was denied, but previously retained another file's content/copy actions; model regression and native phone-12-denied-file-fixed.png now show no content or copy/share actions. Native Markdown exposed literal heading/list syntax and a blank code area; parser and wrapping renderer repair passed against the same existing reply (phone-16-markdown-fixed.png). Feed decision kinds, activity expansion and remaining reply actions still need their full UI journey |
| Terminal replay/input/detach and stale runtime | Already-running source, exact input, source survives detach and denied rebind | Live replay/detach and alternate TUI passed; cold-open/reopen/fully-detached recovery regressions repaired; latency, runtime replacement and agent feasibility gate pending |
| Terminal repaint flicker | No intermediate blank screen during steady TUI updates | Early synchronized-output release reproduced and repaired. Viewer now uses positioned repaints after its first full restore; geometry, screen and mode/theme changes require a full restore. Package regression checks cover both screens and independent viewers. Final live clip native-flicker-repaint-fixed.gif contains 110 frames over 6.06 seconds, with no blank header frames; the first synchronization-only candidate still exposed one blank frame and was rejected. Original source PIDs and official cmux stayed running. The subsequently discovered local restart failure was repaired and verified with five restarts; see receipts below. Source-peer restart continuity passed with a 20-second outage: native-peer-recovery-v3-20s.json retained all six bindings/viewer PIDs and producer epochs, observed reconnecting then watching, and resumed live TUI frames. |
| Initial split nesting and pane tabs | Actual source topology vs local topology, labels and hidden terminal replay | Actual three-pane nested split with four terminals and a hidden tab passed; source names now preserved |
| Remote topology reconciliation | Add/remove/reorder source resources without restarting their processes | Implemented bounded metadata reconciliation with safety tests. Live testing found native tab insertion order differs from the fixture; initial tab ordering repaired. Final native baseline, add, reorder and remove passed with six seconds of stable exact layout and watching status per stage (topology-final-*.json). Original six viewer IDs, local surface IDs and viewer PIDs were retained; original source PIDs stayed alive. Regressions covered delayed tab publication, an already-exited removed viewer and late replay resurrection. Post-change restart retained the same six viewers (native-restart-topology-before/after.json); screenshot native-topology-final.png |
| Snapshot subscriptions, event reconnect and gaps | Bounded delivery, independent cursors and explicit resnapshot after a gap | Dedicated cmux event monitor and private durable boot/sequence cursor implemented. Unit checks cover EOF reconnect, new boot, gap and cancellation; a real Unix socket fixture additionally checks actual subscription framing, replay, boot/gap reset and cursor reuse after monitor restart. The official-cmux connection created its owner-only cursor. Bounded phone subscriptions with independent cursors remain pending |
| Durable mutation receipts/cursors | Lost responses and Bridge restart never cause blind duplicate writes | Durable per-device chat/interrupt/Feed/input intents and receipts implemented. Restart, unknown completion, storage corruption/full/unavailable, negative acknowledgement and revoked receipt reads pass behavioral tests. Signed HTTPS restart retains the grant and operation with one backend attempt. Real official-cmux input repeated across isolated Bridge process restart reached its original source exactly once (native-durable-before/after and native-durable-server-before/after.json); native-durable-once.png. Dedicated cmux event cursor now persists separately; subscription cursors remain pending |
| CLI discover/connect/mirror families | Actual command results, same state/authority as GUI | discover/connect/cancel/forget and mirror exercised against private resident sockets. Status without enrollment originally failed; now returns saved hosts plus idle enrollment. Approval-read ordering and owner-error propagation covered by focused regressions |
| Sizing, colors, cursor/modes and alternate screens | Live controlled terminal programs, representative size changes | Smaller-pane alternate TUI originally blank; actual cmux read-text check failed then passed after positional repaint. Focus/mouse report restoration polluted an Agent draft; modes suppressed after primary/alternate regression tests failed then passed. Native mirror focus change left the original prompt empty; broader resize/cursor-mode checks pending |
| Native sidebar integration | Keep original local list; native Remote group below it, original row styles | User corrected the replacement-sidebar design. Default sidebar restored; real native group and group-block ordering verified; screenshot native-sidebar-remote-group.png. Bridge integration implemented; replacement extension removed from default build |
| Native remote inventory and lazy attachment | Every authorized remote workspace appears; selection opens its existing producers | Scoped native inventory and selection waiters implemented. Native click opened five existing source terminals in the exact pending workspace; repeated open retained that workspace and five viewers. Receipt native-remote-lazy-open.json; screenshot native-remote-lazy-open.png. A real temporary grouping failure was repaired and behavior-tested; Completed-view restart recovery passed with the same workspace, five surface IDs and five viewer PIDs; native-restart-before/after.json and native-bridge-restart-restored.png. Offline/partial restart cases remain. Catalog status/recovery repaired: closed real row reports paused; one explicit open recreated a pending row and attached six original producers, repeated open retained one workspace. native-catalog-close-live.json, native-catalog-recovery-one-open.json and native-catalog-recovery-after.json; native-catalog-recovered.png. Tests also cover moved windows, partial mirrors, slow publication and lost recreation receipts |
| Physical LAN and iPhone device acceptance | Two Macs and physical iPhone, camera/network/Keychain evidence | Device availability requested; current environment proves one Mac plus Simulator only |
| Localization/build/signature/test coverage | Executed scoped checks on current candidate | Current combined checkout: 152 package tests and 20 actual phone-model checks passed; 172 phone and 38 Mac locale keys match. Mac dropped-response repair build and iOS project/Markdown repair builds passed. Native cold-start composer and project/Markdown recovery screenshots are recorded. No new localized UI string keys were introduced by these repairs |
| Screenshot deliverable | Persistent images for each actual stage, visible final embeds | Existing partial flow under .build/verification/ui-flow; add complete evidence |

## Latest regression receipts

Current passed screenshot stages (private artifacts; this is not the completed
whole-product acceptance):

| Stage | Screenshot |
| --- | --- |
| Remote Bridge recovery after a 20-second outage | [Recovered mirror](../.build/verification/full-acceptance/native-peer-recovered.png) |
| Native Remote group after five resident restarts | [Native mirror](../.build/verification/full-acceptance/native-restart-read-drop-fixed.png) |
| Phone cold-start authorization and sessions | [Sessions](../.build/verification/full-acceptance/phone-07-restored-sessions.png) |
| Interrupted history with Send restored | [Composer](../.build/verification/full-acceptance/phone-08-interrupted-send-restored.png) |
| Project changes | [Changes](../.build/verification/full-acceptance/phone-09-project-changes.png) |
| Scoped README preview | [File](../.build/verification/full-acceptance/phone-10-project-file.png) |
| Actual Git diff | [Diff](../.build/verification/full-acceptance/phone-11-project-diff.png) |
| Rejected outside path without stale content | [Denied file](../.build/verification/full-acceptance/phone-12-denied-file-fixed.png) |
| Existing Agent reply with rendered headings, lists and visible code | [Markdown](../.build/verification/full-acceptance/phone-16-markdown-fixed.png) |

Private native evidence lives under `.build/verification/full-acceptance`:

- `agent-mirror-focus-fixed.png`: the existing Claude session after mirror focus
  changes, with its draft empty; the source runtime was not restarted.
- `phone-05-running-stop.png` and `agent-mirror-phone-stop.png`: phone Stop control
  followed by interruption of the same cmux-bound producer.
- `phone-06-stop-button-red.png`: completed/interrupted turn with a stale Stop
  control, captured before the composer predicate repair. This is failure evidence,
  not a passed final-state screenshot.
- `native-durable-once.png`: a real approved test terminal received one unique
  input; the same signed operation after a Bridge process restart returned its
  existing receipt without another source acknowledgement.
- `native-topology-final.png`: native Remote group after stable source addition,
  tab reorder and deletion, then a resident restart. The same six retained
  viewer processes and local surface IDs survived every stage.
- `native-restart-read-drop-fixed.png` and `native-restart-read-drop-fixed-before/after-1..5.json`:
  five consecutive resident restarts retained the same workspace, six surface IDs
  and six viewer PIDs. The previous failure was traced to a lost socket response
  being misreported as malformed JSON; a real socket regression failed before
  that classification repair and passed afterwards. Snapshot reads reconnect,
  while received malformed JSON and input writes are not automatically retried.
- `topology-repaired-remove-late-red.json`: the earlier removal receipt appeared
  successful but later paused; retained as failure evidence, not final acceptance.
- `connect-status.json`: resident owner channel returned two saved connections
  and idle enrollment, without starting another request.

Focused failing/passing logs are stored outside Git under `/tmp` with prefixes
`cmux-remote-focus-mode`, `cmux-remote-phone-interruption` and
`cmux-remote-connect-status`. Full native revalidation is still required where
noted in the table. Phone evidence comes only from this task's
cmux-remote-full-acceptance device (63B93D25-5A0F-4A47-A729-60AD1A62DF00).
Simulator keyboard focus can move to another window; verify the window and draft
before sending, and do not count another device's image as this task's evidence.

Windows/Linux adapters, media galleries, native/lossless mirror parity and release
publication are explicitly future or excluded scope in the source design; they
are not established by this first macOS/iPhone acceptance.

## Mac-only recovery validation, 2026-10-12

- The old viewer exited after a source outage exceeded its 15-second budget.
  That live attempt failed and is not counted as recovery evidence.
- The new viewer retained all six existing viewer processes and local surface
  IDs across a deliberate 20-second source Bridge outage/restart. The source
  certificate/identity and grants were unchanged. Status moved from reconnecting
  back to watching, and a subsequent frame from the same TUI producer changed.
  Source PIDs 34409, 34452 and 88560 and official cmux PID 77233 stayed alive.
  Receipt: `native-peer-recovery-v3-20s.json`; screenshots:
  `native-peer-disconnected.png` and `native-peer-recovered.png`. The final owner
  candidate also restored all six existing viewer PIDs and bindings after its own
  restart (`native-peer-final-owner-restart.json`).
- Scoped Mac recovery/topology/transport/render tests: final 79 tests in 12 suites
  passed after the checkpoint repair. The final Mac app and CLI builds passed; 39
  English/Simplified Chinese Mac localization keys match. No phone implementation
  or Simulator checks were run for these changes.
- A new partial-restore regression proved that saving a healthy mirror discarded
  another offline mirror's checkpoint. Failed-restoration metadata is now retained
  across unrelated saves, with explicit forget still removing it. Its red/green
  logs are `/tmp/cmux-remote-peer-checkpoint-red.log` and
  `/tmp/cmux-remote-peer-checkpoint-green.log`.

The current evidence uses separate authenticated Bridge processes on one Mac.
Two physical Macs, endpoint relocation, the complete Mac enrollment GUI journey,
additional sizing/mode cases and release signing remain separate acceptance gates.

## Frozen candidate installation and saved-host GUI flow

The frozen 2026-10-12 Companion was installed over this project's previous
Companion. Every installed file matched the candidate manifest; its old
replacement-sidebar extension is absent. The default local Bridge was updated
and restarted independently; source Bridge PID 59515 stayed running.

Cold launch showed saved hosts and nearby services. Selecting the existing
Read-only acceptance host read the authorized workspace without enrollment.
The visible Mirror here action opened six native viewers. Repeating it retained
the same six bindings. A subsequent local Bridge restart retained their PIDs;
Companion quit/relaunch and another explicit open also retained them. Official
cmux and the original source producer PIDs stayed alive.

Receipts: `alpha-install-open-before-repeat.json`,
`alpha-ui-repeat-and-bridge-restart.json`, `alpha-installed-companion-flow.json`.
The screenshot sequence `alpha-01` through `alpha-05` records saved/discovered
hosts, authorized workspaces, open confirmation, post-restart saved access and
the native Remote mirror. This proves the upgraded paired flow on one Mac;
it does not prove fresh enrollment or installation on a second physical Mac.
