# cmux-remote

An independent Mac companion and native iPhone app for the official cmux application. Pair over your local network, read existing Claude/Codex conversations, see a live text preview, send prompts, stop work, answer supported Feed approvals, and inspect project changes and files. No cmux cloud account is involved.

The phone receives structured chat data. It does not render a terminal. cmux continues owning the agents and terminals; this project does not connect to Claude or Codex APIs.

## Build and run

Requires macOS 14+ and Swift 6. The iPhone app requires iOS 17+.

```sh
swift build
.build/debug/cmux-remote serve --pair
```

`init` creates a private state directory, a random bearer credential and a self-signed TLS certificate. `serve` defaults to loopback. For your phone, use `serve --listen 0.0.0.0`, then run `pairing` in a second terminal. It automatically chooses an active private LAN address and displays a QR code. Tap **Scan pairing QR code** in the iPhone app; no host, token or fingerprint needs to be typed. Use `pairing --host <your-Mac-LAN-IP>` to override ambiguous network routing. Advanced settings and JSON import remain available; `pairing --format json` explicitly emits the old JSON format. Treat the QR as a password. The app pins the exact TLS certificate fingerprint before sending authenticated requests.

The recommended `serve --pair` command performs first-time initialization, listens on the LAN, and displays the QR after the listener is ready. Ordinary `serve` remains loopback-only and never prints a credential. The QR option explicitly opts into displaying the device credential; do not redirect that output to public logs.

Open official cmux and run the Bridge command **inside a cmux terminal**. With the default `cmuxOnly` socket mode, processes launched outside cmux are denied, including the bundled CLI; using that CLI does not bypass the ancestry check. The socket path can be overridden with `--socket <path>` or `CMUX_SOCKET_PATH`. The Bridge prefers the bundled official CLI's `rpc` path, keeping cmux's CLI authentication/capability policy intact and prompt data in private stdin rather than argv. Use `--cli <path>` for another official installation. The separate event connection can fall back to snapshot discovery if cmux denies it. `--direct-socket` opts into raw socket transport; configure an appropriate automation/password policy explicitly if needed. The Bridge never changes access settings. `CMUX_REMOTE_SOCKET_PASSWORD` is the direct socket password, separate from the phone pairing credential.

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
