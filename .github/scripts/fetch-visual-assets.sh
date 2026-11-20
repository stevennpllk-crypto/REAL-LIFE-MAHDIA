#!/usr/bin/env bash
# Downloads the free (CC0) Poly Haven textures and HDRI sky used by the
# Mahdia corniche. Binary assets are not committed; CI caches them.
# Usage: bash .github/scripts/fetch-visual-assets.sh   (from the repo root)
set -euo pipefail
mkdir -p assets/textures assets/hdri
base="https://dl.polyhaven.org/file/ph-assets"
fetch() {
  local url="$1" out="$2"
  if [[ -s "$out" ]]; then return 0; fi
  curl --fail --location --retry 3 --silent --show-error "$url" -o "$out"
  test -s "$out"
}
# 1k PBR sets: diffuse, OpenGL normal, roughness.
for asset in plastered_wall cobblestone_pavement precast_stone_paving large_sandstone_blocks_01 beige_wall_001 coast_land_rocks_01 asphalt_02; do
  fetch "$base/Textures/jpg/1k/$asset/${asset}_diff_1k.jpg" "assets/textures/${asset}_diff_1k.jpg"
  fetch "$base/Textures/png/1k/$asset/${asset}_nor_gl_1k.png" "assets/textures/${asset}_nor_gl_1k.png"
  fetch "$base/Textures/jpg/1k/$asset/${asset}_rough_1k.jpg" "assets/textures/${asset}_rough_1k.jpg"
done
# Midday Mediterranean-style sky with scattered clouds (no ground in the HDRI).
fetch "$base/HDRIs/hdr/2k/kloofendal_48d_partly_cloudy_puresky_2k.hdr" "assets/hdri/kloofendal_48d_partly_cloudy_puresky_2k.hdr"
du -h assets/textures/* assets/hdri/*
