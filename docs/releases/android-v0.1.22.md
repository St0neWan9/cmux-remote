# CmuxRemote Android 0.1.22

Background task rows now align the tool type and the task title the way the
iPhone does.

## Conversation

- In the expanded background-task bar, the bullet, the tool name (`Bash`,
  `Shell`, …) and the task title now share the title's first text baseline.
  A wrapped title therefore starts under its own first line instead of the
  bullet and tool name floating in the middle of a two-line row.
- The tool name uses the same medium weight as iOS, and the chevron stays
  centred against the full row.

## Verification

- 117 JVM tests, 15 Compose tests and `scripts/verify.sh` (529 Swift tests).
- The existing background-task Compose test covers the collapsed summary and
  the expanded rows.

## Install

Download `CmuxRemote-Android-0.1.22.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
