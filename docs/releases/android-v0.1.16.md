# CmuxRemote Android 0.1.16

The conversation list keeps its Mac status current again, and a sent prompt no
longer stays at the end once the transcript records it.

## Conversation

- A prompt sent while the Agent is running disappears from the end of the
  conversation as soon as the Mac records it, instead of appearing twice. The
  matching now follows the iPhone's `OutgoingPromptMatcher`: whitespace is
  collapsed, the prompt is compared against messages recorded after the send,
  and an Agent-rewritten prompt (image placeholders, a paste summary) still
  counts when a new user message arrives in the same history.
- The composer stays above the keyboard on short screens and split windows.
  The activity now declares `adjustResize`, so the system no longer pans the
  whole page up on top of the IME inset.

## Conversation list

- Entering the list reads once quietly, as the iPhone's `.task` does, so the
  Mac status dots are filled without a spinner or a visible refresh.
- A Mac that was reachable and then goes away now turns red after three
  consecutive failed reads instead of keeping its last green dot forever.
- The red "unreachable" sentences under the list, next to a single Mac and in
  workspace headings are gone; the pill's red dot carries that state alone.

## Verification

- 117 JVM tests (6 new for the outgoing-prompt matcher), 15 Compose tests and
  `scripts/verify.sh` (527 Swift tests).
- On a task-owned emulator with two real Macs behind isolated Bridges: both
  status dots turn green after entering the list, stopping one Bridge turns its
  pill red after three refreshes with no red text, and restarting it clears the
  dot back to green.

## Install

Download `CmuxRemote-Android-0.1.16.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
