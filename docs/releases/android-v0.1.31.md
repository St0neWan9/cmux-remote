# TermRemote Android 0.1.31

This release introduces **term remote**: the app now works with more than cmux.

## term remote

- The app is now provider-neutral. A Mac can expose cmux workspaces and Rex
  sessions at the same time; both appear as spaces, with their source named.
- Rex sessions are supported through the Rex server socket. Pairing and
  approval lists include Rex spaces, labelled with their source.
- Spaces whose terminals are all closed, or whose terminals no client holds,
  are no longer offered for pairing.

## Terminals

- A Rex terminal opens as a live text screen and refreshes once per second.
- Text input, Send, Esc, Ctrl-C and Tab are explicit, retry-safe operations.
- Shell-only Rex blocks are hidden from the conversation list for now; agent
  conversations remain.

## Install

Download `CmuxRemote-Android-0.1.31.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

TermRemote is not an official cmux product.
