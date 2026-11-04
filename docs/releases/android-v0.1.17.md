# CmuxRemote Android 0.1.17

The connection now stays up in the background instead of being torn down every
time the app leaves the screen.

## Background connection

- A foreground service (`specialUse`, stopped with the task) keeps the process
  and the already-authenticated links alive while the app is away. Live session
  updates and the bounded slow poll keep running, so replies and pending
  requests keep arriving.
- No second connection is created: background and foreground share the same
  `LiveUpdates` sockets. Returning to the app reuses them and only refreshes the
  data, so the page no longer redials every Mac and no longer shows "正在重新连接"
  on every return.
- A network change in the background (Wi-Fi to cellular or back) redials at
  once, as it does in the foreground.
- The 15-minute WorkManager pass remains as a fallback if the process is
  reclaimed by the system.

## Permissions and settings

- Android 13 and later asks for the notification permission; the foreground
  service shows an ongoing, silent notification.
- **连接 → 后台保持连接** (on by default) controls the foreground service. When
  it is on, a **去允许** action opens the system battery-optimization exemption
  prompt; aggressive battery managers can otherwise stop the connection.
- Turning the setting off restores the previous behavior: links pause while the
  app is away and are redialled on return.

## Verification

- 117 JVM tests, 15 Compose tests and `scripts/verify.sh` (527 Swift tests).
- Task-owned emulator with a real `cmux-tui` session behind an isolated Bridge:
  pressing Home starts the foreground service with its ongoing notification,
  returning stops it and removes the notification, and the links are not
  rebuilt. The battery exemption was granted through the new action and
  verified in the system's allowlist.

## Install

Download `CmuxRemote-Android-0.1.17.apk`, open it on Android 10 or later. Same
signing key; installs as an update.

CmuxRemote is not an official cmux product.
