# cmux-remote contributor instructions

This is an independent companion. Never modify, replace, restart, or re-sign an installed cmux app. Never connect to a provider API or start a separate agent runtime to implement chat.

Read `docs/DESIGN.md` before changing protocol, authority, or data ownership. Maintain Swift 6 concurrency checks, constructor injection, bounded requests and streams, explicit cancellation, and one major type per file. Keep credentials out of logs, fixtures and Git. New errors must expose stable codes; UI localizes those codes.

Before committing, run `scripts/verify.sh`. Compile the iPhone app with `scripts/build-ios.sh` after UI/client changes. Only use a task-owned Simulator for UI work. Do not change a user's cmux socket mode automatically.

Tests must exercise behavior: stale bindings, outcome-unknown writes, transcript partial lines and replacement, certificate pin mismatch, path traversal and replay gaps. Upstream vendored sources retain their original notices; update `Vendor/CmuxAgentChat/UPSTREAM.md` when refreshing them.
