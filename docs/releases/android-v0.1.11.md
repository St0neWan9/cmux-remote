# CmuxRemote Android 0.1.11

Two layout fixes on wide screens and in the conversation header.

## Wide screens

- The persistent sidebar keeps the phone's top-left control. Collapsing it now
  shows the conversation page full width with its normal back button, and that
  back button expands the sidebar instead of closing the conversation. The thin
  rail is gone.
- Collapsing is available only while a conversation is open, so the page can
  never be left with nothing to select.

## Conversation

- The chevron after `Agent · model · Mac` follows the text instead of sitting at
  the far right edge of the header.

## Verification

- 111 JVM tests, 15 Compose tests and `scripts/verify.sh` (527 Swift tests).
- 410 matching Android strings per locale.
- Checked on a simulated 1800×2400 wide screen: expand, collapse to the
  full-width conversation with its back button, and expand again; also checked
  the chevron position on the phone layout.

## Install

Download `CmuxRemote-Android-0.1.11.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
