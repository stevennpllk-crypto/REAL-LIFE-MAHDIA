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

## 2026-11-20 — Object pooling, draw distance and occlusion culling

- **Object pooling**: residents and traffic cars now live in fixed per-slot pools (12 residents, 4 cars). Changing the quality tier parks the extras (detached from the scene tree, so no render/physics/script cost, memory saved first) and re-attaches them when the tier rises. Nothing is freed and rebuilt. Only slots inside the active budget are ever created, so a Low-tier session never loads the full population.
- **Draw distance per tier**: camera far plane Low 160 m / Medium 220 m / High 320 m. Small facade details (windows, balconies, AC units, rails) use `visibility_range_end` of 30 / 55 / 100 m and never cast shadows, so distant buildings render as shell + roof only.
- **Occlusion culling**: `rendering/occlusion_culling/use_occlusion_culling=true`, and every building gets an inset `BoxOccluder3D`, so props, cars and residents fully behind buildings are skipped.
- New test `tests/test_quality_pooling.gd` loads the real Main scene and checks the budgets, pool reuse, draw distance, detail range and occluders on every tier. It was added to the Godot validation workflow.

### Verification status

- Local, Godot 4.3 headless (Linux arm64): project import OK; `test_mobile_movement.gd` 72/72; `test_quality_pooling.gd` 38/38 (run twice).
- Headless runs use the dummy renderer, so these numbers do not measure FPS. **30+ FPS on a 3 GB device still has to be confirmed on a real phone.** No such measurement is claimed.
- APK export and the emulator smoke test still need the GitHub Actions run on this branch.

## 2026-11-21 — Corniche visual overhaul (branch `feat/corniche-visuals`)

Goal: make the starting area look as close as practical to the user's reference image of the sunny Mahdia corniche. A real-time mobile game will look closer to that image, not identical to a photoreal render.

### Renderer and lighting
- Main project renderer switched from GL Compatibility to **Mobile (Vulkan)**. CI still exports a **GLES Compatibility APK** for older devices.
- Fixed a real Compatibility bug: `limits/opengl/max_renderable_lights=0` produced zero-sized light arrays, so GLES3 scene shaders failed to compile (reproduced on Mesa llvmpipe). Now 8 lights / 2 per object.
- Poly Haven CC0 HDRI sky (`kloofendal_48d_partly_cloudy_puresky`) lights the scene (ambient + reflections), with a procedural-sky fallback. ACES tonemapping, glow, depth fog, colour adjustment, directional sun shadows (PSSM, soft filtering).
- SSAO is **not** available in the Mobile or Compatibility renderers in Godot 4.3; it is only enabled if the game runs on Forward+.
- Sun now comes from behind the spawn view over the sea at ~13:00, so facades, people and the fortress are front-lit. Night dims the sky and turns on the lamp glow.

### Corniche scene (`scripts/corniche.gd`, `scripts/mesh_batch.gd`, `shaders/`)
- Rebuilt the spawn area: 3–4 storey whitewashed buildings with blue louvred shutters, wrought-iron balconies, cornices, shopfronts and awnings; café terraces with parasols; corniche road with parked cars (incl. yellow taxis); a 14 m light-stone promenade lined with tall procedural palms (wind-animated fronds) and double lamp posts; a carved stone balustrade with pillars (collision, with three openings so the sea stays swimmable); seawall and rocks; small boats bobbing; Tunisian flag (procedural texture, waving shader); Borj el Kebir with crenellated walls, square bastions, a 25 m keep and an arched gate on a rocky point (walkable, excluded from the swim zone).
- Sea: Gerstner swell + ripple normals, depth-tinted colour, shoreline foam, GGX sky reflections.
- Geometry is merged per material, so a whole building is ~8 draw calls; facade details still use the per-tier draw-distance LOD and every building has a box occluder.
- The player spawns at (68, 0, -48.5) facing west along the promenade toward the fortress. The drivable car is now a sculpted black sedan parked at the curb.
- The north–south avenue no longer runs into the sea; its traffic wraps at the corniche.

### Player and HUD
- Player outfit matches the reference: black t-shirt, black shorts with white stripes, white sneakers, dark hair; the HUD shirt button cycles four outfits (saved).
- HUD rebuilt to the reference layout with vector-drawn icons (no emoji fonts): live rotating minimap (real streets, buildings, residents, car, mission target), home and shirt buttons, location label, mission panel, wallet pill with "+", level label and XP bar, avatar, trophy, settings, friends, chat and mic buttons, a chat log, joystick and the punch / crouch / run / jump cluster (plus interact and dodge).
- Every button does something real: home → return to the corniche spawn; shirt → outfit; "+" → how to earn money; avatar → profile stats; trophy → starter-mission checklist; gear → settings (graphics quality, AI setup); friends → nearby residents with distance and trust; chat → resident chat input; mic → **reads replies aloud with the phone's text-to-speech** (it is not voice input).
- Level/XP is new and real: XP from accepting, buying, delivering, working and AI conversations; saved with life progress. A new player starts at Lv. 1 (the image's "Lv. 8" is not faked).
- Currency stays Tunisian dinars (د.ت), not the image's "$".

### Quality tiers
- Low: 30 FPS, 70% scale, no shadows, no glow, FXAA, low sea detail, static palms. Medium: 45 FPS, 82%, 2-split shadows (40 m), glow, MSAA 2x. High: 60 FPS, 100%, 4-split soft shadows (70 m), glow, MSAA 4x, full sea detail. Resident/traffic budgets, draw distances and pooling are unchanged.

### Verification status
- Local Godot 4.3 (Linux arm64, headless): import OK; `test_mobile_movement.gd` **72/72** (with no resident GLBs, as in the CI validation job); `test_quality_pooling.gd` **38/38**; main scene reaches `MAHDIA_WORLD_READY`.
- Note: with the downloaded resident GLBs present locally, 5 resident-face/elbow checks in `test_mobile_movement.gd` fail on the **original code too** (they test the procedural fallback rig). The CI validation job runs without the GLBs.
- Real rendered screenshots (Xvfb + Mesa lavapipe Vulkan, Mobile renderer; and llvmpipe GL Compatibility) were produced with `tools/capture_screenshot.gd`. In that sandbox the skinned resident GLBs crash lavapipe, so those captures show the procedural resident fallback; the APK uses the GLB residents.
- No FPS measurement on a real phone is claimed.
