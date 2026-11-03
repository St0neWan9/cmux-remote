# CmuxRemote Android 0.1.9

Follow-up to 0.1.8 with the list and conversation details aligned to the iPhone.

## Session list

- The title sits in the middle of the header; the bottom device/refresh bar and
  the standalone "all workspaces" capsule are gone.
- Workspace filtering is under each Mac's own capsule: select the Mac, then open
  its workspaces from the same pill. The all-Macs pill now reads "All".
- A background refresh no longer turns every Mac's status: only a Mac that is
  actually being dialed shows the spinner, and the pull-to-refresh indicator
  appears only for a manual pull. The first load keeps its centered overlay.
- A single failed read no longer flips a Mac to unreachable; the red dot only
  follows a Mac that stays down, so the list stops flickering between states.
- Session rows show only the conversation facts; the per-Mac error stays with
  that Mac.

## Conversation

- A finished reply begins with "Worked for / 运行 3m 47s" and the divider, where
  the live timer was while it ran; it is no longer shown at the bottom.
- The reply time in the footer follows the action icons instead of being
  right-aligned.
- Operation rows show the agent's own description of the tool call; the
  command or input stays inside the expanded card.
- Long operation groups open on their own page from the summary row, as on the
  iPhone: no inner scroller and no "view all" button below. A group up to five
  operations expands in place; a longer one draws its newest ten while running.
- The model is switched from the subtitle under the title, as on the iPhone;
  the separate model pill on the right is gone.
- The two-part composer keeps the same field node when it expands, so tapping
  the input focuses it and opens the keyboard.
- Loading is limited to a first read with no content (centred overlay) or an
  explicit pull; project and conversation pages keep their content while a
  background refresh runs.

## Fixed since the first 0.1.8 build

- The signed status probe now signs `/v2/status` (the Bridge maps it to its v1
  status route), so enrollment no longer fails after approval.
- Single-Mac session lists read every host bucket again.
- The focused composer keeps focus across its layout change.

## Verification

- 111 JVM tests, 15 Compose tests and `scripts/verify.sh` (527 Swift tests).
- 407 matching Android strings per locale.
- Isolated Bridge against the real `cmux-tui` daemon: enrollment, approval,
  connection detail, three real sessions, conversation history, tool
  descriptions, duration placement and composer focus.
- Signed with the same Android release key.

## Install

Download `CmuxRemote-Android-0.1.9.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
