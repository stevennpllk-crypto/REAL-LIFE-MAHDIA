#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p build

capture_emulator_evidence() {
  adb logcat -d -t 6000 > build/emulator-logcat.txt 2>&1 || true
  adb shell screencap -p /sdcard/mahdia-emulator.png >/dev/null 2>&1 || true
  adb pull /sdcard/mahdia-emulator.png build/mahdia-emulator.png >/dev/null 2>&1 || true
}
trap capture_emulator_evidence EXIT

echo "Waiting for ADB device..."
adb wait-for-device
echo "Waiting for Android boot and Package Manager..."
package_ready=false
for attempt in $(seq 1 180); do
  boot_state="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
  package_state="$(adb shell service check package 2>&1 || true)"
  echo "Readiness attempt $attempt: boot=$boot_state; $package_state"
  if [[ "$boot_state" == "1" ]] && grep -qi "found" <<< "$package_state"; then
    package_ready=true
    break
  fi
  sleep 5
done

if [[ "$package_ready" != "true" ]]; then
  echo "Android Package Manager did not become ready"
  exit 1
fi

test -s build/REAL_LIFE_MAHDIA-debug.apk
adb shell cmd package list packages >/dev/null
adb install -r build/REAL_LIFE_MAHDIA-debug.apk
adb shell monkey -p com.jassim.reallifemahdia 1
# Give the first scene extra time: the world is assembled from many 3D nodes.
sleep 60
activity_state="$(adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' || true)"
echo "$activity_state"
if ! grep -q 'com.jassim.reallifemahdia' <<< "$activity_state"; then
  echo "The game activity is not resumed after startup"
  exit 1
fi
adb shell screencap -p /sdcard/mahdia-emulator.png >/dev/null
adb pull /sdcard/mahdia-emulator.png build/mahdia-emulator.png >/dev/null
adb logcat -d -t 6000 > build/emulator-logcat.txt
if grep -E 'FATAL EXCEPTION|SIGSEGV|Fatal signal' build/emulator-logcat.txt; then
  echo "Fatal application error detected"
  exit 1
fi
echo "APK install and launch smoke test passed."
