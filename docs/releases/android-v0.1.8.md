# CmuxRemote Android 0.1.8

This release completes the Android / iPhone parity pass: every remaining item
from the 500-row audit is either implemented or documented as a deliberate
Android platform equivalent.

## New

- **Per-Mac state everywhere.** The list shows each Mac's own error, workspace
  titles, `conversationStart` grant and in-flight read indicator; a failed read
  no longer clears the workspaces it published before. Background sync dials
  the relay when the LAN is unreachable and refreshes conversations that
  changed since the last stored copy.
- **Start over the list.** Starting a conversation now opens as a
  `ModalBottomSheet` over the connected list, while pairing still replaces the
  shell.
- **Two-part composer.** A focused composer expands to a full-width field with
  attachment, dictation and send on their own row; a user scrolling older text
  no longer has new output pull the page away.
- **Inline decisions.** While the Mac owner has not answered, the pairing page
  keeps its layout and swaps discovery for the request card; failures show as
  inline red text. Approval polling now runs until the enrollment ticket
  expires instead of a fixed 300 seconds.
- **Task details page back.** Agent task sheets load earlier messages with
  `before_seq`, and the task cache keeps the command, byte count and message
  rows for an offline open.
- **Edge back and RTL.** Root-replacement pages carry the iPhone's 24pt edge
  swipe, the drawer mirrors its displacement and drag direction in RTL, and the
  start/feed/project/connection/diagnostics pages share one centered header.
- **Conversation polish.** Per-block text selection, copy-all on tool output,
  full reasoning groups, `Answered:` labels, hourglass/star icons, icon-only
  footer actions, 44dp hit targets, spring image zoom, a 280pt tool-card cap,
  and a single-row background-task summary with a gear to expand it.

## Fixed

- Error codes now localize `draft_storage_failed`, `keychain_failed`,
  `socket_denied` / `socket_unavailable` and `capacity`; socket timeouts are
  reported as timeouts instead of a generic connection failure.
- Protocol and certificate failures during a link handshake fail closed rather
  than silently moving the session to the relay.
- The list no longer redials every Mac on a pull: only Macs not currently
  reachable are redialed, and live pending counts are summed per Mac with the
  stored count used only for a Mac that is not answering.
- Remote images are checked for a single JPEG frame before decoding.

## Verification

- 111 JVM tests and 15 Compose instrumentation tests (indicator, footer,
  drawer, large font, PushIn navigation, Markdown table, task summary,
  selected state, composer focus, and three pixel snapshots) on a task-owned
  phone emulator.
- An isolated Bridge paired with the real `cmux-tui` daemon: enrollment,
  approval, connection detail (`cmux-remote/2`), three real sessions, a
  conversation history read, and the focused composer with a visible keyboard.
- `scripts/verify.sh`: 527 Swift tests, phone-state checks, localization and
  release checks pass.
- Android resources: 407 matching keys in `values`, `values-en` and
  `values-zh`.
- The APK is signed by the Android release key.

## Install

Download `CmuxRemote-Android-0.1.8.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
