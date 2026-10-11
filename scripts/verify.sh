#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --jobs 6
swift build --jobs 6
python3 scripts/check-localization.py
git diff --check
