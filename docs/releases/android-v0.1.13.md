# CmuxRemote Android 0.1.13

A relay recovery fix.

## Fixed

- A relay link that dies while the app is running no longer leaves the phone
  stuck on an unreachable Mac. A failed list read now drops the dead link,
  tries the LAN once, dials the relay again, installs the new link and retries
  the read. This covers the common case where the phone leaves Wi-Fi or the
  Bridge's relay socket is briefly disconnected.
- Pairing over the relay alone works: the post-approval probe now falls back to
  the relay when the LAN path is unavailable, instead of reporting "cannot
  reach this Mac".

## Verification

- 111 JVM tests, 15 Compose tests and `scripts/verify.sh` (527 Swift tests).
- Reproduced the Relay transport against the deployed
  `relay.trentaml.com` Worker with an isolated Bridge: `relay connected`,
  `/v2/identity`, sessions, workspaces and feed all answered over the relay.
- Local diagnosis: Mac `~/.local/state/cmux-remote/bridge.log` and the Bridge's
  `[relay]`/`[link]` lines; Android connection page → 诊断日志 and
  `adb logcat -s cmux-relay`. The Worker logs its connect/disconnect/error
  lines through `wrangler tail` (observability history is disabled).

## Install

Download `CmuxRemote-Android-0.1.13.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
