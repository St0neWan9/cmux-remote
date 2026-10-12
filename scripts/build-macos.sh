#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate-macos-project.py
swift build --jobs 6 --product cmux-remote
# Remove only this task's generated app product so old PlugIns embedding cannot
# survive a transition to ExtensionKit's Extensions directory.
rm -rf "$PWD/.build/macos/Build/Products/Debug/CmuxRemoteMac.app" "$PWD/.build/macos/Build/Products/Debug/Cmux Remote.app" "$PWD/.build/macos/Build/Products/Debug/CmuxRemote.app"
xcodebuild -project mac/CmuxRemoteMac.xcodeproj -scheme CmuxRemoteMac \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/macos \
  CODE_SIGN_IDENTITY="${CMUX_REMOTE_MAC_SIGNING_IDENTITY:--}" CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES ONLY_ACTIVE_ARCH=YES build
app="$PWD/.build/macos/Build/Products/Debug/CmuxRemote.app"
mkdir -p "$app/Contents/Helpers"
cp .build/debug/cmux-remote "$app/Contents/Helpers/cmux-remote"
codesign --force --sign "${CMUX_REMOTE_MAC_SIGNING_IDENTITY:--}" "$app/Contents/Helpers/cmux-remote"
codesign --force --sign "${CMUX_REMOTE_MAC_SIGNING_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
