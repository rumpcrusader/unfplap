#!/usr/bin/env bash
# Shared anatomy asset list and archive handling.
#
# The meshes and textures are never committed. They are packed into one zip, upload that zip
# somewhere with a plain URL, and `build.sh --anatomy-zip` or CI unpacks it into
# `assets/anatomy/` before a pack is built. Sourced by `build.sh` and `scripts/pack_anatomy.sh`,
# so the required set has one definition.
#
# Keep this list in step with `anatomy.gd` (mare meshes) and `anon_part.gd` (player part); they
# are the only consumers.

ANATOMY_FILES=(
	winking.scn
	anal.scn
	teats.scn
	skin_bridge.scn
	anon_part.scn
	anon_part_albedo.png
	anon_part_ao.png
	anon_part_nrm.png
)

# anatomy_missing DIR -> prints the missing or empty names, one per line, and returns 1.
anatomy_missing() {
	local dir="$1"
	local missing=()
	local name
	for name in "${ANATOMY_FILES[@]}"; do
		if [ ! -s "$dir/$name" ]; then missing+=("$name"); fi
	done
	if [ "${#missing[@]}" -eq 0 ]; then return 0; fi
	printf '%s\n' "${missing[@]}"
	return 1
}

# anatomy_unpack ZIP DIR -> copy exactly ANATOMY_FILES from ZIP into DIR.
#
# Entries are matched by base name, and every file is written under DIR with the required name,
# so an archive path can never escape the destination and extra entries are ignored.
anatomy_unpack() {
	local zip="$1"
	local dest="$2"
	if [ ! -f "$zip" ]; then
		echo "anatomy archive not found: $zip" >&2
		return 1
	fi
	mkdir -p "$dest"
	python3 - "$zip" "$dest" "${ANATOMY_FILES[@]}" <<'PY'
import os
import sys
import zipfile

archive, dest, *names = sys.argv[1:]
try:
	with zipfile.ZipFile(archive) as zf:
		found = {}
		for info in zf.infolist():
			if info.is_dir():
				continue
			base = os.path.basename(info.filename)
			if base in names and base not in found:
				found[base] = info
		missing = [name for name in names if name not in found]
		if missing:
			raise SystemExit("anatomy archive is missing: " + " ".join(missing))
		for name in names:
			info = found[name]
			if info.file_size <= 0:
				raise SystemExit("anatomy archive has an empty entry: " + name)
			with zf.open(info) as src, open(os.path.join(dest, name), "wb") as out:
				out.write(src.read())
except zipfile.BadZipFile:
	raise SystemExit("anatomy archive is not a zip file: " + archive)
PY
}
