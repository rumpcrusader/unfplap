#!/usr/bin/env bash
# Fetch the external runtime asset archive into the ignored working tree.
#
#   scripts/fetch_assets.sh              -> audio/ and assets/anatomy/
#   scripts/fetch_assets.sh --sources    -> also sources/ for editing the Blender file
#   scripts/fetch_assets.sh --force      -> overwrite local changes
#
# Run this once in a fresh checkout, before --mod-src, tests, smoke, a lab or build.sh. The
# download is verified against the committed scripts/asset_pack.json archive hash and file
# manifest. Local runtime changes are never overwritten unless --force is passed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$ROOT/scripts/asset_pack.py" fetch --root "$ROOT" "$@"
