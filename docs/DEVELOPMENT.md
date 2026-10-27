# Development

Mac Companion and extension builds use `scripts/build-macos.sh`; installation and
the current snapshot-mirror limits are in [MAC-EXTENSION.md](MAC-EXTENSION.md).
`scripts/verify.sh` also checks the separate Mac localization catalog.

Run `scripts/verify.sh` before publishing. Tests use temporary files, synthetic transcripts and fake cmux responders; they do not type into a user's terminal. `scripts/build-ios.sh` generates an Xcode project and compiles the iPhone app for an isolated generic Simulator destination without signing. A build proves compilation, not touch behavior or physical-phone connectivity.

The Mac CLI is built with SwiftPM and requires no paid developer account for local use. Public binary releases need a separate Developer ID signing/notarization workflow. Signing requirements do not depend on Swift versus Go/Rust. The iPhone target uses its own bundle ID and signing team; do not reuse cmux's production identity.

For isolated Simulator installation, run `scripts/install-ios-simulator.sh <task-owned-UDID>` after building. It ad-hoc signs only this project app, with no restricted entitlements. Simulator pairing is stored in an owner-only file inside that Simulator app's sandbox, because there is no provisioning profile for Keychain access groups. Physical iPhone builds use device-only Keychain storage and the selected developer team's profile; Simulator enrollment does not establish physical Keychain or camera verification.

Supported first backend: official cmux on macOS, via its owner-controlled local Unix socket. Discover the socket from explicit CLI/env configuration, the current marker, then documented legacy locations. Actual method invocation, not capability advertisement alone, determines support.

Use English and Simplified Chinese localization in `ios/Resources`. Keep technical machine error codes stable and map them in the UI. Keep local development credentials in a state directory outside the repository.

To refresh the vendored parsing library, copy only public upstream source, record its exact commit, preserve notices, inspect the diff and run all parser/history tests. Never copy personal transcript data into test fixtures.

For packaging, manually run the **Package verification** workflow in GitHub
Actions. It runs the package/model checks and builds the iPhone Simulator and Mac
Companion targets on macOS. Commits, pull requests and merges do not trigger CI.

## Connection and phone UX status

The shared connection phases in [the unified plan](UNIFIED-CONNECTION-PLAN.md)
now use signed v2 enrollment, Bonjour reachability, explicit host trust, owner
approval, scoped device grants and independent revocation. See
[the wire contract](CONNECTION-V2.md). Phone subscriptions and durable mutation
receipts/cursors remain future work. Mac mirror readiness is a separate gate.

## Live verification — 2026-10-12

The installed official cmux app was tested with its existing `cmuxOnly` socket mode and Claude Code 2.1.296. The Bridge was launched in a dedicated cmux terminal. A second workspace ran Claude Code in this repository; no installed cmux files or socket settings were changed.

The task-owned `cmux-remote-verification` iPhone Simulator enrolled through the Debug pairing-file hook, using the normal pinned HTTPS client. Its UI discovered the live session, displayed the initial transcript, sent a prompt, and automatically displayed Claude's exact `CMUX_REMOTE_PHONE_OK_1012` reply. The phone Stop button then interrupted a running count request; the desktop showed `Interrupted · What should Claude do instead?`. This validates real session discovery, history, sending, reply refresh and interrupt routing. It does not establish token-by-token preview fidelity, physical-camera scanning, physical-device Keychain, or Wi-Fi connectivity.

Live sessions now appear before read-only history. The interrupt guard was repaired: sends still reject a desktop draft/dialog, while interrupts require the same fresh identity checks without the typing-only restriction. The regression failed with `input_busy` on commit `0d4193e` and passed after the repair using `swift test --jobs 6 --filter ServiceTests.interruptCanStopAnAgentWithBlockedTyping`.

Immediate Bridge restart after an active HTTPS connection originally failed with `Address already in use`. Listener address reuse repairs this without changing the paired endpoint. The regression failed on commit `89780d0` and passed after the repair using `swift test --jobs 6 --filter HTTPSIntegrationTests.bridgeCanRestartImmediatelyOnItsPairedPort`. Final scoped verification passed 26 tests in 8 suites, the SwiftPM build, 52 matching English/Simplified Chinese localization keys and whitespace checks; the iOS generic Simulator build also passed.

## Mac extension verification — 2026-10-12

The independent Mac containing app and public sidebar extension compile with the
Swift 6 toolchain on Apple Silicon. Deep/strict code-signature checks pass and
`pluginkit` registers one `cmux-remote.desktop.sidebar` extension under
the official production extension point. Official cmux was not modified,
restarted, or re-signed; its selected sidebar was not changed.

