# CmuxRemote Android 0.1.19

Conversation layout and keyboard behavior now match the iPhone.

## Conversation

- The running row (`运行中 6m 41s`) sits directly above the composer, where the
  iPhone's bottom inset draws it, instead of at the end of the transcript.
- The jump-to-latest circle keeps its 44dp shape on short screens when the
  keyboard is up; a small viewport can no longer squeeze it into an oval.
- Tapping empty conversation space hides the keyboard, clears the field's focus
  and collapses the composer back to its one-line bar. Taps on messages and
  buttons keep their own behavior.

## Conversation list

- Entering the app shows each saved Mac's connecting indicator while its first
  link is dialled, then the green or red dot (included from 0.1.18).

## Verification

- 117 JVM tests, 15 Compose tests and `scripts/verify.sh` (527 Swift tests).
- Task-owned emulator, real `cmux-tui` session through an isolated Bridge:
  the running row renders above the composer; on a 1080x1600 window with the
  composer expanded the jump-to-latest circle stays round; tapping empty space
  clears the `EditText` focus and restores the one-line bar.

## Install

Download `CmuxRemote-Android-0.1.19.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
