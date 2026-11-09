#!/usr/bin/env bash
# Validate a prepared release, or the metadata of a pushed tag in CI.
#
#   scripts/release_check.sh
#     Local release check: clean master, release commit, version/changelog/target game,
#     test suites, self-verifying preflight build, then a review packet and the exact
#     push/tag commands. It never tags or pushes.
#
#   scripts/release_check.sh --ci --tag v0.3.2 [--notes-out FILE]
#     CI metadata check: annotated tag on master, version/changelog/docs consistency, and
#     optionally write the release-notes body. It does not need the full game project.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { echo "RELEASE_CHECK_FAIL $*" >&2; exit 1; }
usage() { sed -n '2,11p' "$0"; }

CI=0
TAG=""
NOTES=""
while [ "$#" -gt 0 ]; do
	case "$1" in
		--ci) CI=1; shift ;;
		--tag)
			[ "$#" -ge 2 ] || fail "--tag needs a release tag"
			TAG="$2"; shift 2
			;;
		--notes-out)
			[ "$#" -ge 2 ] || fail "--notes-out needs a file path"
			NOTES="$2"; shift 2
			;;
		-h|--help) usage; exit 0 ;;
		*) fail "unknown argument: $1" ;;
	esac
done

if [ "$CI" -eq 1 ]; then
	[ -n "$TAG" ] || fail "--ci needs --tag"
	[ "$(git cat-file -t "refs/tags/$TAG" 2>/dev/null || true)" = "tag" ] || fail "tag $TAG is not annotated"
	git rev-parse --verify --quiet refs/remotes/origin/master >/dev/null || fail "origin/master is not fetched"
	if ! git merge-base --is-ancestor "$TAG^{commit}" refs/remotes/origin/master; then
		fail "tag $TAG is not on master"
	fi
	VERSION="${TAG#v}"
	[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "tag must be vMAJOR.MINOR.PATCH: $TAG"
	scripts/check_release.py "$VERSION" --tag "$TAG" --mode ci --notes-out "$NOTES"
	if [ -n "$NOTES" ]; then echo "Release notes written to $NOTES"; fi
	echo "RELEASE_CHECK_CI_OK tag=$TAG version=$VERSION"
	exit 0
fi

[ -f "$ROOT/../../project.godot" ] || fail "run from the mod inside the full game project"
[ -z "$(git status --porcelain)" ] || fail "working tree is not clean; commit the release metadata first"
BRANCH="$(git branch --show-current)"
[ "$BRANCH" = "master" ] || fail "check a release from master, not $BRANCH"

VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])' "$ROOT/mod.json")"
TAG="v$VERSION"
if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
	fail "tag $TAG already exists"
fi
SUBJECT="$(git log -1 --format=%s)"
[ "$SUBJECT" = "build: release $VERSION" ] || fail "HEAD subject must be 'build: release $VERSION', found '$SUBJECT'"
mapfile -t CHANGED < <(git show --pretty=format: --name-only HEAD | sed '/^$/d' | sort)
if [ "${#CHANGED[@]}" -ne 2 ] || [ "${CHANGED[0]}" != "changelog.txt" ] || [ "${CHANGED[1]}" != "mod.json" ]; then
	printf 'RELEASE_CHECK_FAIL release commit must touch only changelog.txt and mod.json, found:\n%s\n' "${CHANGED[*]}" >&2
	exit 1
fi

GAME_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["game_version"])' "$ROOT/mod.json")"
scripts/check_release.py "$VERSION" --tag "$TAG" --mode local

echo "Running test suites..."
scripts/test_all.sh
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
echo
echo "RELEASE_REVIEW"
echo "version: $VERSION"
echo "target game: $GAME_VERSION"
echo "commit: $HASH"
echo "files: ${CHANGED[*]}"
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
printf '  git push origin master\n'
printf '  git tag -a %s %s -m "unfplap %s" -m "target game: %s" -m "source commit: %s"\n' \
	"$TAG" "$HASH" "$VERSION" "$GAME_VERSION" "$HASH"
printf '  git push origin %s\n' "$TAG"
echo "RELEASE_CHECK_OK version=$VERSION"
