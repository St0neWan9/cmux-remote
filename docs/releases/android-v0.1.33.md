# TermRemote Android 0.1.33

The app now uses the Term Remote identity.

## Identity

- New application ID `dev.trenta.termremote`. Android treats it as a different app,
  so this version installs beside the old one rather than updating it.
- Pairing links use `term-remote://`, and the connection protocol, signatures and
  relay headers use the Term Remote names. A Bridge must run the Term Remote
  identity too; older Bridges and older phone builds cannot talk to this one.
- Device grants made under the old identity do not carry over. Pair the phone again
  from the Mac's Add Device screen.

## Install

1. Uninstall the old CmuxRemote/TermRemote app.
2. Download `TermRemote-Android-0.1.33.apk` and open it on Android 10 or later.
3. Scan the pairing code shown on the Mac.

Same signing key as earlier releases.

TermRemote is not an official cmux product.
