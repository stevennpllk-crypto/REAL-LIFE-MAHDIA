#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p build

capture_emulator_evidence() {
  adb logcat -d -t 8000 > build/emulator-logcat.txt 2>&1 || true
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
adb logcat -c
adb shell monkey -p com.jassim.reallifemahdia 1

# A resumed Android Activity is not proof that Godot loaded the game scene.
# Wait for the explicit marker printed at the end of Main.gd::_ready().
scene_ready=false
for attempt in $(seq 1 36); do
  if adb logcat -d | grep -q "MAHDIA_WORLD_READY"; then
    scene_ready=true
    echo "Main world scene reported ready on attempt $attempt."
    break
  fi
  echo "Waiting for Mahdia world scene... attempt $attempt/36"
  sleep 5
done
if [[ "$scene_ready" != "true" ]]; then
  echo "Game did not finish initializing its main world scene."
  exit 1
fi

activity_state="$(adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' || true)"
echo "$activity_state"
if ! grep -q 'com.jassim.reallifemahdia' <<< "$activity_state"; then
  echo "The game activity is not resumed after startup"
  exit 1
fi

# Allow a few rendered frames after scene initialization before inspecting pixels.
sleep 5
adb shell screencap -p /sdcard/mahdia-emulator.png >/dev/null
adb pull /sdcard/mahdia-emulator.png build/mahdia-emulator.png >/dev/null
adb logcat -d -t 8000 > build/emulator-logcat.txt

# Decode the PNG using only Python's standard library. The old Godot splash
# was almost entirely black (<2% bright pixels); a rendered outdoor scene
# must contain a substantial amount of non-dark image content.
python3 - <<'PY'
import struct
import zlib

path = "build/mahdia-emulator.png"
data = open(path, "rb").read()
if data[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit("Screenshot is not a valid PNG")
offset = 8
compressed = bytearray()
width = height = color_type = bit_depth = None
while offset < len(data):
    length = struct.unpack(">I", data[offset:offset + 4])[0]
    kind = data[offset + 4:offset + 8]
    chunk = data[offset + 8:offset + 8 + length]
    if kind == b"IHDR":
        width, height, bit_depth, color_type, _, _, _ = struct.unpack(">IIBBBBB", chunk)
    elif kind == b"IDAT":
        compressed.extend(chunk)
    elif kind == b"IEND":
        break
    offset += length + 12

channels = {2: 3, 6: 4}.get(color_type)
if bit_depth != 8 or channels is None:
    raise SystemExit(f"Unsupported screenshot PNG format: depth={bit_depth}, color={color_type}")
raw = zlib.decompress(compressed)
stride = width * channels
previous = bytearray(stride)
bright = total = 0
pos = 0
for _y in range(height):
    filt = raw[pos]
    pos += 1
    scan = bytearray(raw[pos:pos + stride])
    pos += stride
    for i in range(stride):
        left = scan[i - channels] if i >= channels else 0
        up = previous[i]
        upper_left = previous[i - channels] if i >= channels else 0
        if filt == 1:
            scan[i] = (scan[i] + left) & 255
        elif filt == 2:
            scan[i] = (scan[i] + up) & 255
        elif filt == 3:
            scan[i] = (scan[i] + ((left + up) // 2)) & 255
        elif filt == 4:
            p = left + up - upper_left
            pa, pb, pc = abs(p - left), abs(p - up), abs(p - upper_left)
            predictor = left if pa <= pb and pa <= pc else (up if pb <= pc else upper_left)
            scan[i] = (scan[i] + predictor) & 255
        elif filt != 0:
            raise SystemExit(f"Unsupported PNG filter: {filt}")
    for i in range(0, stride, channels):
        if max(scan[i:i + 3]) > 40:
            bright += 1
        total += 1
    previous = scan

ratio = bright / max(total, 1)
print(f"Screenshot check: {width}x{height}, bright-pixel ratio={ratio:.3f}")
if ratio < 0.05:
    raise SystemExit("Screenshot is still too dark; likely splash screen or failed rendering.")
PY

if grep -E 'FATAL EXCEPTION|SIGSEGV|Fatal signal' build/emulator-logcat.txt; then
  echo "Fatal application error detected"
  exit 1
fi
echo "APK install, world-scene initialization, and rendered-screen smoke test passed."
