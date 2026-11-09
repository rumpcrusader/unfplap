#!/usr/bin/env bash
# Validate a prepared release, or the metadata of a pushed tag in CI.
#
#   scripts/check_release.sh
#     Local release check: clean tree, version/changelog/target game, test suites,
#     self-verifying preflight build, then a review packet and the exact push/tag commands.
#     It never tags or pushes.
#
#   scripts/check_release.sh --ci --tag v0.3.2 --branch master [--notes-out FILE]
#     CI metadata check: annotated tag on the default branch, clean tag checkout, version,
#     changelog and notes. It does not need the full game project.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { echo "RELEASE_CHECK_FAIL $*" >&2; exit 1; }
usage() { sed -n '2,11p' "$0"; }

CI=0
TAG=""
BRANCH=""
NOTES=""
while [ "$#" -gt 0 ]; do
	case "$1" in
		--ci) CI=1; shift ;;
		--tag)
			[ "$#" -ge 2 ] || fail "--tag needs a release tag"
			TAG="$2"; shift 2
			;;
		--branch)
			[ "$#" -ge 2 ] || fail "--branch needs a branch name"
			BRANCH="$2"; shift 2
			;;
		--notes-out)
			[ "$#" -ge 2 ] || fail "--notes-out needs a file path"
			NOTES="$2"; shift 2
			;;
		-h|--help) usage; exit 0 ;;
		*) fail "unknown argument: $1" ;;
	esac
done

if [ "$CI" -eq 0 ] && { [ -n "$TAG" ] || [ -n "$BRANCH" ] || [ -n "$NOTES" ]; }; then
	fail "--tag, --branch and --notes-out require --ci"
fi

stash_installed_packs() {
	local dirs=()
	[ -n "${UNFPLAP_MODS_DIR:-}" ] && dirs+=("$UNFPLAP_MODS_DIR")
	dirs+=("${XDG_DATA_HOME:-$HOME/.local/share}/home-equestria-public/mods")
	[ -n "${APPDATA:-}" ] && dirs+=("$APPDATA/home-equestria-public/mods")
	local dir file backup moved=0
	for dir in "${dirs[@]}"; do
		[ -d "$dir" ] || continue
		for file in "$dir"/unfplap*.pck; do
			[ -e "$file" ] || continue
			backup="$file.bak"
			if [ -e "$backup" ]; then backup="$file.$(date +%Y%m%d-%H%M%S).bak"; fi
			mv "$file" "$backup"
			echo "STASHED $file -> $backup"
			moved=1
		done
	done
	if [ "$moved" -eq 0 ]; then echo "No installed unfplap packs to stash."; fi
}

if [ "$CI" -eq 1 ]; then
	[ -n "$TAG" ] || fail "--ci needs --tag"
	[ -n "$BRANCH" ] || fail "--ci needs --branch"
	[ "$(git cat-file -t "$TAG" 2>/dev/null || true)" = "tag" ] || fail "tag $TAG is not annotated"
	[ "$(git rev-parse HEAD)" = "$(git rev-parse "$TAG^{commit}")" ] || fail "HEAD is not the tag commit"
	[ -z "$(git status --porcelain)" ] || fail "tag checkout is not clean"
	git rev-parse --verify --quiet "refs/remotes/origin/$BRANCH" >/dev/null || fail "origin/$BRANCH is not fetched"
	if ! git merge-base --is-ancestor "$TAG^{commit}" "refs/remotes/origin/$BRANCH"; then
		fail "tag $TAG is not on $BRANCH"
	fi
	VERSION="${TAG#v}"
	[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "tag must be vMAJOR.MINOR.PATCH: $TAG"
	scripts/check_release_metadata.py "$VERSION" --tag "$TAG" --mode ci --notes-out "$NOTES"
	if [ -n "$NOTES" ]; then echo "Release notes written to $NOTES"; fi
	echo "RELEASE_CHECK_CI_OK tag=$TAG version=$VERSION"
	exit 0
fi

[ -f "$ROOT/../../project.godot" ] || fail "run from the mod inside the full game project"
[ -z "$(git status --porcelain)" ] || fail "working tree is not clean; commit the release metadata first"

VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])' "$ROOT/mod.json")"
TAG="v$VERSION"
if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
	fail "tag $TAG already exists"
fi
CHANGED=()
while IFS= read -r path; do
	[ -n "$path" ] && CHANGED+=("$path")
done < <(git show --pretty=format: --name-only HEAD | sed '/^$/d' | sort)

GAME_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["game_version"])' "$ROOT/mod.json")"
scripts/check_release_metadata.py "$VERSION" --tag "$TAG" --mode local

if ! command -v godot >/dev/null 2>&1; then
	fail "Godot is not on PATH"
fi
GODOT_REPORT="$(godot --version | sed -n '1p')"
[[ "$GODOT_REPORT" == 4.5.2* ]] || fail "release checks require Godot 4.5.2, found $GODOT_REPORT"

echo "Running test suites..."
scripts/test_all.sh
echo "Stashing installed unfplap packs..."
stash_installed_packs
echo "Running source smoke..."
scripts/smoke.sh
echo "Building and verifying the preflight pack..."
./build.sh
[ -z "$(git status --porcelain)" ] || fail "tests or build changed tracked files; review and commit them first"

PCK="$ROOT/dist/unfplap-$VERSION.pck"
SUM="$PCK.sha256"
[ -f "$PCK" ] || fail "build did not produce $PCK"
[ -f "$SUM" ] || fail "build did not write $SUM"

HASH="$(git rev-parse HEAD)"
DEFAULT_BRANCH="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
DEFAULT_BRANCH="${DEFAULT_BRANCH#origin/}"
[ -n "$DEFAULT_BRANCH" ] || DEFAULT_BRANCH="master"
echo
echo "RELEASE_REVIEW"
echo "version: $VERSION"
echo "target game: $GAME_VERSION"
echo "commit: $HASH"
echo "branch: $DEFAULT_BRANCH"
echo "godot: $GODOT_REPORT"
echo "files: ${CHANGED[*]:-}"
echo "changelog:"
awk -v tag="v$VERSION" '
	$0 == tag { inside = 1; print; next }
	inside && $0 ~ /^v[0-9]/ { exit }
	inside { print }
' changelog.txt
echo "preflight: $PCK"
cat "$SUM"
echo "Preflight only; CI rebuilds the published pack and attaches its own .sha256."
echo
echo "Before pushing, install $PCK and run the relevant lab pass."
echo "If it is good, the user runs:"
printf '  git push origin %s\n' "$DEFAULT_BRANCH"
printf '  git tag -a %s %s -m "unfplap %s" -m "target game: %s" -m "source commit: %s"\n' \
	"$TAG" "$HASH" "$VERSION" "$GAME_VERSION" "$HASH"
printf '  git push origin %s\n' "$TAG"
echo "RELEASE_CHECK_OK version=$VERSION"
