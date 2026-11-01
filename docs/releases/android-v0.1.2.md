# CmuxRemote Android 0.1.2

Adding a Mac now looks like the iPhone's page, includes a relay address, and
the scanner is easier to aim and use at a distance.

## Added

- **Relay address and directory.** Add an `https://…` relay under **Relay** and
  the page lists the Macs that relay currently publishes. Every entry is
  verified against its host signature and enrollment window exactly like a
  scanned code; a forged entry only drops itself. Pairing with a listed Mac
  still needs the Mac owner's approval, and enrollment falls back to the
  encrypted link when the Mac has no reachable LAN address.
- **Pairing layout follows iOS.** The page is now Scan, Nearby Macs, Relay,
  Advanced, in that order. The large pairing-code field is gone; a link or the
  signed enrollment JSON the Mac exports is pasted under **Advanced**.
- **The app icon matches iOS.**

## Scanner

- Tap the preview to focus, with a short square marker where the tap landed;
  the camera also focuses the middle of the frame when it opens.
- The frame is a guide, not a requirement: any complete code in view is
  decoded, so it does not have to line up with the corners.
- Zoom controls (`− 1.0× +`) enlarge a distant code, and decoding now runs on a
  1920×1080 stream with a lower fallback.
- A torch toggle appears on devices with a flash.

The desktop app is unchanged; this release contains the Android APK only.

## Install

Download `CmuxRemote-Android-0.1.2.apk`, open it on Android 10 or later, and
allow the camera when asked. It uses the same signing key as 0.1.0 and 0.1.1,
so it installs as an update and keeps existing pairings, conversations and
relay addresses.

## Verification

The APK is signed by the Android release key (certificate SHA-256
`c6fbc46c9a91a1d5338382afb72489267d041f9a6a13224589c938036aeb5066`).
Compare the download with the attached `.sha256` file.

CmuxRemote is not an official cmux product.
