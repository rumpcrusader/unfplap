#!/usr/bin/env bash
# Pack the local anatomy assets into the archive that `build.sh --anatomy-zip` and CI consume.
#
#   scripts/pack_anatomy.sh                     -> dist/unfplap-anatomy.zip
#   scripts/pack_anatomy.sh --out FILE.zip      -> FILE.zip
#   scripts/pack_anatomy.sh --upload            -> upload it to pone.rs and update
#                                                  ANATOMY_ARCHIVE_URL in scripts/anatomy_assets.sh
#   scripts/pack_anatomy.sh --upload --no-write -> upload and print the URL, leave the file alone
#
# Only the required meshes and textures are added, all at the archive root, so the extractor
# never has to guess a folder layout. The archive is written under dist/, which is ignored.
# Entries carry a fixed timestamp, so unchanged assets always produce the same bytes and the
# upload dedupe returns the same URL. Commit the rewritten ANATOMY_ARCHIVE_URL before tagging.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=scripts/anatomy_assets.sh
source "$SCRIPT_DIR/anatomy_assets.sh"

UPLOAD_ENDPOINT="https://pone.rs/upload"
ASSETS_FILE="$SCRIPT_DIR/anatomy_assets.sh"
OUT="$ROOT/dist/unfplap-anatomy.zip"
UPLOAD=0
WRITE=1

while [ "$#" -gt 0 ]; do
	case "$1" in
		--out)
			if [ "$#" -lt 2 ]; then echo "--out needs a file path." >&2; exit 1; fi
			OUT="$2"
			shift 2
			;;
		--upload)
			UPLOAD=1
			shift
			;;
		--no-write)
			WRITE=0
			shift
			;;
		-h|--help)
			sed -n '2,14p' "$0"
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			exit 1
			;;
	esac
done

if [ "$WRITE" -eq 0 ] && [ "$UPLOAD" -eq 0 ]; then
	echo "--no-write needs --upload; there is no other URL to print." >&2
	exit 1
fi

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
# writestr with a fixed ZipInfo keeps the archive byte-identical across machines and runs.
python3 - "$OUT" "$ANATOMY_DIR" "${ANATOMY_FILES[@]}" <<'PY'
import os
import sys
import zipfile

out, src, *names = sys.argv[1:]
tmp = out + ".tmp"
stamp = (1980, 1, 1, 0, 0, 0)
with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zf:
	for name in names:
		info = zipfile.ZipInfo(name, stamp)
		info.compress_type = zipfile.ZIP_DEFLATED
		info.external_attr = 0o644 << 16
		with open(os.path.join(src, name), "rb") as handle:
			zf.writestr(info, handle.read())
os.replace(tmp, out)
PY

echo "ANATOMY_PACKED $OUT"

if [ "$UPLOAD" -eq 0 ]; then
	echo "Pass --upload to publish this archive to pone.rs and update ANATOMY_ARCHIVE_URL."
	exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
	echo "curl is needed to upload the archive." >&2
	exit 1
fi

# The host answers with {"success": true, "files": [{"url": ...}]} and dedupes identical bytes.
response="$(curl --fail-with-body --silent --show-error \
	--form "files[]=@$OUT" "$UPLOAD_ENDPOINT")"
url="$(python3 - "$response" <<'PY'
import json
import sys

try:
	data = json.loads(sys.argv[1])
except json.JSONDecodeError:
	raise SystemExit("upload did not answer with json: " + sys.argv[1])
files = data.get("files") if isinstance(data, dict) else None
if not data.get("success") or not files or not isinstance(files[0], dict):
	raise SystemExit("upload failed: " + sys.argv[1])
print(files[0].get("url", ""))
PY
)"

if ! [[ "$url" =~ ^https://u\.pone\.rs/[a-z0-9]+\.zip$ ]]; then
	echo "Upload answered with an unexpected URL: $url" >&2
	exit 1
fi

# Never write a URL into the source before the host actually serves the whole archive.
local_size="$(wc -c < "$OUT" | tr -d ' ')"
head="$(curl --fail --silent --show-error --location --head "$url")"
remote_size="$(printf '%s\n' "$head" | tr -d '\r' \
	| awk 'tolower($1) == "content-length:" { value = $2 } END { print value }')"
if [ "$remote_size" != "$local_size" ]; then
	echo "Upload check failed: host serves $remote_size bytes, archive is $local_size." >&2
	exit 1
fi

if [ "$WRITE" -eq 1 ]; then
	python3 - "$ASSETS_FILE" "$url" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
url = sys.argv[2]
text = path.read_text(encoding="utf-8")
pattern = re.compile(r'^ANATOMY_ARCHIVE_URL=.*$', re.MULTILINE)
match = pattern.search(text)
if not match:
	raise SystemExit(f"ANATOMY_ARCHIVE_URL is not declared in {path}")
if match.group(0) == f'ANATOMY_ARCHIVE_URL="{url}"':
	print(f"ANATOMY_URL_UNCHANGED {url}")
	raise SystemExit(0)
path.write_text(pattern.sub(f'ANATOMY_ARCHIVE_URL="{url}"', text, count=1), encoding="utf-8")
if f'ANATOMY_ARCHIVE_URL="{url}"' not in path.read_text(encoding="utf-8"):
	raise SystemExit(f"could not write {url} into {path}")
print(f"ANATOMY_URL_UPDATED {path} {url}")
PY
else
	echo "ANATOMY_UPLOADED $url"
fi
