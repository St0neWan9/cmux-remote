# CmuxRemote Android 0.1.6

An approved Mac on a remote network now loads its conversations, and the list
shows one loading indicator instead of two.

## Fixed

- **A relay connection no longer stalls after the handshake.** The phone read
  the Bridge's runtime epoch through a direct LAN request even when it had just
  dialed the relay; that request could never answer, so the list refresh never
  ran. It now reads the epoch over the link, hands it to the signed-read client,
  and reuses the host's existing repository so refreshes travel the same relay
  link. Verified against the production relay: `GET /v2/identity`,
  `/v2/relay`, `/v2/sessions`, `/v2/workspaces` and `/v2/feed` all answered over
  the relay, and the real workspace sessions appeared.
- **The approved relay permit is refreshed automatically.** After connecting,
  the phone verifies the host-signed `GET /v2/relay` hint and saves the current
  approved permit, so a Mac that rotates its relay does not need a new pairing.
- **One loading indicator.** The list drew both the pull-to-refresh indicator
  and its own spinner; only the pull-to-refresh one remains.

This release carries the 0.1.5 fixes too: the approved relay permit from the
enrollment status is saved, older Bridges are accepted, cards span the page,
and the scanner has a frame, tap-to-focus, zoom and the iOS icon.

A Mac paired by a build before 0.1.5 still holds the enrollment window's permit;
remove and pair it once to store the approved one.

## Install

Download `CmuxRemote-Android-0.1.6.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

## Verification

The APK is signed by the Android release key (certificate SHA-256
`c6fbc46c9a91a1d5338382afb72489267d041f9a6a13224589c938036aeb5066`).

CmuxRemote is not an official cmux product.
