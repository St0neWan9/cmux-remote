# Development

Run `scripts/verify.sh` before publishing. Tests use temporary files, synthetic transcripts and fake cmux responders; they do not type into a user's terminal. `scripts/build-ios.sh` generates an Xcode project and compiles the iPhone app for an isolated generic Simulator destination without signing. A build proves compilation, not touch behavior or physical-phone connectivity.

The Mac CLI is built with SwiftPM and requires no paid developer account for local use. Public binary releases need a separate Developer ID signing/notarization workflow. Signing requirements do not depend on Swift versus Go/Rust. The iPhone target uses its own bundle ID and signing team; do not reuse cmux's production identity.

Supported first backend: official cmux on macOS, via its owner-controlled local Unix socket. Discover the socket from explicit CLI/env configuration, the current marker, then documented legacy locations. Actual method invocation, not capability advertisement alone, determines support.

Use English and Simplified Chinese localization in `ios/Resources`. Keep technical machine error codes stable and map them in the UI. Keep local development credentials in a state directory outside the repository.

To refresh the vendored parsing library, copy only public upstream source, record its exact commit, preserve notices, inspect the diff and run all parser/history tests. Never copy personal transcript data into test fixtures. CI builds Swift package tests and the iPhone Simulator target on macOS.
