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
adb shell am force-stop com.jassim.reallifemahdia
adb shell am start -W -n com.jassim.reallifemahdia/com.godot.game.GodotApp

# Require the first playable frame before waiting for the complete city.
player_ready=false
for attempt in $(seq 1 24); do
  if adb logcat -d | grep -q "MAHDIA_PLAYER_READY"; then
    player_ready=true
    echo "Playable player/camera/HUD initialized on attempt $attempt."
    break
  fi
  sleep 5
done
if [[ "$player_ready" != "true" ]]; then
  echo "Player scene did not initialize. Recent Godot log:"
  adb logcat -d -s godot:I godot:E GodotActivity:V | tail -n 120 || true
  exit 1
fi

# Confirm the player itself uses the imported human asset, not the old blocky fallback.
if ! adb logcat -d | grep -q "MAHDIA_PLAYER_IMPORTED=1"; then
  echo "Imported human player model was not confirmed in the Android runtime."
  adb logcat -d | grep "MAHDIA_PLAYER_" | tail -n 40 || true
  exit 1
fi

scene_ready=false
for attempt in $(seq 1 48); do
  if adb logcat -d | grep -q "MAHDIA_WORLD_READY"; then
    scene_ready=true
    echo "Main world scene reported ready on attempt $attempt."
    break
  fi
  sleep 5
done
if [[ "$scene_ready" != "true" ]]; then
  echo "City scene did not finish initializing. Recent Godot log:"
  adb logcat -d -s godot:I godot:E GodotActivity:V | tail -n 160 || true
  exit 1
fi

# A successful world render is not enough: require imported human GLB assets
# to instantiate in the live Android scene, not merely exist in the build ZIP.
if ! adb logcat -d | grep -Eq 'MAHDIA_IMPORTED_RESIDENTS=[1-9][0-9]*/'; then
  echo "No imported human resident model was confirmed in the Android runtime."
  adb logcat -d | grep 'MAHDIA_IMPORTED_' | tail -n 40 || true
  exit 1
fi
adb logcat -d | grep 'MAHDIA_IMPORTED_' | tail -n 20

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
from math import sqrt

data = open("build/mahdia-emulator.png", "rb").read()
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
pos = 0
center_colors = set()
center_luma = []
for y in range(height):
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
    if int(height * 0.20) <= y < int(height * 0.72):
        for x in range(int(width * 0.20), int(width * 0.80), 3):
            i = x * channels
            red, green, blue = scan[i], scan[i + 1], scan[i + 2]
            center_colors.add((red >> 3, green >> 3, blue >> 3))
            center_luma.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
    previous = scan

mean = sum(center_luma) / max(len(center_luma), 1)
variance = sum((v - mean) ** 2 for v in center_luma) / max(len(center_luma), 1)
deviation = sqrt(variance)
print(f"Scene pixels: {width}x{height}; center color buckets={len(center_colors)}; luminance deviation={deviation:.1f}")
if len(center_colors) < 24 or deviation < 8.0:
    raise SystemExit("The game scene is still visually flat: 3D world geometry was not detected in the center of the screenshot.")
PY

app_pid="$(adb shell pidof com.jassim.reallifemahdia | tr -d '\\r' | awk '{print $1}')"
if [[ -n "$app_pid" ]] && adb logcat -d --pid="$app_pid" | grep -E 'FATAL EXCEPTION|SIGSEGV|Fatal signal'; then
  echo "Fatal error detected in the game process"
  exit 1
fi
echo "APK install, world-scene initialization, and rendered-screen smoke test passed."