The Companion was launched and visually inspected. Bonjour returned a nearby
Bridge, and selecting it displayed explicit first-use identity confirmation.
The test request was cancelled; no network grant was approved by this check.
The updated UI was relaunched after installation. Mac English/Simplified Chinese
resources contain 27 matching keys, and the iPhone compatibility build passes.

Package verification passes 51 behavior tests in 17 suites, including signed TLS
replay/input, scope denial before cmux access, hibernation rejection, changed
producer epochs, duplicate/unknown input, independent detach, and first-use trust
gating. These tests use isolated synthetic responders, not user Agents.

The focused command `swift test --jobs 6 --filter CLIControlTests.lostMirrorWorkspaceCreateIsOutcomeUnknown`
failed with `socket_unavailable` before mirror-create operations were classified
as mutations, then passed after returning `outcome_unknown` instead. No create
is retried automatically after a lost response.

A direct `cmux-remote doctor` from this agent process did not obtain the installed
cmux socket authority. The implementation does not relax socket mode to work
around that denial. Real replay, interactive typing, full workspace layout and
physical two-Mac acceptance remain unverified; run those from an authorized local
Bridge and selected test workspace before claiming native mirror readiness.

### Continued live mirror acceptance — 2026-10-12

Two isolated resident Bridges were started inside a newly created official-cmux
test workspace, retaining the original `cmuxOnly` policy. A second test workspace
ran two plain Python processes in a horizontal split. The Mac client enrolled
through the real signed HTTPS protocol and was approved only for that source
workspace with `workspaceRead`, `terminalRead` and `terminalInput` capabilities.
No existing Agent session was used for mirror input.

The local mirror created two viewer panels with the same split orientation and
displayed the existing source processes' increasing counters. Typing
`CMUX_MIRROR_INPUT_OK_1012` into the local viewer produced the exact
`SOURCE_RECEIVED CMUX_MIRROR_INPUT_OK_1012` response from the original source
process. Ctrl-] exited that viewer while the other viewer kept updating and both
source process PIDs remained alive. This establishes actual terminal replay,
input routing and independent detach through official cmux, with two Bridges on
one Mac. It does not establish physical two-Mac networking, exact layout ratios,
full scrollback or native/lossless mirroring.

The first real viewer exited on a large frame: setting raw input nonblocking also
affected stdout's shared tty descriptor, and `EAGAIN` was mistaken for a closed
output. The focused `swift test --jobs 6 --filter TerminalOutputTests` failed with
`terminal_unavailable` before the repair and passed afterward. The shared writer
now handles partial writes, `EINTR` and `EAGAIN`, using a bounded cancellable
readiness wait. A saved-host entry was also added to the Companion UI so a valid
grant remains usable with an empty discovery list; its behavior test passes.

The installed Companion's Bonjour list remained empty during this continuation,
although a separate Network-framework browse and DNS-SD browse saw all live test
services. Saved-host selection, workspace loading and the **Mirror here** button
were visually verified; the button created a fresh two-panel mirror after the
previous local viewer workspace was closed.
The official cmux Extensions beta gate was disabled, hiding its puzzle button;
enabling that setting was requested from the user and is not claimed completed.
System registration still does not establish actual ExtensionKit loading in cmux.

Final verification passed 53 package tests in 18 suites, all six phone-state
checks, 28 matching Mac localization keys and the Mac/iOS build wrappers. An
additional focused writer check covers a stalled output descriptor's deadline.
English/Simplified Chinese catalogs were audited and no temporary discovery
logging remains in the client source.

## Connection v2 and phone layout verification — 2026-10-12

### Extension loading and Mac discovery continuation

At the user's request, Extensions beta was enabled in official cmux Settings.
The installed public sidebar extension loaded through ExtensionKit, displayed
its local workspace list after metadata/selection access was approved, and
selected the task-owned Bridge workspace through the SDK. Official cmux was
neither restarted nor modified. Installation now unregisters this project's
Xcode build product so the system extension picker shows only the installed copy.

The Companion now reads Bonjour hints and resolves observed peers through the
private local Bridge (`mac.discovery.list/resolve`). The GUI's earlier direct
browse remained empty; no system-wide network/privacy protection was relaxed.
The underlying shared Network-framework browser runs in the resident cmux-spawned
CLI process. The actual Companion UI displayed both test-host services, omitted
the local Bridge itself, and selected its saved source host directly from the
discovered list with the existing host identity, TLS pin and grant intact.
Identity confirmation for an unpaired host was displayed and cancelled without
creating a grant. Behavior tests cover owner-channel discovery, rejection of
unobserved resolutions, refreshing discovery, and saved-host selection.

