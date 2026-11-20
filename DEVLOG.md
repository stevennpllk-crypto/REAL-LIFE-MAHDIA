# REAL LIFE: MAHDIA — Development Log

## 2026-11-20 — Android player visual smoke-test alignment

- Inspected the Godot 4.3 project, current main-branch tree, latest commits, and GitHub Actions results.
- Confirmed the Godot validation workflow passed: project import/parse, mobile movement tests, and a short main-scene launch.
- Confirmed both Android APK export steps succeeded and both APK artifacts were uploaded.
- Diagnosed the Android emulator workflow failure: the smoke test required `MAHDIA_PLAYER_IMPORTED=1`, while the latest player change intentionally disables the imported player rig until its shoulder/rest pose is verified and uses the procedural human visual instead.
- Added an explicit `MAHDIA_PLAYER_VISUAL=IMPORTED|PROCEDURAL` runtime diagnostic.
- Updated the Android smoke test to accept either visual mode while still requiring player readiness, world readiness, imported resident checks, resumed activity, and a rendered-scene screenshot.
- Updated README documentation to explain the temporary player visual fallback.

### Verification status

- Source changes committed to branch `fix/android-smoke-procedural-player`.
- A fresh GitHub Actions run is required to validate the patched smoke test. No post-patch APK or emulator result is claimed yet.

## 2026-11-20 — Real mobile quality tiers

- Implemented a visible in-game quality button with Low / Medium / High cycling.
- Low: 30 FPS cap, 70% 3D render scale, shadows off, 5 residents, 2 traffic cars.
- Medium: 45 FPS cap, 82% 3D render scale, shadows off, 8 residents, 3 traffic cars.
- High: 60 FPS cap, full 3D render scale, shadows on, 12 residents, 4 traffic cars.
- Android starts at Medium; desktop starts at High. Physics tick rate remains fixed at 60 Hz across tiers.
- Changing tiers saves resident memory, rebuilds the active population, and persists the selected quality level.
- Updated Android smoke-test expectations for the mobile Medium default.
- Occlusion culling and runtime object pooling are not claimed as complete: the current scene uses a small fixed set of traffic/resident instances. These need a renderer/device benchmark and a real dynamic spawn/despawn path before being enabled without risking CPU/RAM regressions.
