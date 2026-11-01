# CmuxRemote Android 0.1.7

The Android client closes the feature and layout gaps against the iPhone app,
and fixes the data-routing problems that only appeared with more than one Mac.

## New

- **Several Macs work as independent hosts.** Every approved Mac keeps its own
  encrypted link, relay dial and reachability state; the list groups by Mac and
  workspace, and the drawer is a full conversation tree with search and sort.
- **Feed replies go back to the Mac that asked.** Feed items carry their host
  and session; pending reminders can be opened per Mac.
- **New conversations can target any approved Mac**, browse subfolders and carry
  a durable operation id, so an unknown outcome is checked instead of opening a
  second terminal.
- **Conversation parity** — images attach to their own messages, draft images
  preview, speech has its own draft strip, activity groups open on their own
  page, tool cards show status, completion time and every referenced file, and
  Markdown tables size columns to their content and keep alignment.
- **Legacy opt-in pairing** — paste a `cmux-remote://pair?v=1` code or fill in a
  Mac's host, port, shared token and certificate fingerprint. This is the only
  shared-authority path; it requires `--legacy` on the Mac and is clearly
  labelled as not revocable per device.

## Fixed

- The grant files (`connections.json` and the legacy `paired.json`) are sealed
  by a non-exportable Keystore AES-GCM key; a plaintext file from an earlier
  build is migrated on the next write.
- The unknown-send record is keyed by host and conversation, and another send is
  blocked until the receipt is inspected.
- Android now pauses approval polling in the background and resumes it on return.
- LAN probes and relay dials start together; a relay-only Mac no longer waits
  out the LAN timeout.
- Background sync keeps the newest twelve conversations' text warm, not only the
  list and pending count.

## Verification

- 111 JVM tests, including new coverage for the legacy codec, decision policy,
  project rename parsing and prompt unwrapping.
- 4 Compose instrumentation tests (Feed semantics, a session row as one target,
  and a rendered-pixel smoke test) ran on a task-owned foldable emulator.
- `scripts/verify.sh` passes: 527 Swift tests, phone-state checks, iOS/Mac
  localization, release checks and signing-material checks.
- The APK is signed by the Android release key (certificate SHA-256
  `c6fbc46c9a91a1d5338382afb72489267d041f9a6a13224589c938036aeb5066`).

## Install

Download `CmuxRemote-Android-0.1.7.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
