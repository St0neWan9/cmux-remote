#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate-macos-project.py
swift build --jobs 6 --product term-remote
# Keep the old command name pointing at the renamed binary for local scripts.
ln -sf term-remote .build/debug/cmux-remote
# Remove only this task's generated app product so old PlugIns embedding cannot
# survive a transition to ExtensionKit's Extensions directory.
rm -rf "$PWD/.build/macos/Build/Products/Debug/TermRemoteMac.app" "$PWD/.build/macos/Build/Products/Debug/Cmux Remote.app" "$PWD/.build/macos/Build/Products/Debug/TermRemote.app" "$PWD/.build/macos/Build/Products/Debug/TermRemote.app"
xcodebuild -project mac/TermRemoteMac.xcodeproj -scheme TermRemoteMac \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/macos \
  CODE_SIGN_IDENTITY="${CMUX_REMOTE_MAC_SIGNING_IDENTITY:--}" CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES ONLY_ACTIVE_ARCH=YES build
app="$PWD/.build/macos/Build/Products/Debug/TermRemote.app"
mkdir -p "$app/Contents/Helpers"
cp .build/debug/term-remote "$app/Contents/Helpers/term-remote"
codesign --force --sign "${CMUX_REMOTE_MAC_SIGNING_IDENTITY:--}" "$app/Contents/Helpers/term-remote"
codesign --force --sign "${CMUX_REMOTE_MAC_SIGNING_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
