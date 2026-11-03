#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# CI runners run every HTTPS/WebSocket suite at once and their local handshake occasionally misses the
# dial deadline; serializing there keeps the run deterministic. A developer's machine stays parallel.
if [ "${CI:-}" = "true" ]; then swift test --jobs 6 --no-parallel
else swift test --jobs 6; fi
swift build --jobs 6
python3 scripts/check-phone-state.py
python3 scripts/check-localization.py
python3 scripts/check-macos-localization.py
python3 scripts/check-ios-release.py
scripts/check-signing-material.sh
git diff --check
