# CmuxRemote Android 0.1.3

Pairing works with older Mac builds again, and a rejected or expired code now
says what to do.

## Fixed

- **A Mac running an older Bridge accepts the request again.** Older builds do
  not know the `android` client kind or the `conversationStart` capability and
  reject the whole enrollment. The phone now retries once as the kind and scope
  those builds understand, so the device appears in the Mac's pending list
  (read, control, Feed, project; opening new terminals needs a newer Mac build).
- **A missing pending request explains itself.** `enrollment_closed`,
  `enrollment_expired`, `request_expired` and `invalid_pairing` have their own
  messages instead of the Mac's English sentence. The waiting page now says
  that reopening **Add Device** on the Mac cancels earlier QR requests, so scan
  again immediately and do not refresh that page or restart the Mac app.

Multiple devices are supported: approved Macs and their grants are independent.
The only serialization is the short-lived QR window — opening a new one
cancels still-pending requests from the previous QR window.

The desktop app is unchanged; this release contains the Android APK only.

## Install

Download `CmuxRemote-Android-0.1.3.apk`, open it on Android 10 or later. It uses
the same signing key as earlier releases and installs as an update.

## Verification

The APK is signed by the Android release key (certificate SHA-256
`c6fbc46c9a91a1d5338382afb72489267d041f9a6a13224589c938036aeb5066`).
Compare the download with the attached `.sha256` file.

CmuxRemote is not an official cmux product.
