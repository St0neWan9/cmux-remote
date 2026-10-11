# cmux-remote

An independent Mac companion and native iPhone app for the official cmux application. Pair over your local network, read existing Claude/Codex conversations, see a live text preview, send prompts, stop work, answer supported Feed approvals, and inspect project changes and files. No cmux cloud account is involved.

The phone receives structured chat data. It does not render a terminal. cmux continues owning the agents and terminals; this project does not connect to Claude or Codex APIs.

## Build and run

Requires macOS 14+ and Swift 6. The iPhone app requires iOS 17+.

```sh
swift build
.build/debug/cmux-remote init
.build/debug/cmux-remote serve
```

`init` creates a private state directory, a random bearer credential and a self-signed TLS certificate. `serve` defaults to loopback. For your phone, use `serve --listen 0.0.0.0`, then run `pairing --host <your-Mac-LAN-IP>` locally and enter its pairing information in the app. Treat the pairing output as a password. The app pins the exact TLS certificate fingerprint before sending authenticated requests.

The socket path can be overridden with `--socket <path>` or `CMUX_SOCKET_PATH`. The Bridge does not change cmux access settings. If its process is denied, enable an appropriate cmux automation/password policy explicitly. Pass a socket password through `CMUX_REMOTE_SOCKET_PASSWORD`; this is separate from the phone bearer credential.

Generate and build the phone project:

```sh
python3 scripts/generate-ios-project.py
scripts/build-ios.sh
open ios/CmuxRemote.xcodeproj
```

Choose your own signing team to install on a physical iPhone. There is no dependency on cmux's iOS app or signing identity.

## Design and verification

- [Detailed design](docs/DESIGN.md)
- [API and source mapping](docs/API.md)
- [Development and validation](docs/DEVELOPMENT.md)

Run `scripts/verify.sh` for package tests and build. The first implementation is a development baseline, not a promise of complete provider-version compatibility. Live screen extraction is a best-effort preview; transcript messages replace it when committed. Historical sessions without a verified live surface are read-only. Codex Feed actions only work when cmux exposes an actionable request.

## License

GPL-3.0-or-later. The pinned cmux parsing package retains its upstream copyright and license. SwiftNIO and SwiftNIO SSL retain their own licenses. This project is independent and is not an official cmux product.
