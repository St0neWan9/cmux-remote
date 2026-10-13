#!/usr/bin/env bash
# Build, Developer ID sign, notarize and package the Mac menu bar app for download.
# Signing material comes from scripts/with-macos-signing.py; nothing secret is printed.
set -euo pipefail
cd "$(dirname "$0")/.."
version="${CMUX_REMOTE_MAC_VERSION:-0.1.0}"
build="${CMUX_REMOTE_MAC_BUILD_NUMBER:-1}"
notarize=0
for arg in "$@"; do
  case "$arg" in
    --version=*) version="${arg#*=}" ;;
    --build-number=*) build="${arg#*=}" ;;
    --notarize) notarize=1 ;;
    -h|--help) echo 'Usage: scripts/package-macos.sh [--version=0.1.0] [--build-number=1] [--notarize]'; exit 0 ;;
    *) echo 'Unknown packaging option' >&2; exit 1 ;;
  esac
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid version' >&2; exit 1; }
[[ "$build" =~ ^[1-9][0-9]{0,8}$ ]] || { echo 'Invalid build number' >&2; exit 1; }
identity="${CMUX_REMOTE_MAC_SIGNING_IDENTITY:?Run through scripts/with-macos-signing.py}"
notary=()
if [[ "$notarize" == 1 ]]; then
  notary=(--key "${CMUX_REMOTE_NOTARY_KEY_PATH:?}" --key-id "${CMUX_REMOTE_NOTARY_KEY_ID:?}" --issuer "${CMUX_REMOTE_NOTARY_ISSUER:?}")
  # Fail before a long build when the notary credentials are wrong or lack access.
  xcrun notarytool history "${notary[@]}" --output-format json >/dev/null || { echo 'Notary credentials rejected' >&2; exit 1; }
fi

out="$PWD/.build/macos-release"
dist="$out/dist"
rm -rf "$out"
mkdir -p "$dist"
echo "Packaging CmuxRemote $version ($build)"

python3 scripts/generate-macos-project.py >/dev/null
swift build -c release --arch arm64 --arch x86_64 --product cmux-remote
helper_source="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/cmux-remote"
xcodebuild -project mac/CmuxRemoteMac.xcodeproj -scheme CmuxRemoteMac -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$out/DerivedData" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  "MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$build" build

app="$out/CmuxRemote.app"
ditto "$out/DerivedData/Build/Products/Release/CmuxRemote.app" "$app"
mkdir -p "$app/Contents/Helpers"
cp "$helper_source" "$app/Contents/Helpers/cmux-remote"
main_binary="$app/Contents/MacOS/CmuxRemote"
helper="$app/Contents/Helpers/cmux-remote"

for binary in "$main_binary" "$helper"; do
  archs="$(lipo -archs "$binary")"
  [[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]] || { echo "$(basename "$binary") is not universal: $archs" >&2; exit 1; }
  minos="$(vtool -show-build "$binary" | awk '/minos/ {print $2; exit}')"
  [[ "$(printf '%s\n14.0\n' "$minos" | sort -V | tail -1)" == "14.0" ]] || { echo "$(basename "$binary") requires macOS $minos" >&2; exit 1; }
done

sign() { codesign --force --options runtime --timestamp --sign "$identity" "$@"; }
# Inside-out: nested code first, the bundle last, so the outer seal covers final bytes.
while IFS= read -r -d '' nested; do sign "$nested"; done < <(find "$app/Contents" \( -name '*.dylib' -o -name '*.framework' \) -print0)
sign "$helper"
sign "$app"

codesign --verify --deep --strict --verbose=2 "$app"
for binary in "$main_binary" "$helper"; do
  details="$(codesign -dvv "$binary" 2>&1)"
  grep -q '^Authority=Developer ID Application:' <<<"$details" || { echo "$(basename "$binary") lacks a Developer ID signature" >&2; exit 1; }
  grep -q '^Timestamp=' <<<"$details" || { echo "$(basename "$binary") lacks a secure timestamp" >&2; exit 1; }
  grep -Eq 'flags=0x[0-9a-f]*\(.*runtime' <<<"$details" || { echo "$(basename "$binary") lacks the hardened runtime" >&2; exit 1; }
  if codesign -d --entitlements - "$binary" 2>/dev/null | grep -q 'get-task-allow'; then
    echo "$(basename "$binary") carries get-task-allow" >&2; exit 1
  fi
done

submit() {
  local result status id
  result="$(xcrun notarytool submit "$1" "${notary[@]}" --wait --timeout 30m --output-format json)" || true
  status="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$result")"
  id="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' <<<"$result")"
  echo "Notarization $id: $status"
  if [[ "$status" != "Accepted" ]]; then
    [[ -n "$id" ]] && xcrun notarytool log "$id" "${notary[@]}" || true
    exit 1
  fi
}

# A ticket can lag behind an Accepted notarization (stapler error 68), so retry briefly.
staple() {
  local attempt
  for attempt in 1 2 3 4 5 6; do
    if xcrun stapler staple "$1"; then xcrun stapler validate "$1"; return; fi
    [[ "$attempt" == 6 ]] && return 1
    sleep $((attempt * 15))
  done
}

if [[ "$notarize" == 1 ]]; then
  ditto -c -k --keepParent "$app" "$out/notarize.zip"
  submit "$out/notarize.zip"
  rm "$out/notarize.zip"
  # Staple before archiving: a zip cannot carry a ticket, but the app inside it can.
  staple "$app"
  spctl --assess --type execute --verbose=2 "$app"
fi

ditto -c -k --keepParent "$app" "$dist/CmuxRemote-$version.zip"

dmg_root="$out/dmg"
mkdir -p "$dmg_root"
ditto "$app" "$dmg_root/CmuxRemote.app"
ln -s /Applications "$dmg_root/Applications"
dmg="$dist/CmuxRemote-$version.dmg"
# hdiutil occasionally reports a busy device on CI runners; retry a bounded number of times.
for attempt in 1 2 3; do
  if hdiutil create -volname "CmuxRemote $version" -srcfolder "$dmg_root" -fs HFS+ -format UDZO -ov "$dmg"; then break; fi
  [[ "$attempt" == 3 ]] && exit 1
  sleep 5
done
codesign --force --timestamp --sign "$identity" "$dmg"
if [[ "$notarize" == 1 ]]; then
  submit "$dmg"
  staple "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
fi

(cd "$dist" && shasum -a 256 "CmuxRemote-$version.dmg" "CmuxRemote-$version.zip" > SHA256SUMS.txt)
cat "$dist/SHA256SUMS.txt"
echo "Artifacts in $dist"
