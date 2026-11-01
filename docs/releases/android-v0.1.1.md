# CmuxRemote Android 0.1.1

Scanning a pairing code works without guessing where the camera is pointing.

## Fixed

- **A frame to aim at.** The scanner dims everything outside a square frame
  with corner brackets, so it is clear which part of the preview is read.
- **Tap to focus, and focus on open.** Tapping the preview focuses and meters
  at that point and leaves a short square marker where it landed; the middle
  of the frame is focused once when the camera opens. Close-up codes that used
  to stay blurry can now be read.
- **A sharper analysis stream.** Decoding now runs on a 1280×720 stream
  instead of the camera's low default, which small or distant codes need.
- **A light when it is dark.** Devices with a flash get a torch toggle under
  the frame.
- **A clear failure.** A device with no usable camera says so instead of
  showing a black preview, and the preview stays under the frame on every
  device (TextureView).

The desktop app is unchanged; this release contains the Android APK only.

## Install

Download `CmuxRemote-Android-0.1.1.apk`, open it on Android 10 or later, and
allow the camera when asked. Existing pairings and local conversations are
kept; this build uses the same signing key as 0.1.0.

## Verification

The APK is signed by the Android release key (certificate SHA-256
`c6fbc46c9a91a1d5338382afb72489267d041f9a6a13224589c938036aeb5066`).
Compare the download with the attached `.sha256` file.

CmuxRemote is not an official cmux product.
