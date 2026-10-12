#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
device_id="${1:?Pass the explicit task-owned cmux-remote Simulator UDID}"
SIMULATOR_ID="$device_id" python3 - <<'PY'
import json, os, subprocess
values = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '-j']))['devices']
device = next((d for items in values.values() for d in items if d['udid'] == os.environ['SIMULATOR_ID']), None)
assert device and device['name'].startswith('cmux-remote-') and device['state'] == 'Booted', 'Use an already booted, task-owned cmux-remote Simulator'
PY
python3 scripts/generate-ios-project.py
native_arch="$(uname -m)"
if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == "1" ]]; then native_arch=arm64; fi
python3 scripts/run-ios-navigation-tests.py "$device_id" "$native_arch" "${@:2}"
