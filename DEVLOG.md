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
