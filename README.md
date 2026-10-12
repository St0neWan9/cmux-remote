# cmux-remote

An independent Mac companion and native iPhone app for the official cmux application. Pair over your local network, read existing Claude/Codex conversations, see a live text preview, send prompts, stop work, answer supported Feed approvals, and inspect project changes and files. No cmux cloud account is involved.

The phone receives structured chat data. It does not render a terminal. cmux continues owning the agents and terminals; this project does not connect to Claude or Codex APIs.

## Build and run

Requires macOS 14+ and Swift 6. The iPhone app requires iOS 17+.

```sh
swift build
.build/debug/cmux-remote serve --pair
```

`serve --pair` opens a short-lived enrollment window and displays a QR code. Scan it in the iPhone app, then approve that exact device on the Mac. The QR supplies host identity and certificate trust; it no longer contains a permanent shared token. The phone saves its own private identity and signed grant. Bonjour finds nearby Bridges, while QR and manual entry remain available when discovery is unavailable.

```sh
.build/debug/cmux-remote enrollment pending
.build/debug/cmux-remote enrollment approve REQUEST_ID --workspace WORKSPACE_UUID --control
.build/debug/cmux-remote clients list
.build/debug/cmux-remote clients revoke CLIENT_ID
```

Each device has separately revocable access to explicitly approved workspaces. Omit `--control` for viewing-only access. The new protocol is documented in [Connection v2](docs/CONNECTION-V2.md), including bootstrap verification, owner commands, per-request signatures, endpoint relocation and legacy migration. `serve --legacy` is an explicit migration mode; ordinary v2 enrollment never promotes an old shared token.

Open official cmux and run the Bridge **inside a cmux terminal**. The default `cmuxOnly` socket mode rejects processes started outside cmux, including the bundled CLI. `--socket`, `CMUX_SOCKET_PATH` and `--cli` can select the installed socket/CLI; they do not bypass its access policy. The Bridge never changes socket settings. Agent input uses the existing official cmux session, and no provider connection is created by this app.

Generate and build the phone project:

```sh
python3 scripts/generate-ios-project.py
scripts/build-ios.sh
open ios/CmuxRemote.xcodeproj
```

The project defaults to the owner's Apple team; choose your own signing team for
a fork or physical iPhone installation. There is no dependency on cmux's iOS app
or signing identity. [TestFlight packaging](docs/TESTFLIGHT.md) covers the signed
IPA and manual GitHub Actions upload workflow.

## Design and verification

- [Detailed design](docs/DESIGN.md)
- [API and source mapping](docs/API.md)
- [Development and validation](docs/DEVELOPMENT.md)
- [Native Remote groups and terminal mirrors](docs/MAC-EXTENSION.md)
- [Planned shared discovery, enrollment, and Mac mirroring](docs/UNIFIED-CONNECTION-PLAN.md)

LAN discovery and per-client authorization are shared by the iPhone client and
the Mac Companion. A public sidebar extension and snapshot-based terminal mirror
are available as a development implementation; see the Mac guide for build,
enrollment and capability requirements. Native/lossless mirror parity and a
physical two-Mac acceptance run are not established by the package tests.

Run `scripts/verify.sh` for package tests and build. The first implementation is a development baseline, not a promise of complete provider-version compatibility. Live screen extraction is a best-effort preview; transcript messages replace it when committed. Historical sessions without a verified live surface are read-only. Codex Feed actions only work when cmux exposes an actionable request.

## License

GPL-3.0-or-later. The pinned cmux parsing package retains its upstream copyright and license. SwiftNIO and SwiftNIO SSL retain their own licenses. This project is independent and is not an official cmux product.