Development signing is selectable but defaults to ad-hoc. A trial Apple-issued
development identity triggered an existing sandbox-container ACL approval during
startup. The UI tool refused access to that system approval window, so final live
verification uses the independent `.sidebar.local` development identity with a
new empty sandbox. The existing container was preserved. The official sidebar
selection was updated from the obsolete extension ID to that installed development
ID; cmux's current picker otherwise kept selecting the no-longer-installed ID.
No installed cmux code or system security protection was changed.
Mac screenshots are saved under `.build/verification/ui-flow` outside Git.

The final verification passes 58 package tests in 18 suites, all six phone-state
checks, 28 matching Mac localization keys and 83 phone localization keys. Mac and
iOS wrapper builds and deep/strict signatures pass. After the final update, the
actual UI again discovered two hosts, loaded the approved workspace, created its
two-panel mirror and showed the running extension's workspace list. The tests
also verify that disabled discovery stays disabled when refreshed.

The task-owned iPhone Simulator enrolled a new device through the v2 bootstrap
and owner-approved workspace scope. An actual Bonjour browse resolved the LAN
endpoint, and the client relocated from loopback while retaining its identity
and grant. The phone restored that grant after app and Bridge restarts.

In the existing official cmux Claude session, phone sends produced real replies,
read-only README tool activity appeared as a collapsed group, and stop was
exercised on a long-running reply. The new interface was checked with a long
history, user bubbles, selectable Markdown, activity expansion, menus and a
floating send/stop composer. It keeps historical reading separate from following
new messages and preserves unlabeled fenced code. The Simulator remains open.

Scoped regressions cover permission changes during backend awaits, stale binding
refresh, IPv6 endpoint formatting, interrupted turns and enrollment lifecycle.
The actual iOS-model harness checks six behaviors, including a submission that
finishes after scene pause and a later desktop turn with an unobserved idle
transition. English and Simplified Chinese phone catalogs have 80 matching keys.
The isolated connection/phone submission passes 41 package tests in 15 suites
and all six actual-model checks; the generic iOS Simulator build passes. Camera scanning on a physical phone,
physical device-only Keychain and Wi-Fi handoff still require device acceptance.
Automated touch dragging did not yield a reliable Simulator acceptance result;
inertial scrolling while replies grow and the iOS 17 gesture fallback remain
explicit visual coverage gaps.

After cancellation, cmux can retain a working snapshot even when Claude has
restored the prompt. The phone acknowledges the successful stop request without
claiming completion or suppressing further stop controls. The acknowledgement
clears on an observed state change, a new user message, or a phone send.

## Conversation overlap rendering

The header and composer float over a white page with no fill of their own. Each
timeline row carries a layer effect (`HeaderContentEffect`) whose Metal stitchable
shaders (`ConversationHeader.metal`) blur the ink entering the top and bottom
bands and fade it toward the page, so the page stays white and only the ink under
the bars is softened.

## Reply text selection

Prose is SwiftUI text, so a reply copies with the pages' own controls rather than
in-place selection. A reply's footer offers Copy, Share, Quote and Select Text;
Select Text opens the text on its own page (`SelectTextPage`) in a `UITextView`,
where the system's handles, magnifier and edit menu can take any part of it. The
reader's own message and a tool's text offer the same Copy / Select Text pair
from a long press. In-place selection is deliberately not used: the per-row layer
effect rasterizes the row, and a rasterized row draws the selection interaction as
a placeholder.

## Mac B LAN verification — 2026-10-12

The physical client Mac (`thunderfoot`, macOS 26.6.2 / arm64) connected to the
dedicated `cmux Alpha Remote` service on Valuz-Studio over Bonjour and pinned
HTTPS. Both official cmux apps stayed running. The client used a new window and
received only workspace/terminal read and terminal input access to the dedicated
source acceptance workspace. Companion discovery, first-use trust, host approval,
saved-host restoration, native Remote grouping, three panes/six tabs, ordinary
and hidden-tab input, and repeated open were exercised. The mirror was opened
through the documented CLI; the UI automation tool could not click Mirror here,
so that button's physical-client journey is not claimed verified.

One local Bridge restart and a remote Bridge restart retained all six binding
IDs, viewer PIDs and producer epochs. A 20-second suspension of only the dedicated
remote Bridge produced `reconnecting`, then `watching` and advancing TUI frames
with the original source PID. Reusing one confirmed input operation before and
after the remote restart produced one source acknowledgement. Ctrl-] detached one
local viewer; closing and explicitly reopening the test mirror restored all six
original producer epochs. Existing Claude/Codex sessions were not controlled;
their acceptance gate remains pending.

