# CmuxRemote Android 0.1.12

A small conversation-page fix.

## Conversation

- The centred loading spinner shown while the first history read was still in
  flight is gone; the connection pill alone reports the state.
- Tapping the jump-to-latest button now keeps following: the page stays at the
  newest output as the reply streams, until the reader drags upward. Scrolling
  back to the end resumes following. Programmatic scrolling no longer counts
  as the reader leaving the bottom.

## Verification

- 111 JVM tests, 15 Compose tests and `scripts/verify.sh` (527 Swift tests).
- Checked against a live `cmux-tui` session through an isolated Bridge: scroll
  up, tap the centred button, and hold at the bottom across 14 seconds of new
  output; a manual upward drag then stops following.

## Install

Download `CmuxRemote-Android-0.1.12.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
