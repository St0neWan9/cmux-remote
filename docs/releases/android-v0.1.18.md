# CmuxRemote Android 0.1.18

Entering the app now shows that the Macs are being connected, instead of
looking idle while the first links are dialled.

## Conversation list

- On launch, every saved Mac's filter pill turns its connecting indicator while
  its first link and read are in flight, matching the iPhone's `.connecting`
  state. The indicator becomes a green or red dot when the read answers, so a
  slow relay dial is no longer silent.
- A background read still does not turn any pill, so returning to the app does
  not flicker the status dots.
- A first install has no saved pairing, so it opens the pairing page and starts
  LAN discovery (and the relay directory when an address is added); a link can
  only be opened after the Mac owner approves the device.

## Verification

- 117 JVM tests, 15 Compose tests and `scripts/verify.sh` (527 Swift tests).
- Task-owned emulator with a real `cmux-tui` session behind an isolated Bridge:
  cold start restores the saved Mac, dials the link and reads the list, with the
  pill's state moving from connecting to green. A hung listener on the Mac's
  port resolves to the red dot after the read fails.

## Install

Download `CmuxRemote-Android-0.1.18.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
