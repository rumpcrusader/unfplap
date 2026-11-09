#!/usr/bin/env bash
# Build one standalone mod pack from this repository.
#
#   ./build.sh                  -> dist/unfplap-<version>.pck
#   ./build.sh --out FILE.pck   -> FILE.pck
#
# Godot 4.5 must be on PATH; the release check requires 4.5.2. The pack contains only the tracked
# runtime tree plus the fetched resource runtime, imported asset data and the generated
# mod.built.json. The build stages that tree in a throwaway minimal Godot project at the same
# res://mods/<id>/ paths the game uses, imports assets there, and packs the staging tree. A fresh
# checkout needs scripts/fetch_assets.sh first; this script verifies the fetched set and never
# downloads it.
#
# The packer verifies its own output against the same manifest: required runtime files, no
# development files, readable import data and a .sha256 beside the pack. A failed check removes
# the pack.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT=""

while [ "$#" -gt 0 ]; do
	case "$1" in
		--out)
			if [ "$#" -lt 2 ]; then echo "--out needs a file path." >&2; exit 1; fi
			OUT="$2"
			shift 2
			;;
		-h|--help)
			sed -n '2,16p' "$0"
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			exit 1
			;;
	esac
done

for tool in godot python3 git; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "$tool is needed on PATH." >&2
		exit 1
	fi
done

if [ ! -f "$ROOT/mod.json" ] || [ ! -f "$ROOT/.pckignore" ]; then
	echo "Expected mod.json and .pckignore beside build.sh." >&2
	exit 1
fi

if ! python3 "$ROOT/scripts/asset_pack.py" verify --root "$ROOT"; then
	echo "Run scripts/fetch_assets.sh once in this checkout." >&2
	exit 1
fi

ID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8"))["id"])' "$ROOT/mod.json")"
VERSION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])' "$ROOT/mod.json")"
if ! [[ "$ID" =~ ^[a-z0-9_]{1,40}$ ]]; then
	echo "mod.json id is not a valid mod id: $ID" >&2
	exit 1
fi
if [ -z "$VERSION" ]; then
	echo "mod.json version is empty." >&2
	exit 1
fi

if [ -z "$OUT" ]; then OUT="$ROOT/dist/$ID-$VERSION.pck"; fi
mkdir -p "$(dirname "$OUT")"

STAGE="$(mktemp -d)"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

MOD="$STAGE/mods/$ID"
mkdir -p "$MOD"
tar -C "$ROOT" --exclude-from="$ROOT/.pckignore" -cf - . | tar -C "$MOD" -xf -

# The manifest is the single required-file contract: every tracked and fetched runtime file must
# be packed, and the packer rejects anything not in this list.
EXPECTED="$STAGE/expected.txt"
python3 "$ROOT/scripts/build_manifest.py" "$ROOT" > "$EXPECTED"
export MOD_EXPECTED_FILES="$EXPECTED"

cat > "$STAGE/project.godot" <<EOF
config_version=5

[application]

config/name="$ID build"
EOF

echo "Importing resources..."
godot --headless --path "$STAGE" --import

cp "$ROOT/tools/pack.gd" "$STAGE/pack.gd"
godot --headless --path "$STAGE" --script res://pack.gd -- --out "$OUT"

echo "Copy $OUT into the game's mods folder and enable it in Settings -> Mods."
echo "Checksum: $OUT.sha256"
