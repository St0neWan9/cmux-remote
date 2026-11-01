# CmuxRemote Android 0.1.5

An approved device now reaches its Mac through the relay, and every page
outside a conversation uses the iPhone's full-width cards.

## Fixed

- **Authorization worked, but the list could not load over the relay.** The
  Bridge returns a relay permit bound to the approved device in the enrollment
  status. The phone used the enrollment window's permit instead, so every read
  over the relay was refused even though the device had been approved. The
  approved permit is now verified and saved with the connection; a device
  authorized on a remote network lists its Mac normally.
- **Cards span the page.** Add Device, New Conversation, Feed, Connection
  Details and the list's reminders used to shrink to the width of their text.
  They now fill the page like iOS; the conversation page is unchanged.

The relay also no longer refuses a revoked identity at the transport layer
(deployed separately); the Bridge still rejects its reads until the owner
approves a new enrollment.

## Install

Download `CmuxRemote-Android-0.1.5.apk`, open it on Android 10 or later. Same
signing key; installs as an update. If a Mac is already paired but still shows
"cannot reach", remove and pair it again so the approved relay permit is saved.

## Verification

A device was enrolled through `https://relay.trentaml.com` with an unreachable
LAN endpoint, approved read-only on one workspace, and then listed that
workspace's real sessions over the relay. The saved connection carries a relay
permit of kind `approved`, not `enrollment`. The APK is signed by the Android
release key (certificate SHA-256
`c6fbc46c9a91a1d5338382afb72489267d041f9a6a13224589c938036aeb5066`).

CmuxRemote is not an official cmux product.
