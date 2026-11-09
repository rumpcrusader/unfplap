#!/usr/bin/env bash
# Submit one release pack to the community mod store, or preview that submission.
#
#   scripts/publish_store.sh                              preview the latest release
#   scripts/publish_store.sh --tag v0.3.1                 preview that release
#   scripts/publish_store.sh --tag v0.3.1 --submit        mirror it and insert the store row
#   scripts/publish_store.sh --tag v0.3.1 --submit --force
#                                                         submit even when the version exists
#
# A preview downloads the release pack and, when present, its .sha256, verifies both, uploads the
# pack to pone.rs, verifies the served size and hash, runs the store's duplicate guard and prints
# the exact row it would insert. It never writes to the store. --submit does the same and then
# inserts the row.
#
# The store is the static page at https://unrivaled-cannoli-17cf6d.netlify.app/; its form POSTs
# straight to Supabase with the publishable key below, which is public in that page, not a secret.
# Rows land unapproved, so the store admin still reviews every submission.
#
# Environment: GITHUB_REPOSITORY (owner/repo) and GH_TOKEN (optional; both are set in Actions).
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-rumpcrusader/unfplap}"
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
STORE_URL="https://dnnidcsjkiqkgrsdfbag.supabase.co/rest/v1/mods"
STORE_KEY="sb_publishable_9l8is_aKGCTFsI7m8PQF2w_h_hCJ0H1"
STORE_TITLE="Unfplap"
UPLOAD_ENDPOINT="https://pone.rs/upload"

TAG=""
SUBMIT=0
FORCE=0

usage() {
	sed -n '2,18p' "$0"
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--tag)
			if [ "$#" -lt 2 ]; then echo "--tag needs a release tag." >&2; exit 1; fi
			TAG="$2"
			shift 2
			;;
		--submit)
			SUBMIT=1
			shift
			;;
		--force)
			FORCE=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			exit 1
			;;
	esac
done

for tool in curl python3; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "$tool is needed." >&2
		exit 1
	fi
done

work="$(mktemp -d "${TMPDIR:-/tmp}/unfplap-store.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# api URL OUTFILE -> GitHub API call; uses the token when one is available.
api() {
	local url="$1"
	local out="$2"
	if [ -n "$TOKEN" ]; then
		curl --fail-with-body --silent --show-error --location \
			--header "Authorization: Bearer $TOKEN" \
			--header "Accept: application/vnd.github+json" \
			--output "$out" "$url"
	else
		curl --fail-with-body --silent --show-error --location \
			--header "Accept: application/vnd.github+json" \
			--output "$out" "$url"
	fi
}

# store_versions -> the stored versions of STORE_TITLE as json.
store_versions() {
	curl --fail-with-body --silent --show-error \
		--header "apikey: $STORE_KEY" \
		--header "Authorization: Bearer $STORE_KEY" \
		"$STORE_URL?select=mod_version&title=eq.$STORE_TITLE"
}

if [ -z "$TAG" ]; then
	api "https://api.github.com/repos/$REPO/releases/latest" "$work/latest.json"
	TAG="$(python3 - "$work/latest.json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["tag_name"])
PY
)"
	echo "latest release is $TAG"
fi

case "$TAG" in
	v*) VERSION="${TAG#v}" ;;
	*) echo "release tags start with v: $TAG" >&2; exit 1 ;;
esac

api "https://api.github.com/repos/$REPO/releases/tags/$TAG" "$work/release.json"
python3 - "$work/release.json" "$work/asset.json" "$work/sum_asset.json" "$VERSION" <<'PY'
import json
import sys

release_path, asset_path, sum_path, version = sys.argv[1:5]
release = json.load(open(release_path, encoding="utf-8"))
pck = f"unfplap-{version}.pck"
sum_name = pck + ".sha256"
found = {}
for asset in release.get("assets", []):
    if asset.get("name") in (pck, sum_name):
        found[asset["name"]] = asset
if pck not in found:
    raise SystemExit(f"{release.get('tag_name')} has no asset {pck}")
json.dump(found[pck], open(asset_path, "w", encoding="utf-8"))
if sum_name in found:
    json.dump(found[sum_name], open(sum_path, "w", encoding="utf-8"))
else:
    print(f"CHECKSUM_MISSING {release.get('tag_name')} has no asset {sum_name}", file=sys.stderr)
PY

asset_url="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["browser_download_url"])' "$work/asset.json")"
asset_size="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["size"])' "$work/asset.json")"

curl --fail-with-body --silent --show-error --location \
	--output "$work/unfplap-$VERSION.pck" "$asset_url"

local_size="$(wc -c < "$work/unfplap-$VERSION.pck" | tr -d ' ')"
if [ "$local_size" != "$asset_size" ]; then
	echo "Downloaded pack is $local_size bytes, release asset is $asset_size." >&2
	exit 1
fi

local_sha="$(python3 - "$work/unfplap-$VERSION.pck" <<'PY'
import hashlib
import sys

digest = hashlib.sha256()
with open(sys.argv[1], "rb") as handle:
	for chunk in iter(lambda: handle.read(1024 * 1024), b""):
		digest.update(chunk)
