# TermRemote Android 0.1.36

More reliable connections, faster live message updates, reliable scroll-to-bottom on open, and iOS-matched bottom bar alignment.

## Connection Stability & Live Refresh

- Serialized HPKE AEAD packet sealing and sending on the encrypted link so concurrent ACKs and requests no longer break cipher ordering and drop connections mid-session.
- Fixed relay live-update supervision so dropped relay links reconnect automatically, re-subscribe to watched paths, and reattach cleanly without hanging pending requests.
- Subscribed to live `/preview` updates, switched open-conversation refreshes to immediate single-flight scheduling without cancelling in-flight reads, and parallelized transcript, preview, and feed reads to match iOS refresh speed.

## Conversation UI & Background Tasks

- Fixed opening a conversation not landing at the true bottom (and showing the scroll-to-bottom button) when bottom chrome or late-measuring rows resize the viewport.
- Aligned the background tasks bar, queued prompts bar, running status line, and resting/expanded composer widths left and right to match iOS.
- Pairs with the updated Mac Bridge to display Antigravity background tasks and their logs.

## Install

Download `TermRemote-Android-0.1.36.apk`, open it on Android 10 or later. Same signing key as `0.1.35`; installs as an update.

TermRemote is not an official cmux product.
