#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! xcrun --sdk iphonesimulator metal --version >/dev/null 2>&1; then
  xcodebuild -downloadComponent MetalToolchain
fi
python3 scripts/generate-ios-project.py
xcodebuild -project ios/CmuxRemote.xcodeproj -scheme CmuxRemote \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO build
