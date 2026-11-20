#!/usr/bin/env python3
"""Compare the player's Unfplap data with the shipped data, and promote values.

Three shipped documents, two promotion targets:

    settings/settings.json     declared settings
    settings/characters.json   the global `default` profile, the per-mare profiles and the
                               per-mare placement rows
    settings/prompts.json      the AI prompt text; read-only here, never a promotion target

    scripts/settings_sync.py diff    [--project-root DIR] [--settings PATH] [--json OUT]
    scripts/settings_sync.py promote PATH [PATH ...] [--project-root DIR] [--settings PATH] [--dry-run]
    scripts/settings_sync.py diff --characters    [...]
    scripts/settings_sync.py promote --characters PATH [PATH ...] [...]

`diff` is read-only. `promote` writes the player's value into the target document; it never edits
the player's profile, so the player keeps the value they already have. `--settings` names the
player's `settings.json`; the character mode reads the `characters.json` beside it. This tool is
pure JSON: it never launches Godot and never runs the migration. Launch the game once and close it
before diffing, so the player's profile is current.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

MISSING = object()
MOD_PREFIX = Path("mods/unfplap")
NEVER_FILE = Path(".opencode/skills/sync-settings/never_sync.json")
SETTINGS_FILE = Path("settings/settings.json")
CHARACTERS_FILE = Path("settings/characters.json")
# A list setting stores a set of names; order is not a difference.
SET_PATHS = {"caress.ignore", "presentation.standing.caress.ignore"}
# Player leaves that are never promoted: the schema version and the section open state.
STRUCTURAL = ("version",)
# Placement rows for these ids are declared settings, not per-mare character rows.
RESERVED_PLACEMENT_IDS = ("default", "anon")
# Player roots that belong to the characters document; the path is the same on both sides.
CHARACTER_ROOTS = ("default", "characters")


def mod_root_for(project_root: Path) -> Path:
    return project_root / MOD_PREFIX


def project_root_default() -> Path:
    # scripts/settings_sync.py -> mods/unfplap/scripts -> mods/unfplap -> mods -> project root
    return Path(__file__).resolve().parents[3]


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise SystemExit(f"cannot read {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise SystemExit(f"not valid JSON: {path}: {error}") from error
    if not isinstance(value, dict):
        raise SystemExit(f"not a JSON object: {path}")
    return value


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8"
    )


def get_path(data: Any, path: str) -> Any:
    node = data
    for part in path.split("."):
        if not isinstance(node, dict) or part not in node:
            return MISSING
        node = node[part]
    return node


def set_path(data: dict[str, Any], path: str, value: Any, create: bool = False) -> None:
    parts = path.split(".")
    node = data
    for part in parts[:-1]:
        child = node.get(part)
        if not isinstance(child, dict):
            if not create:
                raise SystemExit(f"not a block in the shipped data: {path}")
            child = {}
            node[part] = child
        node = child
    node[parts[-1]] = value


def flatten(value: Any, prefix: str = "") -> list[tuple[str, Any]]:
    out: list[tuple[str, Any]] = []
    if isinstance(value, dict):
        for key, child in value.items():
            path = f"{prefix}.{key}" if prefix else str(key)
            out.extend(flatten(child, path))
    else:
        out.append((prefix, value))
    return out


def color_key(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    text = value.strip().lstrip("#").lower()
    if not re.fullmatch(r"[0-9a-f]{6}([0-9a-f]{2})?", text):
        return None
    return text if len(text) == 8 else text + "ff"


def is_set_path(path: str) -> bool:
    return path in SET_PATHS or path.endswith(".caress.ignore") \
        or path.endswith(".preferences.touch") or path.endswith(".preferences.talk") \
        or path.endswith(".preferences.dislikes")


def equal_value(a: Any, b: Any, path: str = "") -> bool:
    if isinstance(a, bool) or isinstance(b, bool):
        return isinstance(a, bool) and isinstance(b, bool) and a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(float(a) - float(b)) <= 1e-6
    ca, cb = color_key(a), color_key(b)
    if ca is not None and cb is not None:
        return ca == cb
    if isinstance(a, list) and isinstance(b, list):
        if is_set_path(path):
            return sorted(str(x) for x in a) == sorted(str(x) for x in b)
        return len(a) == len(b) and all(equal_value(x, y, path) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, dict):
        return set(a) == set(b) and all(
            equal_value(a[key], b[key], f"{path}.{key}" if path else key) for key in a
        )
    return a == b


def short(value: Any, limit: int = 120) -> str:
    text = json.dumps(value, ensure_ascii=False, sort_keys=True)
    return text if len(text) <= limit else text[: limit - 1] + "…"


def resolve_profile(settings_arg: str | None) -> Path:
    if settings_arg:
        path = Path(settings_arg).expanduser().resolve()
        if not path.exists():
            raise SystemExit(f"settings.json not found: {path}")
        return path
    candidates: list[Path] = []
    xdg = os.environ.get("XDG_DATA_HOME")
    if xdg:
        candidates.append(Path(xdg) / "home-equestria-public/mods/data/unfplap/settings.json")
    candidates.append(
        Path.home() / ".local/share/home-equestria-public/mods/data/unfplap/settings.json"
    )
    appdata = os.environ.get("APPDATA")
    if appdata:
        candidates.append(
            Path(appdata) / "home-equestria-public/mods/data/unfplap/settings.json"
        )
    candidates.append(
        Path.home()
        / "Library/Application Support/home-equestria-public/mods/data/unfplap/settings.json"
    )
    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()
    raise SystemExit("settings.json not found; pass --settings PATH")


def load_never(mod_root: Path) -> set[str]:
    path = mod_root / NEVER_FILE
    if not path.exists():
        return set()
    return {str(value) for value in read_json(path).get("paths", [])}


def is_structural(path: str) -> bool:
    return any(path == root or path.startswith(root + ".") for root in STRUCTURAL) \
        or path == "ui.sections" or path.startswith("ui.sections.")


def is_mare_placement(path: str) -> bool:
    parts = path.split(".")
    return len(parts) >= 4 and parts[0] == "anatomy" and parts[1] == "placement" \
        and parts[2] not in RESERVED_PLACEMENT_IDS


def character_target(path: str) -> str | None:
    """The characters path a player override would promote to, or None for a settings path."""
    if path.split(".", 1)[0] in CHARACTER_ROOTS or is_mare_placement(path):
        return path
    return None


def compare_settings(shipped: dict[str, Any], player: dict[str, Any],
                     never: set[str]) -> dict[str, Any]:
    diffs: list[dict[str, Any]] = []
    missing: list[str] = []
    for path, shipped_value in flatten(shipped):
        if path in never:
            continue
        player_value = get_path(player, path)
        if player_value is MISSING:
            missing.append(path)
            continue
        if equal_value(player_value, shipped_value, path):
            continue
        diffs.append({"path": path, "player": player_value, "shipped": shipped_value})
    shipped_paths = {path for path, _ in flatten(shipped)}
    player_only = [path for path, _ in flatten(player)
                   if path not in shipped_paths and not is_structural(path)]
    characters = [path for path in player_only if character_target(path) is not None]
    dead = [path for path in player_only if character_target(path) is None]
    return {
        "mode": "settings",
        "diffs": diffs,
        "missing": missing,
        "characters": characters,
        "dead": dead,
        "never": sorted(never),
    }


def compare_characters(shipped: dict[str, Any], player: dict[str, Any],
                       never: set[str]) -> dict[str, Any]:
    diffs: list[dict[str, Any]] = []
    missing: list[str] = []
    for path, player_value in flatten(player):
        target = character_target(path)
        if target is None or target in never:
            continue
        shipped_value = get_path(shipped, target)
        if shipped_value is MISSING:
            missing.append(target)
            continue
        if equal_value(player_value, shipped_value, target):
            continue
        diffs.append({"path": target, "player": player_value, "shipped": shipped_value})
    return {
        "mode": "characters",
        "diffs": diffs,
        "missing": missing,
        "characters": [],
        "dead": [],
        "never": sorted(never),
    }


def report(profile: Path, shipped: Path, result: dict[str, Any]) -> None:
    print(f"profile: {profile}")
    print(f"shipped: {shipped}")
    print("never synced: " + (", ".join(result["never"]) or "none"))
    if result["mode"] == "characters":
        print(f"character differences: {len(result['diffs'])}")
        for index, item in enumerate(result["diffs"], 1):
            print(f"  {index}. {item['path']}")
            print(f"     player: {short(item['player'])}")
            print(f"     shipped: {short(item['shipped'])}")
        print(f"missing from the character file (promotable): {len(result['missing'])}")
        for path in result["missing"][:12]:
            print("  - " + path)
        if len(result["missing"]) > 12:
            print("  …")
        return
    print(f"differences: {len(result['diffs'])}")
    for index, item in enumerate(result["diffs"], 1):
        print(f"  {index}. {item['path']}")
        print(f"     player: {short(item['player'])}")
        print(f"     shipped: {short(item['shipped'])}")
    print(f"missing from the player file (filled by the merge): {len(result['missing'])}")
    for path in result["missing"][:12]:
        print("  - " + path)
    if len(result["missing"]) > 12:
        print("  …")
    print(f"character overrides (promote with --characters): {len(result['characters'])}")
    for path in result["characters"][:12]:
        print("  - " + path)
    if len(result["characters"]) > 12:
        print("  …")
    print(f"unknown player leaves: {len(result['dead'])}")
    for path in result["dead"]:
        print("  - " + path)


def command_diff(args: argparse.Namespace) -> int:
    project_root = Path(args.project_root).expanduser().resolve()
    mod_root = mod_root_for(project_root)
    shipped_path = mod_root / (CHARACTERS_FILE if args.characters else SETTINGS_FILE)
    profile = resolve_profile(args.settings)
    never = load_never(mod_root)
    shipped = read_json(shipped_path)
    if args.characters:
        profile = profile.with_name("characters.json")
        player = read_json(profile) if profile.exists() else {}
        result = compare_characters(shipped, player, never)
    else:
        player = read_json(profile)
        result = compare_settings(shipped, player, never)
    report(profile, shipped_path, result)
    if args.json:
        payload = {"profile": str(profile), "shipped": str(shipped_path), **result}
        write_json(Path(args.json).expanduser(), payload)
        print("plan " + args.json)
    return 0


def command_promote(args: argparse.Namespace) -> int:
    project_root = Path(args.project_root).expanduser().resolve()
    mod_root = mod_root_for(project_root)
    shipped_path = mod_root / (CHARACTERS_FILE if args.characters else SETTINGS_FILE)
    shipped = read_json(shipped_path)
    profile = resolve_profile(args.settings)
    if args.characters:
        profile = profile.with_name("characters.json")
    player = read_json(profile)
    never = load_never(mod_root)
    changed = 0
    for path in args.paths:
        if path in never:
            raise SystemExit(f"refusing to promote a never-sync path: {path}")
        if args.characters:
            if character_target(path) is None:
                raise SystemExit(f"not a character path: {path}")
            player_value = get_path(player, path)
            if player_value is MISSING:
                raise SystemExit(f"the player has no value at {path}")
            shipped_value = get_path(shipped, path)
            if shipped_value is not MISSING:
                if isinstance(shipped_value, dict):
                    raise SystemExit(f"not a leaf path: {path}")
                if equal_value(player_value, shipped_value, path):
                    print(f"unchanged {path}")
                    continue
        else:
            shipped_value = get_path(shipped, path)
            if shipped_value is MISSING:
                raise SystemExit(f"not a shipped default path: {path}")
            if isinstance(shipped_value, dict):
                raise SystemExit(f"not a leaf path: {path}")
            player_value = get_path(player, path)
            if player_value is MISSING:
                raise SystemExit(f"the player has no value at {path}")
            if isinstance(player_value, dict):
                raise SystemExit(f"the player value at {path} is a block, not a leaf")
            if equal_value(player_value, shipped_value, path):
                print(f"unchanged {path}")
                continue
        before = "missing" if shipped_value is MISSING else short(shipped_value)
        print(f"promote {path}: {before} -> {short(player_value)}")
        if not args.dry_run:
            set_path(shipped, path, player_value, create=args.characters)
        changed += 1
    if args.dry_run:
        print(f"dry run: {changed} path(s) would change")
        return 0
    if changed:
        write_json(shipped_path, shipped)
        print(f"promoted {changed} path(s) into {shipped_path}")
    else:
        print("nothing to promote")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", default=str(project_root_default()))
    parser.add_argument("--settings", default=None,
                        help="player settings.json path; character mode reads its sibling")
    sub = parser.add_subparsers(dest="command", required=True)

    diff = sub.add_parser("diff", help="compare the player profile with the shipped data")
    diff.add_argument("--project-root", default=argparse.SUPPRESS)
    diff.add_argument("--settings", default=argparse.SUPPRESS)
    diff.add_argument("--characters", action="store_true",
                      help="compare the character overrides with settings/characters.json")
    diff.add_argument("--json", default=None, help="write the report as JSON")
    diff.set_defaults(func=command_diff)

    promote = sub.add_parser("promote", help="write player values into the shipped data")
    promote.add_argument("paths", nargs="+", metavar="PATH")
    promote.add_argument("--project-root", default=argparse.SUPPRESS)
    promote.add_argument("--settings", default=argparse.SUPPRESS)
    promote.add_argument("--characters", action="store_true",
                         help="write into settings/characters.json")
    promote.add_argument("--dry-run", action="store_true")
    promote.set_defaults(func=command_promote)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
