# CmuxRemote Android 0.1.10

Refinements to the 0.1.9 list and conversation layout.

## Conversation

- The tool card's result line now reads left to right: exit code on the left,
  completion time or the running state at the trailing edge.
- Tool titles keep their spacing with each other, while the gap against the
  surrounding content is slightly larger.
- The duration label `Worked for / 运行 3m 47s` and its divider sit at the top
  of the reply item; the footer time follows the action icons.
- Tool rows show the agent's description; the command stays inside the card.
- Operation groups follow the iPhone's policy: up to five expand in place, a
  longer one opens its own page from the summary, and the newest ten are drawn
  while it runs. No inner scroller and no "view all" button.
- A reply ending with an earlier message the timeline no longer holds shows
  "this conversation is long" at the top, where the missing part would be.
- The composer is shorter at rest: a single line, 30pt corners, 38pt actions and
  34pt send/stop circles; focus expands it to the full-width two-row layout.
- The jump-to-latest button is centred at the bottom, and tapping it resumes
  following so later output keeps the page at the newest message.
- The header subtitle stops at `Agent · model · Mac`; no running/resumable/
  read-only word follows.

## Wide screens

- The persistent sidebar has the same top-left collapse control as the phone.
  A thin handle on the left reopens it.

## Fixed

- Chinese operation counts read `2 项操作` rather than `2 个操作`.
- A single failed read no longer flips connection status; only a Mac that stays
  down is shown as unreachable, and background refreshes no longer turn every
  Mac's tab.

## Verification

- 111 JVM tests, 15 Compose tests and `scripts/verify.sh` (527 Swift tests).
- 410 matching Android strings per locale.
- Checked against a real `cmux-tui` daemon through an isolated Bridge: tool card
  footer alignment, operation counts, header subtitle, composer height, centred
  latest button and focus behaviour.

## Install

Download `CmuxRemote-Android-0.1.10.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
