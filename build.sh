#!/usr/bin/env bash
# Build one standalone mod pack from this repository.
#
#   ./build.sh                     -> dist/unfplap.pck
#   ./build.sh --out FILE.pck      -> FILE.pck
#   ./build.sh --no-extends        -> release pack for compiled game builds
#   GODOT=/path/to/godot ./build.sh
#
# The pack contains only the runtime tree selected by .pckignore, imported asset data and the
# generated mod.built.json. The build stages that tree in a throwaway minimal Godot project at
# the same res://mods/<id>/ paths the game uses, imports assets there, and packs the staging tree.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT="${GODOT:-godot}"
OUT=""
STRIP_EXTENDS=false

while [ "$#" -gt 0 ]; do
	case "$1" in
		--out)
			if [ "$#" -lt 2 ]; then echo "--out needs a file path." >&2; exit 1; fi
			OUT="$2"
			shift 2
			;;
		--no-extends)
			STRIP_EXTENDS=true
			shift
			;;
		-h|--help)
			sed -n '2,12p' "$0"
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			exit 1
			;;
	esac
done

if [ -x "$GODOT" ]; then
	GODOT_BIN="$GODOT"
elif command -v "$GODOT" >/dev/null 2>&1; then
	GODOT_BIN="$(command -v "$GODOT")"
else
	echo "Godot not found: set GODOT to the Godot 4.5 executable." >&2
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
if ! [[ "$ID" =~ ^[a-z0-9_]{1,40}$ ]]; then
	echo "mod.json id is not a valid mod id: $ID" >&2
	exit 1
fi

if [ -z "$OUT" ]; then OUT="$ROOT/dist/$ID.pck"; fi
mkdir -p "$(dirname "$OUT")"

STAGE="$(mktemp -d)"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

MOD="$STAGE/mods/$ID"
mkdir -p "$MOD"
tar -C "$ROOT" --exclude-from="$ROOT/.pckignore" -cf - . | tar -C "$MOD" -xf -

# A release pack for a game that ships compiled .gdc scripts drops the parked extension both
# from mod.json (pack.gd) and from the pack itself.
if [ "$STRIP_EXTENDS" = true ]; then
	rm -rf "$MOD/ext"
fi

cat > "$STAGE/project.godot" <<EOF
config_version=5

[application]

config/name="$ID build"
EOF

echo "Importing resources..."
"$GODOT_BIN" --headless --path "$STAGE" --import

cp "$ROOT/tools/pack.gd" "$STAGE/pack.gd"
PACK_ARGS=(--out "$OUT")
if [ "$STRIP_EXTENDS" = true ]; then PACK_ARGS+=(--no-extends); fi
"$GODOT_BIN" --headless --path "$STAGE" --script res://pack.gd -- "${PACK_ARGS[@]}"

echo "Copy $OUT into the game's mods folder and enable it in Settings -> Mods."
