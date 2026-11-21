#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p build

LIVE_LOG="build/emulator-live-logcat.txt"
LOGCAT_PID=""

capture_emulator_evidence() {
  if [[ -n "$LOGCAT_PID" ]]; then kill "$LOGCAT_PID" >/dev/null 2>&1 || true; fi
  adb logcat -d -t 3000 > build/emulator-logcat.txt 2>&1 || true
  adb shell screencap -p /sdcard/mahdia-emulator.png >/dev/null 2>&1 || true
  adb pull /sdcard/mahdia-emulator.png build/mahdia-emulator.png >/dev/null 2>&1 || true
}
trap capture_emulator_evidence EXIT

echo "Waiting for ADB device..."
adb wait-for-device
echo "Waiting for Android boot and Package Manager..."
package_ready=false
for attempt in $(seq 1 120); do
  boot_state="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
  package_state="$(adb shell service check package 2>&1 || true)"
  echo "Readiness attempt $attempt: boot=$boot_state; $package_state"
  if [[ "$boot_state" == "1" ]] && grep -qi "found" <<< "$package_state"; then
    package_ready=true
    break
  fi
  sleep 1
done

if [[ "$package_ready" != "true" ]]; then
  echo "Android Package Manager did not become ready"
  exit 1
fi

test -s build/REAL_LIFE_MAHDIA-debug.apk
adb shell cmd package list packages >/dev/null
adb install -r build/REAL_LIFE_MAHDIA-debug.apk
adb logcat -c
LIVE_LOG="build/emulator-live-logcat.txt"
adb logcat -v brief > "$LIVE_LOG" 2>&1 &
LOGCAT_PID=$!
adb shell am force-stop com.jassim.reallifemahdia
adb shell am start -W -n com.jassim.reallifemahdia/com.godot.game.GodotApp

# Require the first playable frame before waiting for the complete city.
player_ready=false
for attempt in $(seq 1 40); do
  if grep -q "MAHDIA_PLAYER_READY" "$LIVE_LOG"; then
    player_ready=true
    echo "Playable player/camera/HUD initialized on attempt $attempt."
    break
  fi
  sleep 0.5
done
if [[ "$player_ready" != "true" ]]; then
  echo "Player scene did not initialize. Recent Godot log:"
  grep -E "godot|GodotActivity" "$LIVE_LOG" | tail -n 120 || true
  exit 1
fi

# The playable Android build must use the textured, rigged human GLB.
# Do not silently accept the geometric procedural mannequin as a successful player model.
if ! grep -q 'MAHDIA_PLAYER_VISUAL=IMPORTED' "$LIVE_LOG"; then
  echo "Expected the imported realistic player model, but it was not activated."
  grep "MAHDIA_PLAYER_" "$LIVE_LOG" | tail -n 40 || true
  exit 1
fi
if ! grep -q 'MAHDIA_PLAYER_IMPORTED=1' "$LIVE_LOG"; then
  echo "Imported player visual did not report its rig diagnostics."
  exit 1
fi
echo "Imported textured player model confirmed in the Android runtime."

# Reject a rig only when the runtime diagnostic positively identifies it as inverted.
# Some GLB exporters store bone rest offsets in a way that cannot be reconstructed
# from the exposed rest transforms; UNVERIFIED must not abort startup before the
# world can render. The rendered-scene screenshot check below remains mandatory.
if grep -q 'MAHDIA_PLAYER_VISUAL=IMPORTED' "$LIVE_LOG" && grep -q 'MAHDIA_PLAYER_ORIENTATION=INVERTED' "$LIVE_LOG"; then
  echo "Player rig was positively identified as inverted."
  grep 'MAHDIA_PLAYER_ORIENTATION=' "$LIVE_LOG" | tail -n 10 || true
  exit 1
fi
if grep -q 'MAHDIA_PLAYER_VISUAL=IMPORTED' "$LIVE_LOG" && grep -q 'MAHDIA_PLAYER_ORIENTATION=UPRIGHT' "$LIVE_LOG"; then
  echo "Player rig orientation verified upright."
else
  echo "Player rig orientation is not measurable from rest data; continue to rendered-scene validation."
  grep 'MAHDIA_PLAYER_ORIENTATION=' "$LIVE_LOG" | tail -n 10 || true
fi

scene_ready=false
for attempt in $(seq 1 120); do
  if grep -q "MAHDIA_WORLD_READY" "$LIVE_LOG"; then
    scene_ready=true
    echo "Main world scene reported ready on attempt $attempt."
    break
  fi
  sleep 0.5
done
if [[ "$scene_ready" != "true" ]]; then
  echo "City scene did not finish initializing. Recent Godot log:"
  grep -E "godot|GodotActivity" "$LIVE_LOG" | tail -n 160 || true
  exit 1
fi

