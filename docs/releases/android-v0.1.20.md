# CmuxRemote Android 0.1.20

Tool calls inside an expanded operation group sit together.

## Conversation

- Consecutive tool calls in an expanded `N 项操作` group no longer get an extra
  gap between them; the rows carry their own padding, so adjacent calls touch
  as they do on the iPhone while reasoning keeps its paragraph break.
- The group opens with the same small gap under its summary as before.

## Verification

- 117 JVM tests, 15 Compose tests and `scripts/verify.sh` (527 Swift tests).
- Rendered on a task-owned emulator against a real `cmux-tui` session with an
  isolated Bridge.

## Install

Download `CmuxRemote-Android-0.1.20.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
