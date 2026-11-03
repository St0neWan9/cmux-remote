#!/usr/bin/env bash
# Builds the Android client, runs its JVM tests, and captures one screenshot per
# required form factor on task-owned emulators. It never touches a user's AVD.
set -euo pipefail
cd "$(dirname "$0")/.."
JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export JAVA_HOME

phone="${PHONE_DEVICE:-emulator-5556}"
fold="${FOLD_DEVICE:-emulator-5558}"
out="${OUT_DIR:-.build/android-shots}"
mkdir -p "$out"

echo "== build and test"
(cd android && ./gradlew testDebugUnitTest assembleDebug --no-daemon)

apk=android/app/build/outputs/apk/debug/app-debug.apk
for device in "$phone" "$fold"; do
  if ! adb -s "$device" get-state >/dev/null 2>&1; then
    echo "skip $device: not running"
    continue
  fi
  adb -s "$device" install -r "$apk" >/dev/null
  adb -s "$device" shell am force-stop com.cmuxremote.mobile
  adb -s "$device" shell am start -n com.cmuxremote.mobile/.MainActivity >/dev/null
  sleep 8
  adb -s "$device" exec-out screencap -p > "$out/$device-list.png"
  echo "captured $out/$device-list.png"
done