print(digest.hexdigest())
PY
)"
if [ -f "$work/sum_asset.json" ]; then
	sum_url="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["browser_download_url"])' "$work/sum_asset.json")"
	curl --fail-with-body --silent --show-error --location \
		--output "$work/unfplap-$VERSION.pck.sha256" "$sum_url"
	release_sha="$(awk 'NR == 1 { print $1 }' "$work/unfplap-$VERSION.pck.sha256")"
	if [ "$local_sha" != "$release_sha" ]; then
		echo "Downloaded pack sha256 $local_sha does not match release checksum $release_sha." >&2
		exit 1
	fi
else
	echo "Release has no .sha256 asset; using the downloaded pack hash for the mirror check." >&2
fi

release_url="$(curl --fail-with-body --silent --show-error \
	--form "files[]=@$work/unfplap-$VERSION.pck" "$UPLOAD_ENDPOINT")"
file_url="$(python3 - "$release_url" <<'PY'
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

if ! [[ "$file_url" =~ ^https://u\.pone\.rs/[a-z0-9]+\.pck$ ]]; then
	echo "Upload answered with an unexpected URL: $file_url" >&2
	exit 1
fi

curl --fail-with-body --silent --show-error --location \
	--output "$work/mirror-$VERSION.pck" "$file_url"
served_size="$(wc -c < "$work/mirror-$VERSION.pck" | tr -d ' ')"
if [ "$served_size" != "$local_size" ]; then
	echo "Mirror check failed: host serves $served_size bytes, pack is $local_size." >&2
	exit 1
fi
mirror_sha="$(python3 - "$work/mirror-$VERSION.pck" <<'PY'
import hashlib
import sys

digest = hashlib.sha256()
with open(sys.argv[1], "rb") as handle:
	for chunk in iter(lambda: handle.read(1024 * 1024), b""):
		digest.update(chunk)
print(digest.hexdigest())
PY
)"
if [ "$mirror_sha" != "$local_sha" ]; then
	echo "Mirror check failed: host serves sha256 $mirror_sha, pack is $local_sha." >&2
	exit 1
fi

# The row carries the release's own mod.json, so the version and game version match the pack.
if ! curl --fail-with-body --silent --show-error --location \
	--output "$work/mod.json" "https://raw.githubusercontent.com/$REPO/$TAG/mod.json"; then
	echo "Could not read mod.json at $TAG." >&2
	exit 1
fi

python3 - "$work/mod.json" "$STORE_TITLE" "$file_url" "$VERSION" > "$work/payload.json" <<'PY'
import json
import sys

mod_path, title, url, version = sys.argv[1:5]
mod = json.load(open(mod_path, encoding="utf-8"))
if mod.get("version") != version:
	raise SystemExit(f"mod.json version {mod.get('version')} does not match tag {version}")
payload = {
	"title": title,
	"description": mod.get("description", ""),
	"mod_info": "",
	"file_url": url,
	"is_nsfw": True,
	"for_version": mod.get("game_version", ""),
	"mod_version": version,
}
json.dump(payload, sys.stdout, indent=2)
sys.stdout.write("\n")
PY

existing="$(store_versions)"
duplicate="$(python3 - "$existing" "$VERSION" <<'PY'
import json
import sys

rows = json.loads(sys.argv[1] or "[]")
print("1" if any(row.get("mod_version") == sys.argv[2] for row in rows) else "0")
PY
)"

echo "store title: $STORE_TITLE"
echo "version: $VERSION"
echo "mirror: $file_url"
echo "payload:"
cat "$work/payload.json"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "### Community store"
		echo
		echo "- Tag: \`$TAG\`"
		echo "- Version: \`$VERSION\`"
		echo "- Mirror: $file_url ($served_size bytes)"
		echo "- Duplicate guard: $([ "$duplicate" = "1" ] && echo "version already in the store" || echo "version is new")"
		echo
		echo '```json'
		cat "$work/payload.json"
		echo '```'
	} >> "$GITHUB_STEP_SUMMARY"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		echo "tag=$TAG"
		echo "version=$VERSION"
		echo "file_url=$file_url"
	} >> "$GITHUB_OUTPUT"
fi

if [ "$SUBMIT" -eq 0 ]; then
	echo "PREVIEW_ONLY nothing was written to the store; rerun with --submit to insert it."
	exit 0
fi

if [ "$duplicate" = "1" ] && [ "$FORCE" -eq 0 ]; then
	echo "STORE_SKIPPED $STORE_TITLE $VERSION is already in the store; use --force to insert another row."
	exit 0
fi

response="$(curl --fail-with-body --silent --show-error \
	--request POST "$STORE_URL" \
	--header "apikey: $STORE_KEY" \
	--header "Authorization: Bearer $STORE_KEY" \
	--header "Content-Type: application/json" \
	--header "Prefer: return=representation" \
	--data-binary "@$work/payload.json")"

row_id="$(python3 - "$response" <<'PY'
import json
import sys

try:
	rows = json.loads(sys.argv[1] or "[]")
except json.JSONDecodeError:
	rows = []
print(rows[0].get("id", "?") if rows else "?")
PY
)"

echo "STORE_SUBMITTED id=$row_id title=$STORE_TITLE version=$VERSION"
echo "The row is unapproved until the store admin reviews it."
