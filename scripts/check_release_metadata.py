#!/usr/bin/env python3
"""Check the release metadata shared by the local preflight and CI.

Usage: scripts/check_release_metadata.py VERSION --tag TAG --mode local|ci [--notes-out FILE]
"""
import argparse
import json
import pathlib
import re
import sys

HEADING = re.compile(r"^v\d+\.\d+\.\d+$")


def fail(why):
    raise SystemExit("RELEASE_CHECK_FAIL " + why)


def section(text, heading):
    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines) if line.strip()), None)
    if start is None:
        fail("changelog.txt is empty")
    if lines[start].strip() != heading:
        fail("changelog.txt must start with %s, found %s" % (heading, lines[start].strip()))
    body = []
    for line in lines[start + 1:]:
        if HEADING.fullmatch(line.strip()):
            break
        body.append(line)
    return "\n".join(body).strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--mode", choices=("local", "ci"), required=True)
    parser.add_argument("--notes-out", default="")
    args = parser.parse_args()

    root = pathlib.Path.cwd()
    mod = json.loads((root / "mod.json").read_text(encoding="utf-8"))
    version = args.version
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        fail("version must be MAJOR.MINOR.PATCH: %s" % version)
    if str(mod.get("version", "")) != version:
        fail("mod.json version %s does not match %s" % (mod.get("version", ""), version))
    game_version = str(mod.get("game_version", ""))
    if not game_version:
        fail("mod.json game_version is empty")
    if args.tag != "v" + version:
        fail("tag %s does not match version %s" % (args.tag, version))

    changelog = (root / "changelog.txt").read_text(encoding="utf-8")
    body = section(changelog, "v" + version)
    if not body:
        fail("changelog.txt has no section for v%s" % version)
    if any(line.strip() == "- TODO" for line in body.splitlines()):
        fail("changelog.txt still has the placeholder for v%s" % version)
    bullets = [line.strip() for line in body.splitlines() if line.strip().startswith("- ")]
    if not bullets:
        fail("changelog.txt has no bullets for v%s" % version)

    if args.mode == "local":
        project = (root.parent.parent / "project.godot").read_text(encoding="utf-8")
        match = re.search(r'^config/version="([^"]+)"', project, re.MULTILINE)
        if match is None:
            fail("project.godot has no config/version")
        if match.group(1) != game_version:
            fail("project.godot is %s, mod.json targets %s" % (match.group(1), game_version))

    if args.notes_out:
        pathlib.Path(args.notes_out).write_text(body + "\n", encoding="utf-8")
    print("RELEASE_METADATA_OK version=%s game_version=%s" % (version, game_version))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        fail(str(error))
