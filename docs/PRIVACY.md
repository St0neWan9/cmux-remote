# Privacy policy

CmuxRemote is an independent companion app for the official cmux Mac app. It has
no account, no analytics, and no server of its own.

## What CmuxRemote collects

Nothing is sent to the developer, and there is no third-party SDK — no
analytics, advertising, crash reporting or attribution.

## What stays on your devices

- **Pairing material** — a device key and the Mac's certificate fingerprint are
  stored in the iOS Keychain, and the Mac keeps the matching records in its own
  state directory. They never leave the two devices.
- **Conversation cache** — recent conversation text and images are cached in the
  app's own container so a conversation opens quickly. Removing the app removes
  the cache.
- **Settings** — display name, sharing settings and preferences are stored
  locally.

## What travels over the network

- On the local network, the iPhone talks to the Mac directly over an encrypted
  WebSocket that the pair established.
- If you enable a cloud relay, the phone and the Mac use a Cloudflare Worker
  **that you deploy to your own Cloudflare account** with your own registration
  key. Conversation traffic passes through that Worker, which you control; the
  developer of CmuxRemote has no access to it and operates no relay of its own.
- Images and files are transferred only when you open or send them.

## What CmuxRemote does not do

- It does not contact any AI provider. The Mac's agent talks to its provider on
  your behalf, exactly as it does in the terminal.
- It does not upload your conversations, projects or files anywhere else.
- It does not include advertising, tracking or profiling.

## Children

CmuxRemote is a developer tool and is not directed at children.

## Your control

Stop sharing on the Mac, revoke a device under **Devices**, or delete the app to
remove its local data. Revoking a device takes effect immediately: its key can
no longer connect.

## Changes

Material changes to this policy are published in this file and in the app's
release notes.

## Contact

Questions or requests: open an issue at
<https://github.com/St0neWan9/cmux-remote/issues>.
