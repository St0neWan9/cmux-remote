# CmuxRemote Android 0.1.15

The conversation page now follows the iPhone more closely: no stray loading
indicator, queued prompts stay in the transcript, and drafts live inside the
composer.

## Conversation

- Opening a conversation no longer shows the pull-to-refresh spinner; only a
  pull the reader makes spins it, while earlier pages load quietly at the top.
- A prompt sent while the Agent is still running appears at the end of the
  conversation, continuing it, instead of being pinned over older messages.
- The running row's indicator is 12pt, matching the text beside it.
- Prepared image thumbnails are drawn inside the composer's rounded field,
  above the text, and scroll sideways when there are several, as on iOS.
- Tool titles keep the Agent's description while output streams, never the raw
  command; the command lives in the opened card.
- The composer stays usable on short and split screens, and the expanded field
  keeps its side margins.

## Connection

- The "this Mac cannot be reached" pill no longer repeats the device name.
- Intermittent read failures no longer add up into a false offline state: a
  successful read clears the count, and three consecutive failures are
  confirmed with a separate signed status probe before the pill appears.

## Devices

- Filter pills for Macs can be long-pressed and dragged into a new order on
  Android and iOS; the order survives relaunch.
- Approving a Mac again keeps its place in the list instead of moving it to the
  end.

## Verification

- 111 JVM tests, 15 Compose tests and `scripts/verify.sh` (527 Swift tests).
- `scripts/build-ios.sh` after the iOS filter-pill change.
- Exercised against a real `cmux-tui` session through an isolated Bridge on a
  task-owned emulator: opening a conversation, the running row, image drafts
  inside the composer and the inline queued prompt.

## Install

Download `CmuxRemote-Android-0.1.15.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
