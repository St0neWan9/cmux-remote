#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --jobs 6
swift build --jobs 6
python3 scripts/check-phone-state.py
python3 scripts/check-localization.py
python3 scripts/check-macos-localization.py
python3 scripts/check-ios-release.py
git diff --check
