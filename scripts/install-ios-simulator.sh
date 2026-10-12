#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
device_id="${1:?Pass an explicit task-owned cmux-remote Simulator UDID}"
SIMULATOR_ID="$device_id" python3 - <<'PY'
import json,os,subprocess
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','-j']))['devices']
device=next((d for items in devices.values() for d in items if d['udid']==os.environ['SIMULATOR_ID']),None)
assert device and device['name'].startswith('cmux-remote-'), 'Use a task-owned cmux-remote Simulator'
PY
codesign --force --sign - --timestamp=none \
  .build/ios/Build/Products/Debug-iphonesimulator/CmuxRemote.app
xcrun simctl install "$device_id" .build/ios/Build/Products/Debug-iphonesimulator/CmuxRemote.app