# A successful world render is not enough: require imported human GLB assets
# to instantiate in the live Android scene, not merely exist in the build ZIP.
if ! grep -Eq 'MAHDIA_IMPORTED_RESIDENTS=[1-9][0-9]*/' "$LIVE_LOG"; then
  echo "No imported human resident model was confirmed in the Android runtime."
  grep 'MAHDIA_IMPORTED_' "$LIVE_LOG" | tail -n 40 || true
  exit 1
fi
grep 'MAHDIA_IMPORTED_' "$LIVE_LOG" | tail -n 20

# Confirm all imported residents are present. Current GLB assets report
# animations=[], so the game uses procedural skeleton gait rather than an
# authored AnimationPlayer clip; absence of the clip diagnostic is not fatal.
residents_ready=false
for attempt in $(seq 1 20); do
  if grep -q 'MAHDIA_IMPORTED_RESIDENTS=11/12' "$LIVE_LOG"; then
    residents_ready=true
    echo "11 imported residents and one beachwear resident loaded."
    break
  fi
  sleep 1
done
if [[ "$residents_ready" != "true" ]]; then
  echo "Imported resident load check failed."
  grep -E 'MAHDIA_IMPORTED_|MAHDIA_WORLD_READY' "$LIVE_LOG" | tail -n 60 || true
  exit 1
fi
if ! grep -q 'MAHDIA_BEACHGOERS=1/12' "$LIVE_LOG"; then
  echo "The beachwear resident variant was not confirmed in the live scene."
  grep -E 'MAHDIA_IMPORTED_|MAHDIA_BEACHGOERS=' "$LIVE_LOG" | tail -n 40 || true
  exit 1
fi
if grep -q 'MAHDIA_IMPORTED_GAIT_ACTIVE' "$LIVE_LOG"; then
  echo "Resident gait diagnostic:"
  grep 'MAHDIA_IMPORTED_GAIT_ACTIVE' "$LIVE_LOG" | tail -n 8
else
  echo "No authored gait clip diagnostic; current animation-free GLBs use procedural gait fallback."
fi

activity_state="$(adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' || true)"
echo "$activity_state"
if ! grep -q 'com.jassim.reallifemahdia' <<< "$activity_state"; then
  echo "The game activity is not resumed after startup"
  exit 1
fi

# Dismiss Android's one-time immersive-mode confirmation.
# Prefer the actual accessibility bounds for "Got it"; use a verified
# landscape fallback (the button center is around x=71%, y=59%).
screen_size="$(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -n 1 | tr -d '\r')"
screen_width="${screen_size%x*}"
screen_height="${screen_size#*x}"
fallback_x=$((screen_width * 71 / 100))
fallback_y=$((screen_height * 59 / 100))
dialog_dismissed=false
for attempt in $(seq 1 4); do
  adb shell uiautomator dump /sdcard/mahdia-window.xml >/dev/null 2>&1 || true
  adb pull /sdcard/mahdia-window.xml build/mahdia-window.xml >/dev/null 2>&1 || true
  button_bounds="$(python3 - <<'PY'
import re
from pathlib import Path
p = Path("build/mahdia-window.xml")
if p.exists():
    xml = p.read_text(errors="ignore")
    match = re.search(r'text="Got it"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)
    if match:
        x1, y1, x2, y2 = map(int, match.groups())
        print(f"{(x1+x2)//2},{(y1+y2)//2}")
PY
)"
  if [[ -n "$button_bounds" ]]; then
    IFS=, read -r tap_x tap_y <<< "$button_bounds"
    echo "Immersive dialog found; tapping accessibility target at $tap_x,$tap_y."
  else
    tap_x="$fallback_x"
    tap_y="$fallback_y"
    echo "Accessibility target unavailable; tapping verified fallback at $tap_x,$tap_y."
  fi
  adb shell input tap "$tap_x" "$tap_y" >/dev/null 2>&1 || true
  sleep 1
  adb shell uiautomator dump /sdcard/mahdia-window.xml >/dev/null 2>&1 || true
  adb pull /sdcard/mahdia-window.xml build/mahdia-window.xml >/dev/null 2>&1 || true
  if ! grep -q 'Got it' build/mahdia-window.xml 2>/dev/null; then
    dialog_dismissed=true
    echo "Immersive confirmation is no longer exposed by the Android UI."
    break
  fi
done
if [[ "$dialog_dismissed" != "true" ]]; then
  echo "WARNING: immersive dialog could not be verified as dismissed; capture will still be checked."
fi

# Allow a few rendered frames after scene initialization before inspecting pixels.
sleep 3
adb shell screencap -p /sdcard/mahdia-emulator.png >/dev/null
adb pull /sdcard/mahdia-emulator.png build/mahdia-emulator.png >/dev/null
cat "$LIVE_LOG" > build/emulator-logcat.txt

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
