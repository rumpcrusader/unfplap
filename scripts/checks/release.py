"""The release tooling contract: the shell prelude, the shipped files and the manifest."""
from __future__ import annotations

import json
import re

from .context import ROOT, read_text
from .failure import Failure, rel

RELEASE_FILES = (
    ".opencode/skills/release/SKILL.md",
    ".opencode/commands/release.md",
    "scripts/prepare_release.sh",
    "scripts/check_release.sh",
    "scripts/check_release_metadata.py",
    "scripts/build_manifest.py",
    "scripts/asset_pack.py",
    "scripts/pack_assets.sh",
    "scripts/fetch_assets.sh",
    "scripts/asset_pack.json",
    "assets/README.md",
)
SHELL_ENTRIES = ("build.sh", "lab.sh", "lab-stress.sh", "lab-vr.sh")


def project_game_version() -> str:
    if ROOT.parent.name != "mods":
        return ""
    project = ROOT.parent.parent / "project.godot"
    if not project.is_file():
        return ""
    match = re.search(r'^config/version="([^"]+)"', project.read_text(encoding="utf-8"),
                      re.MULTILINE)
    return match.group(1) if match else ""


def check_release(failure: Failure) -> None:
    # Every bash entry point runs under errexit, so a failing tool stops it.
    shell_paths = [ROOT / name for name in SHELL_ENTRIES]
    shell_paths += sorted((ROOT / "scripts").glob("*.sh"))
    for path in shell_paths:
        lines = [line.strip() for line in read_text(str(path)).splitlines()]
        if "set -euo pipefail" not in lines:
            failure.add("%s must run under 'set -euo pipefail'" % rel(path))

    # The release and asset tooling ships with the mod.
    for name in RELEASE_FILES:
        if not (ROOT / name).is_file():
            failure.add("missing release file: %s" % name)

    # The manifest is the entry contract: one known id, a dotted version and the project's game.
    try:
        manifest = json.loads(read_text(str(ROOT / "mod.json")))
    except (OSError, json.JSONDecodeError) as error:
        failure.add("mod.json does not parse: %s" % error)
        manifest = {}
    if not isinstance(manifest, dict):
        failure.add("mod.json must contain an object")
        manifest = {}
    if manifest.get("id") != "unfplap":
        failure.add('mod.json id must be "unfplap"')
    if not re.fullmatch(r"\d+\.\d+\.\d+", str(manifest.get("version", ""))):
        failure.add("mod.json version must be MAJOR.MINOR.PATCH")
    if "extends" in manifest:
        failure.add("mod.json must declare an entry, not an extends")
    if manifest.get("entry") != "res://mods/unfplap/main.gd":
        failure.add("mod.json entry must be res://mods/unfplap/main.gd")
    game_version = project_game_version()
    if game_version and str(manifest.get("game_version", "")) != game_version:
        failure.add("mod.json game_version %s does not match the project (%s)" % (
            manifest.get("game_version", ""), game_version))
