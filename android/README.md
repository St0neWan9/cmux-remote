# Cmux Remote for Android

Android client for the same Mac Bridge the iPhone app uses. It pairs as its own
device (Ed25519 identity, owner approval, per-device revocation) and speaks the
signed v2 HTTPS API.

This is a first slice: pairing, conversation list, history, send, stop and Feed
replies work. It has been exercised against the isolated fixture, **not** an
installed cmux.

## What is implemented

- **Adaptive shell** — shared `PaneLayoutPolicy`, the same breakpoints as iOS:
  - shortest side `< 600dp` → single column (ordinary phones in both
    orientations, outer displays, narrow split windows);
  - `600–719dp` → two panes, browser 240–280dp;
  - `720dp+` → two panes, browser 320–400dp;
  - `>= 1100dp` with detail `>= 480dp` → optional supporting pane;
  - vertical hinge snaps the divider; horizontal half-open becomes tabletop.
- **Pairing** — scan or paste the Mac's expiring `cmux-remote://enroll` code
  (or the signed enrollment JSON the Mac's "import" action copies); the app
  requests access and waits for the owner to approve that exact request.
  An explicitly chosen legacy `/v1` shared-token Mac can also be added from
  Advanced settings or its `cmux-remote://pair?v=1` code; it carries shared
  authority and requires `--legacy` on the Mac.
- **Nearby Macs** — NSD browses `_cmux-remote._tcp` while a pairing page is
  open, verifies each advertised identity against the signed bootstrap, and
  asks before trusting a found Mac. An already-paired Mac is marked, not offered.
- **Transport** — HTTPS only, pinned to the paired leaf certificate (DER
  SHA-256), redirects refused, every request signed with `CmuxV2`.
- **Freshness** — an encrypted `/v3/link` subscription (BouncyCastle's RFC 9180
  HPKE, interoperable with CryptoKit) delivers change notifications; a bounded
  foreground poll (15 s in a conversation, 30 s on the list) is the fallback.
  Both are cancelled with the page, and neither ever resubmits a write.
- **Relay** — when the LAN cannot be reached, the link dials the host's
  Cloudflare relay and every resource read travels over it in acknowledged
  64 KiB chunks. Verified end to end against a real Bridge and relay.
- **Conversations** — list, history, replaceable preview, send, stop.
- **Feed** — pending permissions and questions, answered with fixed choices.
- **Images** — pick up to four, re-encoded to bounded JPEGs; recorded previews
  open with pinch/double-tap zoom.
- **Project** — changed files, diffs and file contents, read-only.
- **Layout** — the iPhone's own arrangement on a phone: a left drawer with the
  workspace tree, search that takes the header, sort by workspace or time,
  workspace and status filters, collapsible groups and pull to refresh.
- **Several Macs** — every approved Mac is kept and merged into one list with
  per-Mac tabs; each can be removed on its own.
- **Rendering** — Markdown (headings, lists, code, tables, inline styles, links),
  activity groups with expandable tool cards, the full tool record page, an
  answerable question card, the reply footer (copy/share/quote/select) and a
  select-text page.
- **Session actions** — model menu from the Mac's own configuration, rename,
  reopen an ended session, detached-task records.
- **New conversations** — approved workspace, folder from the Bridge, agent and
  optional first message; opening the terminal is the Bridge's fixed command.
- **Dictation** — on-device SpeechRecognizer only; no network recognizer, 60 s and
  8 KiB bounds, and the transcript never leaves the phone.
- **Pairing by camera** — CameraX + bundled ML Kit scanning of the QR code.
- **Connection and diagnostics** — identity, certificate, capabilities, transport,
  key backing, reachability probe, background-sync switch, remove this Mac, and a
  500-entry redacted diagnostic log fed by real requests, enrollment and link
  events (ids in routes become `:id`).
- **Timing and model** — the live run timer, each finished reply's duration and
  completion time, the conversation-time page, and the model the transcript
  last reported; a model switch the agent asks to confirm is confirmed first.
- **Recovery and actions** — force stop with confirmation, an unknown-send
  banner that checks the receipt instead of resending, an outgoing bubble with
  its delivery state, and the reply/quote/select-text footer.
- **Long press and references** — user bubbles offer copy/select; agent text
  uses the platform selection menu; tool cards show input, output, exit code,
  duration and referenced files, and open one on the project page.
- **Localization** — English and Simplified Chinese resources.
- **Storage** — the grant is verified before use; the identity key is wrapped by
  a non-exportable Android Keystore key, and a plaintext key left by an older
  build is adopted into it rather than replaced. The session list and pending
  count from the last background pass are shown on launch until a live read
  replaces them; a failed read keeps the previous list.
- **Local conversations** — every page read is kept in SQLite (`conversations.sqlite`)
  keyed by host and session, bounded to 24 conversations, 60,000 messages and
  128 MiB per conversation (512 MiB for the file). Opening a conversation shows
  the stored copy at once, then either confirms it or replaces it when the
  Bridge reports a new generation; scrolling back reads stored pages before the
  network, and an open conversation fills its copy backwards (up to 64 pages).
  Removing a Mac removes its stored conversations.
- **Stored task records** — the last page of each background task opened is kept
  in a bounded file cache (16 tasks, 4 MiB each); reopening the sheet shows it at
  once, then the read confirms or replaces it. Removing a Mac removes its tasks.
- **Background sync** — WorkManager's periodic read warms that snapshot for every
  paired Mac (best effort; the system decides when it runs).

## Not implemented yet

- Revocation notices in the UI.
- Physical foldable testing; real `FoldingFeature` posture tests on hardware.
- Deep links, notifications, TTS and haptics are intentionally out of scope.

## Build and test

```sh
cd android
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
  ./gradlew testDebugUnitTest assembleDebug
```

The APK is `app/build/outputs/apk/debug/app-debug.apk`. It uses Gradle 8.9,
AGP 8.7.3, Kotlin 2.0.21, Compose BOM 2024.12.01, minSdk 29, targetSdk 35.

`local.properties` points at the local Android SDK and is ignored by Git.

### Against the isolated Bridge

The fixture runs the real `ConnectionAuthority`, `SessionService` and
`HTTPServer` with an in-memory cmux stand-in. It never reads or changes an
installed cmux and starts no Agent.

```sh
# 1. Build the fixture (from the repository root)
swift build --product CmuxRemoteBridge
python3 scripts/build-enrollment-fixture.py

# 2. Run it; it prints one enroll= line
.build/enrollment-fixture /tmp/cmux-android-fixture 7799 --auto-approve 0

# 3. Run the protocol tests with that code
cd android
CMUX_FIXTURE_ENROLL='cmux-remote://enroll?v=2&payload=…' \
  ./gradlew testDebugUnitTest
```

`BridgeIntegrationTest` covers enrollment → approval → sessions → history →
send → stop → Feed reply, and that two different keys are two different
devices. Without `CMUX_FIXTURE_ENROLL` those three tests skip.

### On a device or emulator

```sh
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Paste the code into the field. Debug builds also accept
`am start … --es enroll_file /data/local/tmp/enroll.txt`, because the `&` in a
code does not survive `adb shell` quoting.

## Emulators

Create task-owned AVDs (do not reuse a user's):

```sh
echo no | avdmanager create avd -n cmux-remote-phone \
  -k "system-images;android-35;google_apis;arm64-v8a" -d pixel_7 --force
echo no | avdmanager create avd -n cmux-remote-fold \
  -k "system-images;android-35;google_apis;arm64-v8a" -d "7.6in Foldable" --force
```

Run them with a window:

```sh
emulator -avd cmux-remote-phone -port 5556 -no-audio -no-boot-anim -gpu host -no-snapshot
emulator -avd cmux-remote-fold  -port 5558 -no-audio -no-boot-anim -gpu host -no-snapshot
```

The 7.6-inch fold AVD exposes a 1768×2208 @420dpi inner display (~673dp) and
enters two-pane. `wm size 884x2208` simulates an outer/compact width, and
`wm size 2399x1079` an ordinary phone in landscape; reset with `wm size reset`.