Testing `main` at `95fb435` exposed an incorrect `system.tree` parameter: `all`
left the inventory scoped to the current window and could cause another window's
mirror to be mistaken for closed. `all_windows` repairs both inventory reads.
The unfocused-window regression failed before the repair and passed afterward.
The phone-model harness also now uses SwiftPM's reported product directory and
supports both native and Swift Build module objects. Final `scripts/verify.sh`
passed 201 package tests, 90 actual phone-model checks and both localization
catalog checks; the Mac wrapper build and installed signature checks passed.
Receipts are in `.build/verification/mac-b-lan-20261012/`, outside Git. The tested
baseline was `95fb435`, with the inventory and harness repairs described above.

## TestFlight packaging

The iOS release configuration follows the adjacent Valuz Fastlane flow, using
its public team ID with cmux-remote's independent Bundle ID and App Store
profile. A manually dispatched GitHub workflow imports an existing distribution
certificate into a temporary keychain, exports an IPA, and uploads only when
requested. Signing secrets and the App Store Connect app record are not copied
from Valuz. See [TestFlight setup](TESTFLIGHT.md).

Local verification passed 201 package tests, 90 phone behavioral checks, seven
release checks, the SwiftPM build, both localization audits (212 phone and 39
Mac keys), the iOS Simulator build and an unsigned device Release archive. The
archive's Bundle ID/version/build, AppIcon and privacy manifest were inspected;
Fastlane's build/upload lanes load with the locked dependencies. No signed IPA
export or Apple upload was performed: this repository currently has no signing
secrets configured, and this app's Apple record/access remains to be verified.

## First signed iPhone package — 2026-10-12

The owner account registered the app's first bundle ID and created a separate
App Store Connect record for it; both are retired, see *Signing moved to the
maintainer's individual team* below.
The phone's invariant display name is **Cmux Remote** in English and Simplified
Chinese. Its new opaque 1024-pixel icon incorporates cmux's cyan-to-violet
chevron reference; the generation prompts and upstream provenance are recorded
in `ios/Resources/APP-ICON.md`.

A dedicated App Store profile was generated with the owner's existing Apple
Distribution certificate. A real device Release archive and signed IPA export
for `0.1.0 (1)` passed. The upload guard verified the actual IPA identity,
version/build, nonexpired App Store profile and deep/strict code signature.
The actual bundle display name and both localized InfoPlist catalogs (five
matching keys) were checked. The package suite (201 tests), 90 phone checks,
seven release guards, SwiftPM build, both ordinary localization audits and the
iOS Simulator build passed. The signed IPA is in `.build/ios-release/dist/`,
outside Git. TestFlight upload is pending approval to generate a dedicated
Developer API key and store the signing credentials in the repository's
TestFlight environment Secrets; the prepared key has not been generated.


## TestFlight activation — 2026-10-12

After explicit owner authorization, the dedicated Developer API key and existing
owner-team distribution identity were stored in the repository's `testflight`
environment Secrets. Deployment branch policy allows only `main`. No signing
credential files are tracked in Git. The private P8 backup is outside the
checkout with restricted permissions; the temporary P12 export was cleaned up.

The signed `0.1.0 (1)` package uploaded through Fastlane, completed Apple
processing, and is **Ready to Test** in the internal **Owner** group. Only the
account owner was added, with invitation status **Invited**. External testers
and public invitation links were not configured.

[The manual packaging run](https://github.com/St0neWan9/cmux-remote/actions/runs/38249260373)
on code SHA `61dd6d20ca2af2b4c07c5f1fb4ccbc418feb014a` passed all executed steps:
201 package tests, 90 phone checks, seven release guards, SwiftPM build,
localization audits, Fastlane loading, temporary keychain import, provisioning
profile retrieval, device archive, signed IPA export and artifact upload. Its
`0.1.0 (2)` IPA was downloaded and independently passed the actual payload,
profile and deep/strict code-signature guard. The CI run did not upload that
second build. Account screenshots and signed packages stay under `.build/`,
outside Git. Physical iPhone installation and paired LAN use remain separate
acceptance steps.

## Signing moved to the maintainer's individual team — 2026-10-26

The iPhone app now ships under the maintainer's individual team `7G42499LWB` with
bundle ID `cmux-remote.mobile` and its own App Store Connect record (**Cmux Remote
for Mobile**). The account it shipped under before that — its record, team and
Apple Distribution identity — is retired: no workflow, script or local check uses
it. The current account's API key lives at
`~/.cmux-remote-release/huiyuanjia/notary.json`, which `scripts/testflight-status.py`
reads; an App Store Connect key only lists its own account's apps, so a key from
the retired account reports an empty build list rather than an error.
