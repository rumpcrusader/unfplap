#!/usr/bin/env bash
# Build the external runtime asset archive, or upload it and update the release contract.
#
#   scripts/pack_assets.sh                     -> dist/unfplap-assets-<hash>.zip
#   scripts/pack_assets.sh --out FILE.zip      -> FILE.zip
#   scripts/pack_assets.sh --local             -> the archive + dist/asset_pack.local.json
#   scripts/pack_assets.sh --upload            -> upload to pone.rs and commit the contract
#
# The archive holds `runtime/` (audio and anatomy packed into the mod) and `sources/` (the V2
# Blender source, never packed). Run this only when a runtime asset or its Blender source changed.
# A normal release reuses the committed archive URL and hash. `--local` writes an ignored contract
# for testing an unuploaded asset set; see assets/README.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$ROOT/scripts/asset_pack.py" pack --root "$ROOT" "$@"
