# Development

Run `scripts/verify.sh` before publishing. Tests use temporary files, synthetic transcripts and fake cmux responders; they do not type into a user's terminal. `scripts/build-ios.sh` generates an Xcode project and compiles the iPhone app for an isolated generic Simulator destination without signing. A build proves compilation, not touch behavior or physical-phone connectivity.

The Mac CLI is built with SwiftPM and requires no paid developer account for local use. Public binary releases need a separate Developer ID signing/notarization workflow. Signing requirements do not depend on Swift versus Go/Rust. The iPhone target uses its own bundle ID and signing team; do not reuse cmux's production identity.

For isolated Simulator installation, run `scripts/install-ios-simulator.sh <task-owned-UDID>` after building. It ad-hoc signs only this project app, with no restricted entitlements. Simulator pairing is stored in an owner-only file inside that Simulator app's sandbox, because there is no provisioning profile for Keychain access groups. Physical iPhone builds use device-only Keychain storage and the selected developer team's profile; Simulator enrollment does not establish physical Keychain or camera verification.

Supported first backend: official cmux on macOS, via its owner-controlled local Unix socket. Discover the socket from explicit CLI/env configuration, the current marker, then documented legacy locations. Actual method invocation, not capability advertisement alone, determines support.

Use English and Simplified Chinese localization in `ios/Resources`. Keep technical machine error codes stable and map them in the UI. Keep local development credentials in a state directory outside the repository.

To refresh the vendored parsing library, copy only public upstream source, record its exact commit, preserve notices, inspect the diff and run all parser/history tests. Never copy personal transcript data into test fixtures. CI builds Swift package tests and the iPhone Simulator target on macOS.

## Live verification — 2026-10-12

The installed official cmux app was tested with its existing `cmuxOnly` socket mode and Claude Code 2.1.296. The Bridge was launched in a dedicated cmux terminal. A second workspace ran Claude Code in this repository; no installed cmux files or socket settings were changed.

The task-owned `cmux-remote-verification` iPhone Simulator enrolled through the Debug pairing-file hook, using the normal pinned HTTPS client. Its UI discovered the live session, displayed the initial transcript, sent a prompt, and automatically displayed Claude's exact `CMUX_REMOTE_PHONE_OK_1012` reply. The phone Stop button then interrupted a running count request; the desktop showed `Interrupted · What should Claude do instead?`. This validates real session discovery, history, sending, reply refresh and interrupt routing. It does not establish token-by-token preview fidelity, physical-camera scanning, physical-device Keychain, or Wi-Fi connectivity.

Live sessions now appear before read-only history. The interrupt guard was repaired: sends still reject a desktop draft/dialog, while interrupts require the same fresh identity checks without the typing-only restriction. The regression failed with `input_busy` on commit `0d4193e` and passed after the repair using `swift test --jobs 6 --filter ServiceTests.interruptCanStopAnAgentWithBlockedTyping`.

Immediate Bridge restart after an active HTTPS connection originally failed with `Address already in use`. Listener address reuse repairs this without changing the paired endpoint. The regression failed on commit `89780d0` and passed after the repair using `swift test --jobs 6 --filter HTTPSIntegrationTests.bridgeCanRestartImmediatelyOnItsPairedPort`. Final scoped verification passed 26 tests in 8 suites, the SwiftPM build, 52 matching English/Simplified Chinese localization keys and whitespace checks; the iOS generic Simulator build also passed.
