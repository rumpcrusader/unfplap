#!/usr/bin/env bash
# Lint the shipped GDScript with gdlint 4.5.0. Tests and tools are excluded because gdtoolkit's
# parser rejects some valid test syntax.
# Usage: scripts/lint.sh
# Godot is not needed; install the pin in scripts/requirements-lint.txt.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v gdlint >/dev/null 2>&1; then
	printf 'gdlint not found. Install: python3 -m pip install -r scripts/requirements-lint.txt\n' >&2
	exit 1
fi

version="$(gdlint --version 2>/dev/null | awk '{print $2}')"
if [[ "$version" != "4.5.0" ]]; then
	printf 'gdlint 4.5.0 required (found %s).\n' "$version" >&2
	exit 1
fi

mapfile -t files < <(git ls-files '*.gd' | grep -v -e '^tests/' -e '^tools/')
if [[ "${#files[@]}" -eq 0 ]]; then
	printf 'LINT_PASS (no files)\n'
	exit 0
fi

gdlint "${files[@]}"

# The gate carries its own fixtures; a broken rule must fail here, not silently pass.
if ! python3 "$ROOT/scripts/comments.py" --self-test >/dev/null; then
	python3 "$ROOT/scripts/comments.py" --self-test
	exit 1
fi
python3 "$ROOT/scripts/comments.py" --check

printf 'LINT_PASS %d files\n' "${#files[@]}"
