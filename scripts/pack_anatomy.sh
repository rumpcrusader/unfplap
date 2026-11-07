#!/usr/bin/env bash
# Pack the local anatomy assets into the archive that `build.sh --anatomy-zip` and CI consume.
#
#   scripts/pack_anatomy.sh                 -> dist/unfplap-anatomy.zip
#   scripts/pack_anatomy.sh --out FILE.zip  -> FILE.zip
#
# Only the required meshes and textures are added, all at the archive root, so the extractor
# never has to guess a folder layout. The archive is written under dist/, which is ignored.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=scripts/anatomy_assets.sh
source "$SCRIPT_DIR/anatomy_assets.sh"

OUT="$ROOT/dist/unfplap-anatomy.zip"

while [ "$#" -gt 0 ]; do
	case "$1" in
		--out)
			if [ "$#" -lt 2 ]; then echo "--out needs a file path." >&2; exit 1; fi
			OUT="$2"
			shift 2
			;;
		-h|--help)
			sed -n '2,8p' "$0"
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			exit 1
			;;
	esac
done

if ! command -v python3 >/dev/null 2>&1; then
	echo "python3 is needed to write the archive." >&2
	exit 1
fi

ANATOMY_DIR="$ROOT/assets/anatomy"
if ! missing="$(anatomy_missing "$ANATOMY_DIR")"; then
	printf 'Missing anatomy assets in assets/anatomy/:\n%s\n' "$missing" >&2
	exit 1
fi

mkdir -p "$(dirname "$OUT")"
python3 - "$OUT" "$ANATOMY_DIR" "${ANATOMY_FILES[@]}" <<'PY'
import os
import sys
import zipfile

out, src, *names = sys.argv[1:]
tmp = out + ".tmp"
with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zf:
	for name in names:
		zf.write(os.path.join(src, name), arcname=name)
os.replace(tmp, out)
PY

echo "ANATOMY_PACKED $OUT"
