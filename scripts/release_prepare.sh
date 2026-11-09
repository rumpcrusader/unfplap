#!/usr/bin/env bash
# Prepare the mechanical part of a release.
#
#   scripts/release_prepare.sh              -> print the current version, target game and tags
#   scripts/release_prepare.sh 0.3.2        -> bump mod.json and insert the changelog section
#
# The script refuses a dirty tree, a non-master branch, an existing tag, a version that does not
# increase, and a mod.json game_version that does not match project.godot. It never commits.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { echo "RELEASE_PREPARE_FAIL $*" >&2; exit 1; }

usage() { sed -n '2,8p' "$0"; }

case "${1:-}" in
	-h|--help) usage; exit 0 ;;
esac
if [ "$#" -gt 1 ]; then fail "usage: scripts/release_prepare.sh [VERSION]"; fi

if [ ! -f "$ROOT/mod.json" ] || [ ! -f "$ROOT/changelog.txt" ]; then
	fail "run from the mod repository root (mod.json and changelog.txt missing)"
fi

if [ "$#" -eq 0 ]; then
	python3 - "$ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
mod = json.loads((root / "mod.json").read_text(encoding="utf-8"))
print("current_version=%s" % mod.get("version", ""))
print("target_game=%s" % mod.get("game_version", ""))
PY
	echo "last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo none)"
	echo "branch=$(git branch --show-current)"
	if last="$(git describe --tags --abbrev=0 2>/dev/null)"; then
		echo "commits_since=$(git rev-list --count "$last"..HEAD)"
	else
		echo "commits_since=$(git rev-list --count HEAD)"
	fi
	exit 0
fi

VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be MAJOR.MINOR.PATCH: $VERSION"
[ -f "$ROOT/../../project.godot" ] || fail "run from the mod inside the full game project"
[ -z "$(git status --porcelain)" ] || fail "working tree is not clean"
BRANCH="$(git branch --show-current)"
[ "$BRANCH" = "master" ] || fail "release from master, not $BRANCH"
if git rev-parse --verify --quiet "refs/tags/v$VERSION" >/dev/null; then
	fail "tag v$VERSION already exists"
fi

python3 - "$ROOT" "$VERSION" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
version = sys.argv[2]
mod_path = root / "mod.json"
changelog_path = root / "changelog.txt"
project_path = root.parent.parent / "project.godot"

def fail(why):
    raise SystemExit("RELEASE_PREPARE_FAIL " + why)

def semver(text):
    if not re.fullmatch(r"\d+\.\d+\.\d+", str(text)):
        return None
    return tuple(int(part) for part in str(text).split("."))

mod = json.loads(mod_path.read_text(encoding="utf-8"))
current = str(mod.get("version", ""))
game_version = str(mod.get("game_version", ""))
if semver(current) is None:
    fail("mod.json version is not semver: %s" % current)
if semver(version) <= semver(current):
    fail("new version %s must be greater than %s" % (version, current))
if not game_version:
    fail("mod.json game_version is empty")

project = project_path.read_text(encoding="utf-8")
match = re.search(r'^config/version="([^"]+)"', project, re.MULTILINE)
if match is None:
    fail("project.godot has no config/version")
project_version = match.group(1)
if project_version != game_version:
    fail("mod.json game_version %s does not match project.godot %s; update compatibility in a separate commit" % (game_version, project_version))

changelog = changelog_path.read_text(encoding="utf-8")
first = next((line.strip() for line in changelog.splitlines() if line.strip()), "")
if first == "v" + version:
    fail("changelog already has a v%s section" % version)

mod["version"] = version
mod_path.write_text(json.dumps(mod, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
changelog_path.write_text("v%s\n- TODO\n\n%s" % (version, changelog), encoding="utf-8")
print("RELEASE_PREPARE_EDIT version=%s game_version=%s" % (version, game_version))
PY

echo "RELEASE_PREPARE_OK $VERSION"
if last="$(git describe --tags --abbrev=0 2>/dev/null)"; then
	echo "Commits since $last:"
	git log --oneline "$last"..HEAD
else
	echo "Commits:"
	git log --oneline
fi
echo "Next: replace the TODO with user-facing bullets, commit mod.json and changelog.txt, then run scripts/release_check.sh."
