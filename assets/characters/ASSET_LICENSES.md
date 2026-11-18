# Resident character assets

The Android build workflow downloads four rigged human character models from CodeLove 3D Models:

- Male Adult 01: https://models.codelove.in/models/male-adult-01/
- Male Adult 02: https://models.codelove.in/models/male-adult-02/
- Female Adult 02: https://models.codelove.in/models/female-adult-02/
- Female Party 01: https://models.codelove.in/models/female-party-01/

The source pages identify these models as glTF 2.0 GLB files under the MIT License, with the license embedded in each model. The models have textured materials and rigged Biped skeletons. Keep the embedded license metadata with each asset when modifying or redistributing it.

The APK build fetches these files before Godot imports the project, so no network download is required by the running game. If the download step fails, the build fails clearly rather than silently shipping the procedural placeholders.
