# CmuxRemote Android 0.1.23

Rotating a phone or tablet no longer crashes the app.

## Background connection

- The foreground service used to be started in `onPause` and stopped in
  `onStart`. A configuration change does both in quick succession, so Android
  could report `ForegroundServiceDidNotStartInTimeException` and close the app.
- The service is now tied to the app having connected Macs: the page starts it
  once the shell is connected and leaves it running until the setting is turned
  off, the last Mac is removed, or the app is finished. Rotations, permission
  dialogs and short pauses no longer start and stop it.
- The ongoing connection notification is therefore shown while the app is open
  as well; Android requires it for the service that keeps the links alive.

## Verification

- Reproduced the crash on an emulator by rotating; after the change, repeated
  rotations at phone size and at a 1067dp tablet layout (two panes) leave no
  `FATAL EXCEPTION` and no `ForegroundServiceDidNotStartInTimeException`.
- 117 JVM tests, 15 Compose tests and `scripts/verify.sh` (529 Swift tests).

## Install

Download `CmuxRemote-Android-0.1.23.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
