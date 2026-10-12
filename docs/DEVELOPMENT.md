# Development

Run `scripts/verify.sh` before publishing. Tests use temporary files, synthetic transcripts and fake cmux responders; they do not type into a user's terminal. `scripts/build-ios.sh` generates an Xcode project and compiles the iPhone app for an isolated generic Simulator destination without signing. A build proves compilation, not touch behavior or physical-phone connectivity.

The Mac CLI is built with SwiftPM and requires no paid developer account for local use. Public binary releases need a separate Developer ID signing/notarization workflow. Signing requirements do not depend on Swift versus Go/Rust. The iPhone target uses its own bundle ID and signing team; do not reuse cmux's production identity.

For isolated Simulator installation, run `scripts/install-ios-simulator.sh <task-owned-UDID>` after building. It ad-hoc signs only this project app, with no restricted entitlements. Simulator pairing is stored in an owner-only file inside that Simulator app's sandbox, because there is no provisioning profile for Keychain access groups. Physical iPhone builds use device-only Keychain storage and the selected developer team's profile; Simulator enrollment does not establish physical Keychain or camera verification.

Supported first backend: official cmux on macOS, via its owner-controlled local Unix socket. Discover the socket from explicit CLI/env configuration, the current marker, then documented legacy locations. Actual method invocation, not capability advertisement alone, determines support.

Use English and Simplified Chinese localization in `ios/Resources`. Keep technical machine error codes stable and map them in the UI. Keep local development credentials in a state directory outside the repository.

To refresh the vendored parsing library, copy only public upstream source, record its exact commit, preserve notices, inspect the diff and run all parser/history tests. Never copy personal transcript data into test fixtures. CI builds Swift package tests and the iPhone Simulator target on macOS.

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

## Connection v2 and phone layout verification — 2026-10-12

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

The header keeps a white page background. A bounded SwiftUI layer shader blurs
and fades message pixels beneath the floating controls; it does not add a tinted
backdrop. The iOS target compiles `ConversationHeader.metal` into its default
shader library. `scripts/build-ios.sh` checks the Metal compiler and downloads
Apple's official Metal Toolchain component if the active Xcode lacks it.
