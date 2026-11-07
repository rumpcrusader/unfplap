#!/usr/bin/env bash
# Build one standalone mod pack from this repository.
#
#   ./build.sh                          -> dist/unfplap-<version>.pck
#   ./build.sh --out FILE.pck            -> FILE.pck
#   ./build.sh --anatomy-zip FILE.zip    -> unpack the anatomy archive first
#   ./build.sh --no-anatomy              -> code-only pack, no adult anatomy
#
# Godot 4.5 must be on PATH. The pack contains only the runtime tree selected by .pckignore,
# imported asset data and the generated mod.built.json. The build stages that tree in a
# throwaway minimal Godot project at the same res://mods/<id>/ paths the game uses, imports
# assets there, and packs the staging tree.
#
# The anatomy meshes and textures are not in the repository. A normal build requires all of them
# under assets/anatomy/ and fails when any are missing. Pass --anatomy-zip to unpack them from
# the archive first, or --no-anatomy to build without the feature.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/anatomy_assets.sh
source "$ROOT/scripts/anatomy_assets.sh"
OUT=""
ANATOMY_ZIP=""
NO_ANATOMY=0

while [ "$#" -gt 0 ]; do
	case "$1" in
		--out)
			if [ "$#" -lt 2 ]; then echo "--out needs a file path." >&2; exit 1; fi
			OUT="$2"
			shift 2
			;;
		--anatomy-zip)
			if [ "$#" -lt 2 ]; then echo "--anatomy-zip needs a file path." >&2; exit 1; fi
			ANATOMY_ZIP="$2"
			shift 2
			;;
		--no-anatomy)
			NO_ANATOMY=1
			shift
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

if ! command -v godot >/dev/null 2>&1; then
	echo "Godot not found on PATH (need the Godot 4.5 executable)." >&2
	exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
	echo "python3 is needed to read mod.json." >&2
	exit 1
fi

if [ ! -f "$ROOT/mod.json" ] || [ ! -f "$ROOT/.pckignore" ]; then
	echo "Expected mod.json and .pckignore beside build.sh." >&2
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

if [ "$NO_ANATOMY" -eq 1 ] && [ -n "$ANATOMY_ZIP" ]; then
	echo "--anatomy-zip and --no-anatomy cannot be combined." >&2
	exit 1
fi

ANATOMY_DIR="$ROOT/assets/anatomy"
if [ -n "$ANATOMY_ZIP" ]; then
	echo "Unpacking anatomy assets from $ANATOMY_ZIP..."
	anatomy_unpack "$ANATOMY_ZIP" "$ANATOMY_DIR"
fi
if [ "$NO_ANATOMY" -eq 1 ]; then
	echo "ANATOMY skipped (--no-anatomy)"
elif missing="$(anatomy_missing "$ANATOMY_DIR")"; then
	echo "ANATOMY ok ${#ANATOMY_FILES[@]}/${#ANATOMY_FILES[@]}"
else
	printf 'ANATOMY_FAIL missing in assets/anatomy/:\n%s\n' "$missing" >&2
	echo "Pack them with scripts/pack_anatomy.sh, unpack the archive there, or pass --no-anatomy." >&2
	exit 1
fi

if [ -z "$OUT" ]; then OUT="$ROOT/dist/$ID-$VERSION.pck"; fi
mkdir -p "$(dirname "$OUT")"

STAGE="$(mktemp -d)"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

MOD="$STAGE/mods/$ID"
mkdir -p "$MOD"
TAR_ARGS=(--exclude-from="$ROOT/.pckignore")
# --no-anatomy must drop the assets even when they sit in the working tree.
if [ "$NO_ANATOMY" -eq 1 ]; then TAR_ARGS+=(--exclude="./assets/anatomy"); fi
tar -C "$ROOT" "${TAR_ARGS[@]}" -cf - . | tar -C "$MOD" -xf -

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
