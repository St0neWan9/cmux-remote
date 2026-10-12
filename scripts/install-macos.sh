#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_app="$PWD/.build/macos/Build/Products/Debug/CmuxRemoteMac.app"
destination="${CMUX_REMOTE_MAC_DESTINATION:-$HOME/Applications/CmuxRemoteMac.app}"
expected="com.st0newan9.cmux-remote.mac"
test -d "$source_app" || { echo "Run scripts/build-macos.sh first." >&2; exit 1; }
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")" = "$expected"
if [[ -e "$destination" ]]; then
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")" = "$expected" || {
    echo "Refusing to overwrite an unrelated application." >&2; exit 1;
  }
fi
mkdir -p "$(dirname "$destination")"
staging_dir="$(mktemp -d "$(dirname "$destination")/cmux-remote-install.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
ditto "$source_app" "$staging_dir/CmuxRemoteMac.app"
codesign --verify --deep --strict "$staging_dir/CmuxRemoteMac.app"
# Retire only this project's replacement sidebar and swap a clean bundle.
for old_extension in "$destination/Contents/Extensions/RemoteSidebar.appex" "$PWD/.build/macos/Build/Products/Debug/RemoteSidebar.appex"; do
  if [[ -d "$old_extension" ]]; then pluginkit -r "$old_extension" || true; fi
done
launchservices="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
if [[ "$source_app" != "$destination" ]]; then "$launchservices" -u "$source_app"; fi
if [[ -e "$destination" ]]; then mv "$destination" "$staging_dir/previous.app"; fi
if ! mv "$staging_dir/CmuxRemoteMac.app" "$destination"; then
  if [[ -d "$staging_dir/previous.app" ]]; then mv "$staging_dir/previous.app" "$destination"; fi
  exit 1
fi
"$launchservices" -f "$destination"
if [[ "${CMUX_REMOTE_MAC_OPEN:-1}" == "1" ]]; then open -g "$destination"; fi
echo "Companion installed. Keep cmux's Default Workspaces sidebar; mirrors appear in its native Remote group."
