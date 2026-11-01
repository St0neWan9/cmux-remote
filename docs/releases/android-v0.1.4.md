# CmuxRemote Android 0.1.4

Pairing from outside the LAN now actually reaches the relay, and a device the
Mac has revoked says so instead of failing as a dead link.

## Fixed

- **Relay enrollment no longer waits on an unreachable LAN twice.** After the
  direct request times out, the phone dials the relay immediately instead of
  first attempting the LAN WebSocket for another timeout.
- **A revoked identity is named.** The relay refuses a device whose identity
  the Mac revoked before the enrollment ever reaches the Mac, answering
  `401 revoked`. That is now shown as a revoked device with the action below,
  not as “cannot reach this Mac”.
- **A connecting state is visible.** While an enrollment is in flight the page
  shows “Connecting to the Mac…” (LAN, then relay, up to about 30 seconds).

## Added

- **Reset this phone's identity** (under **Advanced**) for a device the Mac has
  revoked. It deletes the device key, every paired Mac and the local
  conversation cache, then pairing starts as a new device. This is the only way
  to re-pair through a relay with a revoked identity; pairing again on the same
  LAN also clears the revoked flag without resetting.
- The relay address example is now generic (`https://your-relay.workers.dev`).

The desktop app is unchanged; this release contains the Android APK only.

## Install

Download `CmuxRemote-Android-0.1.4.apk`, open it on Android 10 or later. Same
signing key as earlier releases; it installs as an update.

## Verification

After resetting the test identity, a pairing code whose LAN endpoint was
deliberately unreachable enrolled over `https://relay.trentaml.com`, opened the
encrypted link (`relayed=true`) and appeared in the Mac's pending list. The APK
is signed by the Android release key (certificate SHA-256
`c6fbc46c9a91a1d5338382afb72489267d041f9a6a13224589c938036aeb5066`); compare the
download with the attached `.sha256`.

CmuxRemote is not an official cmux product.
